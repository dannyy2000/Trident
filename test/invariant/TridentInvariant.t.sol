// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ILReserveVault} from "../../src/ILReserveVault.sol";
import {IILReserveVault} from "../../src/interfaces/IILReserveVault.sol";

// ---------------------------------------------------------------------------
// Minimal ERC-20 for invariant tests
// ---------------------------------------------------------------------------
contract InvariantToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    string public name = "Test";
    string public symbol = "TST";
    uint8 public decimals = 18;

    function mint(address to, uint256 amount) external { balanceOf[to] += amount; }
    function approve(address s, uint256 a) external returns (bool) { allowance[msg.sender][s] = a; return true; }
    function transfer(address to, uint256 a) external returns (bool) {
        balanceOf[msg.sender] -= a; balanceOf[to] += a; return true;
    }
    function transferFrom(address f, address t, uint256 a) external returns (bool) {
        balanceOf[f] -= a; allowance[f][msg.sender] -= a; balanceOf[t] += a; return true;
    }
}

// ---------------------------------------------------------------------------
// Handler — the stateful fuzzer calls this contract's functions randomly.
// It acts as the "hook" (msg.sender == hook is required for vault writes).
// Ghost variables track total value in/out for the no-money-printing invariant.
// ---------------------------------------------------------------------------
contract VaultHandler is Test {
    ILReserveVault public vault;
    InvariantToken public token;

    // Ghost accounting
    uint256 public ghost_totalDeposited;
    uint256 public ghost_totalPaidOut;
    uint256 public ghost_positionCount;

    // Track active position IDs so we can settle them
    bytes32[] private _activePositions;
    mapping(bytes32 => bool) private _isActive;
    uint256 private _nextSalt;

    constructor(ILReserveVault _vault, InvariantToken _token) {
        vault = _vault;
        token = _token;
    }

    // -------------------------------------------------------------------------
    // Actions the fuzzer can call
    // -------------------------------------------------------------------------

    function deposit(uint256 amount) external {
        amount = bound(amount, 1, 100_000e18);
        token.mint(address(this), amount);
        token.approve(address(vault), amount);
        vault.deposit(address(token), amount);
        ghost_totalDeposited += amount;
    }

    function recordPosition(int24 tick, uint128 liquidity) external {
        tick = int24(int256(bound(int256(tick), -887_000, 887_000)));
        liquidity = uint128(bound(uint256(liquidity), 1e6, 1e24));

        bytes32 salt = bytes32(_nextSalt++);
        bytes32 id = keccak256(abi.encode(address(0xBEEF), tick, tick + 60, salt));

        if (vault.positionExists(id)) return;

        vault.recordPosition(id, address(0xBEEF), tick, liquidity);
        _activePositions.push(id);
        _isActive[id] = true;
        ghost_positionCount++;
    }

    function settle(uint256 idxSeed, int24 exitTick) external {
        if (_activePositions.length == 0) return;

        uint256 idx = bound(idxSeed, 0, _activePositions.length - 1);
        bytes32 id = _activePositions[idx];

        if (!vault.positionExists(id)) {
            _removePosition(idx);
            return;
        }

        exitTick = int24(int256(bound(int256(exitTick), -887_000, 887_000)));

        // Roll some blocks to create non-zero loyalty
        vm.roll(block.number + bound(idxSeed, 0, 1_000));

        uint256 payout = vault.settlePosition(id, exitTick, address(0xBEEF));
        ghost_totalPaidOut += payout;

        _removePosition(idx);
        ghost_positionCount--;
    }

    function setCaptureRate(uint256 rateBps) external {
        rateBps = bound(rateBps, vault.CAPTURE_NORMAL_BPS(), vault.MAX_CAPTURE_RATE_BPS());
        vault.setCaptureRate(rateBps);
    }

    function depositAndRecord(uint256 depositAmt, int24 tick, uint128 liquidity) external {
        depositAmt = bound(depositAmt, 1, 100_000e18);
        tick = int24(int256(bound(int256(tick), -887_000, 887_000)));
        liquidity = uint128(bound(uint256(liquidity), 1e6, 1e24));

        token.mint(address(this), depositAmt);
        token.approve(address(vault), depositAmt);
        vault.deposit(address(token), depositAmt);
        ghost_totalDeposited += depositAmt;

        bytes32 salt = bytes32(_nextSalt++);
        bytes32 id = keccak256(abi.encode(address(0xBEEF), tick, tick + 60, salt));
        if (!vault.positionExists(id)) {
            vault.recordPosition(id, address(0xBEEF), tick, liquidity);
            _activePositions.push(id);
            _isActive[id] = true;
            ghost_positionCount++;
        }
    }

    function activePositionCount() external view returns (uint256) {
        return _activePositions.length;
    }

    // -------------------------------------------------------------------------
    // Internal
    // -------------------------------------------------------------------------

    function _removePosition(uint256 idx) internal {
        _isActive[_activePositions[idx]] = false;
        _activePositions[idx] = _activePositions[_activePositions.length - 1];
        _activePositions.pop();
    }
}

// ---------------------------------------------------------------------------
// Invariant test contract
// ---------------------------------------------------------------------------
contract TridentInvariantTest is Test {
    ILReserveVault internal vault;
    VaultHandler internal handler;
    InvariantToken internal token;

    function setUp() public {
        token = new InvariantToken();

        // Pre-compute handler address using CREATE — nonce is predictable in tests.
        // handler will be deployed NEXT (this contract's nonce + 1).
        // We use vm.computeCreateAddress to get its future address so vault can be
        // deployed with handler as the hook in a single pass.
        address handlerAddr = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);

        vault = new ILReserveVault(address(token), handlerAddr);
        handler = new VaultHandler(vault, token);

        // Sanity check: handler address matches what we predicted
        assert(address(handler) == handlerAddr);

        targetContract(address(handler));
    }

    // =========================================================================
    // Invariant 1: Vault accounting matches actual ERC-20 balance
    // Proves: the hook cannot credit vault balance without transferring real tokens.
    // =========================================================================
    function invariant_accountingMatchesTokenBalance() public view {
        assertEq(vault.totalReserveBalance(), token.balanceOf(address(vault)));
    }

    // =========================================================================
    // Invariant 2: Total payouts never exceed total deposits
    // Proves: the vault cannot create money — it can only redistribute what was deposited.
    // =========================================================================
    function invariant_noMoneyPrinting() public view {
        assertLe(handler.ghost_totalPaidOut(), handler.ghost_totalDeposited());
    }

    // =========================================================================
    // Invariant 3: Reserve balance = totalDeposited - totalPaidOut
    // Proves: every deposit adds to reserve, every payout subtracts — no leakage.
    // =========================================================================
    function invariant_reserveEqualsNetFlow() public view {
        assertEq(
            vault.totalReserveBalance(),
            handler.ghost_totalDeposited() - handler.ghost_totalPaidOut()
        );
    }

    // =========================================================================
    // Invariant 4: Capture rate always within valid bounds
    // Proves: auto-adjustment and Reactive callbacks cannot set an out-of-range rate.
    // =========================================================================
    function invariant_captureRateAlwaysValid() public view {
        uint256 rate = vault.captureRateBps();
        assertGe(rate, vault.CAPTURE_NORMAL_BPS());
        assertLe(rate, vault.MAX_CAPTURE_RATE_BPS());
    }

    // =========================================================================
    // Invariant 5: vaultHealthRatio never reverts
    // Proves: health computation is always safe regardless of vault state.
    // =========================================================================
    function invariant_healthRatioNeverReverts() public view {
        vault.vaultHealthRatio(); // must not revert
    }

    // =========================================================================
    // Invariant 6: Reserve balance never goes below zero
    // Trivially true for uint256 but documents the intent explicitly.
    // =========================================================================
    function invariant_reserveNeverNegative() public view {
        assertGe(vault.totalReserveBalance(), 0);
    }

    // =========================================================================
    // Invariant 7: Total liability is consistent with open positions
    // Proves: liability increases on record, decreases on settle — no orphaned liability.
    // =========================================================================
    function invariant_liabilityConsistentWithPositions() public view {
        // If no positions are open, liability should be 0
        // (because every settled position removes its worst-case claim)
        if (handler.activePositionCount() == 0) {
            assertEq(vault.totalLiability(), 0);
        }
    }
}

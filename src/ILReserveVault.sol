// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IILReserveVault} from "./interfaces/IILReserveVault.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {FullMath} from "v4-core/libraries/FullMath.sol";

/// @title ILReserveVault
/// @notice Holds the IL insurance reserve and pays out to long-term LPs at withdrawal.
///
///         Funding:  The hook calls deposit() after every swap, routing captureRateBps% of
///                   the swap fee here.
///
///         Payouts:  The hook calls settlePosition() when an LP removes liquidity.
///                   Payout = liquidity × IL_factor × loyalty_factor × health_ratio,
///                   capped at MAX_SINGLE_CLAIM_PCT of the current reserve.
///
///         IL factor:    linear proxy based on ticks moved (5e13/tick, max 50%).
///                       Proportional to price movement — not exact AMM math, but
///                       monotone, bounded, and avoids an oracle call inside the vault.
///
///         Loyalty:      (blocks_held / LOYALTY_TARGET_BLOCKS) × 1e18.
///                       A JIT provider held for 1 block earns ~0. A 30-day LP earns 100%.
///
///         Health ratio: reserve / totalLiability. Liability = sum of worst-case claims for
///                       all open positions. Below 0.3: emergency rate. Below 0.8: low rate.
contract ILReserveVault is IILReserveVault, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @dev Linear IL approximation: 5e13 wei of factor per tick moved.
    ///      At 10,000 ticks (≈100% price move): 5e17 → hits MAX_IL_FACTOR cap.
    uint256 public constant IL_PER_TICK = 5e13;

    /// @notice Maximum IL factor applied to any position (50% of liquidity)
    uint256 public constant MAX_IL_FACTOR = 0.5e18;

    /// @notice Maximum fraction of vault any single settlement can claim (10%)
    uint256 public constant MAX_SINGLE_CLAIM_PCT = 0.1e18;

    /// @notice Block duration for full loyalty (≈30 days at 12 s/block on mainnet)
    uint256 public constant LOYALTY_TARGET_BLOCKS = 216_000;

    /// @notice Absolute ceiling on capture rate — Reactive can never push above 30%
    uint256 public constant MAX_CAPTURE_RATE_BPS = 3_000;

    // Health thresholds (scaled 1e18)
    uint256 public constant HEALTH_LOW = 0.8e18;
    uint256 public constant HEALTH_EMERGENCY = 0.3e18;

    // Capture rate tiers (basis points)
    uint256 public constant CAPTURE_NORMAL_BPS = 1_000;    // 10%
    uint256 public constant CAPTURE_LOW_BPS = 1_500;       // 15%
    uint256 public constant CAPTURE_EMERGENCY_BPS = 2_000; // 20%

    // -------------------------------------------------------------------------
    // Immutables
    // -------------------------------------------------------------------------

    /// @notice The single ERC-20 token the vault accepts and pays out
    IERC20 public immutable payoutToken;

    /// @notice Only this address can call write functions
    address public immutable hook;

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    uint256 private _captureRateBps = CAPTURE_NORMAL_BPS;

    /// @dev Tracked in accounting (not read from balanceOf) to avoid donation attacks
    uint256 public totalReserveBalance;

    /// @dev Sum of worst-case claims across all open positions
    uint256 public totalLiability;

    struct VaultPosition {
        bool exists;
        address lp;
        int24 entryTick;
        uint128 liquidity;
        uint256 entryBlock;
    }

    mapping(bytes32 => VaultPosition) private _positions;

    // -------------------------------------------------------------------------
    // Errors (interface errors inherited — only declare vault-specific ones)
    // -------------------------------------------------------------------------

    error WrongToken(address given, address expected);
    error CaptureRateTooHigh(uint256 given, uint256 max);

    // -------------------------------------------------------------------------
    // Modifier
    // -------------------------------------------------------------------------

    modifier onlyHook() {
        if (msg.sender != hook) revert OnlyHook();
        _;
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address _payoutToken, address _hook) {
        payoutToken = IERC20(_payoutToken);
        hook = _hook;
    }

    // -------------------------------------------------------------------------
    // IILReserveVault — position lifecycle
    // -------------------------------------------------------------------------

    /// @inheritdoc IILReserveVault
    function recordPosition(bytes32 positionId, address lp, int24 entryTick, uint128 liquidity)
        external
        override
        onlyHook
    {
        if (_positions[positionId].exists) revert PositionAlreadyExists(positionId);

        _positions[positionId] = VaultPosition({
            exists: true,
            lp: lp,
            entryTick: entryTick,
            liquidity: liquidity,
            entryBlock: block.number
        });

        // Increase liability by the worst-case claim for this position
        totalLiability += _worstCaseClaim(liquidity);

        // Liability just increased — check if capture rate needs adjusting
        _autoAdjustCaptureRate();

        emit PositionRecorded(positionId, lp, entryTick, block.number);
    }

    /// @inheritdoc IILReserveVault
    function settlePosition(bytes32 positionId, int24 exitTick, address recipient)
        external
        override
        onlyHook
        nonReentrant
        returns (uint256 payout)
    {
        VaultPosition memory pos = _positions[positionId];
        if (!pos.exists) revert PositionNotFound(positionId);

        // Remove position and reduce liability before computing payout
        delete _positions[positionId];
        uint256 worstCase = _worstCaseClaim(pos.liquidity);
        totalLiability = totalLiability > worstCase ? totalLiability - worstCase : 0;

        uint256 ilFactor = _computeILFactor(pos.entryTick, exitTick);
        uint256 loyaltyFactor = _computeLoyaltyFactor(pos.entryBlock);
        uint256 healthRatio = _cappedHealthRatio();

        // Cascade multiply: each step scales down from liquidity
        uint256 rawClaim = FullMath.mulDiv(uint256(pos.liquidity), ilFactor, 1e18);
        uint256 loyaltyAdjusted = FullMath.mulDiv(rawClaim, loyaltyFactor, 1e18);
        payout = FullMath.mulDiv(loyaltyAdjusted, healthRatio, 1e18);

        // Cap at MAX_SINGLE_CLAIM_PCT of reserve — no single LP drains the vault
        uint256 maxPayout = FullMath.mulDiv(totalReserveBalance, MAX_SINGLE_CLAIM_PCT, 1e18);
        if (payout > maxPayout) payout = maxPayout;

        // Hard floor: never pay more than what's actually in the reserve
        if (payout > totalReserveBalance) payout = totalReserveBalance;

        if (payout > 0) {
            totalReserveBalance -= payout;
            payoutToken.safeTransfer(recipient, payout);
        }

        emit VaultPayout(pos.lp, ilFactor, loyaltyFactor, payout);
    }

    // -------------------------------------------------------------------------
    // IILReserveVault — vault funding
    // -------------------------------------------------------------------------

    /// @inheritdoc IILReserveVault
    /// @dev The hook must approve this vault before calling. Pulls tokens via transferFrom.
    function deposit(address token, uint256 amount) external override onlyHook {
        if (token != address(payoutToken)) revert WrongToken(token, address(payoutToken));
        if (amount == 0) revert ZeroAmount();

        payoutToken.safeTransferFrom(msg.sender, address(this), amount);
        totalReserveBalance += amount;
        _autoAdjustCaptureRate();

        emit VaultDeposit(token, amount, totalReserveBalance);
    }

    // -------------------------------------------------------------------------
    // IILReserveVault — Reactive callbacks
    // -------------------------------------------------------------------------

    /// @inheritdoc IILReserveVault
    function setCaptureRate(uint256 newRateBps) external override onlyHook {
        if (newRateBps > MAX_CAPTURE_RATE_BPS) revert CaptureRateTooHigh(newRateBps, MAX_CAPTURE_RATE_BPS);
        uint256 old = _captureRateBps;
        _captureRateBps = newRateBps;
        emit CaptureRateUpdated(old, newRateBps);
    }

    // -------------------------------------------------------------------------
    // IILReserveVault — views
    // -------------------------------------------------------------------------

    /// @inheritdoc IILReserveVault
    function captureRateBps() external view override returns (uint256) {
        return _captureRateBps;
    }

    /// @inheritdoc IILReserveVault
    function totalReserve(address token) external view override returns (uint256) {
        return token == address(payoutToken) ? totalReserveBalance : 0;
    }

    /// @inheritdoc IILReserveVault
    /// @dev Returns 1e18 (neutral) when there are no open positions (no liability).
    function vaultHealthRatio() public view override returns (uint256) {
        if (totalLiability == 0) return 1e18;
        return FullMath.mulDiv(totalReserveBalance, 1e18, totalLiability);
    }

    /// @inheritdoc IILReserveVault
    function previewPayout(bytes32 positionId, int24 currentTick) external view override returns (uint256) {
        VaultPosition memory pos = _positions[positionId];
        if (!pos.exists) return 0;

        uint256 ilFactor = _computeILFactor(pos.entryTick, currentTick);
        uint256 loyaltyFactor = _computeLoyaltyFactor(pos.entryBlock);
        uint256 healthRatio = _cappedHealthRatio();

        uint256 rawClaim = FullMath.mulDiv(uint256(pos.liquidity), ilFactor, 1e18);
        uint256 loyaltyAdjusted = FullMath.mulDiv(rawClaim, loyaltyFactor, 1e18);
        uint256 estimated = FullMath.mulDiv(loyaltyAdjusted, healthRatio, 1e18);

        uint256 maxPayout = FullMath.mulDiv(totalReserveBalance, MAX_SINGLE_CLAIM_PCT, 1e18);
        return estimated > maxPayout ? maxPayout : estimated;
    }

    /// @inheritdoc IILReserveVault
    function positionExists(bytes32 positionId) external view override returns (bool) {
        return _positions[positionId].exists;
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    function _computeILFactor(int24 entryTick, int24 exitTick) internal pure returns (uint256) {
        int24 diff = entryTick >= exitTick ? entryTick - exitTick : exitTick - entryTick;
        uint256 absDiff = uint256(int256(diff));
        uint256 factor = absDiff * IL_PER_TICK;
        return factor > MAX_IL_FACTOR ? MAX_IL_FACTOR : factor;
    }

    function _computeLoyaltyFactor(uint256 entryBlock) internal view returns (uint256) {
        uint256 blocksHeld = block.number - entryBlock;
        if (blocksHeld >= LOYALTY_TARGET_BLOCKS) return 1e18;
        return FullMath.mulDiv(blocksHeld, 1e18, LOYALTY_TARGET_BLOCKS);
    }

    /// @dev Health capped at 1e18 for payout — overfunding doesn't pay >100% of IL
    function _cappedHealthRatio() internal view returns (uint256) {
        uint256 h = vaultHealthRatio();
        return h > 1e18 ? 1e18 : h;
    }

    /// @dev Worst-case claim for a position = liquidity * MAX_IL_FACTOR / 1e18
    function _worstCaseClaim(uint128 liquidity) internal pure returns (uint256) {
        return FullMath.mulDiv(uint256(liquidity), MAX_IL_FACTOR, 1e18);
    }

    function _autoAdjustCaptureRate() internal {
        uint256 health = vaultHealthRatio();
        uint256 newRate;

        if (health >= HEALTH_LOW) {
            newRate = CAPTURE_NORMAL_BPS;
        } else if (health >= HEALTH_EMERGENCY) {
            newRate = CAPTURE_LOW_BPS;
        } else {
            newRate = CAPTURE_EMERGENCY_BPS;
        }

        if (newRate != _captureRateBps) {
            emit CaptureRateUpdated(_captureRateBps, newRate);
            _captureRateBps = newRate;
        }
    }
}

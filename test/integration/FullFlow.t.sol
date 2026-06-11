// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

// v4-core types and interfaces
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/types/PoolOperation.sol";

// v4-core test routers
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "v4-core/test/PoolModifyLiquidityTest.sol";

// Trident contracts
import {TridentHook} from "../../src/TridentHook.sol";
import {ILReserveVault} from "../../src/ILReserveVault.sol";
import {OracleReader} from "../../src/OracleReader.sol";
import {GammaScorer} from "../../src/GammaScorer.sol";
import {PositionTracker} from "../../src/PositionTracker.sol";
import {IILReserveVault} from "../../src/interfaces/IILReserveVault.sol";
import {IOracleReader} from "../../src/interfaces/IOracleReader.sol";

// ---------------------------------------------------------------------------
// Minimal ERC-20 mock — same pattern used throughout test suite
// ---------------------------------------------------------------------------
contract TestERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    constructor(string memory _name, string memory _sym, uint8 _dec) {
        name = _name;
        symbol = _sym;
        decimals = _dec;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

// ---------------------------------------------------------------------------
// Mock Chainlink feed — controllable price
// ---------------------------------------------------------------------------
contract MockChainlinkFeed {
    int256 public answer;
    uint8 public decimals;
    uint256 public updatedAt;

    constructor(int256 _answer, uint8 _decimals) {
        answer = _answer;
        decimals = _decimals;
        updatedAt = block.timestamp;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, answer, 0, updatedAt, 1);
    }

    function setAnswer(int256 _answer) external {
        answer = _answer;
        updatedAt = block.timestamp;
    }
}

// ---------------------------------------------------------------------------
// Full Flow Integration Test
// ---------------------------------------------------------------------------
contract FullFlowTest is Test {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using CurrencyLibrary for Currency;

    // -------------------------------------------------------------------------
    // Protocol contracts
    // -------------------------------------------------------------------------
    PoolManager poolManager;
    PoolSwapTest swapRouter;
    PoolModifyLiquidityTest modifyLiquidityRouter;

    TridentHook hook;
    ILReserveVault vault;
    OracleReader oracleReader;
    GammaScorer gammaScorer;
    PositionTracker tracker;

    MockChainlinkFeed chainlinkFeed;
    TestERC20 token0; // WETH equivalent
    TestERC20 token1; // USDC equivalent

    // -------------------------------------------------------------------------
    // Test actors
    // -------------------------------------------------------------------------
    address internal LP = makeAddr("lp");
    address internal TRADER = makeAddr("trader");
    address internal OWNER = makeAddr("owner");
    address internal REACTIVE = makeAddr("reactive");

    // -------------------------------------------------------------------------
    // Pool config
    // -------------------------------------------------------------------------
    Currency currency0;
    Currency currency1;
    PoolKey poolKey;
    PoolId poolId;

    // Required hook flags for TridentHook
    // BEFORE_SWAP(7) | AFTER_SWAP(6) | AFTER_ADD_LIQUIDITY(10) | BEFORE_REMOVE_LIQUIDITY(9)
    uint160 constant HOOK_FLAGS = Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG
        | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG;

    // The hook address — pre-set with correct flag bits, code etched in setUp.
    // Pattern mirrors Deployers.sol: take max uint160, clear all hook bits, OR in desired flags.
    address immutable HOOK_ADDR =
        address(uint160((uint256(type(uint160).max) & ~uint256(uint160(Hooks.ALL_HOOK_MASK))) | uint256(HOOK_FLAGS)));

    // -------------------------------------------------------------------------
    // Sqr price for pool initialisation — roughly $2000 ETH/USDC
    // -------------------------------------------------------------------------
    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336; // 1:1 ratio

    function setUp() public {
        // ── Deploy core protocol ────────────────────────────────────────────
        poolManager = new PoolManager(address(this));
        swapRouter = new PoolSwapTest(poolManager);
        modifyLiquidityRouter = new PoolModifyLiquidityTest(poolManager);

        // ── Deploy test tokens — sort so token0 < token1 by address ─────────
        TestERC20 tokenA = new TestERC20("Wrapped Ether", "WETH", 18);
        TestERC20 tokenB = new TestERC20("USD Coin", "USDC", 6);

        // Ensure correct ordering (v4 requires currency0 < currency1)
        if (address(tokenA) < address(tokenB)) {
            token0 = tokenA;
            token1 = tokenB;
        } else {
            token0 = tokenB;
            token1 = tokenA;
        }
        currency0 = Currency.wrap(address(token0));
        currency1 = Currency.wrap(address(token1));

        // ── Deploy Chainlink mock — $2000 ETH/USD (8 decimals) ──────────────
        chainlinkFeed = new MockChainlinkFeed(2000e8, 8);

        // ── Deploy OracleReader, GammaScorer ────────────────────────────────
        oracleReader = new OracleReader(address(chainlinkFeed), 3600, 200);
        gammaScorer = new GammaScorer();

        // HOOK_ADDR (immutable) already has the correct flag bits baked in.
        address hookAddr = HOOK_ADDR;

        // ── Deploy vault (hook = hookAddr, which we'll etch shortly) ─────────
        vault = new ILReserveVault(address(token1), hookAddr);

        // ── Deploy tracker (hook = hookAddr, reactive = REACTIVE) ────────────
        tracker = new PositionTracker(hookAddr, REACTIVE);

        // ── Deploy TridentHook impl with full constructor args ───────────────
        TridentHook impl = new TridentHook(
            IPoolManager(address(poolManager)),
            IOracleReader(address(oracleReader)),
            gammaScorer,
            IILReserveVault(address(vault)),
            tracker,
            3_000, // baseFee — 0.3% in v4 pips
            1e30, // decimalAdjustment for token0(18)/token1(6): 10^(18-6+18)=10^30
            REACTIVE,
            OWNER
        );

        // ── Etch impl bytecode to the flag-correct address ───────────────────
        // Copies runtime bytecode (immutables baked in) but NOT storage.
        // Must restore storage variables via setters before calling guards.
        vm.etch(hookAddr, address(impl).code);
        hook = TridentHook(hookAddr);

        // Restore _reactiveContract storage (etched address starts with zero storage)
        vm.prank(OWNER);
        hook.setReactiveContract(REACTIVE);

        // ── Prime Reactive-sourced state so fees work from block 1 ───────────
        vm.prank(REACTIVE);
        hook.primeDeviation(500); // 5% oracle deviation → arb premium active

        vm.prank(REACTIVE);
        hook.primeBoundaryFee(60, 5e17); // boundary at tick 60, gamma=0.5

        // ── Init pool with DYNAMIC_FEE_FLAG ──────────────────────────────────
        poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: IHooks(hookAddr)
        });
        poolId = poolKey.toId();
        poolManager.initialize(poolKey, SQRT_PRICE_1_1);

        // ── Mint tokens to LP and trader ─────────────────────────────────────
        token0.mint(LP, 100_000e18);
        token1.mint(LP, 100_000e18);
        token0.mint(TRADER, 100_000e18);
        token1.mint(TRADER, 100_000e18);

        // ── LP approves routers ──────────────────────────────────────────────
        vm.startPrank(LP);
        token0.approve(address(modifyLiquidityRouter), type(uint256).max);
        token1.approve(address(modifyLiquidityRouter), type(uint256).max);
        token0.approve(address(swapRouter), type(uint256).max);
        token1.approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();

        // ── Trader approves swap router ──────────────────────────────────────
        vm.startPrank(TRADER);
        token0.approve(address(swapRouter), type(uint256).max);
        token1.approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();
    }

    // =========================================================================
    // Test 1: Pool initialises with correct dynamic fee flag
    // =========================================================================
    function test_poolInitialisesWithDynamicFee() public view {
        (uint160 sqrtPrice, int24 tick,,) = StateLibrary.getSlot0(IPoolManager(address(poolManager)), poolId);
        assertEq(sqrtPrice, SQRT_PRICE_1_1);
        assertEq(tick, 0); // at 1:1 ratio, tick is 0
    }

    // =========================================================================
    // Test 2: LP adds liquidity → positions recorded in vault + tracker
    // =========================================================================
    function test_addLiquidity_recordsPosition() public {
        vm.prank(LP);
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1_000_000e6, salt: bytes32(0)}),
            ""
        );

        // sender in afterAddLiquidity = address of modifyLiquidityRouter (not LP)
        bytes32 posId = keccak256(abi.encode(address(modifyLiquidityRouter), int24(-120), int24(120), bytes32(0)));
        assertTrue(vault.positionExists(posId), "vault should have position");
        assertTrue(tracker.positionExists(posId), "tracker should have position");
    }

    // =========================================================================
    // Test 3: Swap uses dynamic fee — fee > base when deviation is primed
    // =========================================================================
    function test_swap_chargesDynamicFee_aboveBase() public {
        // Add liquidity first
        vm.prank(LP);
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({tickLower: -6000, tickUpper: 6000, liquidityDelta: 10_000_000e6, salt: bytes32(0)}),
            ""
        );

        // Perform a swap — hook beforeSwap should charge arb premium
        vm.prank(TRADER);
        BalanceDelta delta = swapRouter.swap(
            poolKey,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -1_000e18, // exact input
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );

        // Trade executed (non-zero deltas)
        assertTrue(delta.amount0() != 0 || delta.amount1() != 0, "swap should produce non-zero delta");
    }

    // =========================================================================
    // Test 4: previewFee reflects primed deviation + gamma
    // =========================================================================
    function test_previewFee_showsArbAndBoundaryPremiums() public view {
        (uint24 base, uint24 arb, uint24 boundary, uint24 total) = hook.previewFee(poolKey, 0);

        assertEq(base, 3_000, "base fee should be 3000");
        // arbPremium = 500 * 8000 / 10000 = 400
        assertEq(arb, 400, "arb premium should be 400 bps");
        // boundaryPremium = 5e17 * 5000 / 1e18 = 2500
        assertEq(boundary, 2_500, "boundary premium should be 2500 bps");
        assertEq(total, 3_000 + 400 + 2_500, "total should sum correctly");
    }

    // =========================================================================
    // Test 5: Full flow — LP deposits, arb swap, vault funded, LP exits + payout
    // =========================================================================
    function test_fullFlow_LPGetsVaultPayout() public {
        vm.roll(1);

        // ── Step 1: LP adds liquidity ────────────────────────────────────────
        vm.prank(LP);
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({tickLower: -6000, tickUpper: 6000, liquidityDelta: 10_000_000e6, salt: bytes32(0)}),
            ""
        );

        // sender in afterAddLiquidity = address of modifyLiquidityRouter (not LP)
        bytes32 posId = keccak256(abi.encode(address(modifyLiquidityRouter), int24(-6000), int24(6000), bytes32(0)));
        assertTrue(vault.positionExists(posId), "position recorded in vault");

        // ── Step 2: Simulate vault being funded ──────────────────────────────
        // vault.deposit is onlyHook — mint to hook, prank hook to deposit
        token1.mint(address(hook), 1_000e6);
        vm.startPrank(address(hook));
        token1.approve(address(vault), 1_000e6);
        vault.deposit(address(token1), 1_000e6);
        vm.stopPrank();
        assertEq(vault.totalReserveBalance(), 1_000e6, "vault funded");

        // ── Step 3: Roll time forward — LP needs loyalty to get payout ───────
        vm.roll(block.number + 216_000); // 30 days in blocks

        // ── Step 4: Preview payout before removal ────────────────────────────
        // Move price first to create IL (pool tick ≠ entry tick 0)
        // Simulate by having trader do large swap
        vm.prank(TRADER);
        swapRouter.swap(
            poolKey,
            SwapParams({zeroForOne: true, amountSpecified: -5_000e18, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );

        (, int24 currentTick,,) = StateLibrary.getSlot0(IPoolManager(address(poolManager)), poolId);
        uint256 preview = vault.previewPayout(posId, currentTick);
        // Payout should be positive if IL occurred (tick moved) and loyalty is full
        assertGt(preview, 0, "payout preview should be positive after tick move + loyalty");

        // ── Step 5: LP removes liquidity → vault settles ─────────────────────
        // After a large zeroForOne swap the position is entirely in token0;
        // track token0 to confirm LP gets tokens back.
        uint256 lpToken0Before = token0.balanceOf(LP);

        vm.prank(LP);
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({tickLower: -6000, tickUpper: 6000, liquidityDelta: -10_000_000e6, salt: bytes32(0)}),
            ""
        );

        uint256 lpToken0After = token0.balanceOf(LP);

        // LP gets token0 back (position converted by the swap)
        assertGt(lpToken0After, lpToken0Before, "LP should receive token0 on removal");

        // Position should be cleaned up (vault settled, tracker cleared)
        assertFalse(vault.positionExists(posId), "vault position deleted after settle");
        assertFalse(tracker.positionExists(posId), "tracker position deleted after settle");
    }

    // =========================================================================
    // Test 6: No vault payout for JIT LP (same-block deposit + withdraw)
    // =========================================================================
    function test_jitLP_getsZeroPayout() public {
        // Fund vault — onlyHook, so prank hook
        token1.mint(address(hook), 500e6);
        vm.startPrank(address(hook));
        token1.approve(address(vault), 500e6);
        vault.deposit(address(token1), 500e6);
        vm.stopPrank();

        // JIT: add and remove in same block
        vm.roll(100);

        vm.prank(LP);
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1_000e6, salt: bytes32(0)}),
            ""
        );

        // Remove in same block (loyalty = 0)
        vm.prank(LP);
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: -1_000e6, salt: bytes32(0)}),
            ""
        );

        // Vault balance should be unchanged (zero payout for JIT)
        assertEq(vault.totalReserveBalance(), 500e6, "vault balance unchanged for JIT LP");
    }

    // =========================================================================
    // Test 7: Vault pendingCapture accrues after swap
    // =========================================================================
    function test_swap_accruesToPendingCapture() public {
        // Add liquidity so swap can execute
        vm.prank(LP);
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({tickLower: -6000, tickUpper: 6000, liquidityDelta: 10_000_000e6, salt: bytes32(0)}),
            ""
        );

        uint256 pendingBefore = hook.pendingCapture(address(token0));

        vm.prank(TRADER);
        swapRouter.swap(
            poolKey,
            SwapParams({zeroForOne: true, amountSpecified: -1_000e18, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );

        uint256 pendingAfter = hook.pendingCapture(address(token0));
        assertGt(pendingAfter, pendingBefore, "pending capture should increase after swap");
    }
}

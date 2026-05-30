// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {TridentHook} from "../../src/TridentHook.sol";
import {IReactiveCallback} from "../../src/interfaces/IReactiveCallback.sol";
import {ITridentHook} from "../../src/interfaces/ITridentHook.sol";
import {IILReserveVault} from "../../src/interfaces/IILReserveVault.sol";
import {IOracleReader} from "../../src/interfaces/IOracleReader.sol";
import {GammaScorer} from "../../src/GammaScorer.sol";
import {PositionTracker} from "../../src/PositionTracker.sol";
import {ILReserveVault} from "../../src/ILReserveVault.sol";

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

// ---------------------------------------------------------------------------
// Minimal mocks — only implement what TridentHook calls
// ---------------------------------------------------------------------------

contract MockPoolManager {
    // TridentHook only calls getSlot0 via StateLibrary (extsload)
    // For unit tests we don't exercise beforeSwap/afterSwap through PoolManager,
    // so a stub address is sufficient for construction.
}

contract MockOracleReader is IOracleReader {
    uint256 public price = 2000e18;
    uint256 public deviationBps;
    bool public manipulated;

    function getPrice() external view override returns (uint256) { return price; }
    function getDeviationBps(uint256) external view override returns (uint256) { return deviationBps; }
    function isOracleManipulated(uint256) external view override returns (bool) { return manipulated; }

    function setDeviation(uint256 bps) external { deviationBps = bps; }
}

contract MockERC20Min {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amt) external { balanceOf[to] += amt; }
    function approve(address s, uint256 a) external returns (bool) { allowance[msg.sender][s] = a; return true; }
    function transfer(address to, uint256 a) external returns (bool) {
        balanceOf[msg.sender] -= a; balanceOf[to] += a; return true;
    }
    function transferFrom(address f, address t, uint256 a) external returns (bool) {
        balanceOf[f] -= a; allowance[f][msg.sender] -= a; balanceOf[t] += a; return true;
    }
}

// ---------------------------------------------------------------------------
// Test contract
// ---------------------------------------------------------------------------
contract TridentHookTest is Test {
    TridentHook internal hook;
    MockOracleReader internal oracle;
    GammaScorer internal scorer;
    ILReserveVault internal vault;
    PositionTracker internal tracker;
    MockERC20Min internal token;

    address internal reactiveContract;
    address internal unauthorised;
    address internal owner;

    uint24 internal constant BASE_FEE = 3_000; // 0.3%

    function setUp() public {
        owner = makeAddr("owner");
        reactiveContract = makeAddr("reactive");
        unauthorised = makeAddr("unauthorised");

        oracle = new MockOracleReader();
        scorer = new GammaScorer();
        token = new MockERC20Min();

        // Deploy vault with address(this) as hook for now, we'll wire it up below
        vault = new ILReserveVault(address(token), address(this));

        // Deploy tracker with hook + reactive adapter
        tracker = new PositionTracker(address(this), reactiveContract);

        // Deploy TridentHook — poolManager is just a stub address for unit tests
        hook = new TridentHook(
            IPoolManager(address(0xdead)), // stub — not called in unit tests
            IOracleReader(address(oracle)),
            scorer,
            IILReserveVault(address(vault)),
            tracker,
            BASE_FEE,
            reactiveContract,
            owner
        );
    }

    // =========================================================================
    // Constants
    // =========================================================================

    function test_constants_correct() public view {
        assertEq(hook.MAX_FEE_BPS(), 50_000);
        assertEq(hook.ARB_AMPLIFIER(), 8_000);
        assertEq(hook.MAX_BOUNDARY_PREMIUM_BPS(), 5_000);
        assertEq(hook.LOYALTY_TARGET_BLOCKS(), 216_000);
        assertEq(hook.baseFee(), BASE_FEE);
        assertEq(hook.owner(), owner);
    }

    // =========================================================================
    // previewFee — fee computation via primed state
    // =========================================================================

    function _dummyKey() internal pure returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(1)),
            fee: 0x800000, // DYNAMIC_FEE_FLAG
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
    }

    function test_previewFee_baseFeeOnly_whenNoPrimed() public view {
        // Both primed values are 0 by default
        (uint24 base, uint24 arb, uint24 boundary, uint24 total) = hook.previewFee(_dummyKey(), 0);
        assertEq(base, BASE_FEE);
        assertEq(arb, 0);
        assertEq(boundary, 0);
        assertEq(total, BASE_FEE);
    }

    function test_previewFee_arbPremium_scales_withDeviation() public {
        vm.prank(reactiveContract);
        hook.primeDeviation(500); // 5% oracle deviation

        (, uint24 arb,, uint24 total) = hook.previewFee(_dummyKey(), 0);
        // arbPremium = 500 * 8000 / 10000 = 400 bps
        assertEq(arb, 400);
        assertEq(total, BASE_FEE + 400);
    }

    function test_previewFee_boundaryPremium_atMaxGamma() public {
        vm.prank(reactiveContract);
        hook.primeBoundaryFee(0, 1e18); // full gamma score

        (,, uint24 boundary,) = hook.previewFee(_dummyKey(), 0);
        // boundaryPremium = 1e18 * 5000 / 1e18 = 5000 bps
        assertEq(boundary, 5_000);
    }

    function test_previewFee_cappedAtMaxFee() public {
        // Set extreme deviation that would push total over MAX_FEE_BPS
        vm.prank(reactiveContract);
        hook.primeDeviation(100_000); // huge deviation

        (,,, uint24 total) = hook.previewFee(_dummyKey(), 0);
        assertLe(total, hook.MAX_FEE_BPS());
    }

    function test_previewFee_manipulationCapApplied() public {
        vm.prank(reactiveContract);
        hook.primeDeviation(10_000); // 100% deviation → huge arb premium
        vm.prank(reactiveContract);
        hook.setOracleManipulated(true);

        (,,, uint24 total) = hook.previewFee(_dummyKey(), 0);
        // When manipulated: cap at MANIPULATION_FEE_CAP_BPS = 3000
        assertLe(total, 3_000);
    }

    function test_previewFee_noManipulationCap_whenFalse() public {
        vm.prank(reactiveContract);
        hook.primeDeviation(1_000); // moderate deviation
        // oracleManipulated is false by default

        (,,, uint24 total) = hook.previewFee(_dummyKey(), 0);
        // Should NOT be capped by manipulation guard
        assertGt(total, BASE_FEE);
    }

    // =========================================================================
    // Reactive callbacks — access control
    // =========================================================================

    function test_primeDeviation_onlyReactive() public {
        vm.prank(unauthorised);
        vm.expectRevert(IReactiveCallback.OnlyReactiveContract.selector);
        hook.primeDeviation(500);
    }

    function test_primeDeviation_setsValue() public {
        vm.prank(reactiveContract);
        hook.primeDeviation(750);
        assertEq(hook.primedDeviationBps(), 750);
    }

    function test_primeBoundaryFee_onlyReactive() public {
        vm.prank(unauthorised);
        vm.expectRevert(IReactiveCallback.OnlyReactiveContract.selector);
        hook.primeBoundaryFee(100, 5e17);
    }

    function test_primeBoundaryFee_setsValues() public {
        vm.prank(reactiveContract);
        hook.primeBoundaryFee(-200, 7e17);
        assertEq(hook.primedBoundaryTick(), -200);
        assertEq(hook.primedGammaScore(), 7e17);
    }

    function test_primeBoundaryFee_emitsEvent() public {
        vm.prank(reactiveContract);
        vm.expectEmit(false, false, false, true);
        emit IReactiveCallback.BoundaryPrimed(-200, 7e17);
        hook.primeBoundaryFee(-200, 7e17);
    }

    function test_setOracleManipulated_onlyReactive() public {
        vm.prank(unauthorised);
        vm.expectRevert(IReactiveCallback.OnlyReactiveContract.selector);
        hook.setOracleManipulated(true);
    }

    function test_setOracleManipulated_setsFlag() public {
        assertFalse(hook.oracleManipulated());
        vm.prank(reactiveContract);
        hook.setOracleManipulated(true);
        assertTrue(hook.oracleManipulated());
    }

    function test_markOutOfRange_onlyReactive() public {
        vm.prank(unauthorised);
        vm.expectRevert(IReactiveCallback.OnlyReactiveContract.selector);
        hook.markOutOfRange(bytes32(uint256(1)), address(0xBEEF));
    }

    function test_updateCaptureRate_onlyReactive() public {
        vm.prank(unauthorised);
        vm.expectRevert(IReactiveCallback.OnlyReactiveContract.selector);
        hook.updateCaptureRate(1_500);
    }

    function test_setReactiveContract_onlyOwner() public {
        vm.prank(unauthorised);
        vm.expectRevert(TridentHook.OnlyOwner.selector);
        hook.setReactiveContract(address(0x1234));
    }

    function test_setReactiveContract_updatesAddress() public {
        address newReactive = makeAddr("newReactive");
        vm.prank(owner);
        hook.setReactiveContract(newReactive);

        // New reactive address can now call primeDeviation
        vm.prank(newReactive);
        hook.primeDeviation(100);
        assertEq(hook.primedDeviationBps(), 100);
    }

    function test_setReactiveContract_emitsEvent() public {
        address newReactive = makeAddr("newReactive");
        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit IReactiveCallback.ReactiveContractUpdated(reactiveContract, newReactive);
        hook.setReactiveContract(newReactive);
    }

    // =========================================================================
    // ITridentHook views
    // =========================================================================

    function test_vault_returnsCorrectAddress() public view {
        assertEq(hook.vault(), address(vault));
    }

    function test_oracleReader_returnsCorrectAddress() public view {
        assertEq(hook.oracleReader(), address(oracle));
    }

    function test_pendingCapture_startsAtZero() public view {
        assertEq(hook.pendingCapture(address(token)), 0);
    }

    // =========================================================================
    // getHookPermissions
    // =========================================================================

    function test_hookPermissions_correct() public view {
        (bool beforeSwap, bool afterSwap, bool afterAddLiq, bool beforeRemoveLiq) = (
            hook.getHookPermissions().beforeSwap,
            hook.getHookPermissions().afterSwap,
            hook.getHookPermissions().afterAddLiquidity,
            hook.getHookPermissions().beforeRemoveLiquidity
        );
        assertTrue(beforeSwap);
        assertTrue(afterSwap);
        assertTrue(afterAddLiq);
        assertTrue(beforeRemoveLiq);
        assertFalse(hook.getHookPermissions().beforeAddLiquidity);
        assertFalse(hook.getHookPermissions().afterRemoveLiquidity);
        assertFalse(hook.getHookPermissions().afterSwapReturnDelta);
    }

    // =========================================================================
    // Fuzz — fee computation properties
    // =========================================================================

    function testFuzz_previewFee_totalAlwaysGteBase(uint256 deviationBps, uint256 gammaScore) public {
        deviationBps = bound(deviationBps, 0, 1_000_000);
        gammaScore = bound(gammaScore, 0, 1e18);

        vm.prank(reactiveContract);
        hook.primeDeviation(deviationBps);
        vm.prank(reactiveContract);
        hook.primeBoundaryFee(0, gammaScore);

        (uint24 base,,, uint24 total) = hook.previewFee(_dummyKey(), 0);
        assertGe(total, base);
    }

    function testFuzz_previewFee_neverExceedsMaxFee(uint256 deviationBps, uint256 gammaScore) public {
        deviationBps = bound(deviationBps, 0, 10_000_000);
        gammaScore = bound(gammaScore, 0, 1e18);

        vm.prank(reactiveContract);
        hook.primeDeviation(deviationBps);
        vm.prank(reactiveContract);
        hook.primeBoundaryFee(0, gammaScore);

        (,,, uint24 total) = hook.previewFee(_dummyKey(), 0);
        assertLe(total, hook.MAX_FEE_BPS());
    }

    function testFuzz_previewFee_manipulationCapAlwaysRespected(uint256 deviationBps) public {
        deviationBps = bound(deviationBps, 0, 10_000_000);

        vm.prank(reactiveContract);
        hook.primeDeviation(deviationBps);
        vm.prank(reactiveContract);
        hook.setOracleManipulated(true);

        (,,, uint24 total) = hook.previewFee(_dummyKey(), 0);
        assertLe(total, 3_000); // MANIPULATION_FEE_CAP_BPS
    }

    function testFuzz_arbPremium_monotonicWithDeviation(uint256 dev1, uint256 dev2) public {
        dev1 = bound(dev1, 0, 100_000);
        dev2 = bound(dev2, dev1, 100_000);

        vm.prank(reactiveContract);
        hook.primeDeviation(dev1);
        (, uint24 arb1,,) = hook.previewFee(_dummyKey(), 0);

        vm.prank(reactiveContract);
        hook.primeDeviation(dev2);
        (, uint24 arb2,,) = hook.previewFee(_dummyKey(), 0);

        assertGe(arb2, arb1);
    }

    function testFuzz_boundaryPremium_monotonicWithGamma(uint256 g1, uint256 g2) public {
        g1 = bound(g1, 0, 1e18);
        g2 = bound(g2, g1, 1e18);

        vm.prank(reactiveContract);
        hook.primeBoundaryFee(0, g1);
        (,, uint24 b1,) = hook.previewFee(_dummyKey(), 0);

        vm.prank(reactiveContract);
        hook.primeBoundaryFee(0, g2);
        (,, uint24 b2,) = hook.previewFee(_dummyKey(), 0);

        assertGe(b2, b1);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PositionTracker} from "../../src/PositionTracker.sol";

contract PositionTrackerTest is Test {
    PositionTracker internal tracker;

    address internal reactiveAdapter;
    address internal unauthorised;

    // Shared test position data
    address internal constant LP = address(0xBEEF);
    int24 internal constant TICK_LOWER = -120;
    int24 internal constant TICK_UPPER = 120;
    int24 internal constant ENTRY_TICK = 10;
    uint128 internal constant LIQUIDITY = 1_000_000e18;
    bytes32 internal constant SALT = bytes32(uint256(1));

    bytes32 internal positionId;

    function setUp() public {
        reactiveAdapter = makeAddr("reactive");
        unauthorised = makeAddr("unauthorised");

        // Deploy with address(this) as the hook so we can call write functions directly
        tracker = new PositionTracker(address(this), reactiveAdapter);

        positionId = tracker.derivePositionId(LP, TICK_LOWER, TICK_UPPER, SALT);
    }

    // =========================================================================
    // recordEntry — unit tests
    // =========================================================================

    function test_recordEntry_storesAllFields() public {
        vm.roll(42); // set a known block number
        tracker.recordEntry(positionId, LP, TICK_LOWER, TICK_UPPER, ENTRY_TICK, LIQUIDITY);

        PositionTracker.Position memory p = tracker.getPosition(positionId);
        assertTrue(p.exists);
        assertEq(p.lp, LP);
        assertEq(p.tickLower, TICK_LOWER);
        assertEq(p.tickUpper, TICK_UPPER);
        assertEq(p.entryTick, ENTRY_TICK);
        assertEq(p.liquidity, LIQUIDITY);
        assertEq(p.entryBlock, 42);
        assertFalse(p.outOfRange);
    }

    function test_recordEntry_revertsOnDuplicate() public {
        tracker.recordEntry(positionId, LP, TICK_LOWER, TICK_UPPER, ENTRY_TICK, LIQUIDITY);
        vm.expectRevert(abi.encodeWithSelector(PositionTracker.PositionAlreadyExists.selector, positionId));
        tracker.recordEntry(positionId, LP, TICK_LOWER, TICK_UPPER, ENTRY_TICK, LIQUIDITY);
    }

    function test_recordEntry_revertsFromNonHook() public {
        vm.prank(unauthorised);
        vm.expectRevert(PositionTracker.OnlyHook.selector);
        tracker.recordEntry(positionId, LP, TICK_LOWER, TICK_UPPER, ENTRY_TICK, LIQUIDITY);
    }

    function test_recordEntry_emitsEvent() public {
        vm.roll(7);
        vm.expectEmit(true, true, false, true);
        emit PositionTracker.PositionRecorded(positionId, LP, ENTRY_TICK, 7);
        tracker.recordEntry(positionId, LP, TICK_LOWER, TICK_UPPER, ENTRY_TICK, LIQUIDITY);
    }

    // =========================================================================
    // getPosition — unit tests
    // =========================================================================

    function test_getPosition_revertsWhenNotFound() public {
        bytes32 unknown = keccak256("unknown");
        vm.expectRevert(abi.encodeWithSelector(PositionTracker.PositionNotFound.selector, unknown));
        tracker.getPosition(unknown);
    }

    // =========================================================================
    // positionExists — unit tests
    // =========================================================================

    function test_positionExists_trueAfterRecord() public {
        assertFalse(tracker.positionExists(positionId));
        tracker.recordEntry(positionId, LP, TICK_LOWER, TICK_UPPER, ENTRY_TICK, LIQUIDITY);
        assertTrue(tracker.positionExists(positionId));
    }

    function test_positionExists_falseAfterDelete() public {
        tracker.recordEntry(positionId, LP, TICK_LOWER, TICK_UPPER, ENTRY_TICK, LIQUIDITY);
        tracker.deletePosition(positionId);
        assertFalse(tracker.positionExists(positionId));
    }

    // =========================================================================
    // markOutOfRange — unit tests
    // =========================================================================

    function test_markOutOfRange_hookCanMark() public {
        tracker.recordEntry(positionId, LP, TICK_LOWER, TICK_UPPER, ENTRY_TICK, LIQUIDITY);
        tracker.markOutOfRange(positionId);
        assertTrue(tracker.getPosition(positionId).outOfRange);
    }

    function test_markOutOfRange_reactiveCanMark() public {
        tracker.recordEntry(positionId, LP, TICK_LOWER, TICK_UPPER, ENTRY_TICK, LIQUIDITY);
        vm.prank(reactiveAdapter);
        tracker.markOutOfRange(positionId);
        assertTrue(tracker.getPosition(positionId).outOfRange);
    }

    function test_markOutOfRange_revertsFromUnauthorised() public {
        tracker.recordEntry(positionId, LP, TICK_LOWER, TICK_UPPER, ENTRY_TICK, LIQUIDITY);
        vm.prank(unauthorised);
        vm.expectRevert(PositionTracker.OnlyHookOrReactive.selector);
        tracker.markOutOfRange(positionId);
    }

    function test_markOutOfRange_revertsWhenNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(PositionTracker.PositionNotFound.selector, positionId));
        tracker.markOutOfRange(positionId);
    }

    function test_markOutOfRange_emitsEvent() public {
        tracker.recordEntry(positionId, LP, TICK_LOWER, TICK_UPPER, ENTRY_TICK, LIQUIDITY);
        vm.expectEmit(true, false, false, false);
        emit PositionTracker.PositionMarkedOutOfRange(positionId);
        tracker.markOutOfRange(positionId);
    }

    // =========================================================================
    // deletePosition — unit tests
    // =========================================================================

    function test_deletePosition_removesRecord() public {
        tracker.recordEntry(positionId, LP, TICK_LOWER, TICK_UPPER, ENTRY_TICK, LIQUIDITY);
        tracker.deletePosition(positionId);
        assertFalse(tracker.positionExists(positionId));
    }

    function test_deletePosition_revertsWhenNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(PositionTracker.PositionNotFound.selector, positionId));
        tracker.deletePosition(positionId);
    }

    function test_deletePosition_revertsFromNonHook() public {
        tracker.recordEntry(positionId, LP, TICK_LOWER, TICK_UPPER, ENTRY_TICK, LIQUIDITY);
        vm.prank(unauthorised);
        vm.expectRevert(PositionTracker.OnlyHook.selector);
        tracker.deletePosition(positionId);
    }

    function test_deletePosition_allowsReRecordAfterDelete() public {
        tracker.recordEntry(positionId, LP, TICK_LOWER, TICK_UPPER, ENTRY_TICK, LIQUIDITY);
        tracker.deletePosition(positionId);
        // Should not revert — position slot is clean
        tracker.recordEntry(positionId, LP, TICK_LOWER, TICK_UPPER, ENTRY_TICK, LIQUIDITY);
        assertTrue(tracker.positionExists(positionId));
    }

    // =========================================================================
    // derivePositionId — unit tests
    // =========================================================================

    function test_derivePositionId_deterministic() public view {
        bytes32 id1 = tracker.derivePositionId(LP, TICK_LOWER, TICK_UPPER, SALT);
        bytes32 id2 = tracker.derivePositionId(LP, TICK_LOWER, TICK_UPPER, SALT);
        assertEq(id1, id2);
    }

    function test_derivePositionId_differentSalt_differentId() public view {
        bytes32 id1 = tracker.derivePositionId(LP, TICK_LOWER, TICK_UPPER, bytes32(uint256(1)));
        bytes32 id2 = tracker.derivePositionId(LP, TICK_LOWER, TICK_UPPER, bytes32(uint256(2)));
        assertNotEq(id1, id2);
    }

    function test_derivePositionId_differentLP_differentId() public {
        bytes32 id1 = tracker.derivePositionId(LP, TICK_LOWER, TICK_UPPER, SALT);
        address otherLp = makeAddr("other");
        bytes32 id2 = tracker.derivePositionId(otherLp, TICK_LOWER, TICK_UPPER, SALT);
        assertNotEq(id1, id2);
    }

    // =========================================================================
    // Constructor
    // =========================================================================

    function test_constructor_revertsOnZeroHook() public {
        vm.expectRevert(PositionTracker.ZeroAddress.selector);
        new PositionTracker(address(0), reactiveAdapter);
    }

    function test_constructor_revertsOnZeroReactive() public {
        vm.expectRevert(PositionTracker.ZeroAddress.selector);
        new PositionTracker(address(this), address(0));
    }

    // =========================================================================
    // Fuzz tests
    // =========================================================================

    function testFuzz_recordAndGet_roundtrip(
        address lp,
        int24 tickLower,
        int24 tickUpper,
        int24 entryTick,
        uint128 liquidity,
        bytes32 salt,
        uint256 blockNum
    ) public {
        vm.assume(lp != address(0));
        vm.assume(liquidity > 0);
        blockNum = bound(blockNum, 1, type(uint64).max);
        vm.roll(blockNum);

        bytes32 pid = tracker.derivePositionId(lp, tickLower, tickUpper, salt);
        tracker.recordEntry(pid, lp, tickLower, tickUpper, entryTick, liquidity);

        PositionTracker.Position memory p = tracker.getPosition(pid);
        assertEq(p.lp, lp);
        assertEq(p.tickLower, tickLower);
        assertEq(p.tickUpper, tickUpper);
        assertEq(p.entryTick, entryTick);
        assertEq(p.liquidity, liquidity);
        assertEq(p.entryBlock, blockNum);
        assertFalse(p.outOfRange);
    }

    function testFuzz_deletePosition_clearsExistence(bytes32 salt) public {
        bytes32 pid = tracker.derivePositionId(LP, TICK_LOWER, TICK_UPPER, salt);
        tracker.recordEntry(pid, LP, TICK_LOWER, TICK_UPPER, ENTRY_TICK, LIQUIDITY);
        assertTrue(tracker.positionExists(pid));
        tracker.deletePosition(pid);
        assertFalse(tracker.positionExists(pid));
    }

    function testFuzz_derivePositionId_uniquePerSalt(bytes32 salt1, bytes32 salt2) public view {
        vm.assume(salt1 != salt2);
        bytes32 id1 = tracker.derivePositionId(LP, TICK_LOWER, TICK_UPPER, salt1);
        bytes32 id2 = tracker.derivePositionId(LP, TICK_LOWER, TICK_UPPER, salt2);
        assertNotEq(id1, id2);
    }

    function testFuzz_derivePositionId_deterministicAcrossCalls(
        address lp,
        int24 tickLower,
        int24 tickUpper,
        bytes32 salt
    ) public view {
        assertEq(
            tracker.derivePositionId(lp, tickLower, tickUpper, salt),
            tracker.derivePositionId(lp, tickLower, tickUpper, salt)
        );
    }
}

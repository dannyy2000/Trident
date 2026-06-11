// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ILReserveVault} from "../../src/ILReserveVault.sol";
import {IILReserveVault} from "../../src/interfaces/IILReserveVault.sol";

// ---------------------------------------------------------------------------
// Minimal ERC-20 mock — mint, transfer, transferFrom, approve
// ---------------------------------------------------------------------------
contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "insufficient");
        require(allowance[from][msg.sender] >= amount, "not approved");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

// ---------------------------------------------------------------------------
// Tests — address(this) acts as the hook throughout
// ---------------------------------------------------------------------------
contract ILReserveVaultTest is Test {
    ILReserveVault internal vault;
    MockERC20 internal token;

    address internal constant LP = address(0xBEEF);
    address internal unauthorised = makeAddr("unauthorised");

    uint128 internal constant LIQUIDITY = 1_000_000e18;
    bytes32 internal constant POS_ID = bytes32(uint256(1));

    function setUp() public {
        token = new MockERC20();
        // address(this) is the hook
        vault = new ILReserveVault(address(token), address(this));
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    function _deposit(uint256 amount) internal {
        token.mint(address(this), amount);
        token.approve(address(vault), amount);
        vault.deposit(address(token), amount);
    }

    function _recordPosition(bytes32 id, int24 entryTick, uint128 liquidity) internal {
        vault.recordPosition(id, LP, entryTick, liquidity);
    }

    // =========================================================================
    // deposit — unit tests
    // =========================================================================

    function test_deposit_increasesReserve() public {
        _deposit(100e18);
        assertEq(vault.totalReserveBalance(), 100e18);
        assertEq(vault.totalReserve(address(token)), 100e18);
    }

    function test_deposit_revertsFromNonHook() public {
        token.mint(unauthorised, 100e18);
        vm.prank(unauthorised);
        vm.expectRevert(IILReserveVault.OnlyHook.selector);
        vault.deposit(address(token), 100e18);
    }

    function test_deposit_revertsOnWrongToken() public {
        address wrongToken = makeAddr("wrong");
        vm.expectRevert();
        vault.deposit(wrongToken, 100e18);
    }

    function test_deposit_revertsOnZeroAmount() public {
        vm.expectRevert(IILReserveVault.ZeroAmount.selector);
        vault.deposit(address(token), 0);
    }

    function test_deposit_emitsEvent() public {
        token.mint(address(this), 50e18);
        token.approve(address(vault), 50e18);
        vm.expectEmit(false, false, false, true);
        emit IILReserveVault.VaultDeposit(address(token), 50e18, 50e18);
        vault.deposit(address(token), 50e18);
    }

    function test_deposit_accumulatesAcrossMultipleCalls() public {
        _deposit(100e18);
        _deposit(200e18);
        assertEq(vault.totalReserveBalance(), 300e18);
    }

    // =========================================================================
    // recordPosition — unit tests
    // =========================================================================

    function test_recordPosition_increasesLiability() public {
        uint256 liabilityBefore = vault.totalLiability();
        _recordPosition(POS_ID, 0, LIQUIDITY);
        uint256 expectedWorstCase = LIQUIDITY * vault.MAX_IL_FACTOR() / 1e18;
        assertEq(vault.totalLiability(), liabilityBefore + expectedWorstCase);
    }

    function test_recordPosition_revertsOnDuplicate() public {
        _recordPosition(POS_ID, 0, LIQUIDITY);
        vm.expectRevert(abi.encodeWithSelector(IILReserveVault.PositionAlreadyExists.selector, POS_ID));
        _recordPosition(POS_ID, 0, LIQUIDITY);
    }

    function test_recordPosition_revertsFromNonHook() public {
        vm.prank(unauthorised);
        vm.expectRevert(IILReserveVault.OnlyHook.selector);
        vault.recordPosition(POS_ID, LP, 0, LIQUIDITY);
    }

    function test_recordPosition_emitsEvent() public {
        vm.roll(99);
        vm.expectEmit(true, true, false, true);
        emit IILReserveVault.PositionRecorded(POS_ID, LP, 0, 99);
        _recordPosition(POS_ID, 0, LIQUIDITY);
    }

    // =========================================================================
    // settlePosition — unit tests
    // =========================================================================

    function test_settlePosition_zeroPayoutForJIT() public {
        _deposit(1_000e18);
        _recordPosition(POS_ID, 0, LIQUIDITY);
        // JIT: same block, 0 blocks held → loyalty = 0 → payout = 0
        uint256 payout = vault.settlePosition(POS_ID, 100, LP);
        assertEq(payout, 0);
    }

    function test_settlePosition_fullLoyaltyLP() public {
        _deposit(1_000e18);
        _recordPosition(POS_ID, 0, LIQUIDITY);

        // Simulate 30 days of blocks held
        vm.roll(block.number + vault.LOYALTY_TARGET_BLOCKS());

        uint256 payout = vault.settlePosition(POS_ID, 1000, LP); // 1000 ticks moved
        assertGt(payout, 0);
        assertLe(payout, vault.MAX_SINGLE_CLAIM_PCT() * 1_000e18 / 1e18);
    }

    function test_settlePosition_deletesPosition() public {
        _deposit(100e18);
        _recordPosition(POS_ID, 0, LIQUIDITY);
        vault.settlePosition(POS_ID, 0, LP);
        // Trying to settle again should revert
        vm.expectRevert(abi.encodeWithSelector(IILReserveVault.PositionNotFound.selector, POS_ID));
        vault.settlePosition(POS_ID, 0, LP);
    }

    function test_settlePosition_decreasesLiability() public {
        _deposit(100e18);
        _recordPosition(POS_ID, 0, LIQUIDITY);
        uint256 liabilityAfterRecord = vault.totalLiability();
        vault.settlePosition(POS_ID, 0, LP);
        assertLt(vault.totalLiability(), liabilityAfterRecord);
    }

    function test_settlePosition_revertsWhenNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(IILReserveVault.PositionNotFound.selector, POS_ID));
        vault.settlePosition(POS_ID, 0, LP);
    }

    function test_settlePosition_revertsFromNonHook() public {
        _recordPosition(POS_ID, 0, LIQUIDITY);
        vm.prank(unauthorised);
        vm.expectRevert(IILReserveVault.OnlyHook.selector);
        vault.settlePosition(POS_ID, 0, LP);
    }

    function test_settlePosition_transfersTokensToRecipient() public {
        _deposit(1_000e18);
        _recordPosition(POS_ID, 0, LIQUIDITY);
        vm.roll(block.number + vault.LOYALTY_TARGET_BLOCKS());

        uint256 balanceBefore = token.balanceOf(LP);
        uint256 payout = vault.settlePosition(POS_ID, 5000, LP);
        assertEq(token.balanceOf(LP), balanceBefore + payout);
    }

    function test_settlePosition_reserveDecreasesExactlyByPayout() public {
        _deposit(1_000e18);
        _recordPosition(POS_ID, 0, LIQUIDITY);
        vm.roll(block.number + vault.LOYALTY_TARGET_BLOCKS());

        uint256 reserveBefore = vault.totalReserveBalance();
        uint256 payout = vault.settlePosition(POS_ID, 5000, LP);
        assertEq(vault.totalReserveBalance(), reserveBefore - payout);
    }

    function test_settlePosition_respectsMaxSingleClaimCap() public {
        _deposit(1_000e18);
        // Record a HUGE position
        _recordPosition(POS_ID, 0, type(uint128).max);
        vm.roll(block.number + vault.LOYALTY_TARGET_BLOCKS() * 10);

        uint256 maxAllowed = vault.MAX_SINGLE_CLAIM_PCT() * 1_000e18 / 1e18; // 10% of 1000e18 = 100e18
        uint256 payout = vault.settlePosition(POS_ID, 10_000, LP);
        assertLe(payout, maxAllowed);
    }

    function test_settlePosition_lowHealthReducesPayout() public {
        // Deposit a tiny amount against large liability → low health
        _deposit(1e18); // tiny reserve
        _recordPosition(POS_ID, 0, LIQUIDITY);
        bytes32 pos2 = bytes32(uint256(2));
        vault.recordPosition(pos2, LP, 0, LIQUIDITY * 100); // huge liability

        vm.roll(block.number + vault.LOYALTY_TARGET_BLOCKS());
        uint256 payout = vault.settlePosition(POS_ID, 5000, LP);

        // With low health, payout should be very small
        assertLt(payout, 0.1e18);
    }

    // =========================================================================
    // vaultHealthRatio — unit tests
    // =========================================================================

    function test_healthRatio_neutralWithNoLiability() public view {
        assertEq(vault.vaultHealthRatio(), 1e18);
    }

    function test_healthRatio_decreasesWithLiability() public {
        _deposit(100e18);
        _recordPosition(POS_ID, 0, LIQUIDITY);
        uint256 health = vault.vaultHealthRatio();
        // Reserve is 100e18, liability is LIQUIDITY * 0.5 = 500_000e18 → health << 1
        assertLt(health, 1e18);
    }

    function test_healthRatio_increasesWithDeposits() public {
        _recordPosition(POS_ID, 0, LIQUIDITY);
        _deposit(100e18);
        uint256 health1 = vault.vaultHealthRatio();
        _deposit(100e18);
        uint256 health2 = vault.vaultHealthRatio();
        assertGt(health2, health1);
    }

    // =========================================================================
    // captureRate auto-adjustment — unit tests
    // =========================================================================

    function test_captureRate_staysNormalWhenHealthy() public {
        // Large deposit relative to liability → healthy vault
        _deposit(1_000_000e18);
        _recordPosition(POS_ID, 0, 1); // tiny liquidity → tiny liability
        assertEq(vault.captureRateBps(), vault.CAPTURE_NORMAL_BPS());
    }

    function test_captureRate_elevatesWhenLow() public {
        // Create low health: tiny reserve, large liability
        _deposit(1e15); // dust reserve
        _recordPosition(POS_ID, 0, LIQUIDITY); // big liability
        // health < HEALTH_LOW → should trigger CAPTURE_LOW or CAPTURE_EMERGENCY
        uint256 rate = vault.captureRateBps();
        assertGe(rate, vault.CAPTURE_LOW_BPS());
    }

    function test_captureRate_emergencyWhenCritical() public {
        // vault health < 0.3 → emergency rate
        _deposit(1e12);
        _recordPosition(POS_ID, 0, LIQUIDITY);
        assertEq(vault.captureRateBps(), vault.CAPTURE_EMERGENCY_BPS());
    }

    // =========================================================================
    // setCaptureRate — unit tests
    // =========================================================================

    function test_setCaptureRate_works() public {
        vault.setCaptureRate(1500);
        assertEq(vault.captureRateBps(), 1500);
    }

    function test_setCaptureRate_revertsAboveMax() public {
        // Precompute before vm.expectRevert — otherwise the getter call consumes the expectRevert
        uint256 maxRate = vault.MAX_CAPTURE_RATE_BPS();
        vm.expectRevert();
        vault.setCaptureRate(maxRate + 1);
    }

    function test_setCaptureRate_revertsFromNonHook() public {
        vm.prank(unauthorised);
        vm.expectRevert(IILReserveVault.OnlyHook.selector);
        vault.setCaptureRate(1500);
    }

    // =========================================================================
    // previewPayout — unit tests
    // =========================================================================

    function test_previewPayout_returnsZeroForUnknown() public view {
        assertEq(vault.previewPayout(POS_ID, 0), 0);
    }

    function test_previewPayout_matchesSettlement() public {
        _deposit(1_000e18);
        _recordPosition(POS_ID, 100, LIQUIDITY);
        vm.roll(block.number + vault.LOYALTY_TARGET_BLOCKS());

        uint256 preview = vault.previewPayout(POS_ID, 1100); // 1000 ticks moved
        uint256 actual = vault.settlePosition(POS_ID, 1100, LP);
        assertEq(preview, actual);
    }

    // =========================================================================
    // Fuzz tests
    // =========================================================================

    function testFuzz_payout_neverExceedsReserve(uint256 depositAmount, uint256 tickMove, uint256 blocksHeld) public {
        depositAmount = bound(depositAmount, 1e6, 1_000_000e18);
        tickMove = bound(tickMove, 0, 50_000);
        blocksHeld = bound(blocksHeld, 0, vault.LOYALTY_TARGET_BLOCKS() * 2);

        _deposit(depositAmount);
        _recordPosition(POS_ID, 0, LIQUIDITY);

        vm.roll(block.number + blocksHeld);

        uint256 reserveBefore = vault.totalReserveBalance();
        uint256 payout = vault.settlePosition(POS_ID, int24(int256(tickMove)), LP);

        assertLe(payout, reserveBefore);
        assertEq(vault.totalReserveBalance(), reserveBefore - payout);
    }

    function testFuzz_payout_longerHoldNeverLessThanShorterHold(uint256 tickMove, uint256 blocks1, uint256 blocks2)
        public
    {
        tickMove = bound(tickMove, 1, 50_000);
        blocks1 = bound(blocks1, 0, vault.LOYALTY_TARGET_BLOCKS());
        blocks2 = bound(blocks2, blocks1, vault.LOYALTY_TARGET_BLOCKS());

        _deposit(10_000e18);

        // Single position — preview at blocks1 then again at blocks2 (same vault state)
        vm.roll(100);
        _recordPosition(POS_ID, 0, LIQUIDITY);

        vm.roll(100 + blocks1);
        uint256 preview1 = vault.previewPayout(POS_ID, int24(int256(tickMove)));

        vm.roll(100 + blocks2);
        uint256 preview2 = vault.previewPayout(POS_ID, int24(int256(tickMove)));

        // Longer hold → loyalty is higher or equal → payout is higher or equal
        assertGe(preview2, preview1);
    }

    function testFuzz_ilFactor_alwaysBounded(int24 entryTick, int24 exitTick) public {
        // Use the vault to expose the IL factor indirectly via deposit + settle
        // Direct test: record and settle same block with varied ticks to observe payout scaling
        _deposit(1_000_000e18);

        int24 entry = int24(int256(bound(int256(entryTick), -887_272, 887_272)));
        int24 exit_ = int24(int256(bound(int256(exitTick), -887_272, 887_272)));

        vault.recordPosition(POS_ID, LP, entry, 1e18); // small liquidity
        vm.roll(block.number + vault.LOYALTY_TARGET_BLOCKS());
        uint256 payout = vault.settlePosition(POS_ID, exit_, LP);

        // Payout should always be bounded by MAX_SINGLE_CLAIM_PCT of reserve
        uint256 maxAllowed = vault.MAX_SINGLE_CLAIM_PCT() * 1_000_000e18 / 1e18;
        assertLe(payout, maxAllowed);
    }

    function testFuzz_loyaltyFactor_zeroAtZeroBlocks(uint256 tickMove) public {
        tickMove = bound(tickMove, 1, 50_000);
        _deposit(1_000e18);

        // Record and settle in SAME block → loyalty = 0 → payout = 0
        vm.roll(999);
        vault.recordPosition(POS_ID, LP, 0, LIQUIDITY);
        uint256 payout = vault.settlePosition(POS_ID, int24(int256(tickMove)), LP);
        assertEq(payout, 0);
    }

    function testFuzz_totalReserve_tracksDepositsAccurately(uint256 a, uint256 b) public {
        a = bound(a, 1, 1_000e18);
        b = bound(b, 1, 1_000e18);
        _deposit(a);
        _deposit(b);
        assertEq(vault.totalReserveBalance(), a + b);
        assertEq(vault.totalReserve(address(token)), a + b);
    }

    function testFuzz_healthRatio_increasesMonotonicallyWithDeposits(uint256 baseDeposit, uint256 extraDeposit)
        public
    {
        baseDeposit = bound(baseDeposit, 1e6, 1_000e18);
        extraDeposit = bound(extraDeposit, 1e6, 1_000e18);

        _recordPosition(POS_ID, 0, LIQUIDITY);
        _deposit(baseDeposit);
        uint256 health1 = vault.vaultHealthRatio();
        _deposit(extraDeposit);
        uint256 health2 = vault.vaultHealthRatio();
        assertGe(health2, health1);
    }
}

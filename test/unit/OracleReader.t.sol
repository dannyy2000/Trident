// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {OracleReader} from "../../src/OracleReader.sol";

// ---------------------------------------------------------------------------
// Mock Chainlink feed — controllable answer, timestamp, and decimals
// ---------------------------------------------------------------------------
contract MockAggregatorV3 {
    int256 public answer;
    uint256 public updatedAt;
    uint8 private _decimals;

    constructor(int256 _answer, uint8 decimals_) {
        answer = _answer;
        updatedAt = block.timestamp;
        _decimals = decimals_;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, answer, 0, updatedAt, 1);
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function setAnswer(int256 _answer) external {
        answer = _answer;
    }

    function setUpdatedAt(uint256 _updatedAt) external {
        updatedAt = _updatedAt;
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
contract OracleReaderTest is Test {
    uint256 constant STALENESS = 3600; // 1 hour
    uint256 constant MANIPULATION_BPS = 200; // 2%

    MockAggregatorV3 internal feed;
    OracleReader internal oracle;

    function setUp() public {
        // Warp to a realistic timestamp so staleness arithmetic doesn't underflow
        // (Foundry starts at block.timestamp = 1; subtracting STALENESS would underflow)
        vm.warp(STALENESS * 10);
        // $2,100 with 8 decimals — standard Chainlink ETH/USD format
        feed = new MockAggregatorV3(2100e8, 8);
        oracle = new OracleReader(address(feed), STALENESS, MANIPULATION_BPS);
    }

    // =========================================================================
    // getPrice — unit tests
    // =========================================================================

    function test_getPrice_normalisesTo1e18() public view {
        // 2100 * 1e8 from feed, scaled up by 1e10 → 2100 * 1e18
        assertEq(oracle.getPrice(), 2100e18);
    }

    function test_getPrice_revertsWhenStale() public {
        feed.setUpdatedAt(block.timestamp - STALENESS - 1);
        vm.expectRevert();
        oracle.getPrice();
    }

    function test_getPrice_passesAtExactStalenessThreshold() public {
        // updatedAt = now - STALENESS  →  age == threshold  →  NOT stale (strictly greater reverts)
        feed.setUpdatedAt(block.timestamp - STALENESS);
        oracle.getPrice(); // should not revert
    }

    function test_getPrice_revertsOnZeroAnswer() public {
        feed.setAnswer(0);
        vm.expectRevert();
        oracle.getPrice();
    }

    function test_getPrice_revertsOnNegativeAnswer() public {
        feed.setAnswer(-1);
        vm.expectRevert();
        oracle.getPrice();
    }

    function test_getPrice_6decimalFeed() public {
        // Some Chainlink feeds use 6 decimals (e.g. USDC/USD on some chains)
        MockAggregatorV3 feed6 = new MockAggregatorV3(1e6, 6); // $1.00 at 6 decimals
        OracleReader oracle6 = new OracleReader(address(feed6), STALENESS, MANIPULATION_BPS);
        assertEq(oracle6.getPrice(), 1e18);
    }

    // =========================================================================
    // getDeviationBps — unit tests
    // =========================================================================

    function test_deviationBps_oracleAbovePool_5percent() public view {
        // oracle=2100, pool=2000 → diff=100, denom=2000 → 100*10000/2000 = 500 bps
        assertEq(oracle.getDeviationBps(2000e18), 500);
    }

    function test_deviationBps_zeroWhenEqual() public view {
        // oracle == pool → no deviation
        assertEq(oracle.getDeviationBps(2100e18), 0);
    }

    function test_deviationBps_oracleBelowPool() public view {
        // oracle=2100, pool=2205 → diff=105, denom=2205 → 105*10000/2205 = 476 bps
        assertEq(oracle.getDeviationBps(2205e18), 476);
    }

    function test_deviationBps_revertsOnZeroPoolPrice() public {
        vm.expectRevert();
        oracle.getDeviationBps(0);
    }

    function test_deviationBps_largeDeviation() public view {
        // oracle=2100, pool=1000 → diff=1100, denom=1000 → 11000 bps (110%)
        assertEq(oracle.getDeviationBps(1000e18), 11000);
    }

    function test_deviationBps_tinyDeviation() public view {
        // oracle=2100, pool=2101e18 → diff=1e18, denom=2101e18 → 1*10000/2101 = 4 bps
        assertEq(oracle.getDeviationBps(2101e18), 4);
    }

    // =========================================================================
    // isOracleManipulated — unit tests
    // =========================================================================

    function test_isManipulated_trueWhenLargeDeviation() public view {
        // oracle=2100e18, twap=2000e18 → 500bps > 200bps → true
        assertTrue(oracle.isOracleManipulated(2000e18));
    }

    function test_isManipulated_falseWhenSmallDeviation() public view {
        // oracle=2100e18, twap=2095e18 → ~23bps < 200bps → false
        assertFalse(oracle.isOracleManipulated(2095e18));
    }

    function test_isManipulated_falseWhenEqual() public view {
        assertFalse(oracle.isOracleManipulated(2100e18));
    }

    function test_isManipulated_falseOnZeroTwap() public view {
        // Zero TWAP only possible at pool genesis; safe default is false
        assertFalse(oracle.isOracleManipulated(0));
    }

    function test_isManipulated_respectsThreshold() public {
        // Use a higher threshold — same prices should now NOT be manipulated
        OracleReader oracle1000bps = new OracleReader(address(feed), STALENESS, 1000);
        // oracle=2100, twap=2000 → 500bps < 1000bps → false
        assertFalse(oracle1000bps.isOracleManipulated(2000e18));
    }

    // =========================================================================
    // getDeviationBps — fuzz tests
    // =========================================================================

    function testFuzz_deviationBps_neverReverts(uint256 poolPrice) public view {
        // Any non-zero pool price should never revert (oracle price is always fresh in setUp)
        vm.assume(poolPrice > 0 && poolPrice <= type(uint128).max);
        oracle.getDeviationBps(poolPrice);
    }

    function testFuzz_deviationBps_zeroWhenOraclePriceEqualsPoolPrice(uint256 rawAnswer) public {
        // Keep rawAnswer small enough that rawAnswer * 1e10 (poolPrice) stays in uint256
        rawAnswer = bound(rawAnswer, 1, 1e15);
        feed.setAnswer(int256(rawAnswer));
        // OracleReader scales by 1e10 (8 decimal feed), so 1e18 price = rawAnswer * 1e10
        uint256 poolPrice = rawAnswer * 1e10;
        assertEq(oracle.getDeviationBps(poolPrice), 0);
    }

    function testFuzz_deviationBps_zeroOnlyWhenPricesMatch(uint256 poolPrice) public view {
        // Deviation is 0 only when pool price is close enough to oracle that integer
        // truncation rounds to 0 bps (i.e. diff < poolPrice/10000). Outside that band it's > 0.
        vm.assume(poolPrice > 0 && poolPrice <= type(uint128).max);
        uint256 oraclePrice = oracle.getPrice(); // 2100e18
        uint256 diff = poolPrice >= oraclePrice ? poolPrice - oraclePrice : oraclePrice - poolPrice;
        uint256 dev = oracle.getDeviationBps(poolPrice);
        // If diff >= poolPrice/10000, deviation must be at least 1 bps
        if (diff >= poolPrice / 10_000) {
            assertGt(dev, 0);
        }
    }

    function testFuzz_deviationBps_increasesAsFurtherAboveOracle(uint256 multiplierBps) public view {
        // When pool > oracle: deviation = (pool - oracle)/pool = 1 - oracle/pool
        // As pool increases further above oracle, deviation increases monotonically
        multiplierBps = bound(multiplierBps, 10_002, 20_000);
        uint256 poolPriceHigh = 2100e18 * multiplierBps / 10_000;
        uint256 poolPriceLow = 2100e18 * 10_001 / 10_000; // just 0.01% above oracle
        uint256 devHigh = oracle.getDeviationBps(poolPriceHigh);
        uint256 devLow = oracle.getDeviationBps(poolPriceLow);
        assertGe(devHigh, devLow);
    }

    // =========================================================================
    // isOracleManipulated — fuzz tests
    // =========================================================================

    function testFuzz_isManipulated_neverReverts(uint256 twapPrice) public view {
        vm.assume(twapPrice <= type(uint128).max);
        // Must never revert regardless of twap input
        oracle.isOracleManipulated(twapPrice);
    }

    function testFuzz_isManipulated_trueWhenTwapFarBelow(uint256 twapPrice) public view {
        // oracle=2100e18. Any twap below half (1050e18) gives >100% deviation (>10000bps)
        // which is always > MANIPULATION_BPS (200), so must return true
        vm.assume(twapPrice > 0 && twapPrice < 1050e18);
        assertTrue(oracle.isOracleManipulated(twapPrice));
    }

    function testFuzz_isManipulated_falseWhenClose(uint256 twapPrice) public view {
        // Within 1% of oracle (2100e18 ± 21e18) → deviation < 100bps < 200bps → false
        twapPrice = bound(twapPrice, 2079e18, 2100e18);
        assertFalse(oracle.isOracleManipulated(twapPrice));
    }

    function testFuzz_isManipulated_consistentWithDeviationBps(uint256 twapPrice) public view {
        // isManipulated must agree with manual bps check
        vm.assume(twapPrice > 0 && twapPrice <= type(uint128).max);
        uint256 oraclePrice = oracle.getPrice();
        uint256 diff = oraclePrice >= twapPrice ? oraclePrice - twapPrice : twapPrice - oraclePrice;
        // Use same formula as contract
        bool expectedManipulated;
        if (twapPrice > 0) {
            uint256 divBps = diff * 10_000 / twapPrice;
            expectedManipulated = divBps > MANIPULATION_BPS;
        }
        assertEq(oracle.isOracleManipulated(twapPrice), expectedManipulated);
    }
}

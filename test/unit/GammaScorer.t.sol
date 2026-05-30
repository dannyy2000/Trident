// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {GammaScorer} from "../../src/GammaScorer.sol";

contract GammaScorerTest is Test {
    GammaScorer internal scorer;

    int24 constant TICK_SPACING = 60; // 0.30% pool

    function setUp() public {
        scorer = new GammaScorer();
    }

    // =========================================================================
    // Unit tests — computeGammaScore
    // =========================================================================

    function test_score_onBoundary() public view {
        // currentTick == boundaryTick → 0 spacings away → 1e18 / 1 = 1e18
        uint256 score = scorer.computeGammaScore(100, 100, TICK_SPACING);
        assertEq(score, 1e18);
    }

    function test_score_oneSpacingAway() public view {
        // 60 ticks away with spacing=60 → 1 spacing → 1e18 / 2 = 5e17
        uint256 score = scorer.computeGammaScore(160, 100, TICK_SPACING);
        assertEq(score, 5e17);
    }

    function test_score_twoSpacingsAway() public view {
        // 120 ticks away → 2 spacings → 1e18 / 3 = 333_333_333_333_333_333
        uint256 score = scorer.computeGammaScore(220, 100, TICK_SPACING);
        assertEq(score, uint256(1e18) / 3);
    }

    function test_score_tenSpacingsAway() public view {
        // 600 ticks away → 10 spacings → 1e18 / 11
        uint256 score = scorer.computeGammaScore(700, 100, TICK_SPACING);
        assertEq(score, uint256(1e18) / 11);
    }

    function test_score_currentBelowBoundary() public view {
        // Symmetric: below boundary gives same score as above
        uint256 scoreAbove = scorer.computeGammaScore(160, 100, TICK_SPACING);
        uint256 scoreBelow = scorer.computeGammaScore(40, 100, TICK_SPACING);
        assertEq(scoreAbove, scoreBelow);
    }

    function test_score_negativeTicks_oneSpacingAway() public view {
        // -100 to -160: diff=60, spacing=60 → 1 spacing → 1e18/2 = 5e17
        uint256 score = scorer.computeGammaScore(-100, -160, TICK_SPACING);
        assertEq(score, 5e17); // 60 ticks = 1 spacing → 1e18/2
    }

    function test_score_acrosszero() public view {
        // current=30, boundary=-30 → diff=60 → 1 spacing → 5e17
        uint256 score = scorer.computeGammaScore(30, -30, TICK_SPACING);
        assertEq(score, 5e17);
    }

    function test_score_partialSpacing_floorsToLower() public view {
        // 89 ticks away with spacing=60 → floor(89/60) = 1 spacing → 1e18/2
        uint256 score = scorer.computeGammaScore(189, 100, TICK_SPACING);
        assertEq(score, 5e17);
    }

    function test_score_differentTickSpacings() public view {
        // Same raw distance, different tick spacings → different scores
        // 60 ticks away: spacing=10 → 6 spacings → 1e18/7
        //                spacing=60 → 1 spacing  → 1e18/2
        uint256 scoreFineTier = scorer.computeGammaScore(160, 100, 10);
        uint256 scoreCoarseTier = scorer.computeGammaScore(160, 100, 60);
        assertLt(scoreFineTier, scoreCoarseTier);
        assertEq(scoreFineTier, uint256(1e18) / 7);
        assertEq(scoreCoarseTier, 5e17);
    }

    function test_score_revertsOnZeroTickSpacing() public {
        vm.expectRevert();
        scorer.computeGammaScore(100, 50, 0);
    }

    function test_score_revertsOnNegativeTickSpacing() public {
        vm.expectRevert();
        scorer.computeGammaScore(100, 50, -60);
    }

    function test_score_veryFarAway_approachesZero() public view {
        // 887220 ticks away (near max tick range) with spacing=60 → 14787 spacings → 1e18/14788 ≈ 67_624
        uint256 score = scorer.computeGammaScore(887220, 0, TICK_SPACING);
        assertGt(score, 0);
        assertLt(score, 1e14); // less than 0.01% of max score
    }

    // =========================================================================
    // Fuzz tests — computeGammaScore
    // =========================================================================

    function testFuzz_score_alwaysInRange(int24 current, int24 boundary, int24 spacing) public view {
        spacing = int24(int256(bound(int256(spacing), 1, 200)));
        // Bound ticks to valid Uniswap range to avoid int24 overflow on diff
        current = int24(int256(bound(int256(current), -887_000, 887_000)));
        boundary = int24(int256(bound(int256(boundary), -887_000, 887_000)));

        uint256 score = scorer.computeGammaScore(current, boundary, spacing);
        assertGe(score, 0);
        assertLe(score, 1e18);
    }

    function testFuzz_score_onBoundaryAlwaysMax(int24 tick, int24 spacing) public view {
        spacing = int24(int256(bound(int256(spacing), 1, 200)));
        tick = int24(int256(bound(int256(tick), -887_000, 887_000)));

        // When current == boundary, score is always exactly 1e18
        assertEq(scorer.computeGammaScore(tick, tick, spacing), 1e18);
    }

    function testFuzz_score_monotoneDecreasing(uint256 spacingsAway, int24 spacing) public view {
        spacing = int24(int256(bound(int256(spacing), 1, 200)));
        spacingsAway = bound(spacingsAway, 0, 1000);

        int24 boundary = 0;
        // dist1 and dist2 must stay within int24 bounds
        int24 dist1 = int24(int256(spacingsAway * uint256(int256(spacing))));
        int24 dist2 = int24(int256((spacingsAway + 1) * uint256(int256(spacing))));

        uint256 score1 = scorer.computeGammaScore(dist1, boundary, spacing);
        uint256 score2 = scorer.computeGammaScore(dist2, boundary, spacing);

        // Further away must be less than or equal (equal happens when floored spacing is same)
        assertGe(score1, score2);
    }

    function testFuzz_score_symmetric(int24 boundary, uint256 rawDiff, int24 spacing) public view {
        spacing = int24(int256(bound(int256(spacing), 1, 200)));
        rawDiff = bound(rawDiff, 0, 887_000);
        boundary = int24(int256(bound(int256(boundary), -443_000, 443_000)));

        int24 above = int24(int256(int256(boundary) + int256(rawDiff)));
        int24 below = int24(int256(int256(boundary) - int256(rawDiff)));

        uint256 scoreAbove = scorer.computeGammaScore(above, boundary, spacing);
        uint256 scoreBelow = scorer.computeGammaScore(below, boundary, spacing);

        // Symmetric: same distance above or below boundary → same score
        assertEq(scoreAbove, scoreBelow);
    }

    function testFuzz_score_neverReverts(int24 current, int24 boundary, int24 spacing) public view {
        spacing = int24(int256(bound(int256(spacing), 1, 887_272)));
        current = int24(int256(bound(int256(current), -887_272, 887_272)));
        boundary = int24(int256(bound(int256(boundary), -887_272, 887_272)));
        scorer.computeGammaScore(current, boundary, spacing);
    }
}

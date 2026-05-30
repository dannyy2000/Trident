// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title GammaScorer
/// @notice Pure-math contract that computes how exposed an LP position is to Gamma risk
///         based on how close the current pool price is to the nearest range boundary.
///
///         Formula (normalised to 1e18):
///             gammaScore = 1e18 / (tickSpacingsAway + 1)
///
///         Examples with tickSpacing = 60:
///             currentTick == boundaryTick          → 1e18   (100% — on the boundary)
///             60 ticks away  (1 spacing)            → 5e17   (50%)
///             600 ticks away (10 spacings)           → ~9.1e16 (9%)
///             6000 ticks away (100 spacings)         → ~9.9e15 (1%)
///
///         The hook multiplies this score by MAX_BOUNDARY_PREMIUM_BPS to get
///         the additional fee premium charged on swaps near a boundary cluster.
///
///         Normalising by tickSpacing is critical — a 0.05% pool (tickSpacing=10) and
///         a 0.30% pool (tickSpacing=60) have very different "steps per tick", so raw
///         tick distance alone would produce incomparable scores across fee tiers.
contract GammaScorer {
    error InvalidTickSpacing(int24 tickSpacing);

    /// @notice Computes the Gamma score for the current pool position.
    /// @param currentTick         The pool's current price tick (from slot0)
    /// @param nearestBoundaryTick The tick of the nearest LP range boundary (tickLower or tickUpper)
    /// @param tickSpacing         The pool's tick spacing — normalises score across fee tiers
    /// @return gammaScore         Scaled to 1e18. Higher = closer to boundary = more Gamma risk.
    function computeGammaScore(int24 currentTick, int24 nearestBoundaryTick, int24 tickSpacing)
        external
        pure
        returns (uint256 gammaScore)
    {
        if (tickSpacing <= 0) revert InvalidTickSpacing(tickSpacing);

        // Absolute tick distance — safe because valid Uniswap ticks are in [-887272, 887272]
        // so the max diff is 1_774_544, well within int24 range (8_388_607)
        int24 rawDiff = currentTick >= nearestBoundaryTick
            ? currentTick - nearestBoundaryTick
            : nearestBoundaryTick - currentTick;

        // How many full tick-spacing steps away is the boundary?
        // Integer division floors toward zero — a partial step counts as zero extra spacings.
        uint256 tickSpacingsAway = uint256(int256(rawDiff)) / uint256(int256(tickSpacing));

        // 1e18 / (d + 1): monotonically decreasing, max at d=0 (1e18), approaches 0
        gammaScore = 1e18 / (tickSpacingsAway + 1);
    }
}

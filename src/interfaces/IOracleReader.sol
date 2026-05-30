// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IOracleReader
/// @notice Abstraction over Chainlink price feeds with TWAP sanity check.
///         The hook calls this in beforeSwap to get the real-world price and
///         compute how far the pool price has drifted — that drift is the arb premium.
interface IOracleReader {
    /// @notice Returns the latest price from the primary oracle (Chainlink), expressed
    ///         in the same units as the pool's sqrtPriceX96 denominator.
    ///         Reverts if the price is stale (older than STALENESS_THRESHOLD).
    function getPrice() external view returns (uint256 price);

    /// @notice Computes the absolute percentage deviation between the oracle price
    ///         and the pool's current spot price, in basis points (1 bps = 0.01%).
    ///         e.g. oracle=$2100, pool=$2000 → 500 bps (5%)
    /// @param poolPrice The pool's current spot price in the same units as getPrice()
    /// @return deviationBps Deviation in basis points
    function getDeviationBps(uint256 poolPrice) external view returns (uint256 deviationBps);

    /// @notice Returns true if the Chainlink price and the pool's TWAP diverge by more
    ///         than the manipulation threshold. When true, the hook applies a fee cap
    ///         to prevent an attacker from manipulating the oracle to spike arb fees.
    /// @param twapPrice The pool's 5-minute TWAP price
    function isOracleManipulated(uint256 twapPrice) external view returns (bool);
}

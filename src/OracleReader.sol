// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IOracleReader} from "./interfaces/IOracleReader.sol";
import {FullMath} from "v4-core/libraries/FullMath.sol";

/// @dev Minimal Chainlink feed interface — avoids pulling the full chainlink package.
interface AggregatorV3Interface {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    function decimals() external view returns (uint8);
}

/// @title OracleReader
/// @notice Reads a Chainlink price feed and exposes two things the hook needs:
///         1. getDeviationBps  — how far the pool price is from the real-world price (→ arb premium)
///         2. isOracleManipulated — whether Chainlink and the pool TWAP diverge suspiciously (→ fee cap)
///
///         All prices are normalised to 1e18 so callers don't have to care about feed decimals.
contract OracleReader is IOracleReader {
    // -------------------------------------------------------------------------
    // Immutable configuration
    // -------------------------------------------------------------------------

    AggregatorV3Interface public immutable feed;

    /// @notice Maximum age of a Chainlink answer before it is considered stale
    uint256 public immutable STALENESS_THRESHOLD;

    /// @notice Deviation in bps above which oracle vs TWAP is treated as manipulation
    uint256 public immutable MANIPULATION_THRESHOLD_BPS;

    /// @dev Multiply raw Chainlink answer by this to get a 1e18-scaled price
    uint256 private immutable _scaleFactor;

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error StalePrice(uint256 updatedAt, uint256 currentTime, uint256 threshold);
    error InvalidPrice(int256 answer);
    error ZeroPoolPrice();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @param _feed                       Chainlink AggregatorV3 address
    /// @param _stalenessThreshold         Max age in seconds before price is stale (e.g. 3600)
    /// @param _manipulationThresholdBps   Bps divergence above which oracle is deemed manipulated (e.g. 200 = 2%)
    constructor(address _feed, uint256 _stalenessThreshold, uint256 _manipulationThresholdBps) {
        feed = AggregatorV3Interface(_feed);
        STALENESS_THRESHOLD = _stalenessThreshold;
        MANIPULATION_THRESHOLD_BPS = _manipulationThresholdBps;

        uint8 feedDecimals = AggregatorV3Interface(_feed).decimals();
        // feedDecimals is always ≤ 18 for every Chainlink feed in existence
        _scaleFactor = 10 ** (18 - uint256(feedDecimals));
    }

    // -------------------------------------------------------------------------
    // IOracleReader
    // -------------------------------------------------------------------------

    /// @inheritdoc IOracleReader
    function getPrice() external view override returns (uint256) {
        return _readPrice();
    }

    /// @inheritdoc IOracleReader
    function getDeviationBps(uint256 poolPrice) external view override returns (uint256 deviationBps) {
        if (poolPrice == 0) revert ZeroPoolPrice();
        uint256 oraclePrice = _readPrice();
        deviationBps = _absDiffBps(oraclePrice, poolPrice);
    }

    /// @inheritdoc IOracleReader
    /// @dev Returns false (not manipulated) when twapPrice == 0 to avoid division by zero.
    ///      The hook treats a false return as safe, so a zero TWAP causes normal (uncapped) fees
    ///      rather than a hard revert — acceptable because TWAP == 0 only at pool genesis.
    function isOracleManipulated(uint256 twapPrice) external view override returns (bool) {
        if (twapPrice == 0) return false;
        uint256 oraclePrice = _readPrice();
        return _absDiffBps(oraclePrice, twapPrice) > MANIPULATION_THRESHOLD_BPS;
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    function _readPrice() internal view returns (uint256) {
        (, int256 answer,, uint256 updatedAt,) = feed.latestRoundData();

        if (block.timestamp - updatedAt > STALENESS_THRESHOLD) {
            revert StalePrice(updatedAt, block.timestamp, STALENESS_THRESHOLD);
        }
        if (answer <= 0) revert InvalidPrice(answer);

        // FullMath.mulDiv uses 512-bit intermediate — safe against any realistic Chainlink price
        return FullMath.mulDiv(uint256(answer), _scaleFactor, 1);
    }

    /// @dev Returns |a - b| / b in bps. Denominator is always b.
    ///      For getDeviationBps: a=oracle, b=poolPrice → deviation relative to pool.
    ///      For isOracleManipulated: a=oracle, b=twapPrice → divergence relative to TWAP.
    function _absDiffBps(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 diff = a >= b ? a - b : b - a;
        return FullMath.mulDiv(diff, 10_000, b);
    }
}

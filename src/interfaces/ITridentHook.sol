// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "v4-core/types/PoolKey.sol";

/// @title ITridentHook
/// @notice Public view interface for the Trident hook.
///         Consumers (frontends, monitoring, Reactive) use this to read
///         live fee breakdown and system configuration without touching internals.
interface ITridentHook {
    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted on every swap with a full breakdown of how the fee was composed
    event SwapFeeBreakdown(
        bytes32 indexed poolId,
        uint24 baseFee,
        uint24 arbPremiumBps,
        uint24 boundaryPremiumBps,
        uint24 totalFee,
        uint256 vaultCapture
    );

    /// @notice Emitted when the oracle manipulation guard trips and the fee is capped
    event OracleManipulationGuardTriggered(uint256 chainlinkPrice, uint256 twapPrice, uint256 divergenceBps);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error PoolNotInitialised();
    error ExceedsMaxFee(uint24 computed, uint24 maxFee);
    error OnlyPoolManager();

    // -------------------------------------------------------------------------
    // Fee preview — useful for frontend and simulations
    // -------------------------------------------------------------------------

    /// @notice Simulates what dynamic fee a swap would pay right now.
    ///         Does NOT execute a swap; purely for display.
    /// @param key          The pool to simulate for
    /// @param swapAmount   The amount being swapped (used to estimate pool price impact)
    /// @return baseFee          The pool's configured base fee (bps)
    /// @return arbPremium       The arb detection premium (bps)
    /// @return boundaryPremium  The gamma/boundary proximity premium (bps)
    /// @return totalFee         Sum of all three (bps)
    function previewFee(PoolKey calldata key, int256 swapAmount)
        external
        view
        returns (uint24 baseFee, uint24 arbPremium, uint24 boundaryPremium, uint24 totalFee);

    // -------------------------------------------------------------------------
    // Configuration views
    // -------------------------------------------------------------------------

    /// @notice Maximum fee the hook will ever charge, regardless of oracle deviation
    function MAX_FEE_BPS() external view returns (uint24);

    /// @notice The oracle deviation amplifier constant.
    ///         arbPremium = deviationBps * ARB_AMPLIFIER / 1e4
    function ARB_AMPLIFIER() external view returns (uint256);

    /// @notice Maximum boundary premium added when gamma score = 1 (price at boundary)
    function MAX_BOUNDARY_PREMIUM_BPS() external view returns (uint24);

    /// @notice Target hold duration in blocks for a full loyalty factor (= 1.0)
    function LOYALTY_TARGET_BLOCKS() external view returns (uint256);

    /// @notice Address of the IL Reserve Vault
    function vault() external view returns (address);

    /// @notice Address of the oracle reader
    function oracleReader() external view returns (address);
}

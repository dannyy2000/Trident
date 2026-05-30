// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IReactiveCallback
/// @notice Functions the Reactive Network contract calls back into on the hook side.
///         TridentHook and ReactiveAdapter implement this interface.
///         All functions are restricted to the authorised Reactive contract address.
interface IReactiveCallback {
    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event BoundaryPrimed(int24 nearestBoundary, uint256 gammaScore);
    event LPMarkedOutOfRange(bytes32 indexed positionId, address indexed lp);
    event ReactiveContractUpdated(address indexed oldContract, address indexed newContract);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error OnlyReactiveContract();

    // -------------------------------------------------------------------------
    // Callbacks — invoked by TridentReactive.sol on Reactive Network
    // -------------------------------------------------------------------------

    /// @notice Called when Reactive detects that pool price is drifting toward
    ///         a cluster of LP range boundaries. Pre-primes the boundary fee so
    ///         the next swap pays the correct premium without a cold storage read.
    /// @param nearestBoundaryTick  The tick of the nearest boundary cluster
    /// @param primedGammaScore     Pre-computed gamma score (scaled 1e18)
    function primeBoundaryFee(int24 nearestBoundaryTick, uint256 primedGammaScore) external;

    /// @notice Called when Reactive detects a swap moved price outside a recorded
    ///         LP's range. Marks the position as out-of-range so it is prioritised
    ///         for vault claims (earning zero fees but accumulating IL).
    /// @param positionId   The affected LP position
    /// @param lp           The LP's address (for event indexing)
    function markOutOfRange(bytes32 positionId, address lp) external;

    /// @notice Called by Reactive when vault health crosses a threshold, instructing
    ///         the vault to adjust its capture rate.
    /// @param newCaptureBps  New capture rate in basis points
    function updateCaptureRate(uint256 newCaptureBps) external;

    // -------------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------------

    /// @notice Updates the authorised Reactive contract address.
    ///         Only callable by the hook owner.
    function setReactiveContract(address reactiveContract) external;
}

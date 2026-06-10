// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IReactiveCallback} from "./interfaces/IReactiveCallback.sol";

/// @title ReactiveAdapter
/// @notice Validates that callbacks originate from the authorised TridentReactive contract
///         (deployed on Reactive Network) and forwards them to TridentHook.
///
///         Why this exists:
///           TridentHook's reactive callbacks check msg.sender == reactiveContract.
///           On the destination chain, msg.sender is this adapter — the on-chain entry point
///           that Reactive Network writes to. ReactiveAdapter validates the Reactive origin
///           and acts as a trust boundary between the cross-chain message and the hook.
///
///         Security model:
///           - Only reactiveOrigin (the TridentReactive contract) can call adapter functions.
///           - The adapter is the address set as `reactiveContract` in TridentHook.
///           - Changing either address requires the respective contract's owner.
contract ReactiveAdapter {
    address public immutable hook;
    address public reactiveOrigin;
    address public owner;

    event ReactiveOriginUpdated(address indexed oldOrigin, address indexed newOrigin);

    error OnlyReactiveOrigin();
    error OnlyOwner();
    error ZeroAddress();

    modifier onlyReactiveOrigin() {
        if (msg.sender != reactiveOrigin) revert OnlyReactiveOrigin();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    constructor(address _hook, address _reactiveOrigin) {
        if (_hook == address(0)) revert ZeroAddress();
        hook = _hook;
        reactiveOrigin = _reactiveOrigin; // may be address(0) initially
        owner = msg.sender;
    }

    /// @notice Update reactiveOrigin after TridentReactive is deployed on Reactive Network.
    function setReactiveOrigin(address newOrigin) external onlyOwner {
        if (newOrigin == address(0)) revert ZeroAddress();
        emit ReactiveOriginUpdated(reactiveOrigin, newOrigin);
        reactiveOrigin = newOrigin;
    }

    // -------------------------------------------------------------------------
    // Forwarded callbacks — all require reactiveOrigin as caller
    // -------------------------------------------------------------------------

    /// @notice Forwards oracle deviation update to hook.
    ///         Called by TridentReactive after comparing Chainlink price to pool price.
    function primeDeviation(uint256 deviationBps) external onlyReactiveOrigin {
        ITridentHookCallbacks(hook).primeDeviation(deviationBps);
    }

    /// @notice Forwards boundary fee prime to hook.
    ///         Called by TridentReactive when price drifts toward LP boundary cluster.
    function primeBoundaryFee(int24 nearestBoundaryTick, uint256 gammaScore) external onlyReactiveOrigin {
        IReactiveCallback(hook).primeBoundaryFee(nearestBoundaryTick, gammaScore);
    }

    /// @notice Forwards oracle manipulation flag to hook.
    ///         Called by TridentReactive when Chainlink vs TWAP divergence exceeds threshold.
    function setOracleManipulated(bool manipulated) external onlyReactiveOrigin {
        ITridentHookCallbacks(hook).setOracleManipulated(manipulated);
    }

    /// @notice Forwards out-of-range LP notification to hook.
    ///         Called by TridentReactive when a Swap event moves price outside a tracked LP range.
    function markOutOfRange(bytes32 positionId, address lp) external onlyReactiveOrigin {
        IReactiveCallback(hook).markOutOfRange(positionId, lp);
    }

    /// @notice Forwards vault capture rate update to hook.
    ///         Called by TridentReactive when vault health crosses a threshold.
    function updateCaptureRate(uint256 newCaptureBps) external onlyReactiveOrigin {
        IReactiveCallback(hook).updateCaptureRate(newCaptureBps);
    }

    /// @notice Forwards vault flush trigger to hook.
    ///         Called by TridentReactive periodically to deposit accrued pending capture.
    function flushToVault(address token) external onlyReactiveOrigin {
        IVaultFlush(hook).flushToVault(token);
    }
}

/// @dev Minimal interface for TridentHook functions not in IReactiveCallback
interface ITridentHookCallbacks {
    function primeDeviation(uint256 deviationBps) external;
    function setOracleManipulated(bool manipulated) external;
}

interface IVaultFlush {
    function flushToVault(address token) external;
}

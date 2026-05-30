// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IILReserveVault
/// @notice The on-chain IL insurance reserve. The hook deposits fee captures here
///         after every swap and pays out to LPs when they withdraw.
interface IILReserveVault {
    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event VaultDeposit(address indexed token, uint256 amount, uint256 newBalance);
    event VaultPayout(address indexed lp, uint256 ilAmount, uint256 loyaltyFactor, uint256 payout);
    event CaptureRateUpdated(uint256 oldRate, uint256 newRate);
    event PositionRecorded(bytes32 indexed positionId, address indexed lp, int24 entryTick, uint256 entryBlock);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error ZeroAmount();
    error PositionNotFound(bytes32 positionId);
    error PositionAlreadyExists(bytes32 positionId);
    error InsufficientVaultBalance(uint256 requested, uint256 available);
    error OnlyHook();

    // -------------------------------------------------------------------------
    // Position management — called by hook on liquidity add/remove
    // -------------------------------------------------------------------------

    /// @notice Records an LP's entry state when they add liquidity.
    ///         Called by the hook in afterAddLiquidity.
    /// @param positionId   Unique ID for this LP position (derived from owner + tickLower + tickUpper + salt)
    /// @param lp           Address of the liquidity provider
    /// @param entryTick    Pool tick at the moment of deposit
    /// @param liquidity    Amount of liquidity added
    function recordPosition(bytes32 positionId, address lp, int24 entryTick, uint128 liquidity) external;

    /// @notice Calculates how much IL an LP suffered, applies the loyalty factor,
    ///         scales by vault health, and pays out. Called by the hook in beforeRemoveLiquidity.
    /// @param positionId   The LP's position to settle
    /// @param exitTick     Pool tick at the moment of withdrawal
    /// @param recipient    Address that receives the payout
    /// @return payout      Token amount transferred to recipient
    function settlePosition(bytes32 positionId, int24 exitTick, address recipient) external returns (uint256 payout);

    // -------------------------------------------------------------------------
    // Vault funding — called by hook in afterSwap
    // -------------------------------------------------------------------------

    /// @notice Deposits fee revenue captured from a swap into the reserve.
    ///         Only callable by the hook.
    /// @param token    The currency being deposited (token0 or token1 of the pool)
    /// @param amount   Amount of token to deposit
    function deposit(address token, uint256 amount) external;

    // -------------------------------------------------------------------------
    // Reactive Network callbacks
    // -------------------------------------------------------------------------

    /// @notice Adjusts the fee capture rate based on vault health signal from Reactive.
    ///         Called by ReactiveAdapter when Reactive Network detects health thresholds.
    /// @param newRateBps New capture rate in basis points (e.g. 1000 = 10%)
    function setCaptureRate(uint256 newRateBps) external;

    // -------------------------------------------------------------------------
    // Views
    // -------------------------------------------------------------------------

    /// @notice Current capture rate in basis points (what % of swap fees go to vault)
    function captureRateBps() external view returns (uint256);

    /// @notice Total token balance held in the reserve
    function totalReserve(address token) external view returns (uint256);

    /// @notice Vault health ratio scaled to 1e18. Above 1e18 = overfunded. Below 0.3e18 = emergency.
    ///         Defined as: reserve / total_outstanding_LP_liability
    function vaultHealthRatio() external view returns (uint256);

    /// @notice Preview what payout a position would receive right now without executing
    function previewPayout(bytes32 positionId, int24 currentTick) external view returns (uint256 estimatedPayout);
}

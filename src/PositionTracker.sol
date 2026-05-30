// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title PositionTracker
/// @notice Stores LP entry state (tick, block, liquidity, range) so the IL Reserve Vault
///         can compute impermanent loss and loyalty factor at withdrawal time.
///
///         Access model:
///           - Only `hook`            can record and delete positions.
///           - `hook` OR `reactiveAdapter` can mark a position as out-of-range.
///           - Everyone else           can only call view functions.
///
///         Position ID derivation:
///           positionId = keccak256(abi.encode(lp, tickLower, tickUpper, salt))
///           The hook uses `derivePositionId()` so callers always get the same ID.
contract PositionTracker {
    // -------------------------------------------------------------------------
    // Types
    // -------------------------------------------------------------------------

    struct Position {
        bool exists;
        address lp;
        int24 tickLower;
        int24 tickUpper;
        int24 entryTick;
        uint128 liquidity;
        uint256 entryBlock;
        bool outOfRange;
    }

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    mapping(bytes32 => Position) private _positions;

    address public immutable hook;
    address public immutable reactiveAdapter;

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error OnlyHook();
    error OnlyHookOrReactive();
    error PositionAlreadyExists(bytes32 positionId);
    error PositionNotFound(bytes32 positionId);
    error ZeroAddress();

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event PositionRecorded(bytes32 indexed positionId, address indexed lp, int24 entryTick, uint256 entryBlock);
    event PositionDeleted(bytes32 indexed positionId);
    event PositionMarkedOutOfRange(bytes32 indexed positionId);

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    modifier onlyHook() {
        if (msg.sender != hook) revert OnlyHook();
        _;
    }

    modifier onlyHookOrReactive() {
        if (msg.sender != hook && msg.sender != reactiveAdapter) revert OnlyHookOrReactive();
        _;
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address _hook, address _reactiveAdapter) {
        if (_hook == address(0) || _reactiveAdapter == address(0)) revert ZeroAddress();
        hook = _hook;
        reactiveAdapter = _reactiveAdapter;
    }

    // -------------------------------------------------------------------------
    // Write functions — hook only
    // -------------------------------------------------------------------------

    /// @notice Records an LP's entry state when they add liquidity.
    ///         Called by the hook in `afterAddLiquidity`.
    function recordEntry(
        bytes32 positionId,
        address lp,
        int24 tickLower,
        int24 tickUpper,
        int24 entryTick,
        uint128 liquidity
    ) external onlyHook {
        if (_positions[positionId].exists) revert PositionAlreadyExists(positionId);

        _positions[positionId] = Position({
            exists: true,
            lp: lp,
            tickLower: tickLower,
            tickUpper: tickUpper,
            entryTick: entryTick,
            liquidity: liquidity,
            entryBlock: block.number,
            outOfRange: false
        });

        emit PositionRecorded(positionId, lp, entryTick, block.number);
    }

    /// @notice Deletes a position record after the vault has settled the payout.
    ///         Called by the hook in `beforeRemoveLiquidity` after `settlePosition`.
    function deletePosition(bytes32 positionId) external onlyHook {
        if (!_positions[positionId].exists) revert PositionNotFound(positionId);
        delete _positions[positionId];
        emit PositionDeleted(positionId);
    }

    // -------------------------------------------------------------------------
    // Write functions — hook or Reactive adapter
    // -------------------------------------------------------------------------

    /// @notice Marks a position as out-of-range when Reactive detects price left the LP's range.
    ///         Out-of-range positions earn zero fees but continue accumulating IL — they are
    ///         prioritised for vault claims.
    function markOutOfRange(bytes32 positionId) external onlyHookOrReactive {
        if (!_positions[positionId].exists) revert PositionNotFound(positionId);
        _positions[positionId].outOfRange = true;
        emit PositionMarkedOutOfRange(positionId);
    }

    // -------------------------------------------------------------------------
    // View functions
    // -------------------------------------------------------------------------

    /// @notice Returns the full position record. Reverts if not found.
    function getPosition(bytes32 positionId) external view returns (Position memory) {
        if (!_positions[positionId].exists) revert PositionNotFound(positionId);
        return _positions[positionId];
    }

    /// @notice Returns true if a position with this ID has been recorded and not yet deleted.
    function positionExists(bytes32 positionId) external view returns (bool) {
        return _positions[positionId].exists;
    }

    // -------------------------------------------------------------------------
    // Pure helpers
    // -------------------------------------------------------------------------

    /// @notice Derives the deterministic position ID used throughout the system.
    ///         The hook calls this when recording and settling positions so callers
    ///         always hash the same fields in the same order.
    function derivePositionId(address lp, int24 tickLower, int24 tickUpper, bytes32 salt)
        external
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(lp, tickLower, tickUpper, salt));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AbstractPausableReactive} from "@reactive/abstract-base/AbstractPausableReactive.sol";
import {IReactive} from "@reactive/interfaces/IReactive.sol";

/// @title TridentReactive
/// @notice Deployed on Reactive Network. Subscribes to three event streams on Unichain:
///         1. PoolManager Swap events       → compute arb deviation + gamma, callback primeDeviation + primeBoundaryFee
///         2. Chainlink AnswerUpdated events → update stored oracle price
///         3. PoolManager ModifyLiquidity   → track LP range boundaries for gamma computation
///
///         On every Swap event, TridentReactive:
///           a) Computes oracle deviation using stored Chainlink price vs pool sqrtPriceX96
///           b) Detects oracle manipulation (Chainlink vs TWAP divergence)
///           c) Finds nearest LP boundary and computes gamma score
///           d) Emits Callback events to ReactiveAdapter on Unichain
///
///         Architecture: Reactive Network calls react() → react emits Callback events →
///         Reactive Network executes those callbacks on the destination chain.
///
/// @dev Event topic hashes (verified against v4-core IPoolManager.sol and Chainlink AggregatorV2V3):
///      Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)
///      ModifyLiquidity(bytes32,address,int24,int24,int256,bytes32)
///      AnswerUpdated(int256,uint256,uint256)
contract TridentReactive is AbstractPausableReactive {
    // -------------------------------------------------------------------------
    // Event topic hashes — must match keccak256 of exact event signatures
    // -------------------------------------------------------------------------

    uint256 private constant SWAP_TOPIC =
        uint256(keccak256("Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)"));

    uint256 private constant MODIFY_LIQUIDITY_TOPIC =
        uint256(keccak256("ModifyLiquidity(bytes32,address,int24,int24,int256,bytes32)"));

    uint256 private constant ANSWER_UPDATED_TOPIC =
        uint256(keccak256("AnswerUpdated(int256,uint256,uint256)"));

    // -------------------------------------------------------------------------
    // Immutable configuration
    // -------------------------------------------------------------------------

    /// @notice Chain ID of Unichain (destination chain for callbacks)
    uint256 public immutable DEST_CHAIN_ID;

    /// @notice Uniswap v4 PoolManager address on Unichain
    address public immutable POOL_MANAGER;

    /// @notice Chainlink feed address on Unichain (e.g. ETH/USD)
    address public immutable CHAINLINK_FEED;

    /// @notice ReactiveAdapter address on Unichain — receives all callbacks
    address public immutable REACTIVE_ADAPTER;

    /// @notice Specific pool ID to monitor (other pools are ignored)
    bytes32 public immutable POOL_ID;

    /// @notice Pool tick spacing — used for gamma score normalisation
    int24 public immutable TICK_SPACING;

    /// @notice Scaling divisor for oracle → sqrtPriceX96 conversion.
    ///         = sqrt(10^(oracleDecimals + token0Decimals - token1Decimals))
    ///         e.g. WETH(18)/USDC(6) with 8-decimal Chainlink feed: sqrt(10^20) = 1e10
    uint256 public immutable SQRT_ORACLE_DIVISOR;

    /// @notice Deviation threshold above which oracle is flagged as manipulated (bps)
    uint256 public immutable MANIPULATION_THRESHOLD_BPS;

    // -------------------------------------------------------------------------
    // Mutable state (maintained in the ReactVM copy of this contract)
    // -------------------------------------------------------------------------

    /// @notice Latest Chainlink oracle price (raw, 8 decimals)
    uint256 public latestOraclePrice;

    /// @notice Latest pool sqrtPriceX96 from the most recent Swap event
    uint160 public latestPoolSqrtPrice;

    /// @notice Latest pool tick from the most recent Swap event
    int24 public latestTick;

    /// @notice Simple circular buffer of last 8 pool sqrtPriceX96 values — used as TWAP proxy
    uint160[8] private _sqrtBuffer;
    uint8 private _bufferIdx;
    bool private _bufferFull;

    /// @notice Tracked LP boundary ticks (populated from ModifyLiquidity events)
    int24[] private _boundaries;

    // -------------------------------------------------------------------------
    // Constructor — subscribes to all three event streams
    // -------------------------------------------------------------------------

    /// @param destChainId       EIP-155 chain ID of Unichain
    /// @param poolManager       PoolManager address on Unichain
    /// @param chainlinkFeed     Chainlink AggregatorV3 address on Unichain
    /// @param reactiveAdapter   ReactiveAdapter address on Unichain
    /// @param poolId            keccak256 hash of the PoolKey being monitored
    /// @param tickSpacing       Pool tick spacing (10, 60, or 200)
    /// @param sqrtOracleDivisor sqrt(10^(oracleDec + token0Dec - token1Dec)), e.g. 1e10 for WETH/USDC
    /// @param manipulationBps   Oracle manipulation detection threshold, e.g. 200 (2%)
    /// @param initialOraclePrice Latest Chainlink answer at deploy time (seed value)
    constructor(
        uint256 destChainId,
        address poolManager,
        address chainlinkFeed,
        address reactiveAdapter,
        bytes32 poolId,
        int24 tickSpacing,
        uint256 sqrtOracleDivisor,
        uint256 manipulationBps,
        uint256 initialOraclePrice
    ) payable {
        DEST_CHAIN_ID = destChainId;
        POOL_MANAGER = poolManager;
        CHAINLINK_FEED = chainlinkFeed;
        REACTIVE_ADAPTER = reactiveAdapter;
        POOL_ID = poolId;
        TICK_SPACING = tickSpacing;
        SQRT_ORACLE_DIVISOR = sqrtOracleDivisor;
        MANIPULATION_THRESHOLD_BPS = manipulationBps;
        latestOraclePrice = initialOraclePrice;

        // Subscribe only on top-level Reactive Network (not in ReactVM)
        if (!vm) {
            // 1. Swap events — core trigger for all callbacks
            service.subscribe(
                destChainId, poolManager, SWAP_TOPIC,
                uint256(poolId), // filter to specific pool
                REACTIVE_IGNORE, REACTIVE_IGNORE
            );
            // 2. Chainlink AnswerUpdated — keeps oracle price fresh
            service.subscribe(
                destChainId, chainlinkFeed, ANSWER_UPDATED_TOPIC,
                REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE
            );
            // 3. ModifyLiquidity — tracks LP range boundaries for gamma
            service.subscribe(
                destChainId, poolManager, MODIFY_LIQUIDITY_TOPIC,
                uint256(poolId), // filter to specific pool
                REACTIVE_IGNORE, REACTIVE_IGNORE
            );
        }
    }

    // -------------------------------------------------------------------------
    // AbstractPausableReactive — defines what to pause/resume
    // -------------------------------------------------------------------------

    function getPausableSubscriptions() internal view override returns (Subscription[] memory subs) {
        subs = new Subscription[](3);
        subs[0] = Subscription(DEST_CHAIN_ID, POOL_MANAGER, SWAP_TOPIC, uint256(POOL_ID), REACTIVE_IGNORE, REACTIVE_IGNORE);
        subs[1] = Subscription(DEST_CHAIN_ID, CHAINLINK_FEED, ANSWER_UPDATED_TOPIC, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
        subs[2] = Subscription(DEST_CHAIN_ID, POOL_MANAGER, MODIFY_LIQUIDITY_TOPIC, uint256(POOL_ID), REACTIVE_IGNORE, REACTIVE_IGNORE);
    }

    // -------------------------------------------------------------------------
    // IReactive.react — entry point for all event notifications
    // -------------------------------------------------------------------------

    /// @notice Called by Reactive Network whenever a subscribed event fires.
    ///         Routes to the appropriate handler based on topic_0.
    function react(LogRecord calldata log) external override vmOnly {
        if (log.topic_0 == SWAP_TOPIC) {
            _handleSwap(log);
        } else if (log.topic_0 == ANSWER_UPDATED_TOPIC) {
            _handleOracleUpdate(log);
        } else if (log.topic_0 == MODIFY_LIQUIDITY_TOPIC) {
            _handleModifyLiquidity(log);
        }
    }

    // -------------------------------------------------------------------------
    // Event handlers
    // -------------------------------------------------------------------------

    /// @dev Handles Swap events: computes deviation + gamma, emits 3 callbacks.
    function _handleSwap(LogRecord calldata log) internal {
        // Decode non-indexed Swap fields from log.data
        // Swap(PoolId indexed id, address indexed sender, int128 amount0, int128 amount1,
        //      uint160 sqrtPriceX96, uint128 liquidity, int24 tick, uint24 fee)
        (, , uint160 sqrtPriceX96, , int24 tick,) =
            abi.decode(log.data, (int128, int128, uint160, uint128, int24, uint24));

        // Update state
        latestPoolSqrtPrice = sqrtPriceX96;
        latestTick = tick;
        _updateTwapBuffer(sqrtPriceX96);

        // ── Layer 1: Oracle deviation ─────────────────────────────────────────
        uint256 deviationBps = _computeDeviationBps(sqrtPriceX96);

        // ── Layer 1: Oracle manipulation check ───────────────────────────────
        bool manipulated = _checkManipulation(sqrtPriceX96);

        // ── Layer 2: Gamma score ──────────────────────────────────────────────
        (int24 nearestBoundary, uint256 gammaScore) = _computeGamma(tick);

        // ── Callback 1: primeDeviation ────────────────────────────────────────
        emit Callback(
            DEST_CHAIN_ID,
            REACTIVE_ADAPTER,
            500_000,
            abi.encodeWithSignature("primeDeviation(uint256)", deviationBps)
        );

        // ── Callback 2: primeBoundaryFee (only if boundary is tracked) ────────
        if (nearestBoundary != 0 || _boundaries.length > 0) {
            emit Callback(
                DEST_CHAIN_ID,
                REACTIVE_ADAPTER,
                500_000,
                abi.encodeWithSignature("primeBoundaryFee(int24,uint256)", nearestBoundary, gammaScore)
            );
        }

        // ── Callback 3: oracle manipulation flag ──────────────────────────────
        emit Callback(
            DEST_CHAIN_ID,
            REACTIVE_ADAPTER,
            300_000,
            abi.encodeWithSignature("setOracleManipulated(bool)", manipulated)
        );
    }

    /// @dev Handles Chainlink AnswerUpdated: stores latest oracle price.
    ///      AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 updatedAt)
    ///      topic_1 = current price (indexed int256, stored as uint256 in topic)
    function _handleOracleUpdate(LogRecord calldata log) internal {
        // topic_1 carries the indexed int256 oracle answer
        int256 answer = int256(log.topic_1);
        if (answer > 0) {
            latestOraclePrice = uint256(answer);
        }
    }

    /// @dev Handles ModifyLiquidity: tracks LP range boundaries for gamma computation.
    ///      ModifyLiquidity(PoolId indexed id, address indexed sender,
    ///                      int24 tickLower, int24 tickUpper, int256 liquidityDelta, bytes32 salt)
    function _handleModifyLiquidity(LogRecord calldata log) internal {
        (int24 tickLower, int24 tickUpper, int256 liquidityDelta,) =
            abi.decode(log.data, (int24, int24, int256, bytes32));

        if (liquidityDelta > 0) {
            // New liquidity added — register both range boundaries
            _addBoundary(tickLower);
            _addBoundary(tickUpper);
        }
        // Note: we keep boundaries when liquidity is removed (conservative — may overestimate gamma)
        // In production: track per-LP liquidity to remove boundaries with no remaining liquidity
    }

    // -------------------------------------------------------------------------
    // Computation helpers
    // -------------------------------------------------------------------------

    /// @dev Computes oracle price deviation against pool sqrtPriceX96 in basis points.
    ///      Formula: |sqrtOracle - sqrtPool| * 20000 / sqrtPool
    ///      (×2 factor converts sqrt-space deviation to price-space deviation for small Δ)
    ///      Returns 0 if oracle price is not yet initialised.
    function _computeDeviationBps(uint160 sqrtPriceX96) internal view returns (uint256) {
        if (latestOraclePrice == 0 || sqrtPriceX96 == 0) return 0;

        uint256 sqrtOracle = _oraclePriceToSqrtX96(latestOraclePrice);
        if (sqrtOracle == 0) return 0;

        uint256 diff = sqrtOracle >= uint256(sqrtPriceX96)
            ? sqrtOracle - uint256(sqrtPriceX96)
            : uint256(sqrtPriceX96) - sqrtOracle;

        // Multiply by 20000 (= 2 × 10000) to convert sqrt-space ratio → price-space bps
        return (diff * 20_000) / uint256(sqrtPriceX96);
    }

    /// @dev Returns true if the stored TWAP deviates from current sqrtPrice by more than threshold.
    ///      TWAP = arithmetic mean of last 8 sqrtPriceX96 values.
    function _checkManipulation(uint160 sqrtPriceX96) internal view returns (bool) {
        if (!_bufferFull) return false;

        // Compute average of circular buffer
        uint256 sum;
        for (uint8 i = 0; i < 8; i++) {
            sum += uint256(_sqrtBuffer[i]);
        }
        uint256 twapSqrt = sum / 8;
        if (twapSqrt == 0) return false;

        uint256 diff = uint256(sqrtPriceX96) >= twapSqrt
            ? uint256(sqrtPriceX96) - twapSqrt
            : twapSqrt - uint256(sqrtPriceX96);

        uint256 divergenceBps = (diff * 20_000) / twapSqrt;
        return divergenceBps > MANIPULATION_THRESHOLD_BPS;
    }

    /// @dev Finds nearest LP boundary and computes gamma score.
    ///      gamma_score = 1e18 / (tickSpacingsAway + 1)
    function _computeGamma(int24 currentTick)
        internal
        view
        returns (int24 nearestBoundary, uint256 gammaScore)
    {
        uint256 count = _boundaries.length;
        if (count == 0) return (0, 0);

        int24 nearest = _boundaries[0];
        int256 minDiff = _absDiff(currentTick, nearest);

        for (uint256 i = 1; i < count; i++) {
            int256 d = _absDiff(currentTick, _boundaries[i]);
            if (d < minDiff) {
                minDiff = d;
                nearest = _boundaries[i];
            }
        }

        nearestBoundary = nearest;
        uint256 tickSpacingsAway = uint256(minDiff) / uint256(uint24(TICK_SPACING > 0 ? TICK_SPACING : int24(1)));
        gammaScore = 1e18 / (tickSpacingsAway + 1);
    }

    /// @dev Converts Chainlink oracle price (8 decimals) to approximate sqrtPriceX96.
    ///      sqrtPriceX96 = isqrt(oraclePrice) * 2^96 / SQRT_ORACLE_DIVISOR
    function _oraclePriceToSqrtX96(uint256 oraclePrice) internal view returns (uint256) {
        if (SQRT_ORACLE_DIVISOR == 0) return 0;
        uint256 sqrtPrice = _isqrt(oraclePrice);
        // Multiply first to preserve precision, then divide
        // sqrtPrice * (1 << 96) / SQRT_ORACLE_DIVISOR
        // Safe: sqrtPrice(2000e8) ≈ 4.47e5, 4.47e5 * 2^96 ≈ 3.54e34 — fits in uint256
        return (sqrtPrice * (1 << 96)) / SQRT_ORACLE_DIVISOR;
    }

    /// @dev Integer square root using Babylonian method.
    function _isqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        y = x;
        uint256 z = (x / 2) + 1;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    /// @dev Absolute difference between two int24 values as int256.
    function _absDiff(int24 a, int24 b) internal pure returns (int256) {
        int256 diff = int256(a) - int256(b);
        return diff < 0 ? -diff : diff;
    }

    /// @dev Updates the circular TWAP buffer with a new sqrtPriceX96 observation.
    function _updateTwapBuffer(uint160 sqrtPriceX96) internal {
        _sqrtBuffer[_bufferIdx] = sqrtPriceX96;
        _bufferIdx = (_bufferIdx + 1) % 8;
        if (_bufferIdx == 0) _bufferFull = true;
    }

    /// @dev Adds a tick boundary if not already tracked. Caps at 200 boundaries.
    function _addBoundary(int24 tick) internal {
        if (_boundaries.length >= 200) return; // gas guard
        for (uint256 i = 0; i < _boundaries.length; i++) {
            if (_boundaries[i] == tick) return; // already tracked
        }
        _boundaries.push(tick);
    }

    // -------------------------------------------------------------------------
    // Admin — callable only on top-level Reactive Network (not in ReactVM)
    // -------------------------------------------------------------------------

    /// @notice Manually seed the oracle price. Useful for initial setup before
    ///         the first AnswerUpdated event is received.
    function seedOraclePrice(uint256 price) external rnOnly onlyOwner {
        latestOraclePrice = price;
    }

    /// @notice Manually register an LP boundary tick. Useful for LPs who added
    ///         liquidity before TridentReactive was deployed.
    function addBoundary(int24 tick) external rnOnly onlyOwner {
        _addBoundary(tick);
    }

    /// @notice Returns all tracked LP boundary ticks.
    function boundaries() external view returns (int24[] memory) {
        return _boundaries;
    }
}

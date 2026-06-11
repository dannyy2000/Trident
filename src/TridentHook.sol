// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary, toBalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {FullMath} from "v4-core/libraries/FullMath.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/types/PoolOperation.sol";

import {ITridentHook} from "./interfaces/ITridentHook.sol";
import {IReactiveCallback} from "./interfaces/IReactiveCallback.sol";
import {IILReserveVault} from "./interfaces/IILReserveVault.sol";
import {IOracleReader} from "./interfaces/IOracleReader.sol";

import {GammaScorer} from "./GammaScorer.sol";
import {PositionTracker} from "./PositionTracker.sol";

/// @title TridentHook
/// @notice Three-layer LP protection hook for Uniswap v4.
///
///         Layer 1 — Arb Detector (beforeSwap):
///           Reactive Network primes _primedDeviationBps between swaps by comparing
///           the Chainlink oracle price to the pool spot price. In beforeSwap, the hook
///           converts that deviation into an arb premium on top of the base fee.
///           This means arb bots pay elevated fees proportional to the value they extract.
///
///         Layer 2 — Range Guardian (beforeSwap, additive with Layer 1):
///           Reactive also primes _primedGammaScore when price drifts toward LP boundary
///           clusters. A higher score (price near boundary) → higher boundary premium.
///           For the first time, LPs are compensated MORE when they're in the most danger.
///
///         Layer 3 — IL Reserve Vault (afterAddLiquidity, beforeRemoveLiquidity):
///           10–15% of elevated fee revenue accumulates in ILReserveVault.
///           Long-term LPs receive their IL offset from the vault on withdrawal.
///           JIT LPs held for 1 block receive zero.
///
///         Reactive Network automates everything between swaps:
///           oracle monitoring, boundary drift detection, vault health management,
///           out-of-range LP tracking, and capture rate adjustment.
///
/// @dev Hook address must have bits set for: BEFORE_SWAP, AFTER_SWAP,
///      AFTER_ADD_LIQUIDITY, BEFORE_REMOVE_LIQUIDITY (flags = 0x6C0).
///      Pool must be initialised with lpFee = LPFeeLibrary.DYNAMIC_FEE_FLAG.
contract TridentHook is IHooks, ITridentHook, IReactiveCallback {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @inheritdoc ITridentHook
    uint24 public constant override MAX_FEE_BPS = 50_000; // 5% absolute cap

    /// @inheritdoc ITridentHook
    uint256 public constant override ARB_AMPLIFIER = 8_000;

    /// @inheritdoc ITridentHook
    uint24 public constant override MAX_BOUNDARY_PREMIUM_BPS = 5_000; // 0.5%

    /// @inheritdoc ITridentHook
    uint256 public constant override LOYALTY_TARGET_BLOCKS = 216_000;

    // When oracle manipulation is detected, cap fee at this fraction of MAX_FEE_BPS
    uint24 internal constant MANIPULATION_FEE_CAP_BPS = 3_000; // 0.3%

    // -------------------------------------------------------------------------
    // Immutables
    // -------------------------------------------------------------------------

    IPoolManager public immutable poolManager;

    IOracleReader private immutable _oracleReader;
    GammaScorer private immutable _gammaScorer;
    IILReserveVault private immutable _vault;
    PositionTracker private immutable _positionTracker;

    /// @notice Base fee applied to all swaps before arb and boundary premiums (v4 pips, 1e6 = 100%)
    uint24 public immutable baseFee;

    /// @notice Scales pool sqrtPriceX96 → oracle-compatible 1e18 price.
    ///         = 10^(token0Decimals - token1Decimals + 18)
    ///         e.g. WETH(18)/USDC(6): decimalAdjustment = 1e30
    uint256 public immutable decimalAdjustment;

    address public immutable owner;

    // -------------------------------------------------------------------------
    // Mutable state — Reactive-primed
    // -------------------------------------------------------------------------

    /// @notice Current oracle vs pool price deviation in bps — primed by Reactive
    uint256 public primedDeviationBps;

    /// @notice Primed gamma score (1e18 scaled) — primed by Reactive from boundary monitoring
    uint256 public primedGammaScore;

    /// @notice Nearest boundary tick when Reactive last primed the boundary fee
    int24 public primedBoundaryTick;

    /// @notice Set by Reactive when Chainlink vs TWAP divergence exceeds threshold
    bool public oracleManipulated;

    /// @notice Authorised Reactive contract address
    address private _reactiveContract;

    // -------------------------------------------------------------------------
    // Per-pool state
    // -------------------------------------------------------------------------

    /// @dev Last fee charged per pool — used in afterSwap to estimate vault capture
    mapping(bytes32 => uint24) private _lastFee;

    /// @dev Pending vault capture per ERC-20 token — flushed to vault by flushToVault()
    mapping(address => uint256) private _pendingCapture;

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error OnlyOwner();
    error ZeroAddress();

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event VaultCaptureAccrued(address indexed token, uint256 amount, uint256 totalPending);
    event VaultFlushed(address indexed token, uint256 amount);

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert OnlyPoolManager();
        _;
    }

    modifier onlyOwnerRole() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(
        IPoolManager _poolManager,
        IOracleReader __oracleReader,
        GammaScorer __gammaScorer,
        IILReserveVault __vault,
        PositionTracker __positionTracker,
        uint24 _baseFee,
        uint256 _decimalAdjustment,
        address _reactiveContract_,
        address _owner
    ) {
        if (_owner == address(0)) revert ZeroAddress();
        poolManager = _poolManager;
        _oracleReader = __oracleReader;
        _gammaScorer = __gammaScorer;
        _vault = __vault;
        _positionTracker = __positionTracker;
        baseFee = _baseFee;
        decimalAdjustment = _decimalAdjustment;
        _reactiveContract = _reactiveContract_;
        owner = _owner;
    }

    // -------------------------------------------------------------------------
    // ITridentHook — views
    // -------------------------------------------------------------------------

    /// @inheritdoc ITridentHook
    function previewFee(PoolKey calldata, int256)
        external
        view
        override
        returns (uint24 base, uint24 arbPremium, uint24 boundaryPremium, uint24 totalFee)
    {
        base = baseFee;
        arbPremium = _computeArbPremium(primedDeviationBps);
        boundaryPremium = _computeBoundaryPremium(primedGammaScore);
        totalFee = _capFee(base + arbPremium + boundaryPremium);
        if (oracleManipulated && totalFee > MANIPULATION_FEE_CAP_BPS) {
            totalFee = MANIPULATION_FEE_CAP_BPS;
        }
    }

    /// @inheritdoc ITridentHook
    function vault() external view override returns (address) {
        return address(_vault);
    }

    /// @inheritdoc ITridentHook
    function oracleReader() external view override returns (address) {
        return address(_oracleReader);
    }

    /// @notice Returns the pending vault capture balance for a token
    function pendingCapture(address token) external view returns (uint256) {
        return _pendingCapture[token];
    }

    // -------------------------------------------------------------------------
    // IHooks — hook callbacks
    // -------------------------------------------------------------------------

    function getHookPermissions() public pure returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /// @notice Layer 1 + Layer 2: dynamic fee from oracle deviation + gamma score.
    ///
    ///         Primary path (Reactive pre-primed — gas efficient):
    ///           Uses primedDeviationBps and primedGammaScore set by Reactive between swaps.
    ///
    ///         Fallback path (Reactive offline or first swap after deploy):
    ///           Layer 1: reads slot0 sqrtPriceX96, converts to pool price via decimalAdjustment,
    ///                    calls OracleReader.getDeviationBps(poolPrice) directly.
    ///           Layer 2: reads current tick from slot0, calls GammaScorer.computeGammaScore()
    ///                    against primedBoundaryTick if one has been set.
    function beforeSwap(address, PoolKey calldata key, SwapParams calldata, bytes calldata)
        external
        override
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // Read pool state — needed for fallback oracle/gamma and for afterAddLiquidity consistency
        (uint160 sqrtPriceX96, int24 currentTick,,) = poolManager.getSlot0(key.toId());

        // ── Layer 1: Arb detection ──────────────────────────────────────────────
        uint256 deviationBps = primedDeviationBps;
        if (deviationBps == 0) {
            // Fallback: query oracle directly using live pool price
            uint256 poolPrice = _sqrtPriceToPrice1e18(sqrtPriceX96);
            if (poolPrice > 0) {
                try _oracleReader.getDeviationBps(poolPrice) returns (uint256 dev) {
                    deviationBps = dev;
                } catch {}
            }
        }

        // ── Layer 2: Range guardian ─────────────────────────────────────────────
        uint256 gammaScore = primedGammaScore;
        if (gammaScore == 0 && primedBoundaryTick != 0) {
            // Fallback: compute gamma from live tick vs primed boundary
            try _gammaScorer.computeGammaScore(currentTick, primedBoundaryTick, key.tickSpacing) returns (uint256 score)
            {
                gammaScore = score;
            } catch {}
        }

        // ── Combine and cap ─────────────────────────────────────────────────────
        uint24 arbPremium = _computeArbPremium(deviationBps);
        uint24 boundaryPremium = _computeBoundaryPremium(gammaScore);
        uint24 totalFee = _capFee(baseFee + arbPremium + boundaryPremium);

        // Oracle manipulation guard: if Reactive flagged TWAP/Chainlink divergence, cap fee
        if (oracleManipulated && totalFee > MANIPULATION_FEE_CAP_BPS) {
            totalFee = MANIPULATION_FEE_CAP_BPS;
        }

        bytes32 poolId = PoolId.unwrap(key.toId());
        _lastFee[poolId] = totalFee;

        emit SwapFeeBreakdown(poolId, baseFee, arbPremium, boundaryPremium, totalFee, 0);

        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, totalFee);
    }

    /// @notice Estimates the vault capture from this swap and accrues it to _pendingCapture.
    ///         Actual ERC-20 transfer to vault happens in flushToVault().
    function afterSwap(address, PoolKey calldata key, SwapParams calldata params, BalanceDelta delta, bytes calldata)
        external
        override
        onlyPoolManager
        returns (bytes4, int128)
    {
        bytes32 poolId = PoolId.unwrap(key.toId());
        uint24 fee = _lastFee[poolId];

        if (fee > 0) {
            // Estimate gross input amount from delta
            int128 inputDelta = params.zeroForOne ? delta.amount0() : delta.amount1();
            uint256 inputAmount = inputDelta > 0 ? uint256(uint128(inputDelta)) : uint256(uint128(-inputDelta));

            // Approximate fee = input * fee / 1e6
            uint256 feeAmount = FullMath.mulDiv(inputAmount, fee, 1_000_000);
            uint256 captureAmount = FullMath.mulDiv(feeAmount, _vault.captureRateBps(), 10_000);

            if (captureAmount > 0) {
                address captureCurrency =
                    params.zeroForOne ? Currency.unwrap(key.currency0) : Currency.unwrap(key.currency1);
                _pendingCapture[captureCurrency] += captureAmount;
                emit VaultCaptureAccrued(captureCurrency, captureAmount, _pendingCapture[captureCurrency]);
            }
        }

        return (IHooks.afterSwap.selector, 0);
    }

    /// @notice Layer 3 (record): registers LP entry state in vault and position tracker.
    function afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external override onlyPoolManager returns (bytes4, BalanceDelta) {
        if (params.liquidityDelta > 0) {
            bytes32 positionId = _derivePositionId(sender, params.tickLower, params.tickUpper, params.salt);

            // Get current tick from PoolManager slot0
            (, int24 currentTick,,) = poolManager.getSlot0(key.toId());

            uint128 liquidity = uint128(uint256(params.liquidityDelta));

            _vault.recordPosition(positionId, sender, currentTick, liquidity);
            _positionTracker.recordEntry(positionId, sender, params.tickLower, params.tickUpper, currentTick, liquidity);
        }

        return (IHooks.afterAddLiquidity.selector, toBalanceDelta(0, 0));
    }

    /// @notice Layer 3 (settle): computes IL × loyalty × health → pays out from vault.
    ///         Skips silently for LPs who did not add liquidity through this hook.
    function beforeRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        bytes calldata
    ) external override onlyPoolManager returns (bytes4) {
        bytes32 positionId = _derivePositionId(sender, params.tickLower, params.tickUpper, params.salt);

        if (_vault.positionExists(positionId)) {
            (, int24 currentTick,,) = poolManager.getSlot0(key.toId());
            _vault.settlePosition(positionId, currentTick, sender);
            if (_positionTracker.positionExists(positionId)) {
                _positionTracker.deletePosition(positionId);
            }
        }

        return IHooks.beforeRemoveLiquidity.selector;
    }

    // -------------------------------------------------------------------------
    // No-op hook callbacks (required by IHooks interface)
    // -------------------------------------------------------------------------

    function beforeInitialize(address, PoolKey calldata, uint160) external pure override returns (bytes4) {
        return IHooks.beforeInitialize.selector;
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24) external pure override returns (bytes4) {
        return IHooks.afterInitialize.selector;
    }

    function beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IHooks.beforeAddLiquidity.selector;
    }

    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure override returns (bytes4, BalanceDelta) {
        return (IHooks.afterRemoveLiquidity.selector, toBalanceDelta(0, 0));
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IHooks.beforeDonate.selector;
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IHooks.afterDonate.selector;
    }

    // -------------------------------------------------------------------------
    // IReactiveCallback
    // -------------------------------------------------------------------------

    /// @inheritdoc IReactiveCallback
    function primeBoundaryFee(int24 nearestBoundaryTick, uint256 primedGammaScore_) external override {
        if (msg.sender != _reactiveContract) revert OnlyReactiveContract();
        primedBoundaryTick = nearestBoundaryTick;
        primedGammaScore = primedGammaScore_;
        emit BoundaryPrimed(nearestBoundaryTick, primedGammaScore_);
    }

    /// @inheritdoc IReactiveCallback
    function markOutOfRange(bytes32 positionId, address lp) external override {
        if (msg.sender != _reactiveContract) revert OnlyReactiveContract();
        _positionTracker.markOutOfRange(positionId);
        emit LPMarkedOutOfRange(positionId, lp);
    }

    /// @inheritdoc IReactiveCallback
    function updateCaptureRate(uint256 newCaptureBps) external override {
        if (msg.sender != _reactiveContract) revert OnlyReactiveContract();
        _vault.setCaptureRate(newCaptureBps);
    }

    /// @inheritdoc IReactiveCallback
    function setReactiveContract(address reactiveContract_) external override onlyOwnerRole {
        address old = _reactiveContract;
        _reactiveContract = reactiveContract_;
        emit ReactiveContractUpdated(old, reactiveContract_);
    }

    // -------------------------------------------------------------------------
    // Reactive-primed setters (also callable by Reactive)
    // -------------------------------------------------------------------------

    /// @notice Updates the primed oracle deviation. Called by Reactive after each oracle comparison.
    function primeDeviation(uint256 deviationBps) external {
        if (msg.sender != _reactiveContract) revert OnlyReactiveContract();
        primedDeviationBps = deviationBps;
    }

    /// @notice Sets or clears the oracle manipulation flag. Called by Reactive when
    ///         Chainlink vs TWAP divergence exceeds threshold.
    function setOracleManipulated(bool manipulated) external {
        if (msg.sender != _reactiveContract) revert OnlyReactiveContract();
        oracleManipulated = manipulated;
        if (manipulated) {
            emit OracleManipulationGuardTriggered(0, 0, 0);
        }
    }

    // -------------------------------------------------------------------------
    // Vault flush — called by Reactive or anyone to sweep pending capture to vault
    // -------------------------------------------------------------------------

    /// @notice Transfers accrued pending capture to the vault.
    ///         The hook must hold the corresponding ERC-20 balance for this to succeed.
    ///         In production, Reactive calls this after accumulating sufficient capture.
    function flushToVault(address token) external {
        uint256 amount = _pendingCapture[token];
        if (amount == 0) return;
        _pendingCapture[token] = 0;

        IERC20Minimal(token).approve(address(_vault), amount);
        _vault.deposit(token, amount);

        emit VaultFlushed(token, amount);
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    function _computeArbPremium(uint256 deviationBps) internal pure returns (uint24) {
        // arbPremium = deviationBps * ARB_AMPLIFIER / 10_000
        uint256 premium = FullMath.mulDiv(deviationBps, ARB_AMPLIFIER, 10_000);
        return premium > type(uint24).max ? type(uint24).max : uint24(premium);
    }

    function _computeBoundaryPremium(uint256 gammaScore) internal pure returns (uint24) {
        // boundaryPremium = gammaScore * MAX_BOUNDARY_PREMIUM_BPS / 1e18
        uint256 premium = FullMath.mulDiv(gammaScore, MAX_BOUNDARY_PREMIUM_BPS, 1e18);
        return premium > type(uint24).max ? type(uint24).max : uint24(premium);
    }

    function _capFee(uint256 fee) internal pure returns (uint24) {
        if (fee > MAX_FEE_BPS) return MAX_FEE_BPS;
        return uint24(fee);
    }

    function _derivePositionId(address lp, int24 tickLower, int24 tickUpper, bytes32 salt)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(lp, tickLower, tickUpper, salt));
    }

    /// @dev Converts pool sqrtPriceX96 to a 1e18-scaled price compatible with OracleReader output.
    ///      Formula: price1e18 = (sqrtP^2 / 2^96) * decimalAdjustment / 2^96
    ///               = sqrtP^2 * decimalAdjustment / 2^192
    ///      FullMath handles the 512-bit intermediate so extreme tick values don't overflow.
    ///      decimalAdjustment = 10^(token0Decimals - token1Decimals + 18)
    ///      e.g. WETH(18)/USDC(6): decimalAdjustment = 1e30
    function _sqrtPriceToPrice1e18(uint160 sqrtPriceX96) internal view returns (uint256) {
        if (decimalAdjustment == 0) return 0;
        // Step 1: sqrtP^2 / 2^96  (loses no precision — FullMath uses 512-bit intermediate)
        uint256 priceX96 = FullMath.mulDiv(uint256(sqrtPriceX96), uint256(sqrtPriceX96), 1 << 96);
        // Step 2: scale from X96 to 1e18 using the pool's decimal adjustment
        return FullMath.mulDiv(priceX96, decimalAdjustment, 1 << 96);
    }
}

/// @dev Minimal ERC-20 interface for the vault flush
interface IERC20Minimal {
    function approve(address spender, uint256 amount) external returns (bool);
}

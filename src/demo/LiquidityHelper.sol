// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager}         from "v4-core/interfaces/IPoolManager.sol";
import {IUnlockCallback}      from "v4-core/interfaces/callback/IUnlockCallback.sol";
import {PoolKey}               from "v4-core/types/PoolKey.sol";
import {BalanceDelta}          from "v4-core/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {Currency}              from "v4-core/types/Currency.sol";
import {IERC20Minimal}         from "v4-core/interfaces/external/IERC20Minimal.sol";

/// @notice Minimal add/remove liquidity router for demo/testnet use.
///         For addLiquidity, caller must approve this contract to spend both tokens.
contract LiquidityHelper is IUnlockCallback {
    IPoolManager public immutable poolManager;

    struct CallbackData {
        PoolKey               key;
        ModifyLiquidityParams params;
        address               sender;
    }

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }

    /// @param liquidityDelta  Positive to add, negative to remove (Uniswap v4 liquidity units)
    function modifyLiquidity(
        PoolKey calldata key,
        int256           liquidityDelta,
        int24            tickLower,
        int24            tickUpper,
        bytes32          salt
    ) external returns (BalanceDelta delta) {
        delta = abi.decode(
            poolManager.unlock(abi.encode(CallbackData({
                key:    key,
                params: ModifyLiquidityParams({
                    tickLower:      tickLower,
                    tickUpper:      tickUpper,
                    liquidityDelta: liquidityDelta,
                    salt:           salt
                }),
                sender: msg.sender
            }))),
            (BalanceDelta)
        );
    }

    function unlockCallback(bytes calldata rawData) external override returns (bytes memory) {
        require(msg.sender == address(poolManager), "only pool manager");
        CallbackData memory d = abi.decode(rawData, (CallbackData));

        (BalanceDelta delta,) = poolManager.modifyLiquidity(d.key, d.params, "");

        int256 delta0 = delta.amount0();
        int256 delta1 = delta.amount1();

        // positive => pool received => sender pays
        if (delta0 > 0) _settle(d.key.currency0, d.sender, uint256(delta0));
        if (delta1 > 0) _settle(d.key.currency1, d.sender, uint256(delta1));
        // negative => pool sent => sender receives
        if (delta0 < 0) _take(d.key.currency0, d.sender, uint256(-delta0));
        if (delta1 < 0) _take(d.key.currency1, d.sender, uint256(-delta1));

        return abi.encode(delta);
    }

    function _settle(Currency currency, address payer, uint256 amount) internal {
        poolManager.sync(currency);
        IERC20Minimal(Currency.unwrap(currency)).transferFrom(payer, address(poolManager), amount);
        poolManager.settle();
    }

    function _take(Currency currency, address recipient, uint256 amount) internal {
        poolManager.take(currency, recipient, amount);
    }
}

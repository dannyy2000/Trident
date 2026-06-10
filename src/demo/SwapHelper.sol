// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager}    from "v4-core/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/interfaces/callback/IUnlockCallback.sol";
import {PoolKey}         from "v4-core/types/PoolKey.sol";
import {BalanceDelta}    from "v4-core/types/BalanceDelta.sol";
import {SwapParams}      from "v4-core/types/PoolOperation.sol";
import {Currency}        from "v4-core/types/Currency.sol";
import {IERC20Minimal}   from "v4-core/interfaces/external/IERC20Minimal.sol";

/// @notice Minimal swap router for demo/testnet use.
///         Caller must approve this contract to spend the input token before calling swap().
contract SwapHelper is IUnlockCallback {
    IPoolManager public immutable poolManager;

    struct CallbackData {
        PoolKey    key;
        SwapParams params;
        address    payer;
        address    recipient;
    }

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }

    /// @param key        The Uniswap v4 pool key (must have TridentHook attached)
    /// @param params     zeroForOne, amountSpecified (negative = exactIn), sqrtPriceLimitX96
    /// @param recipient  Who receives the output tokens
    function swap(
        PoolKey    calldata key,
        SwapParams calldata params,
        address             recipient
    ) external returns (BalanceDelta delta) {
        delta = abi.decode(
            poolManager.unlock(
                abi.encode(CallbackData({key: key, params: params, payer: msg.sender, recipient: recipient}))
            ),
            (BalanceDelta)
        );
    }

    function unlockCallback(bytes calldata rawData) external override returns (bytes memory) {
        require(msg.sender == address(poolManager), "only pool manager");
        CallbackData memory d = abi.decode(rawData, (CallbackData));

        BalanceDelta delta = poolManager.swap(d.key, d.params, "");

        int256 delta0 = delta.amount0();
        int256 delta1 = delta.amount1();

        // positive delta => pool received tokens => caller must pay
        if (delta0 > 0) _settle(d.key.currency0, d.payer,     uint256(delta0));
        if (delta1 > 0) _settle(d.key.currency1, d.payer,     uint256(delta1));
        // negative delta => pool sent tokens => caller receives
        if (delta0 < 0) _take(d.key.currency0, d.recipient, uint256(-delta0));
        if (delta1 < 0) _take(d.key.currency1, d.recipient, uint256(-delta1));

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

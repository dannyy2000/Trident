// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

/// @title InitPool
/// @notice Initialises the Uniswap v4 pool with TridentHook attached.
///         Run after Deploy.s.sol — the pool can only be initialised once per PoolKey.
///
///   forge script script/InitPool.s.sol \
///     --rpc-url $UNICHAIN_SEPOLIA_RPC \
///     --broadcast \
///     -vvvv
contract InitPool is Script {
    using PoolIdLibrary for PoolKey;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address poolManager = vm.envAddress("POOL_MANAGER");
        address hookAddr = vm.envAddress("TRIDENT_HOOK_ADDRESS");
        address token0 = vm.envAddress("TOKEN0");
        address token1 = vm.envAddress("TOKEN1");
        int24 tickSpacing = int24(int256(vm.envUint("TICK_SPACING")));

        // Initial sqrtPriceX96 — represents the starting price of the pool.
        // For a 1:1 pool (testing): 79228162514264337593543950336
        // For ETH=$2000: use a pre-calculated value or pass via env
        uint160 sqrtPriceX96 = uint160(vm.envUint("INIT_SQRT_PRICE_X96"));

        // Sort tokens — v4 requires currency0 < currency1 by address
        (address t0, address t1) = token0 < token1 ? (token0, token1) : (token1, token0);

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(t0),
            currency1: Currency.wrap(t1),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: tickSpacing,
            hooks: IHooks(hookAddr)
        });

        bytes32 poolId = PoolId.unwrap(poolKey.toId());

        console2.log("Initialising pool:");
        console2.log("  token0:       ", t0);
        console2.log("  token1:       ", t1);
        console2.log("  tickSpacing:  ", uint256(int256(tickSpacing)));
        console2.log("  hook:         ", hookAddr);
        console2.log("  sqrtPriceX96: ", sqrtPriceX96);
        console2.log("  Pool ID:      ", vm.toString(poolId));

        vm.startBroadcast(deployerKey);
        IPoolManager(poolManager).initialize(poolKey, sqrtPriceX96);
        vm.stopBroadcast();

        console2.log("\nPool initialised successfully.");
        console2.log("Pool ID:", vm.toString(poolId));
    }
}

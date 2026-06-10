// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";

import {TridentReactive} from "../reactive/TridentReactive.sol";

/// @title DeployReactive
/// @notice Deploys TridentReactive to Reactive Network (Lasna testnet).
///
/// ─── Reactive Network setup ───────────────────────────────────────────────────
/// Chain ID:    5318007
/// RPC:         https://lasna-rpc.rnk.dev/
/// Explorer:    https://lasna-omni.reactscan.net/
/// Faucet:      Send SepETH to 0x9b9BB25f1A81078C544C829c5EB7822d747Cf434 on Eth Sepolia
///              (100 REACT per 1 SepETH, max 5 SepETH per tx)
/// ─────────────────────────────────────────────────────────────────────────────
///
/// Deploy sequence (run from your local machine):
///
///   # 1. Deploy TridentReactive on Lasna
///   PRIVATE_KEY=0x... \
///   REACTIVE_ADAPTER_ADDRESS=0x8E511863Cd5092ca7aF19b35611AA80bF06b7322 \
///   POOL_MANAGER=0x00B036B58a818B1BC34d502D3fE730Db729e62AC \
///   CHAINLINK_FEED=0xc34AD85bD0a4385b1d727b351108881e8C34628e \
///   TOKEN0=0x09727dCebbdfC13BCaf2C03ACFc91AB14B27886b \
///   TOKEN1=0x1BE9b1b76eD8d0d40DB33dCafDBCE0448e4FF200 \
///   TRIDENT_HOOK_ADDRESS=0x1370d2f1244050A152F8a8A0922072bb54eBc6C0 \
///   DEST_CHAIN_ID=1301 TICK_SPACING=60 SQRT_ORACLE_DIVISOR=10000000000 \
///   MANIPULATION_THRESHOLD_BPS=200 INITIAL_ORACLE_PRICE=300000000000 \
///   forge script script/DeployReactive.s.sol \
///     --rpc-url https://lasna-rpc.rnk.dev/ \
///     --broadcast -vvvv
///
///   # 2. Note the TridentReactive address from above output
///
///   # 3. Wire the adapter on Unichain with the TridentReactive address
///   PRIVATE_KEY=0x... \
///   REACTIVE_ADAPTER_ADDRESS=0x8E511863Cd5092ca7aF19b35611AA80bF06b7322 \
///   TRIDENT_HOOK_ADDRESS=0x1370d2f1244050A152F8a8A0922072bb54eBc6C0 \
///   TRIDENT_REACTIVE_ADDRESS=<address from step 2> \
///   forge script script/WireReactive.s.sol \
///     --rpc-url https://sepolia.unichain.org \
///     --broadcast -vvvv
contract DeployReactive is Script {
    using PoolIdLibrary for PoolKey;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        // ── Unichain Sepolia addresses (from Deploy.s.sol output) ─────────────
        address reactiveAdapter = vm.envAddress("REACTIVE_ADAPTER_ADDRESS");
        address poolManager     = vm.envAddress("POOL_MANAGER");
        address chainlinkFeed   = vm.envAddress("CHAINLINK_FEED");
        address token0          = vm.envAddress("TOKEN0");
        address token1          = vm.envAddress("TOKEN1");
        address hookAddr        = vm.envAddress("TRIDENT_HOOK_ADDRESS");

        // ── Pool parameters ───────────────────────────────────────────────────
        uint256 destChainId   = vm.envUint("DEST_CHAIN_ID");          // Unichain Sepolia: 1301
        int24   tickSpacing   = int24(int256(vm.envUint("TICK_SPACING"))); // e.g. 60

        // sqrtOracleDivisor = sqrt(10^(chainlinkDecimals + token0Decimals - token1Decimals))
        // For ETH/USD feed (8 dec) with WETH(18)/USDC(6): sqrt(10^(8+18-6)) = sqrt(10^20) = 1e10
        uint256 sqrtOracleDivisor = vm.envUint("SQRT_ORACLE_DIVISOR");

        uint256 manipulationBps   = vm.envUint("MANIPULATION_THRESHOLD_BPS"); // e.g. 200
        uint256 initialOraclePrice = vm.envUint("INITIAL_ORACLE_PRICE");       // e.g. 2000_0000_0000 (Chainlink 8-dec)

        // ── Compute PoolId (must match the pool initialised by InitPool.s.sol) ─
        // Sort tokens — v4 requires currency0 < currency1 by address
        (address t0, address t1) = token0 < token1 ? (token0, token1) : (token1, token0);

        PoolKey memory poolKey = PoolKey({
            currency0:   Currency.wrap(t0),
            currency1:   Currency.wrap(t1),
            fee:         LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: tickSpacing,
            hooks:       IHooks(hookAddr)
        });
        bytes32 poolId = PoolId.unwrap(poolKey.toId());

        console2.log("Dest chain ID:       ", destChainId);
        console2.log("Pool manager:        ", poolManager);
        console2.log("Chainlink feed:      ", chainlinkFeed);
        console2.log("Reactive adapter:    ", reactiveAdapter);
        console2.log("Pool ID:             ", vm.toString(poolId));
        console2.log("Tick spacing:        ", uint256(int256(tickSpacing)));
        console2.log("sqrtOracleDivisor:   ", sqrtOracleDivisor);
        console2.log("manipulationBps:     ", manipulationBps);
        console2.log("initialOraclePrice:  ", initialOraclePrice);

        vm.startBroadcast(deployerKey);

        TridentReactive reactive = new TridentReactive(
            destChainId,
            poolManager,
            chainlinkFeed,
            reactiveAdapter,
            poolId,
            tickSpacing,
            sqrtOracleDivisor,
            manipulationBps,
            initialOraclePrice
        );

        vm.stopBroadcast();

        console2.log("\n====== TridentReactive Deploy Complete ======");
        console2.log("TridentReactive: ", address(reactive));
        console2.log("=============================================");
        console2.log("");
        console2.log("IMPORTANT: if Deploy.s.sol hasn't been run yet, set:");
        console2.log("  REACTIVE_ORIGIN_ADDRESS =", address(reactive));
        console2.log("Then run Deploy.s.sol on Unichain Sepolia.");
    }
}

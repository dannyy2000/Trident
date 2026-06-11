// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {TridentReactive} from "../reactive/TridentReactive.sol";

/// @title RedeployReactive
/// @notice Redeploys TridentReactive on Lasna with the correct subscription pattern.
///
/// ─── Root cause of the previous failure ─────────────────────────────────────
/// The original TridentReactive was deployed with 0 REACT and no subscriptions
/// in the constructor. The Reactive Network system contract requires funds to be
/// present at deployment to register active subscriptions. A post-deploy
/// setupSubscriptions() call with 0 balance registers the subscription but leaves
/// it inactive; the system never executes react().
///
/// ─── What's fixed in the redeployed contract ────────────────────────────────
/// 1. Constructor now calls service.subscribe() inside if(!vm) — runs on Lasna,
///    skipped in ReactVM (where system contract has no code).
/// 2. Deployed with 0.1 REACT value so the system sees funded subscriptions.
///
/// ─── No other contract changes needed ───────────────────────────────────────
/// ReactiveAdapter already has reactiveOrigin = callback proxy (0x9299...). The
/// adapter doesn't reference TridentReactive's address — it only checks msg.sender
/// == callbackProxy. So the new TridentReactive just needs to point at the same
/// ReactiveAdapter, and callbacks will flow through unchanged.
///
/// ─── Run ─────────────────────────────────────────────────────────────────────
///   PRIVATE_KEY=0x... forge script script/RedeployReactive.s.sol \
///     --rpc-url https://lasna-omni-rpc.rnk.dev/ \
///     --broadcast -vvvv
///
/// ─── After deploy ────────────────────────────────────────────────────────────
/// Do a swap on Unichain Sepolia. Within ~30s, check:
///   cast call <NEW_ADDR> "latestPoolSqrtPrice()(uint160)" --rpc-url https://lasna-omni-rpc.rnk.dev/
/// It should be non-zero if react() fired.
contract RedeployReactive is Script {
    // ── Unichain Sepolia addresses (existing, do not change) ─────────────────
    address constant POOL_MANAGER    = 0x00B036B58a818B1BC34d502D3fE730Db729e62AC;
    address constant CHAINLINK_FEED  = 0x467A074ADE6B5D828cd57EB2CeC76Cc396ca6Db6;
    address constant REACTIVE_ADAPTER = 0x7DAd5E3b0A4AfA91414b30AdBf64E33954278b0c;

    // ── Pool parameters ───────────────────────────────────────────────────────
    uint256 constant DEST_CHAIN_ID   = 1301;
    bytes32 constant POOL_ID         = 0x5e1589e36bf91d1b848851741701815f43d2b750dd64b05135b771f340b1d4e6;
    int24   constant TICK_SPACING    = 60;
    // sqrt(10^(8 + 18 - 6)) = sqrt(10^20) = 1e10  (ETH/USD feed 8dec, WETH 18dec, USDC 6dec)
    uint256 constant SQRT_ORACLE_DIVISOR = 10_000_000_000;
    // Latest Chainlink answer at deploy — will be updated live via AnswerUpdated events
    uint256 constant INITIAL_ORACLE_PRICE = 450_000_000_000; // $4500 in 8-dec

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console2.log("Deployer:            ", deployer);
        console2.log("Deployer balance:    ", deployer.balance);
        console2.log("POOL_MANAGER:        ", POOL_MANAGER);
        console2.log("CHAINLINK_FEED:      ", CHAINLINK_FEED);
        console2.log("REACTIVE_ADAPTER:    ", REACTIVE_ADAPTER);
        console2.log("DEST_CHAIN_ID:       ", DEST_CHAIN_ID);
        console2.log("POOL_ID:             ");
        console2.logBytes32(POOL_ID);

        vm.startBroadcast(deployerKey);

        TridentReactive reactive = new TridentReactive{value: 0.1 ether}(
            DEST_CHAIN_ID,
            POOL_MANAGER,
            CHAINLINK_FEED,
            REACTIVE_ADAPTER,
            POOL_ID,
            TICK_SPACING,
            SQRT_ORACLE_DIVISOR,
            INITIAL_ORACLE_PRICE
        );

        vm.stopBroadcast();

        console2.log("\n====== RedeployReactive Complete ======");
        console2.log("NEW TridentReactive:", address(reactive));
        console2.log("ReactiveAdapter:    ", REACTIVE_ADAPTER);
        console2.log("======================================");
        console2.log("");
        console2.log("Next steps:");
        console2.log("1. Do a swap on Unichain Sepolia");
        console2.log("2. Wait ~30s, then check:");
        console2.log("   cast call", address(reactive));
        console2.log("   'latestPoolSqrtPrice()(uint160)'");
        console2.log("   --rpc-url https://lasna-omni-rpc.rnk.dev/");
        console2.log("   (should be non-zero after first swap)");
    }
}

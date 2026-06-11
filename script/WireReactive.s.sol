// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";

interface IReactiveAdapter {
    function setReactiveOrigin(address newOrigin) external;
    function reactiveOrigin() external view returns (address);
}

interface ITridentHookAdmin {
    function setReactiveContract(address reactiveContract_) external;
}

/// @title WireReactive
/// @notice After deploying TridentReactive on Lasna testnet, run this script on Unichain
///         to wire up the ReactiveAdapter with the correct callback proxy address.
///
/// ─── How Reactive Network callback delivery works ───────────────────────────
/// When TridentReactive (on Lasna) emits:
///   emit Callback(DEST_CHAIN_ID, REACTIVE_ADAPTER, gasLimit, calldata)
///
/// The Reactive Network relay delivers it by calling:
///   callbackProxy.callbackRnk(gasLimit, REACTIVE_ADAPTER, calldata)   [on Unichain]
///
/// The callback proxy then calls:
///   REACTIVE_ADAPTER.primeDeviation(...)   [msg.sender = callbackProxy]
///
/// Therefore ReactiveAdapter.reactiveOrigin must be set to the CALLBACK PROXY address,
/// NOT to TridentReactive's Lasna address. The Lasna address is never msg.sender on
/// the destination chain.
/// ─────────────────────────────────────────────────────────────────────────────
///
/// Required env vars:
///   PRIVATE_KEY                — deployer private key (must be adapter owner)
///   REACTIVE_ADAPTER_ADDRESS   — ReactiveAdapter on Unichain
///   TRIDENT_HOOK_ADDRESS       — TridentHook on Unichain
///   CALLBACK_PROXY_ADDRESS     — Reactive Network callback proxy on Unichain
///                                (Unichain Sepolia: 0x9299472A6399Fd1027ebF067571Eb3e3D7837FC4)
///
/// Run:
///   PRIVATE_KEY=0x... \
///   REACTIVE_ADAPTER_ADDRESS=0x7DAd5E3b0A4AfA91414b30AdBf64E33954278b0c \
///   TRIDENT_HOOK_ADDRESS=0x87Bb5917BA1fa7f4EFD08903a5D305971B4146C0 \
///   CALLBACK_PROXY_ADDRESS=0x9299472A6399Fd1027ebF067571Eb3e3D7837FC4 \
///   forge script script/WireReactive.s.sol \
///     --rpc-url https://unichain-sepolia.drpc.org \
///     --broadcast -vvvv
///
/// ALSO REQUIRED on Lasna (separate step):
///   Fund TridentReactive so the Reactive Network can pay for react() execution:
///   cast send 0xa88B927cB30Dd494E81436bf66b84bB6d70Fd629 \
///     --value 0.5ether \
///     --rpc-url https://lasna-omni-rpc.rnk.dev/ \
///     --private-key $PRIVATE_KEY
///
///   If you need REACT on Lasna: send SepETH to 0x9b9BB25f1A81078C544C829c5EB7822d747Cf434
///   on Ethereum Sepolia. You receive 100 REACT per SepETH at your address on Lasna.
contract WireReactive is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address adapterAddr = vm.envAddress("REACTIVE_ADAPTER_ADDRESS");
        address hookAddr = vm.envAddress("TRIDENT_HOOK_ADDRESS");
        address callbackProxy = vm.envAddress("CALLBACK_PROXY_ADDRESS");

        address deployer = vm.addr(deployerKey);
        console2.log("Deployer:          ", deployer);
        console2.log("ReactiveAdapter:   ", adapterAddr);
        console2.log("TridentHook:       ", hookAddr);
        console2.log("Callback proxy:    ", callbackProxy);

        vm.startBroadcast(deployerKey);

        // Set reactiveOrigin to the callback proxy.
        // The callback proxy is msg.sender when Reactive Network delivers callbacks
        // to this adapter — NOT the TridentReactive contract's Lasna address.
        IReactiveAdapter(adapterAddr).setReactiveOrigin(callbackProxy);
        console2.log("ReactiveAdapter.reactiveOrigin set to callback proxy:", callbackProxy);

        vm.stopBroadcast();

        console2.log("\n====== WireReactive Complete ======");
        console2.log("ReactiveAdapter origin:", IReactiveAdapter(adapterAddr).reactiveOrigin());
        console2.log("Callbacks from TridentReactive will now pass the origin check.");
    }
}

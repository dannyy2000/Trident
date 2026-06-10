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
///         to wire up the ReactiveAdapter with the correct origin address.
///
/// Required env vars:
///   PRIVATE_KEY                — deployer private key (must be adapter owner)
///   REACTIVE_ADAPTER_ADDRESS   — ReactiveAdapter on Unichain (0x8E511863...)
///   TRIDENT_HOOK_ADDRESS       — TridentHook on Unichain (0x1370d2f1...)
///   TRIDENT_REACTIVE_ADDRESS   — TridentReactive deployed on Lasna testnet
///
/// Run:
///   PRIVATE_KEY=0x... \
///   REACTIVE_ADAPTER_ADDRESS=0x8E511863Cd5092ca7aF19b35611AA80bF06b7322 \
///   TRIDENT_HOOK_ADDRESS=0x1370d2f1244050A152F8a8A0922072bb54eBc6C0 \
///   TRIDENT_REACTIVE_ADDRESS=<address from Lasna deploy> \
///   forge script script/WireReactive.s.sol \
///     --rpc-url https://sepolia.unichain.org \
///     --broadcast -vvvv
contract WireReactive is Script {
    function run() external {
        uint256 deployerKey      = vm.envUint("PRIVATE_KEY");
        address adapterAddr      = vm.envAddress("REACTIVE_ADAPTER_ADDRESS");
        address hookAddr         = vm.envAddress("TRIDENT_HOOK_ADDRESS");
        address tridentReactive  = vm.envAddress("TRIDENT_REACTIVE_ADDRESS");

        address deployer = vm.addr(deployerKey);
        console2.log("Deployer:          ", deployer);
        console2.log("ReactiveAdapter:   ", adapterAddr);
        console2.log("TridentHook:       ", hookAddr);
        console2.log("TridentReactive:   ", tridentReactive);

        vm.startBroadcast(deployerKey);

        // 1. Tell ReactiveAdapter which Reactive Network contract is allowed to call it
        IReactiveAdapter(adapterAddr).setReactiveOrigin(tridentReactive);
        console2.log("ReactiveAdapter.reactiveOrigin set to:", tridentReactive);

        // 2. Confirm hook still points to this adapter (should already be correct)
        //    If hook._reactiveContract != adapter, call setReactiveContract:
        //    ITridentHookAdmin(hookAddr).setReactiveContract(adapterAddr);

        vm.stopBroadcast();

        console2.log("\n====== WireReactive Complete ======");
        console2.log("ReactiveAdapter origin:", IReactiveAdapter(adapterAddr).reactiveOrigin());
        console2.log("Reactive callbacks from TridentReactive will now reach the hook.");
    }
}

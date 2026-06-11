// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";

interface IReactiveAdapter {
    function setReactiveOrigin(address newOrigin) external;
    function reactiveOrigin() external view returns (address);
}

/// @title FixReactiveWiring
/// @notice One-shot fix: updates ReactiveAdapter.reactiveOrigin to the Reactive Network
///         callback proxy on Unichain Sepolia.
///
/// ─── Root cause ──────────────────────────────────────────────────────────────
/// The original WireReactive script set reactiveOrigin to TridentReactive's Lasna
/// address. But the Reactive Network callback proxy calls ReactiveAdapter directly —
/// msg.sender at ReactiveAdapter is the callback proxy, not the Lasna address.
/// Every callback was reverting with OnlyReactiveOrigin().
///
/// ─── What this fixes ─────────────────────────────────────────────────────────
/// Sets reactiveOrigin = callbackProxy (0x9299472A6399Fd1027ebF067571Eb3e3D7837FC4)
/// so the onlyReactiveOrigin check passes when callbacks arrive.
///
/// ─── Run ─────────────────────────────────────────────────────────────────────
///   PRIVATE_KEY=0x... forge script script/FixReactiveWiring.s.sol \
///     --rpc-url https://unichain-sepolia.drpc.org \
///     --broadcast -vvvv
///
/// ─── Also needed (separate, on Lasna) ────────────────────────────────────────
/// Fund TridentReactive so the system processes events:
///   cast send 0xa88B927cB30Dd494E81436bf66b84bB6d70Fd629 \
///     --value 0.5ether \
///     --rpc-url https://lasna-omni-rpc.rnk.dev/ \
///     --private-key $PRIVATE_KEY
///
/// Get REACT first if needed (send SepETH → Lasna faucet):
///   cast send 0x9b9BB25f1A81078C544C829c5EB7822d747Cf434 \
///     --value 0.5ether \
///     --rpc-url https://eth-sepolia.g.alchemy.com/v2/... \
///     --private-key $PRIVATE_KEY
/// (you receive 50 REACT at your address on Lasna)
contract FixReactiveWiring is Script {
    address constant REACTIVE_ADAPTER  = 0x7DAd5E3b0A4AfA91414b30AdBf64E33954278b0c;
    address constant CALLBACK_PROXY    = 0x9299472A6399Fd1027ebF067571Eb3e3D7837FC4;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console2.log("Deployer:         ", deployer);
        console2.log("ReactiveAdapter:  ", REACTIVE_ADAPTER);
        console2.log("Callback proxy:   ", CALLBACK_PROXY);
        console2.log("Current origin:   ", IReactiveAdapter(REACTIVE_ADAPTER).reactiveOrigin());

        vm.startBroadcast(deployerKey);
        IReactiveAdapter(REACTIVE_ADAPTER).setReactiveOrigin(CALLBACK_PROXY);
        vm.stopBroadcast();

        console2.log("New origin:       ", IReactiveAdapter(REACTIVE_ADAPTER).reactiveOrigin());
        console2.log("\nReactiveAdapter now accepts callbacks from the Reactive Network proxy.");
        console2.log("Next: fund TridentReactive on Lasna with 0.5+ REACT, then do a swap.");
    }
}

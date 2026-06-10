// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2}    from "forge-std/Script.sol";
import {MockChainlinkFeed}   from "../src/demo/MockChainlinkFeed.sol";

/// @notice Update the mock Chainlink feed price.
///         Use during demo to simulate oracle/pool price divergence and trigger arb premium.
///
/// Required env vars:
///   PRIVATE_KEY        - deployer private key
///   MOCK_FEED_ADDRESS  - address of the deployed MockChainlinkFeed
///   NEW_PRICE          - new answer in feed decimals (e.g. 350000000000 for $3500 with 8 decimals)
contract SetOraclePrice is Script {
    function run() external {
        uint256 pk    = vm.envUint("PRIVATE_KEY");
        address feed  = vm.envAddress("MOCK_FEED_ADDRESS");
        int256  price = int256(vm.envUint("NEW_PRICE"));

        vm.startBroadcast(pk);
        MockChainlinkFeed(feed).setAnswer(price);
        vm.stopBroadcast();

        console2.log("Updated feed to:", feed);
        console2.log("New price:      ", price);
    }
}

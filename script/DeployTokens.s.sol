// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {MockERC20} from "../src/demo/MockERC20.sol";

/// @notice Deploys a mintable mock USDC for testnet demos.
///         WETH is the native wrapped ETH at 0x4200000000000000000000000000000000000006.
///         After running this script:
///           1. Note the MockUSDC address
///           2. Sort it against WETH to determine TOKEN0 / TOKEN1
///           3. Call mockUsdc.mint(yourWallet, <amount>) to fund yourself
///           4. Wrap ETH: cast send 0x4200...0006 "deposit()" --value <amount> --rpc-url ...
///
/// Required env vars:
///   PRIVATE_KEY         - deployer private key
///   INITIAL_USDC_MINT   - amount of USDC to mint to deployer (e.g. 1000000000000 = 1,000,000 USDC)
contract DeployTokens is Script {
    address constant WETH = 0x4200000000000000000000000000000000000006;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        uint256 mintAmt = vm.envUint("INITIAL_USDC_MINT");
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);
        MockERC20 usdc = new MockERC20("Demo USD Coin", "dUSDC", 6);
        usdc.mint(deployer, mintAmt);
        vm.stopBroadcast();

        console2.log("MockUSDC:          ", address(usdc));
        console2.log("WETH:              ", WETH);
        console2.log("Minted to deployer:", mintAmt);
        console2.log("");

        // Determine sort order
        if (address(usdc) < WETH) {
            console2.log("TOKEN0 (usdc):", address(usdc));
            console2.log("TOKEN1 (weth):", WETH);
        } else {
            console2.log("TOKEN0 (weth):", WETH);
            console2.log("TOKEN1 (usdc):", address(usdc));
        }
        console2.log("");
        console2.log("Add to .env:");
        console2.log("  NEXT_PUBLIC_TOKEN0=<TOKEN0 above>");
        console2.log("  NEXT_PUBLIC_TOKEN1=<TOKEN1 above>");
        console2.log("  NEXT_PUBLIC_PAYOUT_TOKEN=<TOKEN0 above>  # vault pays in the input token");
    }
}

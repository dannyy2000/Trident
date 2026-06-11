// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";

interface IMockERC20 {
    function mint(address to, uint256 amount) external;
    function balanceOf(address) external view returns (uint256);
}

interface ITridentHook {
    function pendingCapture(address token) external view returns (uint256);
    function flushToVault(address token) external;
}

interface IILReserveVault {
    function totalReserveBalance() external view returns (uint256);
}

/// @title SeedVault
/// @notice Reads accumulated pendingCapture from the hook, mints that amount of mWETH
///         directly to the hook, then calls flushToVault to move it into the vault.
///
///         Run this AFTER doing at least a few swaps so pendingCapture is non-zero.
///         For best demo effect, do 5-10 swaps of 1+ mWETH first.
///
/// Required env vars:
///   PRIVATE_KEY         — deployer key
///   TRIDENT_HOOK        — TridentHook address
///   TOKEN0              — MockWETH (the vault payout token)
///   IL_RESERVE_VAULT    — ILReserveVault address
///
/// Run:
///   PRIVATE_KEY=0x... \
///   TRIDENT_HOOK=0x1370d2f1244050A152F8a8A0922072bb54eBc6C0 \
///   TOKEN0=0x09727dCebbdfC13BCaf2C03ACFc91AB14B27886b \
///   IL_RESERVE_VAULT=0x6aD065F00ABa43f79920d229EDEe5DABCDd3cfFD \
///   forge script script/SeedVault.s.sol \
///     --rpc-url https://sepolia.unichain.org \
///     --broadcast -vvvv
contract SeedVault is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address hook = vm.envAddress("TRIDENT_HOOK");
        address token0 = vm.envAddress("TOKEN0");
        address vault = vm.envAddress("IL_RESERVE_VAULT");

        // Read how much the hook thinks it needs to flush
        uint256 pending = ITridentHook(hook).pendingCapture(token0);
        console2.log("pendingCapture (mWETH units):", pending);

        if (pending == 0) {
            console2.log("ERROR: pendingCapture is 0. Do some swaps first, then re-run.");
            return;
        }

        uint256 vaultBefore = IILReserveVault(vault).totalReserveBalance();
        console2.log("Vault balance before:", vaultBefore);

        vm.startBroadcast(deployerKey);

        // Mint exactly the pending amount directly to the hook (MockERC20 has open mint)
        IMockERC20(token0).mint(hook, pending);
        console2.log("Minted", pending, "mWETH to hook");

        // Hook approves vault and deposits — vault balance increases
        ITridentHook(hook).flushToVault(token0);
        console2.log("flushToVault called");

        vm.stopBroadcast();

        uint256 vaultAfter = IILReserveVault(vault).totalReserveBalance();
        console2.log("Vault balance after: ", vaultAfter);
        console2.log("Vault funded with:   ", vaultAfter - vaultBefore, "mWETH");
        console2.log("");
        console2.log("Vault is live. LPs removing liquidity will receive payout.");
    }
}

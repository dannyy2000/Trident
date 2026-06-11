// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Currency} from "v4-core/types/Currency.sol";

import {TridentHook} from "../src/TridentHook.sol";
import {ILReserveVault} from "../src/ILReserveVault.sol";
import {OracleReader} from "../src/OracleReader.sol";
import {GammaScorer} from "../src/GammaScorer.sol";
import {PositionTracker} from "../src/PositionTracker.sol";
import {ReactiveAdapter} from "../src/ReactiveAdapter.sol";
import {IILReserveVault} from "../src/interfaces/IILReserveVault.sol";
import {IOracleReader} from "../src/interfaces/IOracleReader.sol";

/// @title Deploy
/// @notice Deploys the full Trident system to Unichain Sepolia (or any target chain).
///
/// Prerequisites:
///   1. Deploy TridentReactive on Reactive Network first (DeployReactive.s.sol).
///      You need REACTIVE_ORIGIN_ADDRESS from that deployment.
///   2. Set all env vars in a .env file (see .env.example).
///
/// Run:
///   forge script script/Deploy.s.sol \
///     --rpc-url $UNICHAIN_SEPOLIA_RPC \
///     --broadcast \
///     --verify \
///     -vvvv
///
/// Deployment order (nonce-based for all except TridentHook):
///   N+0  OracleReader        — nonce-based CREATE
///   N+1  GammaScorer         — nonce-based CREATE
///   N+2  ILReserveVault      — nonce-based CREATE (holds hookAddr as immutable)
///   N+3  PositionTracker     — nonce-based CREATE (holds hookAddr + adapterAddr)
///   N+4  TridentHook         — CREATE2 (mined address with correct permission flags)
///   N+5  ReactiveAdapter     — nonce-based CREATE
///
/// The hook is the only contract requiring CREATE2 because its address encodes its
/// Uniswap v4 hook permissions in the lowest 14 bits.
contract Deploy is Script {
    using PoolIdLibrary for PoolKey;

    // ── Hook permission flags — must match TridentHook.getHookPermissions() ──
    uint160 constant HOOK_FLAGS = Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG
        | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG;

    // Maximum salt iterations for hook address mining (expected: ~16_384 on average)
    uint256 constant MINE_LIMIT = 500_000;

    // Chainlink staleness threshold (1 hour) and oracle manipulation guard (2%)
    uint256 constant STALENESS_THRESHOLD = 3600;
    uint256 constant MANIPULATION_THRESHOLD_BPS = 200;

    function run() external {
        // ── Load env ─────────────────────────────────────────────────────────
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        address poolManager = vm.envAddress("POOL_MANAGER");
        address chainlinkFeed = vm.envAddress("CHAINLINK_FEED");
        address payoutToken = vm.envAddress("PAYOUT_TOKEN");
        address reactiveOrigin = vm.envAddress("REACTIVE_ORIGIN_ADDRESS");
        uint256 decimalAdjustment = vm.envUint("DECIMAL_ADJUSTMENT");
        uint24 baseFee = uint24(vm.envUint("BASE_FEE_BPS"));

        console2.log("Deployer:     ", deployer);
        console2.log("Pool manager: ", poolManager);
        console2.log("Payout token: ", payoutToken);

        // ── Pre-compute nonce-based addresses ─────────────────────────────────
        // The nonce BEFORE any broadcast transactions is the current nonce.
        // Each `new Contract()` increments the nonce by 1 (including CREATE2).
        uint256 nonce = vm.getNonce(deployer);

        address oracleReaderAddr = vm.computeCreateAddress(deployer, nonce);
        address gammaScorerAddr = vm.computeCreateAddress(deployer, nonce + 1);
        address vaultAddr = vm.computeCreateAddress(deployer, nonce + 2);
        address trackerAddr = vm.computeCreateAddress(deployer, nonce + 3);
        // nonce + 4 is consumed by the hook's CREATE2 tx (nonce still increments)
        address adapterAddr = vm.computeCreateAddress(deployer, nonce + 5);

        console2.log("\n-- Pre-computed addresses --");
        console2.log("OracleReader (expected):    ", oracleReaderAddr);
        console2.log("GammaScorer  (expected):    ", gammaScorerAddr);
        console2.log("Vault        (expected):    ", vaultAddr);
        console2.log("Tracker      (expected):    ", trackerAddr);
        console2.log("Adapter      (expected):    ", adapterAddr);

        // ── Mine hook CREATE2 salt ─────────────────────────────────────────────
        // We know vault and tracker addresses (nonce-based), so we can fully encode
        // the hook's constructor args and mine a salt that produces the right flags.
        console2.log("\nMining hook address (target flags: 0x%x)...", HOOK_FLAGS);
        (address hookAddr, bytes32 hookSalt) = _mineHookSalt(
            poolManager,
            oracleReaderAddr,
            gammaScorerAddr,
            vaultAddr,
            trackerAddr,
            baseFee,
            decimalAdjustment,
            adapterAddr,
            deployer
        );
        console2.log("Hook address (mined):       ", hookAddr);
        console2.log("Hook salt:                  ", vm.toString(hookSalt));

        // ── Deploy ────────────────────────────────────────────────────────────
        vm.startBroadcast(deployerKey);

        // N+0
        OracleReader oracleReader = new OracleReader(chainlinkFeed, STALENESS_THRESHOLD, MANIPULATION_THRESHOLD_BPS);
        require(address(oracleReader) == oracleReaderAddr, "Deploy: OracleReader address mismatch");

        // N+1
        GammaScorer gammaScorer = new GammaScorer();
        require(address(gammaScorer) == gammaScorerAddr, "Deploy: GammaScorer address mismatch");

        // N+2 — vault immutably records hookAddr (not yet deployed, but address is known)
        ILReserveVault vault = new ILReserveVault(payoutToken, hookAddr);
        require(address(vault) == vaultAddr, "Deploy: Vault address mismatch");

        // N+3 — tracker immutably records hookAddr + adapterAddr (adapter not yet deployed)
        PositionTracker tracker = new PositionTracker(hookAddr, adapterAddr);
        require(address(tracker) == trackerAddr, "Deploy: Tracker address mismatch");

        // N+4 — hook at CREATE2-mined address (nonce still increments by 1)
        TridentHook hook = new TridentHook{salt: hookSalt}(
            IPoolManager(poolManager),
            IOracleReader(oracleReaderAddr),
            GammaScorer(gammaScorerAddr),
            IILReserveVault(vaultAddr),
            PositionTracker(trackerAddr),
            baseFee,
            decimalAdjustment,
            adapterAddr, // _reactiveContract_ — adapter will be deployed at N+5
            deployer // owner
        );
        require(address(hook) == hookAddr, "Deploy: Hook address mismatch - re-run mining");

        // N+5 — adapter validates that msg.sender == reactiveOrigin before forwarding
        ReactiveAdapter adapter = new ReactiveAdapter(hookAddr, reactiveOrigin);
        require(address(adapter) == adapterAddr, "Deploy: Adapter address mismatch");

        vm.stopBroadcast();

        // ── Summary ───────────────────────────────────────────────────────────
        console2.log("\n====== Trident Deploy Complete ======");
        console2.log("OracleReader:    ", address(oracleReader));
        console2.log("GammaScorer:     ", address(gammaScorer));
        console2.log("ILReserveVault:  ", address(vault));
        console2.log("PositionTracker: ", address(tracker));
        console2.log("TridentHook:     ", address(hook));
        console2.log("ReactiveAdapter: ", address(adapter));
        console2.log("=====================================");
        console2.log("");
        console2.log("Next steps:");
        console2.log("  1. Run DeployReactive.s.sol on Reactive Network with:");
        console2.log("     REACTIVE_ADAPTER_ADDRESS =", address(adapter));
        console2.log("  2. Run InitPool.s.sol to create the Uniswap v4 pool with the hook.");
    }

    // ── Internal: mine a CREATE2 salt that produces an address with HOOK_FLAGS ─

    function _mineHookSalt(
        address poolManager_,
        address oracleReader_,
        address gammaScorer_,
        address vault_,
        address tracker_,
        uint24 baseFee_,
        uint256 decimalAdj_,
        address adapter_,
        address owner_
    ) internal view returns (address hookAddr, bytes32 hookSalt) {
        bytes memory constructorArgs = abi.encode(
            IPoolManager(poolManager_),
            IOracleReader(oracleReader_),
            GammaScorer(gammaScorer_),
            IILReserveVault(vault_),
            PositionTracker(tracker_),
            baseFee_,
            decimalAdj_,
            adapter_,
            owner_
        );
        bytes32 initcodeHash = keccak256(abi.encodePacked(type(TridentHook).creationCode, constructorArgs));

        for (uint256 i = 0; i < MINE_LIMIT; i++) {
            hookSalt = bytes32(i);
            // Two-arg form uses Foundry's deterministic CREATE2 factory
            // (0x4e59b44847b379578588920cA78FbF26c0B4956C) — same factory used when
            // Foundry broadcasts `new Contract{salt}()` from a script.
            hookAddr = vm.computeCreate2Address(hookSalt, initcodeHash);
            if (uint160(hookAddr) & Hooks.ALL_HOOK_MASK == HOOK_FLAGS) {
                return (hookAddr, hookSalt);
            }
        }
        revert("HookMiner: exhausted MINE_LIMIT without finding a valid salt");
    }
}

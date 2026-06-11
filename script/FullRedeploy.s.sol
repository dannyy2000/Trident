// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2}    from "forge-std/Script.sol";
import {Hooks}                from "v4-core/libraries/Hooks.sol";
import {IPoolManager}         from "v4-core/interfaces/IPoolManager.sol";
import {LPFeeLibrary}         from "v4-core/libraries/LPFeeLibrary.sol";
import {PoolKey}              from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {IHooks}               from "v4-core/interfaces/IHooks.sol";
import {Currency}             from "v4-core/types/Currency.sol";

import {TridentHook}     from "../src/TridentHook.sol";
import {ILReserveVault}  from "../src/ILReserveVault.sol";
import {OracleReader}    from "../src/OracleReader.sol";
import {GammaScorer}     from "../src/GammaScorer.sol";
import {PositionTracker} from "../src/PositionTracker.sol";
import {ReactiveAdapter} from "../src/ReactiveAdapter.sol";
import {IILReserveVault} from "../src/interfaces/IILReserveVault.sol";
import {IOracleReader}   from "../src/interfaces/IOracleReader.sol";

import {MockChainlinkFeed} from "../src/demo/MockChainlinkFeed.sol";
import {MockERC20}         from "../src/demo/MockERC20.sol";
import {SwapHelper}        from "../src/demo/SwapHelper.sol";
import {LiquidityHelper}   from "../src/demo/LiquidityHelper.sol";

/// @title FullRedeploy
/// @notice Single-command full redeploy of the entire Trident system.
///         Deploys all contracts in the correct nonce order, initialises the
///         Uniswap v4 pool at the correct $3000 ETH/USDC price, and prints
///         every address the frontend needs.
///
/// Required env vars:
///   PRIVATE_KEY   — 0x-prefixed deployer key
///
/// Run:
///   PRIVATE_KEY=0x... forge script script/FullRedeploy.s.sol \
///     --rpc-url https://sepolia.unichain.org \
///     --broadcast --skip-simulation -vvvv
contract FullRedeploy is Script {
    using PoolIdLibrary for PoolKey;

    // ── Constants ────────────────────────────────────────────────────────────
    address constant POOL_MANAGER = 0x00B036B58a818B1BC34d502D3fE730Db729e62AC;

    // Hook CREATE2 permission flags (must match TridentHook.getHookPermissions)
    uint160 constant HOOK_FLAGS =
        Hooks.BEFORE_SWAP_FLAG |
        Hooks.AFTER_SWAP_FLAG |
        Hooks.AFTER_ADD_LIQUIDITY_FLAG |
        Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG;

    uint256 constant MINE_LIMIT = 500_000;

    // Pool parameters
    int24   constant TICK_SPACING = 60;
    uint24  constant BASE_FEE     = 3_000; // 0.30%

    // Correct sqrtPriceX96 for mWETH(18dec)/mUSDC(6dec) at ~$3000
    // = sqrt(3000 * 1e6 / 1e18) * 2^96
    uint160 constant INIT_SQRT_PRICE = 4339505179874779662909440;

    // decimalAdjustment = 10^(token0Decimals - token1Decimals + 18) = 10^(18-6+18) = 10^30
    uint256 constant DECIMAL_ADJUSTMENT = 1_000_000_000_000_000_000_000_000_000_000;

    // Mock Chainlink feed: $3000 with 8 decimals
    int256  constant INITIAL_ORACLE_PRICE = 300_000_000_000; // $3000 * 1e8
    uint8   constant FEED_DECIMALS        = 8;

    // Staleness + manipulation thresholds
    uint256 constant STALENESS_THRESHOLD       = 3_600;
    uint256 constant MANIPULATION_THRESHOLD    = 200;

    // Reactive origin placeholder — replace with real Kopli address if wiring reactive
    address constant REACTIVE_ORIGIN = address(1);

    // Mint amounts for deployer
    uint256 constant WETH_MINT = 100 ether;              // 100 mWETH
    uint256 constant USDC_MINT = 300_000 * 1e6;          // 300,000 mUSDC

    function run() external {
        uint256 pk       = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        // ── Pre-compute nonce-based addresses ─────────────────────────────────
        // Every broadcast call (deploy OR external fn call) consumes one nonce.
        // Full transaction sequence:
        //   N+0   new MockERC20(usdc)
        //   N+1   usdc.mint(deployer, ...)          ← external call = tx
        //   N+2   new MockChainlinkFeed(feed)
        //   N+3   new MockERC20(weth)
        //   N+4   weth.mint(deployer, ...)          ← external call = tx
        //   N+5   new SwapHelper
        //   N+6   new LiquidityHelper
        //   N+7   new OracleReader
        //   N+8   new GammaScorer
        //   N+9   new ILReserveVault
        //   N+10  new PositionTracker
        //   N+11  new TridentHook (CREATE2 via factory — still increments nonce)
        //   N+12  new ReactiveAdapter
        //   N+13  IPoolManager.initialize(...)       ← external call = tx
        uint256 nonce = vm.getNonce(deployer);

        address oracleReaderAddr = vm.computeCreateAddress(deployer, nonce + 7);
        address gammaScorerAddr  = vm.computeCreateAddress(deployer, nonce + 8);
        address vaultAddr        = vm.computeCreateAddress(deployer, nonce + 9);
        address trackerAddr      = vm.computeCreateAddress(deployer, nonce + 10);
        address adapterAddr      = vm.computeCreateAddress(deployer, nonce + 12);

        // Mine hook salt before broadcasting
        console2.log("Mining hook address...");
        (address hookAddr, bytes32 hookSalt) = _mineHookSalt(
            oracleReaderAddr, gammaScorerAddr, vaultAddr, trackerAddr, adapterAddr, deployer
        );
        console2.log("Hook address:", hookAddr);

        vm.startBroadcast(pk);

        // N+0  new MockERC20(usdc)
        MockERC20 usdc = new MockERC20("Mock USDC", "mUSDC", 6);
        // N+1  usdc.mint(...)
        usdc.mint(deployer, USDC_MINT);

        // N+2  new MockChainlinkFeed — seeded at $3000
        MockChainlinkFeed feed = new MockChainlinkFeed(INITIAL_ORACLE_PRICE, FEED_DECIMALS);

        // N+3  new MockERC20(weth)
        MockERC20 weth = new MockERC20("Mock WETH", "mWETH", 18);
        // N+4  weth.mint(...)
        weth.mint(deployer, WETH_MINT);

        // N+5  new SwapHelper
        SwapHelper swapHelper = new SwapHelper(IPoolManager(POOL_MANAGER));

        // N+6  new LiquidityHelper
        LiquidityHelper liqHelper = new LiquidityHelper(IPoolManager(POOL_MANAGER));

        // N+7  new OracleReader
        OracleReader oracleReader = new OracleReader(address(feed), STALENESS_THRESHOLD, MANIPULATION_THRESHOLD);
        require(address(oracleReader) == oracleReaderAddr, "OracleReader addr mismatch");

        // N+8  new GammaScorer
        GammaScorer gammaScorer = new GammaScorer();
        require(address(gammaScorer) == gammaScorerAddr, "GammaScorer addr mismatch");

        // Determine token sort order (v4 requires currency0 < currency1)
        (address token0, address token1) = address(weth) < address(usdc)
            ? (address(weth), address(usdc))
            : (address(usdc), address(weth));

        address payoutToken = token0; // vault pays in token0

        // N+9  new ILReserveVault
        ILReserveVault vault = new ILReserveVault(payoutToken, hookAddr);
        require(address(vault) == vaultAddr, "Vault addr mismatch");

        // N+10 new PositionTracker
        PositionTracker tracker = new PositionTracker(hookAddr, adapterAddr);
        require(address(tracker) == trackerAddr, "Tracker addr mismatch");

        // N+11 new TridentHook (CREATE2)
        TridentHook hook = new TridentHook{salt: hookSalt}(
            IPoolManager(POOL_MANAGER),
            IOracleReader(oracleReaderAddr),
            GammaScorer(gammaScorerAddr),
            IILReserveVault(vaultAddr),
            PositionTracker(trackerAddr),
            BASE_FEE,
            DECIMAL_ADJUSTMENT,
            adapterAddr,
            deployer
        );
        require(address(hook) == hookAddr, "Hook addr mismatch - re-run salt mining");

        // N+12 new ReactiveAdapter
        ReactiveAdapter adapter = new ReactiveAdapter(hookAddr, REACTIVE_ORIGIN);
        require(address(adapter) == adapterAddr, "Adapter addr mismatch");

        // ── Initialise pool ───────────────────────────────────────────────────
        PoolKey memory poolKey = PoolKey({
            currency0:   Currency.wrap(token0),
            currency1:   Currency.wrap(token1),
            fee:         LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: TICK_SPACING,
            hooks:       IHooks(hookAddr)
        });

        IPoolManager(POOL_MANAGER).initialize(poolKey, INIT_SQRT_PRICE);

        bytes32 poolId = PoolId.unwrap(poolKey.toId());

        vm.stopBroadcast();

        // ── Print everything the frontend needs ───────────────────────────────
        console2.log("\n========== FULL REDEPLOY COMPLETE ==========");
        console2.log("TOKEN0 (mWETH):", token0);
        console2.log("TOKEN1 (mUSDC):", token1);
        console2.log("wethIsToken0:  ", address(weth) < address(usdc));
        console2.log("");
        console2.log("HOOK:             ", hookAddr);
        console2.log("VAULT:            ", address(vault));
        console2.log("TRACKER:          ", address(tracker));
        console2.log("ORACLE_READER:    ", address(oracleReader));
        console2.log("REACTIVE_ADAPTER: ", address(adapter));
        console2.log("MOCK_FEED:        ", address(feed));
        console2.log("SWAP_HELPER:      ", address(swapHelper));
        console2.log("LIQUIDITY_HELPER: ", address(liqHelper));
        console2.log("PAYOUT_TOKEN:     ", payoutToken);
        console2.log("POOL_ID:          ", vm.toString(poolId));
        console2.log("");
        console2.log("============ COPY TO frontend/lib/contracts.ts ============");
        console2.log("hook:            '", hookAddr);
        console2.log("vault:           '", address(vault));
        console2.log("tracker:         '", address(tracker));
        console2.log("oracleReader:    '", address(oracleReader));
        console2.log("reactiveAdapter: '", address(adapter));
        console2.log("payoutToken:     '", payoutToken);
        console2.log("swapHelper:      '", address(swapHelper));
        console2.log("liquidityHelper: '", address(liqHelper));
        console2.log("mockFeed:        '", address(feed));
        console2.log("poolManager:     '", POOL_MANAGER);
        console2.log("token0:          '", token0);
        console2.log("token1:          '", token1);
        console2.log("POOL_ID:         '", vm.toString(poolId));
        console2.log("==========================================================");
    }

    function _mineHookSalt(
        address oracleReader_,
        address gammaScorer_,
        address vault_,
        address tracker_,
        address adapter_,
        address owner_
    ) internal view returns (address hookAddr, bytes32 hookSalt) {
        bytes memory args = abi.encode(
            IPoolManager(POOL_MANAGER),
            IOracleReader(oracleReader_),
            GammaScorer(gammaScorer_),
            IILReserveVault(vault_),
            PositionTracker(tracker_),
            BASE_FEE,
            DECIMAL_ADJUSTMENT,
            adapter_,
            owner_
        );
        bytes32 initcodeHash = keccak256(abi.encodePacked(type(TridentHook).creationCode, args));

        for (uint256 i = 0; i < MINE_LIMIT; i++) {
            hookSalt = bytes32(i);
            hookAddr = vm.computeCreate2Address(hookSalt, initcodeHash);
            if (uint160(hookAddr) & Hooks.ALL_HOOK_MASK == HOOK_FLAGS) return (hookAddr, hookSalt);
        }
        revert("HookMiner: no valid salt found within MINE_LIMIT");
    }
}

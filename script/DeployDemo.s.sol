// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {MockChainlinkFeed} from "../src/demo/MockChainlinkFeed.sol";
import {MockERC20}          from "../src/demo/MockERC20.sol";
import {SwapHelper}         from "../src/demo/SwapHelper.sol";
import {LiquidityHelper}    from "../src/demo/LiquidityHelper.sol";
import {IPoolManager}       from "v4-core/interfaces/IPoolManager.sol";

/// @notice Deploys all demo-only infrastructure in one shot:
///           1. MockChainlinkFeed  (nonce N)
///           2. MockWETH           (nonce N+1) ← predicted to be token0 given current deployer nonce
///           3. SwapHelper         (nonce N+2)
///           4. LiquidityHelper    (nonce N+3)
///
///         MockUSDC was already deployed by DeployTokens.s.sol.
///         Run this BEFORE Deploy.s.sol so CHAINLINK_FEED is known.
///
/// Required env vars:
///   PRIVATE_KEY               - deployer private key (0x-prefixed)
///   POOL_MANAGER              - IPoolManager on Unichain Sepolia
///   INITIAL_ETH_USD_PRICE     - Chainlink-format answer, e.g. 300000000000 (=$3000, 8 dec)
///   FEED_DECIMALS             - 8 for standard ETH/USD
///   MOCK_USDC_ADDRESS         - address of MockUSDC from DeployTokens.s.sol
///   WETH_MINT_AMOUNT          - how much MockWETH to mint to deployer, e.g. 100000000000000000000 (=100 ETH)
///   USDC_MINT_AMOUNT          - additional MockUSDC to mint to deployer, e.g. 300000000000 (=300,000 USDC)
contract DeployDemo is Script {
    function run() external {
        uint256 pk          = vm.envUint("PRIVATE_KEY");
        address pm          = vm.envAddress("POOL_MANAGER");
        int256  price       = int256(vm.envUint("INITIAL_ETH_USD_PRICE"));
        uint8   feedDec     = uint8(vm.envUint("FEED_DECIMALS"));
        address mockUSDC    = vm.envAddress("MOCK_USDC_ADDRESS");
        uint256 wethMint    = vm.envUint("WETH_MINT_AMOUNT");
        uint256 usdcMint    = vm.envUint("USDC_MINT_AMOUNT");
        address deployer    = vm.addr(pk);

        vm.startBroadcast(pk);

        // 1. MockChainlinkFeed
        MockChainlinkFeed feed  = new MockChainlinkFeed(price, feedDec);

        // 2. MockWETH — deployed at nonce N+1; predicted lower than MockUSDC → becomes token0
        MockERC20 weth = new MockERC20("Mock WETH", "mWETH", 18);
        weth.mint(deployer, wethMint);

        // Extra USDC mint for LP liquidity
        MockERC20(mockUSDC).mint(deployer, usdcMint);

        // 3 & 4. Routers
        SwapHelper       swapH = new SwapHelper(IPoolManager(pm));
        LiquidityHelper  liqH  = new LiquidityHelper(IPoolManager(pm));

        vm.stopBroadcast();

        // Sort order
        address token0 = address(weth) < mockUSDC ? address(weth) : mockUSDC;
        address token1 = address(weth) < mockUSDC ? mockUSDC : address(weth);
        bool wethIsToken0 = address(weth) < mockUSDC;

        console2.log("=== Demo Contracts ===");
        console2.log("MockChainlinkFeed:", address(feed));
        console2.log("MockWETH:         ", address(weth));
        console2.log("SwapHelper:       ", address(swapH));
        console2.log("LiquidityHelper:  ", address(liqH));
        console2.log("");
        console2.log("=== Token Sort Order ===");
        console2.log("TOKEN0 (lower):", token0, wethIsToken0 ? "(mWETH)" : "(mUSDC)");
        console2.log("TOKEN1 (upper):", token1, wethIsToken0 ? "(mUSDC)" : "(mWETH)");
        console2.log("wethIsToken0:", wethIsToken0);
        console2.log("");
        console2.log("=== Copy to .env ===");
        console2.log("CHAINLINK_FEED=  ", address(feed));
        console2.log("TOKEN0=          ", token0);
        console2.log("TOKEN1=          ", token1);
        console2.log("PAYOUT_TOKEN=    ", token0);
        console2.log("");
        console2.log("=== Copy to frontend/.env.local ===");
        console2.log("NEXT_PUBLIC_MOCK_FEED=       ", address(feed));
        console2.log("NEXT_PUBLIC_SWAP_HELPER=     ", address(swapH));
        console2.log("NEXT_PUBLIC_LIQUIDITY_HELPER=", address(liqH));
        console2.log("NEXT_PUBLIC_TOKEN0=          ", token0);
        console2.log("NEXT_PUBLIC_TOKEN1=          ", token1);
        console2.log("NEXT_PUBLIC_PAYOUT_TOKEN=    ", token0);

        if (!wethIsToken0) {
            console2.log("");
            console2.log("WARNING: weth ended up as token1.");
            console2.log("Use DECIMAL_ADJUSTMENT=1000000 and SQRT_ORACLE_DIVISOR=100");
            console2.log("and set INITIAL_ETH_USD_PRICE=33333 (inverted 1/3000 * 1e8)");
        }
    }
}

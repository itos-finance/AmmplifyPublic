// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/console2.sol";

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IUniswapV3Pool } from "lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import { AmmplifyPositions } from "../AmmplifyPositions.s.sol";

/**
 * @title OpenMaker
 * @notice Example script to open a maker position directly (without NFT wrapper)
 * @dev Run with: forge script script/actions/OpenMaker.s.sol --broadcast --rpc-url <RPC_URL>
 */
contract OpenMaker is AmmplifyPositions {
    function run() public override {
        // Load deployer addresses from .env file
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console2.log("=== Opening Direct Maker Position (No NFT) ===");
        console2.log("Deployer address:", deployer);

        address pool = getPoolAddress("USDC_WETH_3000");

        // Get current pool state
        printPoolState(pool);

        // Query slot0 to get current tick
        (, int24 currentTick, , , , , ) = IUniswapV3Pool(pool).slot0();
        console2.log("Current tick from slot0:", currentTick);

        // Fund the account with tokens (if using mock tokens)
        fundAccount(deployer, 1000000000e6, 10000e18, pool);

        // Set up token approvals for diamond contract
        address[] memory tokens = new address[](2);
        tokens[0] = getToken0(pool);
        tokens[1] = getToken1(pool);
        address[] memory spenders = new address[](1);
        spenders[0] = env.diamond;
        setupApprovals(tokens, spenders, type(uint256).max);

        // Calculate ticks ±300 around current tick, ensuring they're valid for 3000 fee tier (tick spacing = 60)
        int24 tickRange = 300;
        int24 lowTick = getValidTick(currentTick - tickRange, 3000);
        int24 highTick = getValidTick(currentTick + tickRange, 3000);

        MakerParams memory params = MakerParams({
            recipient: 0xbe7dC5cC7977ac378ead410869D6c96f1E6C773e,
            poolAddr: pool,
            lowTick: lowTick,
            highTick: highTick,
            liquidity: 64861280439056 - 10_000,
            isCompounding: true,
            minSqrtPriceX96: MIN_SQRT_RATIO,
            maxSqrtPriceX96: MAX_SQRT_RATIO,
            rftData: ""
        });

        console2.log("=== Maker Parameters ===");
        console2.log("Recipient:", params.recipient);
        console2.log("Pool:", params.poolAddr);
        console2.log("Low Tick:", params.lowTick);
        console2.log("High Tick:", params.highTick);
        console2.log("Liquidity:", params.liquidity);
        console2.log("Is Compounding:", params.isCompounding);

        // Open the position directly (no NFT wrapper)
        uint256 assetId = openMaker(params);

        console2.log("=== Position Created Successfully ===");
        console2.log("Asset ID:", assetId);
        console2.log("Note: This position is NOT wrapped as an NFT");

        // Check balances after
        uint256 usdcBalance = IERC20(getTokenAddress("USDC")).balanceOf(deployer);
        uint256 wethBalance = IERC20(getTokenAddress("WETH")).balanceOf(deployer);

        console2.log("=== Final Balances ===");
        console2.log("USDC Balance:", usdcBalance);
        console2.log("WETH Balance:", wethBalance);

        vm.stopBroadcast();
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/console2.sol";

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

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

        // Get current pool state
        printPoolState(env.usdcWethPool);

        // Fund the account with tokens (if using mock tokens)
        fundAccount(deployer, 1000000000e6, 10000e18);

        // Set up token approvals for diamond contract (approve max to avoid allowance issues)
        setupApprovals(type(uint256).max);

        // Create maker parameters for a position around current price
        MakerParams memory params = getDefaultMakerParams(deployer);

        // Adjust liquidity based on available tokens
        params.liquidity = 1e18;

        // Use valid ticks for 3000 fee tier (tick spacing = 60)
        // Create a smaller range around current price (tick 0) to avoid extreme values
        params.lowTick = -491460; // getValidTick(-14787 * 60, 3000) + 360000;
        params.highTick = 491460; // getValidTick(14787 * 60, 3000) - 360000;
        // params.lowTick = -195720;
        // params.highTick = -191700;
        params.liquidity = 64861280439056;

        console2.log("=== Maker Parameters ===");
        console2.log("Recipient:", params.recipient);
        console2.log("Pool:", params.poolAddr);
        console2.log("Low Tick:", params.lowTick);
        console2.log("High Tick:", params.highTick);
        console2.log("Liquidity:", params.liquidity);
        console2.log("Is Compounding:", params.isCompounding);

        // Open the position directly (no NFT wrapper)
        uint256 assetId = openMakerDirect(params);

        console2.log("=== Position Created Successfully ===");
        console2.log("Asset ID:", assetId);
        console2.log("Note: This position is NOT wrapped as an NFT");

        // Check balances after
        uint256 usdcBalance = IERC20(env.usdcToken).balanceOf(deployer);
        uint256 wethBalance = IERC20(env.wethToken).balanceOf(deployer);

        console2.log("=== Final Balances ===");
        console2.log("USDC Balance:", usdcBalance);
        console2.log("WETH Balance:", wethBalance);

        vm.stopBroadcast();
    }
}

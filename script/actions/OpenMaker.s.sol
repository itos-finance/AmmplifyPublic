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
        // vm.startBroadcast(deployerPrivateKey);
        vm.startPrank(0x590F6252Ec23e47abdDF0643d04aCE057d755363);

        console2.log("=== Opening Direct Maker Position (No NFT) ===");
        console2.log("Deployer address:", deployer);

        // Parameters from user
        address recipient = 0x590F6252Ec23e47abdDF0643d04aCE057d755363;
        address poolAddr = 0xB0B083E0353f7df4D5EE1C812eA8c6960c080373;
        int24 lowTick = 67980;
        int24 highTick = 76080;
        uint128 liquidity = 5470558;
        bool isCompounding = true;
        uint160 minSqrtPriceX96 = 4295128739;
        uint160 maxSqrtPriceX96 = 158456325028528675187087900672;
        bytes memory rftData = "";

        // Create maker parameters with provided values
        MakerParams memory params = MakerParams({
            recipient: recipient,
            poolAddr: poolAddr,
            lowTick: lowTick,
            highTick: highTick,
            liquidity: liquidity,
            isCompounding: isCompounding,
            minSqrtPriceX96: minSqrtPriceX96,
            maxSqrtPriceX96: maxSqrtPriceX96,
            rftData: rftData
        });

        console2.log("=== Maker Parameters ===");
        console2.log("Recipient:", params.recipient);
        console2.log("Pool:", params.poolAddr);
        console2.log("Low Tick:", params.lowTick);
        console2.log("High Tick:", params.highTick);
        console2.log("Liquidity:", params.liquidity);
        console2.log("Is Compounding:", params.isCompounding);
        console2.log("Min SqrtPriceX96:", params.minSqrtPriceX96);
        console2.log("Max SqrtPriceX96:", params.maxSqrtPriceX96);

        // Get token addresses from pool
        address token0 = getToken0(poolAddr);
        address token1 = getToken1(poolAddr);
        console2.log("Token0:", token0);
        console2.log("Token1:", token1);

        // Fund the recipient account with tokens (if using mock tokens)
        fundAccount(recipient, 1000000000e6, 10000e18);

        // Set up token approvals for diamond contract from recipient (approve max to avoid allowance issues)
        vm.startPrank(recipient);
        IERC20(token0).approve(env.simplexDiamond, type(uint256).max);
        IERC20(token1).approve(env.simplexDiamond, type(uint256).max);
        vm.stopPrank();

        // Prank as the recipient address to open the position
        vm.startPrank(recipient);

        // Open the position directly (no NFT wrapper)
        uint256 assetId = openMakerDirect(params);

        vm.stopPrank();

        console2.log("=== Position Created Successfully ===");
        console2.log("Asset ID:", assetId);
        console2.log("Note: This position is NOT wrapped as an NFT");

        // Check balances after
        uint256 token0Balance = IERC20(token0).balanceOf(recipient);
        uint256 token1Balance = IERC20(token1).balanceOf(recipient);

        console2.log("=== Final Balances ===");
        console2.log("Token0 Balance:", token0Balance);
        console2.log("Token1 Balance:", token1Balance);

        // vm.stopBroadcast();
    }
}

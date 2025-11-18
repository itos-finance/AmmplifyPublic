// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.27;

import { console2 } from "forge-std/console2.sol";

import { IERC20 } from "Commons/ERC/interfaces/IERC20.sol";
import { TickMath } from "v3-core/libraries/TickMath.sol";
import { LiquidityAmounts } from "../utils/LiquidityAmounts.sol";

import { AmmplifyForkBase } from "./AmmplifyForkBase.u.sol";
import { IMaker } from "../../src/interfaces/IMaker.sol";

/**
 * @title CapricornFork
 * @notice Test contract for Capricorn fork testing with Ammplify
 * @dev Tests token deployment, pool creation, and maker position deposits
 */
contract CapricornFork is AmmplifyForkBase {
    // Test user
    address public testUser;

    function forkSetup() internal virtual override {
        super.forkSetup();

        // Set up test user
        testUser = makeAddr("testUser");

        // Ensure tokens are created (they should be auto-created if not in JSON)
        // The base class handles this, but we'll verify
        require(address(token0) != address(0), "Token0 not created");
        require(address(token1) != address(0), "Token1 not created");
        require(address(pool) != address(0), "Pool not created");
        require(address(diamond) != address(0), "Diamond not deployed");

        console2.log("=== Setup Complete ===");
        console2.log("Factory:", address(factory));
        console2.log("Token0:", address(token0));
        console2.log("Token1:", address(token1));
        console2.log("Pool:", address(pool));
        console2.log("Diamond:", address(diamond));
        console2.log("Test User:", testUser);
    }

    /**
     * @notice Test that deploys tokens, pool, diamond, mints tokens, and attempts deposit
     */
    function test_DeployAndDeposit() public forkOnly {
        console2.log("\n=== Starting Deploy and Deposit Test ===");

        // Get pool info
        (uint24 fee, int24 tickSpacing, uint160 sqrtPriceX96, int24 currentTick, ) = getPoolInfo();

        console2.log("Pool Info:");
        console2.log("  Fee:", fee);
        console2.log("  Tick Spacing:", tickSpacing);
        console2.log("  Current Tick:", currentTick);
        console2.log("  Sqrt Price X96:", sqrtPriceX96);

        // Mint tokens to test user using deal (works for both MockERC20 and real tokens)
        uint256 mintAmount0 = 1000e18; // 1000 token0
        uint256 mintAmount1 = 1000e18; // 1000 token1

        deal(address(token0), testUser, mintAmount0);
        deal(address(token1), testUser, mintAmount1);

        console2.log("\n=== Tokens Minted ===");
        console2.log("Token0 balance:", token0.balanceOf(testUser));
        console2.log("Token1 balance:", token1.balanceOf(testUser));

        // Calculate tick range around current price
        int24 tickRange = tickSpacing * 10; // 10 tick spacings
        int24 tickLower = getValidTick(currentTick - tickRange, fee);
        int24 tickUpper = getValidTick(currentTick + tickRange, fee);

        console2.log("\n=== Position Parameters ===");
        console2.log("Tick Lower:", tickLower);
        console2.log("Tick Upper:", tickUpper);
        console2.log("Current Tick:", currentTick);

        // Calculate required liquidity and token amounts
        uint128 liquidity = 1e18; // Start with 1e18 liquidity

        // Calculate sqrt prices for tick range
        uint160 sqrtPriceAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtPriceBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        // Calculate required token amounts for this liquidity
        (uint256 requiredAmount0, uint256 requiredAmount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            sqrtPriceAX96,
            sqrtPriceBX96,
            liquidity
        );

        console2.log("\n=== Required Token Amounts ===");
        console2.log("Liquidity:", liquidity);
        console2.log("Required Amount0:", requiredAmount0);
        console2.log("Required Amount1:", requiredAmount1);

        // Ensure we have enough tokens
        require(token0.balanceOf(testUser) >= requiredAmount0, "Insufficient token0");
        require(token1.balanceOf(testUser) >= requiredAmount1, "Insufficient token1");

        // Switch to test user context
        vm.startPrank(testUser);

        // Approve tokens for diamond
        token0.approve(address(diamond), requiredAmount0);
        token1.approve(address(diamond), requiredAmount1);

        console2.log("\n=== Approvals Set ===");
        console2.log("Token0 approved:", requiredAmount0);
        console2.log("Token1 approved:", requiredAmount1);

        // Set price limits (use min/max for safety)
        uint160 minSqrtPriceX96 = TickMath.MIN_SQRT_RATIO + 1;
        uint160 maxSqrtPriceX96 = TickMath.MAX_SQRT_RATIO - 1;

        // Attempt to deposit (open maker position)
        console2.log("\n=== Attempting Deposit ===");
        console2.log("Recipient:", testUser);
        console2.log("Pool:", address(pool));
        console2.log("Low Tick:", tickLower);
        console2.log("High Tick:", tickUpper);
        console2.log("Liquidity:", liquidity);

        IMaker maker = IMaker(address(diamond));

        uint256 assetId = maker.newMaker(
            testUser,
            address(pool),
            tickLower,
            tickUpper,
            liquidity,
            false, // isCompounding
            minSqrtPriceX96,
            maxSqrtPriceX96,
            "" // rftData
        );

        console2.log("\n=== Deposit Successful ===");
        console2.log("Asset ID:", assetId);

        // Verify tokens were transferred
        uint256 balance0After = token0.balanceOf(testUser);
        uint256 balance1After = token1.balanceOf(testUser);

        console2.log("\n=== Final Balances ===");
        console2.log("Token0 balance after:", balance0After);
        console2.log("Token1 balance after:", balance1After);
        console2.log("Token0 used:", mintAmount0 - balance0After);
        console2.log("Token1 used:", mintAmount1 - balance1After);

        // Verify some tokens were used
        assertTrue(balance0After < mintAmount0 || balance1After < mintAmount1, "Tokens should have been used");

        vm.stopPrank();

        console2.log("\n=== Test Complete ===");
    }
}

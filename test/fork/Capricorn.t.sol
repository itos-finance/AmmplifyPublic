// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.27;

import { console2 } from "forge-std/console2.sol";

import { IERC20 } from "Commons/ERC/interfaces/IERC20.sol";
import { TickMath } from "v3-core/libraries/TickMath.sol";
import { LiquidityAmounts } from "../utils/LiquidityAmounts.sol";

import { AmmplifyForkBase } from "./AmmplifyForkBase.u.sol";
import { IMaker } from "../../src/interfaces/IMaker.sol";
import { Opener } from "../../src/integrations/Opener.sol";

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

    /**
     * @notice Test that deploys Opener and opens a position with only one token
     */
    function test_OpenerWithOneToken() public forkOnly {
        console2.log("\n=== Starting Opener Test ===");

        // Add liquidity to the pool first to enable swaps
        _addLiquidityToPool();

        // Deploy Opener contract
        Opener opener = new Opener(address(diamond));
        console2.log("Opener deployed:", address(opener));

        // Get pool info
        (uint24 fee, int24 tickSpacing, uint160 sqrtPriceX96, int24 currentTick, ) = getPoolInfo();

        // Calculate tick range around current price
        int24 tickRange = tickSpacing * 10;
        int24 tickLower = getValidTick(currentTick - tickRange, fee);
        int24 tickUpper = getValidTick(currentTick + tickRange, fee);

        // Calculate sqrt prices for tick range
        uint160 sqrtPriceAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtPriceBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        // Calculate expected liquidity and token amounts upfront (based on original liquidity calculation)
        // This is the liquidity we expect to create with the position
        uint128 expectedLiquidity = 1e18; // Expected liquidity for the position

        // Calculate required token amounts for this liquidity
        (uint256 requiredAmount0, uint256 requiredAmount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            sqrtPriceAX96,
            sqrtPriceBX96,
            expectedLiquidity
        );

        console2.log("\n=== Expected Position Parameters ===");
        console2.log("Expected Liquidity:", expectedLiquidity);
        console2.log("Required Amount0:", requiredAmount0);
        console2.log("Required Amount1:", requiredAmount1);

        // Give user token1 to swap (they'll swap some for token0)
        // Use a reasonable amount that should create a position
        uint256 amountIn = 1000e18; // Amount of token1 to swap
        deal(address(token1), testUser, amountIn);
        deal(address(token0), testUser, 0);

        // Calculate amountSwap: how much tokenOut we expect to get from the swap
        // This is based on the ratio we expect when opening the position
        // If we're providing token1 (tokenIn), we need to swap to get token0 (tokenOut)
        // So amountSwap should be the requiredAmount0 (the amount of token0 we need)
        // If we were providing token0, amountSwap would be requiredAmount1
        address tokenIn = address(token1);
        address tokenOut = tokenIn == address(token0) ? address(token1) : address(token0);
        uint256 amountSwap = tokenOut == address(token0) ? requiredAmount0 : requiredAmount1; // Expected output amount from exact output swap

        console2.log("\n=== User Balances Before ===");
        console2.log("Token0 balance:", token0.balanceOf(testUser));
        console2.log("Token1 balance:", token1.balanceOf(testUser));
        console2.log("Amount to swap (token1):", amountIn);
        console2.log("AmountSwap (expected token0 output):", amountSwap);

        vm.startPrank(testUser);

        // Grant permission to Opener to open positions on behalf of testUser
        IMaker maker = IMaker(address(diamond));
        maker.addPermission(address(opener));
        console2.log("Granted permission to Opener:", address(opener));

        // Approve Opener for token1
        token1.approve(address(opener), type(uint256).max);

        // Set price limits
        uint160 minSqrtPriceX96 = TickMath.MIN_SQRT_RATIO + 1;
        uint160 maxSqrtPriceX96 = TickMath.MAX_SQRT_RATIO - 1;

        // Set minimum output (slippage protection) - allow 50% slippage for test
        uint256 amountOutMinimum = 0; // Accept any amount for this test

        console2.log("\n=== Opening Position with Opener ===");
        console2.log("TokenIn:", address(token1));
        console2.log("AmountIn:", amountIn);
        console2.log("AmountOutMinimum:", amountOutMinimum);
        console2.log("AmountSwap:", amountSwap);

        // Capture balances before operation
        uint256 balance0Before = token0.balanceOf(testUser);
        uint256 balance1Before = token1.balanceOf(testUser);
        console2.log("\n=== Balances Before Operation ===");
        console2.log("Token0 balance before:", balance0Before);
        console2.log("Token1 balance before:", balance1Before);

        // Open position using Opener
        uint256 assetId = opener.openMaker(
            address(pool),
            address(token1), // tokenIn
            amountIn, // amountIn
            tickLower,
            tickUpper,
            false, // isCompounding
            minSqrtPriceX96,
            maxSqrtPriceX96,
            amountOutMinimum,
            amountSwap, // amountSwap: expected output from exact output swap
            "" // rftData
        );

        console2.log("\n=== Position Opened ===");
        console2.log("Asset ID:", assetId);

        // Verify tokens were used
        uint256 balance0After = token0.balanceOf(testUser);
        uint256 balance1After = token1.balanceOf(testUser);

        console2.log("\n=== Final Balances ===");
        console2.log("Token0 balance before:", balance0Before);
        console2.log("Token0 balance after:", balance0After);
        console2.log("Token0 change:", int256(balance0After) - int256(balance0Before));
        console2.log("Token1 balance before:", balance1Before);
        console2.log("Token1 balance after:", balance1After);
        console2.log("Token1 change:", int256(balance1After) - int256(balance1Before));
        console2.log("Token1 used:", amountIn - balance1After);

        // Verify position was created
        assertTrue(assetId > 0, "Asset ID should be greater than 0");
        // Verify tokens were used (some should be refunded if there's leftover)
        assertTrue(balance1After < amountIn || balance0After > 0, "Tokens should have been used or refunded");

        vm.stopPrank();

        console2.log("\n=== Opener Test Complete ===");
    }

    /**
     * @notice Test that Opener reverts when slippage is too high
     */
    function test_OpenerRevertsOnHighSlippage() public forkOnly {
        console2.log("\n=== Starting Slippage Test ===");

        // Add liquidity to the pool first to enable swaps
        _addLiquidityToPool();

        // Deploy Opener contract
        Opener opener = new Opener(address(diamond));

        // Get pool info
        (uint24 fee, int24 tickSpacing, uint160 sqrtPriceX96, int24 currentTick, ) = getPoolInfo();

        // Calculate tick range
        int24 tickRange = tickSpacing * 10;
        int24 tickLower = getValidTick(currentTick - tickRange, fee);
        int24 tickUpper = getValidTick(currentTick + tickRange, fee);

        // Give user token1 to swap
        uint256 amountIn = 1000e18;
        deal(address(token1), testUser, amountIn);
        deal(address(token0), testUser, 0);

        vm.startPrank(testUser);

        // Grant permission to Opener to open positions on behalf of testUser
        IMaker maker = IMaker(address(diamond));
        maker.addPermission(address(opener));

        // Approve Opener
        token1.approve(address(opener), type(uint256).max);

        // Calculate expected liquidity and token amounts upfront
        uint160 sqrtPriceAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtPriceBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
        uint128 expectedLiquidity = 1e18;

        // Calculate required token amounts for this liquidity
        (uint256 requiredAmount0, uint256 requiredAmount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            sqrtPriceAX96,
            sqrtPriceBX96,
            expectedLiquidity
        );

        // Calculate amountSwap based on expected ratio
        // Since we're providing token1, we need token0 as output
        address tokenIn = address(token1);
        address tokenOut = tokenIn == address(token0) ? address(token1) : address(token0);
        uint256 amountSwap = tokenOut == address(token0) ? requiredAmount0 : requiredAmount1;

        // Set a very high minimum output that will definitely fail
        // This simulates expecting way more token0 than we'll actually get
        uint256 amountOutMinimum = 1000000e18; // Way too high, will revert

        console2.log("\n=== Attempting with Insufficient Slippage ===");
        console2.log("AmountIn:", amountIn);
        console2.log("AmountOutMinimum (too high):", amountOutMinimum);
        console2.log("AmountSwap:", amountSwap);

        uint160 minSqrtPriceX96 = TickMath.MIN_SQRT_RATIO + 1;
        uint160 maxSqrtPriceX96 = TickMath.MAX_SQRT_RATIO - 1;

        // This should revert with SlippageTooHigh error
        // Use error signature: keccak256("SlippageTooHigh()")[0:4]
        vm.expectRevert(bytes4(keccak256("SlippageTooHigh()")));
        opener.openMaker(
            address(pool),
            address(token1), // tokenIn
            amountIn, // amountIn
            tickLower,
            tickUpper,
            false, // isCompounding
            minSqrtPriceX96,
            maxSqrtPriceX96,
            amountOutMinimum, // This is too high, will cause revert
            amountSwap,
            ""
        );

        vm.stopPrank();

        console2.log("\n=== Slippage Test Complete (Reverted as Expected) ===");
    }

    /**
     * @notice Helper function to add liquidity to the pool for testing
     */
    function _addLiquidityToPool() internal {
        console2.log("\n=== Adding Liquidity to Pool ===");

        // Get pool info
        (uint24 fee, int24 tickSpacing, uint160 sqrtPriceX96, int24 currentTick, ) = getPoolInfo();

        // Calculate a wide tick range around current price for maximum liquidity coverage
        int24 tickLower = getValidTick(-887272, fee);
        int24 tickUpper = getValidTick(887272, fee);

        // Add substantial liquidity - use large amounts to ensure swaps work
        uint256 amount0Desired = 1000000e18; // 1M token0
        uint256 amount1Desired = 1000000e18; // 1M token1

        // Fund this contract with tokens
        deal(address(token0), address(this), amount0Desired);
        deal(address(token1), address(this), amount1Desired);

        console2.log("Adding liquidity:");
        console2.log("  Tick range:", vm.toString(tickLower), "to", vm.toString(tickUpper));
        console2.log("  Amount0:", amount0Desired);
        console2.log("  Amount1:", amount1Desired);

        // Create position to add liquidity
        createPosition(
            tickLower,
            tickUpper,
            amount0Desired,
            amount1Desired,
            address(this) // recipient
        );

        console2.log("Liquidity added successfully");
    }
}

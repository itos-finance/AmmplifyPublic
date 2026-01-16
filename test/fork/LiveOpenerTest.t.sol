// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.27;

import { console2 } from "forge-std/console2.sol";

import { IERC20 } from "Commons/ERC/interfaces/IERC20.sol";
import { ForkableTest } from "Commons/Test/ForkableTest.sol";
import { IUniswapV3Pool } from "v3-core/interfaces/IUniswapV3Pool.sol";
import { TickMath } from "v3-core/libraries/TickMath.sol";
import { LiquidityAmounts } from "../utils/LiquidityAmounts.sol";

import { SimplexDiamond } from "../../src/Diamond.sol";
import { IMaker } from "../../src/interfaces/IMaker.sol";
import { IView } from "../../src/interfaces/IView.sol";
import { Opener } from "../../src/integrations/Opener.sol";

/**
 * @title LiveOpenerTest
 * @notice Fork tests for Opener contract against live WMON/USDC pool
 * @dev Tests position opening with single-token input and exact output swaps
 *      Uses hardcoded addresses for live deployed contracts
 */
contract LiveOpenerTest is ForkableTest {
    // Hardcoded addresses for WMON/USDC pool testing
    address constant WMON_USDC_POOL = 0x659bD0BC4167BA25c62E05656F78043E7eD4a9da;
    address constant WMON_ADDRESS = 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A;
    address constant USDC_ADDRESS = 0x754704Bc059F8C67012fEd69BC8A327a5aafb603;
    address constant SIMPLEX_DIAMOND = 0x5B5e9d616fAFCCC4865a6C29b6F89Ff3aAE7c892;

    // Struct for swap calculation results
    struct SwapCalculation {
        uint256 amountToKeep;
        uint256 amountToSwap;
        uint256 expectedOutput; // This is the amountSwap parameter for Opener
    }

    // Constants for common fee tiers
    uint24 public constant FEE_TIER_500 = 500; // 0.05%
    uint24 public constant FEE_TIER_3000 = 3000; // 0.3%
    uint24 public constant FEE_TIER_10000 = 10000; // 1%

    // Common tick spacings
    int24 public constant TICK_SPACING_500 = 10;
    int24 public constant TICK_SPACING_3000 = 60;
    int24 public constant TICK_SPACING_10000 = 200;

    // State variables
    IUniswapV3Pool public pool;
    SimplexDiamond public diamond;
    IERC20 public token0;
    IERC20 public token1;
    IERC20 public wmon;
    IERC20 public usdc;

    Opener public opener;
    address public testUser;

    function forkSetup() internal virtual override {
        // Load pool from hardcoded address
        pool = IUniswapV3Pool(WMON_USDC_POOL);

        // Load diamond from hardcoded address
        diamond = SimplexDiamond(payable(SIMPLEX_DIAMOND));

        // Get token0/token1 from pool (maintains correct ordering)
        token0 = IERC20(pool.token0());
        token1 = IERC20(pool.token1());

        // Set wmon and usdc references
        wmon = IERC20(WMON_ADDRESS);
        usdc = IERC20(USDC_ADDRESS);

        // Deploy new Opener
        opener = new Opener();

        // Setup test user
        testUser = makeAddr("testUser");

        console2.log("=== Fork Setup Complete ===");
        console2.log("Diamond:", address(diamond));
        console2.log("Pool:", address(pool));
        console2.log("Token0:", address(token0));
        console2.log("Token1:", address(token1));
        console2.log("WMON:", address(wmon));
        console2.log("USDC:", address(usdc));
        console2.log("Opener:", address(opener));
        console2.log("Test User:", testUser);
    }

    function deploySetup() internal virtual override {
        revert("LiveOpenerTest only supports fork testing");
    }

    // ========== HELPER FUNCTIONS ==========

    /**
     * @notice Get tick spacing for a given fee tier
     */
    function getTickSpacing(uint24 fee) internal pure returns (int24 tickSpacing) {
        if (fee == FEE_TIER_500) return TICK_SPACING_500;
        if (fee == FEE_TIER_3000) return TICK_SPACING_3000;
        if (fee == FEE_TIER_10000) return TICK_SPACING_10000;
        revert("Unsupported fee tier");
    }

    /**
     * @notice Get a valid tick within the tick spacing
     */
    function getValidTick(int24 tick, uint24 fee) internal pure returns (int24 validTick) {
        int24 spacing = getTickSpacing(fee);
        return (tick / spacing) * spacing;
    }

    /**
     * @notice Get pool information
     */
    function getPoolInfo()
        internal
        view
        returns (uint24 fee, int24 tickSpacing, uint160 sqrtPriceX96, int24 tick, uint128 liquidity)
    {
        fee = pool.fee();
        tickSpacing = getTickSpacing(fee);
        (sqrtPriceX96, tick,,,,,) = pool.slot0();
        liquidity = pool.liquidity();
    }

    /**
     * @notice Get decimals for a token
     */
    function getDecimals(address token) internal view returns (uint8) {
        if (token == address(usdc)) return 6;
        if (token == address(wmon)) return 18;
        return 18; // default
    }

    /**
     * @notice Get appropriate amount for a token based on decimals
     * @param baseAmount The amount in "units" (e.g., 1000 = 1000 tokens)
     * @param token The token address
     */
    function getAmount(uint256 baseAmount, address token) internal view returns (uint256) {
        uint8 decimals = getDecimals(token);
        return baseAmount * (10 ** decimals);
    }

    // ========== RATIO CALCULATION HELPERS (from RATIO.md) ==========

    /**
     * @notice Calculate the swap amounts for single-sided deposit using Q96 math
     * @dev Uses sqrtPriceX96 directly to maintain precision for low-price tokens
     *      Implements the algorithm from RATIO.md with high-precision arithmetic
     * @param inputAmount Amount of input token (in token's native decimals)
     * @param currentTick Current pool tick
     * @param lowerTick Lower tick of position
     * @param upperTick Upper tick of position
     * @param isInputToken0 True if user is depositing token0, false for token1
     * @return calc SwapCalculation struct with amounts
     */
    function calculateSwapForDeposit(
        uint256 inputAmount,
        int24 currentTick,
        int24 lowerTick,
        int24 upperTick,
        bool isInputToken0
    ) internal pure returns (SwapCalculation memory calc) {
        // Edge case: zero input
        if (inputAmount == 0) {
            return SwapCalculation(0, 0, 0);
        }

        // Get sqrt prices in Q96 format (full precision)
        uint160 sqrtP = TickMath.getSqrtRatioAtTick(currentTick);
        uint160 sqrtPa = TickMath.getSqrtRatioAtTick(lowerTick);
        uint160 sqrtPb = TickMath.getSqrtRatioAtTick(upperTick);

        // Check if position is out of range
        bool belowRange = currentTick < lowerTick;
        bool aboveRange = currentTick >= upperTick;

        if (belowRange) {
            // Position is below current price - needs only token0
            if (isInputToken0) {
                // User has token0, no swap needed
                return SwapCalculation(inputAmount, 0, 0);
            } else {
                // User has token1, need to swap all to token0
                uint256 expectedOut = _getToken0ForToken1(inputAmount, sqrtP);
                return SwapCalculation(0, inputAmount, expectedOut);
            }
        }

        if (aboveRange) {
            // Position is above current price - needs only token1
            if (!isInputToken0) {
                // User has token1, no swap needed
                return SwapCalculation(inputAmount, 0, 0);
            } else {
                // User has token0, need to swap all to token1
                uint256 expectedOut = _getToken1ForToken0(inputAmount, sqrtP);
                return SwapCalculation(0, inputAmount, expectedOut);
            }
        }

        // Position is in range - calculate the ratio
        // Using the Uniswap V3 liquidity formulas:
        // amount0 = L * (sqrtPb - sqrtP) / (sqrtP * sqrtPb)
        // amount1 = L * (sqrtP - sqrtPa)
        //
        // The ratio of amount0 to amount1 (in value terms) is what we need

        // Calculate the "virtual" amounts needed for equal liquidity contribution
        // We use a reference liquidity and then calculate the ratio

        // For precision, work with large numbers
        // amount0_factor = (sqrtPb - sqrtP) * 1e18 / (sqrtP * sqrtPb / 2^96)
        // amount1_factor = (sqrtP - sqrtPa) * 1e18 / 2^96

        uint256 sqrtPuint = uint256(sqrtP);
        uint256 sqrtPauint = uint256(sqrtPa);
        uint256 sqrtPbuint = uint256(sqrtPb);

        // Calculate amount factors with high precision
        // amount0_factor represents token0 needed per unit liquidity (scaled by 1e18 * 2^96)
        // amount1_factor represents token1 needed per unit liquidity (scaled by 2^96)

        uint256 deltaUpper = sqrtPbuint - sqrtPuint; // sqrtPb - sqrtP
        uint256 deltaLower = sqrtPuint - sqrtPauint; // sqrtP - sqrtPa

        // For token0: amount0 = L * deltaUpper / (sqrtP * sqrtPb)
        // For token1: amount1 = L * deltaLower

        // Value ratio: we need to convert to common units
        // value0 (in token1 terms) = amount0 * price = amount0 * sqrtP^2 / 2^192
        // value1 = amount1

        // value0 = L * deltaUpper * sqrtP / (sqrtPb * 2^96)
        // value1 = L * deltaLower

        // Ratio of value going to token0 vs token1:
        // R = value0 / (value0 + value1)
        // R = (deltaUpper * sqrtP / sqrtPb) / (deltaUpper * sqrtP / sqrtPb + deltaLower * 2^96)

        // Simplify by multiplying all by sqrtPb:
        // R = (deltaUpper * sqrtP) / (deltaUpper * sqrtP + deltaLower * sqrtPb * 2^96 / sqrtPb)
        // Actually let's just compute directly

        // Value0 (scaled): deltaUpper * sqrtP
        uint256 value0Scaled = deltaUpper * sqrtPuint;
        // Value1 (scaled): deltaLower * sqrtPb (to match units after division)
        uint256 value1Scaled = deltaLower * sqrtPbuint;

        // Total value scaled
        uint256 totalValueScaled = value0Scaled + value1Scaled;

        if (totalValueScaled == 0) {
            return SwapCalculation(inputAmount, 0, 0);
        }

        // Fraction of value that should be token0
        // fraction0 = value0Scaled / totalValueScaled

        if (isInputToken0) {
            // User provides token0, needs to swap some to token1
            // The fraction of input that should remain as token0 is value0Scaled / totalValueScaled
            // But we need to account for the price when swapping

            // Amount to keep as token0 (in token0 terms)
            calc.amountToKeep = (inputAmount * value0Scaled) / totalValueScaled;
            calc.amountToSwap = inputAmount - calc.amountToKeep;

            // Expected output in token1 (apply the price conversion)
            calc.expectedOutput = _getToken1ForToken0(calc.amountToSwap, sqrtP);
        } else {
            // User provides token1, needs to swap some to token0
            // The fraction of input that should remain as token1 is value1Scaled / totalValueScaled

            calc.amountToKeep = (inputAmount * value1Scaled) / totalValueScaled;
            calc.amountToSwap = inputAmount - calc.amountToKeep;

            // Expected output in token0
            calc.expectedOutput = _getToken0ForToken1(calc.amountToSwap, sqrtP);
        }
    }

    /**
     * @notice Calculate expected token1 output for token0 input at given sqrt price
     * @dev Uses price = sqrtP^2 / 2^192
     *      NO decimal adjustment needed - Uniswap price is in raw smallest-unit terms
     */
    function _getToken1ForToken0(
        uint256 amount0,
        uint160 sqrtPriceX96
    ) internal pure returns (uint256 amount1) {
        // price = sqrtP^2 / 2^192
        // amount1 = amount0 * price
        // The price already encodes the decimal relationship implicitly
        uint256 sqrtP = uint256(sqrtPriceX96);
        uint256 temp = (amount0 * sqrtP) >> 96;
        amount1 = (temp * sqrtP) >> 96;
    }

    /**
     * @notice Calculate expected token0 output for token1 input at given sqrt price
     * @dev Uses price = sqrtP^2 / 2^192
     *      NO decimal adjustment needed - Uniswap price is in raw smallest-unit terms
     */
    function _getToken0ForToken1(
        uint256 amount1,
        uint160 sqrtPriceX96
    ) internal pure returns (uint256 amount0) {
        // amount0 = amount1 / price = amount1 * 2^192 / sqrtP^2
        // The price already encodes the decimal relationship implicitly
        uint256 sqrtP = uint256(sqrtPriceX96);
        uint256 temp = (amount1 << 96) / sqrtP;
        amount0 = (temp << 96) / sqrtP;
    }

    // ========== TEST: Open with Token0 ==========

    /**
     * @notice Test opening a position by providing only token0
     * @dev User provides token0, Opener swaps for token1, opens position
     */
    function test_OpenWithToken0() public forkOnly {
        console2.log("\n=== Test: Open With Token0 ===");

        // Get pool info
        (uint24 fee, int24 tickSpacing, uint160 sqrtPriceX96, int24 currentTick,) = getPoolInfo();
        console2.log("Current tick:", currentTick);
        console2.log("Sqrt price X96:", sqrtPriceX96);

        // Calculate tick range around current price
        int24 tickRange = tickSpacing * 10;
        int24 tickLower = getValidTick(currentTick - tickRange, fee);
        int24 tickUpper = getValidTick(currentTick + tickRange, fee);

        console2.log("Tick lower:", tickLower);
        console2.log("Tick upper:", tickUpper);

        // User provides token0
        address tokenIn = address(token0);
        uint256 amountIn = getAmount(1000, tokenIn); // 1000 tokens
        deal(address(token0), testUser, amountIn);

        // Calculate the correct swap amount using Q96 math
        bool isInputToken0 = tokenIn == address(token0);

        SwapCalculation memory calc = calculateSwapForDeposit(
            amountIn,
            currentTick,
            tickLower,
            tickUpper,
            isInputToken0
        );

        console2.log("TokenIn:", tokenIn);
        console2.log("AmountIn:", amountIn);
        console2.log("Amount to keep:", calc.amountToKeep);
        console2.log("Amount to swap:", calc.amountToSwap);
        console2.log("Expected output (amountSwap):", calc.expectedOutput);

        // Grant permission to Opener
        vm.startPrank(testUser);
        IMaker(address(diamond)).addPermission(address(opener));

        // Approve Opener
        IERC20(tokenIn).approve(address(opener), type(uint256).max);

        uint256 balanceBefore = token0.balanceOf(testUser);
        console2.log("Token0 balance before:", balanceBefore);

        // Open position with correctly calculated amountSwap
        uint256 assetId = opener.openMaker(
            address(diamond),
            address(pool),
            tokenIn,
            amountIn,
            tickLower,
            tickUpper,
            true, // isCompounding
            TickMath.MIN_SQRT_RATIO + 1,
            TickMath.MAX_SQRT_RATIO - 1,
            0, // amountOutMinimum - accept any for test
            calc.expectedOutput, // Use calculated swap amount
            ""
        );

        vm.stopPrank();

        uint256 balanceAfter = token0.balanceOf(testUser);
        console2.log("Token0 balance after:", balanceAfter);
        console2.log("Token0 used:", balanceBefore - balanceAfter);
        console2.log("Asset ID:", assetId);

        // Verify position was created
        assertTrue(assetId > 0, "Asset ID should be greater than 0");

        // Verify some token0 was used
        assertTrue(balanceAfter < balanceBefore, "Token0 should have been used");

        console2.log("=== Test Complete: Open With Token0 ===");
    }

    // ========== TEST: Open with Token1 ==========

    /**
     * @notice Test opening a position by providing only token1
     * @dev User provides token1, Opener swaps for token0, opens position
     */
    function test_OpenWithToken1() public forkOnly {
        console2.log("\n=== Test: Open With Token1 ===");

        // Get pool info
        (uint24 fee, int24 tickSpacing,, int24 currentTick,) = getPoolInfo();

        // Calculate tick range around current price
        int24 tickRange = tickSpacing * 10;
        int24 tickLower = getValidTick(currentTick - tickRange, fee);
        int24 tickUpper = getValidTick(currentTick + tickRange, fee);

        console2.log("Current tick:", currentTick);
        console2.log("Tick lower:", tickLower);
        console2.log("Tick upper:", tickUpper);

        // User provides token1
        address tokenIn = address(token1);
        uint256 amountIn = getAmount(1000, tokenIn); // 1000 tokens
        deal(address(token1), testUser, amountIn);

        // Calculate the correct swap amount using Q96 math
        bool isInputToken0 = tokenIn == address(token0);

        SwapCalculation memory calc = calculateSwapForDeposit(
            amountIn,
            currentTick,
            tickLower,
            tickUpper,
            isInputToken0
        );

        console2.log("TokenIn:", tokenIn);
        console2.log("AmountIn:", amountIn);
        console2.log("Amount to keep:", calc.amountToKeep);
        console2.log("Amount to swap:", calc.amountToSwap);
        console2.log("Expected output (amountSwap):", calc.expectedOutput);

        // Grant permission and approve
        vm.startPrank(testUser);
        IMaker(address(diamond)).addPermission(address(opener));
        IERC20(tokenIn).approve(address(opener), type(uint256).max);

        uint256 balanceBefore = token1.balanceOf(testUser);

        // Open position with correctly calculated amountSwap
        uint256 assetId = opener.openMaker(
            address(diamond),
            address(pool),
            tokenIn,
            amountIn,
            tickLower,
            tickUpper,
            true,
            TickMath.MIN_SQRT_RATIO + 1,
            TickMath.MAX_SQRT_RATIO - 1,
            0,
            calc.expectedOutput, // Use calculated swap amount
            ""
        );

        vm.stopPrank();

        uint256 balanceAfter = token1.balanceOf(testUser);
        console2.log("Token1 balance before:", balanceBefore);
        console2.log("Token1 balance after:", balanceAfter);
        console2.log("Token1 used:", balanceBefore - balanceAfter);
        console2.log("Asset ID:", assetId);

        assertTrue(assetId > 0, "Asset ID should be greater than 0");
        assertTrue(balanceAfter < balanceBefore, "Token1 should have been used");

        console2.log("=== Test Complete: Open With Token1 ===");
    }

    // ========== TEST: Slippage Protection ==========

    /**
     * @notice Test that high slippage causes revert
     */
    function test_RevertOnHighSlippage() public forkOnly {
        console2.log("\n=== Test: Revert On High Slippage ===");

        (uint24 fee, int24 tickSpacing,, int24 currentTick,) = getPoolInfo();

        int24 tickRange = tickSpacing * 10;
        int24 tickLower = getValidTick(currentTick - tickRange, fee);
        int24 tickUpper = getValidTick(currentTick + tickRange, fee);

        // Give user token0 - use appropriate decimals
        uint256 amountIn = getAmount(1000, address(token0));
        deal(address(token0), testUser, amountIn);

        vm.startPrank(testUser);
        IMaker(address(diamond)).addPermission(address(opener));
        token0.approve(address(opener), type(uint256).max);

        // Set unrealistic amountOutMinimum - expect way more than possible
        uint256 amountOutMinimum = getAmount(1000000, address(token1)); // Expect 1M token1 (impossible)
        uint256 amountSwap = 1e15; // Small swap amount

        // Should revert with SlippageTooHigh
        vm.expectRevert(bytes4(keccak256("SlippageTooHigh()")));
        opener.openMaker(
            address(diamond),
            address(pool),
            address(token0),
            amountIn,
            tickLower,
            tickUpper,
            true,
            TickMath.MIN_SQRT_RATIO + 1,
            TickMath.MAX_SQRT_RATIO - 1,
            amountOutMinimum, // Too high
            amountSwap,
            ""
        );

        vm.stopPrank();

        console2.log("=== Test Complete: Correctly Reverted ===");
    }

    // ========== TEST: Without Permission ==========

    /**
     * @notice Test that opening without permission reverts
     */
    function test_RevertWithoutPermission() public forkOnly {
        console2.log("\n=== Test: Revert Without Permission ===");

        (uint24 fee, int24 tickSpacing,, int24 currentTick,) = getPoolInfo();

        int24 tickRange = tickSpacing * 10;
        int24 tickLower = getValidTick(currentTick - tickRange, fee);
        int24 tickUpper = getValidTick(currentTick + tickRange, fee);

        uint256 amountIn = getAmount(1000, address(token0));
        deal(address(token0), testUser, amountIn);

        vm.startPrank(testUser);
        // NOTE: NOT granting permission
        token0.approve(address(opener), type(uint256).max);

        // Should revert due to missing permission
        vm.expectRevert();
        opener.openMaker(
            address(diamond), address(pool), address(token0), amountIn, tickLower, tickUpper, true, TickMath.MIN_SQRT_RATIO + 1, TickMath.MAX_SQRT_RATIO - 1, 0, 1e12, ""
        );

        vm.stopPrank();

        console2.log("=== Test Complete: Correctly Reverted Without Permission ===");
    }

    // ========== TEST: Refunds Unused Tokens ==========

    /**
     * @notice Test that unused tokens are refunded to user
     */
    function test_RefundsUnusedTokens() public forkOnly {
        console2.log("\n=== Test: Refunds Unused Tokens ===");

        (uint24 fee, int24 tickSpacing,, int24 currentTick,) = getPoolInfo();

        int24 tickRange = tickSpacing * 5; // Narrower range
        int24 tickLower = getValidTick(currentTick - tickRange, fee);
        int24 tickUpper = getValidTick(currentTick + tickRange, fee);

        // Give user much more token0 than needed
        address tokenIn = address(token0);
        uint256 amountIn = getAmount(100000, tokenIn);
        deal(address(token0), testUser, amountIn);

        // Calculate swap amount using ratio algorithm
        SwapCalculation memory calc = calculateSwapForDeposit(
            amountIn, currentTick, tickLower, tickUpper, true
        );

        vm.startPrank(testUser);
        IMaker(address(diamond)).addPermission(address(opener));
        IERC20(tokenIn).approve(address(opener), type(uint256).max);

        uint256 token0Before = token0.balanceOf(testUser);
        uint256 token1Before = token1.balanceOf(testUser);

        uint256 assetId = opener.openMaker(
            address(diamond), address(pool), tokenIn, amountIn, tickLower, tickUpper, true,
            TickMath.MIN_SQRT_RATIO + 1, TickMath.MAX_SQRT_RATIO - 1, 0, calc.expectedOutput, ""
        );

        vm.stopPrank();

        uint256 token0After = token0.balanceOf(testUser);
        uint256 token1After = token1.balanceOf(testUser);

        console2.log("Token0 before:", token0Before);
        console2.log("Token0 after:", token0After);
        console2.log("Token0 refunded:", token0After);
        console2.log("Token1 before:", token1Before);
        console2.log("Token1 after:", token1After);
        console2.log("Asset ID:", assetId);

        // User should have received some refund (since we provided way more than needed)
        uint256 totalRefund = token0After + token1After;
        assertTrue(totalRefund > 0, "Should have received some refund");

        console2.log("=== Test Complete: Refunds Verified ===");
    }

    // ========== TEST: Position At Current Price ==========

    /**
     * @notice Test opening position that spans current price
     */
    function test_OpenPositionAtCurrentPrice() public forkOnly {
        console2.log("\n=== Test: Position At Current Price ===");

        (uint24 fee, int24 tickSpacing,, int24 currentTick,) = getPoolInfo();

        // Position spanning current tick
        int24 tickRange = tickSpacing * 20;
        int24 tickLower = getValidTick(currentTick - tickRange, fee);
        int24 tickUpper = getValidTick(currentTick + tickRange, fee);

        console2.log("Current tick:", currentTick);
        console2.log("Tick lower:", tickLower);
        console2.log("Tick upper:", tickUpper);

        // Verify position spans current tick
        assertTrue(tickLower < currentTick && currentTick < tickUpper, "Position should span current tick");

        uint256 amountIn = getAmount(5000, address(token0));
        deal(address(token0), testUser, amountIn);

        // Calculate swap amount using ratio algorithm
        SwapCalculation memory calc = calculateSwapForDeposit(
            amountIn, currentTick, tickLower, tickUpper, true
        );

        console2.log("Expected output (amountSwap):", calc.expectedOutput);

        vm.startPrank(testUser);
        IMaker(address(diamond)).addPermission(address(opener));
        token0.approve(address(opener), type(uint256).max);

        uint256 assetId = opener.openMaker(
            address(diamond), address(pool), address(token0), amountIn, tickLower, tickUpper, true,
            TickMath.MIN_SQRT_RATIO + 1, TickMath.MAX_SQRT_RATIO - 1, 0, calc.expectedOutput, ""
        );

        vm.stopPrank();

        assertTrue(assetId > 0, "Position should be created");

        console2.log("Asset ID:", assetId);
        console2.log("=== Test Complete: Position At Current Price ===");
    }

    // ========== TEST: Position Below Current Price ==========

    /**
     * @notice Test opening position entirely below current price (100% token0)
     */
    function test_OpenPositionBelowPrice() public forkOnly {
        console2.log("\n=== Test: Position Below Current Price ===");

        (uint24 fee, int24 tickSpacing,, int24 currentTick,) = getPoolInfo();

        // Position entirely below current tick
        int24 tickOffset = tickSpacing * 50; // Far below
        int24 tickWidth = tickSpacing * 10;
        int24 tickUpper = getValidTick(currentTick - tickOffset, fee);
        int24 tickLower = getValidTick(tickUpper - tickWidth, fee);

        console2.log("Current tick:", currentTick);
        console2.log("Tick lower:", tickLower);
        console2.log("Tick upper:", tickUpper);

        // Verify position is below current tick
        assertTrue(tickUpper < currentTick, "Position should be below current tick");

        uint256 amountIn = getAmount(5000, address(token0));
        deal(address(token0), testUser, amountIn);

        // Calculate swap amount using ratio algorithm
        // For position below price with token0 input, no swap needed (Yd = 0)
        SwapCalculation memory calc = calculateSwapForDeposit(
            amountIn, currentTick, tickLower, tickUpper, true
        );

        console2.log("Expected output (amountSwap):", calc.expectedOutput);
        console2.log("Amount to keep:", calc.amountToKeep);

        vm.startPrank(testUser);
        IMaker(address(diamond)).addPermission(address(opener));
        token0.approve(address(opener), type(uint256).max);

        // For position below current price, we need only token0
        // amountSwap should be 0 (no swap needed when providing token0)
        uint256 assetId = opener.openMaker(
            address(diamond), address(pool), address(token0), amountIn, tickLower, tickUpper, true,
            TickMath.MIN_SQRT_RATIO + 1, TickMath.MAX_SQRT_RATIO - 1, 0, calc.expectedOutput, ""
        );

        vm.stopPrank();

        assertTrue(assetId > 0, "Position should be created");

        console2.log("Asset ID:", assetId);
        console2.log("=== Test Complete: Position Below Current Price ===");
    }

    // ========== TEST: Position Above Current Price ==========

    /**
     * @notice Test opening position entirely above current price (100% token1)
     */
    function test_OpenPositionAbovePrice() public forkOnly {
        console2.log("\n=== Test: Position Above Current Price ===");

        (uint24 fee, int24 tickSpacing,, int24 currentTick,) = getPoolInfo();

        // Position entirely above current tick
        int24 tickOffset = tickSpacing * 50; // Far above
        int24 tickWidth = tickSpacing * 10;
        int24 tickLower = getValidTick(currentTick + tickOffset, fee);
        int24 tickUpper = getValidTick(tickLower + tickWidth, fee);

        console2.log("Current tick:", currentTick);
        console2.log("Tick lower:", tickLower);
        console2.log("Tick upper:", tickUpper);

        // Verify position is above current tick
        assertTrue(tickLower > currentTick, "Position should be above current tick");

        uint256 amountIn = getAmount(5000, address(token0));
        deal(address(token0), testUser, amountIn);

        // Calculate swap amount using ratio algorithm
        // For position above price with token0 input, need to swap all to token1 (Xd = 0)
        SwapCalculation memory calc = calculateSwapForDeposit(
            amountIn, currentTick, tickLower, tickUpper, true
        );

        console2.log("Expected output (amountSwap):", calc.expectedOutput);
        console2.log("Amount to swap:", calc.amountToSwap);

        vm.startPrank(testUser);
        IMaker(address(diamond)).addPermission(address(opener));
        token0.approve(address(opener), type(uint256).max);

        // For position above current price with token0, we need to swap all to token1
        uint256 assetId = opener.openMaker(
            address(diamond), address(pool), address(token0), amountIn, tickLower, tickUpper, true,
            TickMath.MIN_SQRT_RATIO + 1, TickMath.MAX_SQRT_RATIO - 1, 0, calc.expectedOutput, ""
        );

        vm.stopPrank();

        assertTrue(assetId > 0, "Position should be created");

        console2.log("Asset ID:", assetId);
        console2.log("=== Test Complete: Position Above Current Price ===");
    }

    // ========== TEST: Liquidity Discount Applied ==========

    /**
     * @notice Verify the 1% liquidity discount is being applied
     */
    function test_LiquidityDiscountApplied() public forkOnly {
        console2.log("\n=== Test: Liquidity Discount Applied ===");

        // Verify the discount constant
        uint256 discount = opener.LIQUIDITY_DISCOUNT_BPS();
        assertEq(discount, 100, "Discount should be 100 BPS (1%)");

        console2.log("Liquidity discount BPS:", discount);
        console2.log("=== Test Complete: Discount Verified ===");
    }

    // ========== REFUND VERIFICATION TESTS ==========

    /**
     * @notice CRITICAL: Verify Opener contract has zero token balance after operation
     * @dev This ensures no tokens are stuck in the contract
     */
    function test_OpenerContractHasZeroBalanceAfter() public forkOnly {
        console2.log("\n=== Test: Opener Contract Has Zero Balance After ===");

        (uint24 fee, int24 tickSpacing,, int24 currentTick,) = getPoolInfo();

        int24 tickRange = tickSpacing * 10;
        int24 tickLower = getValidTick(currentTick - tickRange, fee);
        int24 tickUpper = getValidTick(currentTick + tickRange, fee);

        // Give user more token0 than needed
        uint256 amountIn = getAmount(50000, address(token0));
        deal(address(token0), testUser, amountIn);

        // Calculate swap amount using ratio algorithm
        SwapCalculation memory calc = calculateSwapForDeposit(
            amountIn, currentTick, tickLower, tickUpper, true
        );

        vm.startPrank(testUser);
        IMaker(address(diamond)).addPermission(address(opener));
        token0.approve(address(opener), type(uint256).max);

        // Open position
        opener.openMaker(
            address(diamond),
            address(pool),
            address(token0),
            amountIn,
            tickLower,
            tickUpper,
            true,
            TickMath.MIN_SQRT_RATIO + 1,
            TickMath.MAX_SQRT_RATIO - 1,
            0,
            calc.expectedOutput,
            ""
        );

        vm.stopPrank();

        // CRITICAL: Verify Opener has no tokens left
        uint256 openerBalance0 = token0.balanceOf(address(opener));
        uint256 openerBalance1 = token1.balanceOf(address(opener));

        console2.log("Opener token0 balance:", openerBalance0);
        console2.log("Opener token1 balance:", openerBalance1);

        assertEq(openerBalance0, 0, "Opener should have 0 token0 - tokens stuck!");
        assertEq(openerBalance1, 0, "Opener should have 0 token1 - tokens stuck!");

        console2.log("=== Test Complete: Opener Contract Empty ===");
    }

    /**
     * @notice Test refund when user provides token0 as input
     */
    function test_RefundWithToken0Input() public forkOnly {
        console2.log("\n=== Test: Refund With Token0 Input ===");

        (uint24 fee, int24 tickSpacing,, int24 currentTick,) = getPoolInfo();

        int24 tickRange = tickSpacing * 10;
        int24 tickLower = getValidTick(currentTick - tickRange, fee);
        int24 tickUpper = getValidTick(currentTick + tickRange, fee);

        // Give user 2x token0 than estimated needed
        uint256 amountIn = getAmount(20000, address(token0));
        deal(address(token0), testUser, amountIn);
        deal(address(token1), testUser, 0); // Ensure no initial token1

        // Calculate swap amount using ratio algorithm
        SwapCalculation memory calc = calculateSwapForDeposit(
            amountIn, currentTick, tickLower, tickUpper, true
        );

        vm.startPrank(testUser);
        IMaker(address(diamond)).addPermission(address(opener));
        token0.approve(address(opener), type(uint256).max);

        uint256 userToken0Before = token0.balanceOf(testUser);
        uint256 userToken1Before = token1.balanceOf(testUser);

        console2.log("User token0 before:", userToken0Before);
        console2.log("User token1 before:", userToken1Before);

        opener.openMaker(
            address(diamond),
            address(pool),
            address(token0),
            amountIn,
            tickLower,
            tickUpper,
            true,
            TickMath.MIN_SQRT_RATIO + 1,
            TickMath.MAX_SQRT_RATIO - 1,
            0,
            calc.expectedOutput,
            ""
        );

        vm.stopPrank();

        uint256 userToken0After = token0.balanceOf(testUser);
        uint256 userToken1After = token1.balanceOf(testUser);

        console2.log("User token0 after:", userToken0After);
        console2.log("User token1 after:", userToken1After);

        // User should have received refund of unused token0
        uint256 token0Used = userToken0Before - userToken0After;
        console2.log("Token0 actually used:", token0Used);

        // Verify user got back unused tokens
        assertTrue(userToken0After > 0, "User should have received token0 refund");

        // Verify Opener is empty
        assertEq(token0.balanceOf(address(opener)), 0, "Opener should have 0 token0");
        assertEq(token1.balanceOf(address(opener)), 0, "Opener should have 0 token1");

        console2.log("=== Test Complete: Token0 Input Refund Verified ===");
    }

    /**
     * @notice Test refund when user provides token1 as input
     */
    function test_RefundWithToken1Input() public forkOnly {
        console2.log("\n=== Test: Refund With Token1 Input ===");

        (uint24 fee, int24 tickSpacing,, int24 currentTick,) = getPoolInfo();

        int24 tickRange = tickSpacing * 10;
        int24 tickLower = getValidTick(currentTick - tickRange, fee);
        int24 tickUpper = getValidTick(currentTick + tickRange, fee);

        // Give user 2x token1 than estimated needed
        uint256 amountIn = getAmount(20000, address(token1));
        deal(address(token1), testUser, amountIn);
        deal(address(token0), testUser, 0); // Ensure no initial token0

        // Calculate swap amount using ratio algorithm
        SwapCalculation memory calc = calculateSwapForDeposit(
            amountIn, currentTick, tickLower, tickUpper, false // token1 input
        );

        vm.startPrank(testUser);
        IMaker(address(diamond)).addPermission(address(opener));
        token1.approve(address(opener), type(uint256).max);

        uint256 userToken0Before = token0.balanceOf(testUser);
        uint256 userToken1Before = token1.balanceOf(testUser);

        console2.log("User token0 before:", userToken0Before);
        console2.log("User token1 before:", userToken1Before);

        opener.openMaker(
            address(diamond),
            address(pool),
            address(token1),
            amountIn,
            tickLower,
            tickUpper,
            true,
            TickMath.MIN_SQRT_RATIO + 1,
            TickMath.MAX_SQRT_RATIO - 1,
            0,
            calc.expectedOutput,
            ""
        );

        vm.stopPrank();

        uint256 userToken0After = token0.balanceOf(testUser);
        uint256 userToken1After = token1.balanceOf(testUser);

        console2.log("User token0 after:", userToken0After);
        console2.log("User token1 after:", userToken1After);

        // User should have received refund of unused token1
        uint256 token1Used = userToken1Before - userToken1After;
        console2.log("Token1 actually used:", token1Used);

        // Verify user got back unused tokens
        assertTrue(userToken1After > 0, "User should have received token1 refund");

        // Verify Opener is empty
        assertEq(token0.balanceOf(address(opener)), 0, "Opener should have 0 token0");
        assertEq(token1.balanceOf(address(opener)), 0, "Opener should have 0 token1");

        console2.log("=== Test Complete: Token1 Input Refund Verified ===");
    }

    /**
     * @notice Test refund with significantly more tokens than needed (10x)
     */
    function test_LargeExcessRefund() public forkOnly {
        console2.log("\n=== Test: Large Excess Refund ===");

        (uint24 fee, int24 tickSpacing,, int24 currentTick,) = getPoolInfo();

        int24 tickRange = tickSpacing * 5; // Smaller range = less tokens needed
        int24 tickLower = getValidTick(currentTick - tickRange, fee);
        int24 tickUpper = getValidTick(currentTick + tickRange, fee);

        // Give user 10x more tokens than needed
        uint256 amountIn = getAmount(500000, address(token0)); // Very large amount
        deal(address(token0), testUser, amountIn);

        // Calculate swap amount using ratio algorithm
        SwapCalculation memory calc = calculateSwapForDeposit(
            amountIn, currentTick, tickLower, tickUpper, true
        );

        vm.startPrank(testUser);
        IMaker(address(diamond)).addPermission(address(opener));
        token0.approve(address(opener), type(uint256).max);

        uint256 userToken0Before = token0.balanceOf(testUser);

        opener.openMaker(
            address(diamond),
            address(pool),
            address(token0),
            amountIn,
            tickLower,
            tickUpper,
            true,
            TickMath.MIN_SQRT_RATIO + 1,
            TickMath.MAX_SQRT_RATIO - 1,
            0,
            calc.expectedOutput,
            ""
        );

        vm.stopPrank();

        uint256 userToken0After = token0.balanceOf(testUser);
        uint256 userToken1After = token1.balanceOf(testUser);

        uint256 token0Used = userToken0Before - userToken0After;
        uint256 token0Refund = userToken0After;

        console2.log("Amount provided:", amountIn);
        console2.log("Token0 actually used:", token0Used);
        console2.log("Token0 refunded:", token0Refund);
        console2.log("Token1 received (from swap excess):", userToken1After);

        // Verify large refund was given
        assertTrue(token0Refund > amountIn / 2, "Should have refunded most of the tokens");

        // Verify Opener is empty
        assertEq(token0.balanceOf(address(opener)), 0, "Opener should have 0 token0 after large refund");
        assertEq(token1.balanceOf(address(opener)), 0, "Opener should have 0 token1 after large refund");

        console2.log("=== Test Complete: Large Excess Refund Verified ===");
    }
}

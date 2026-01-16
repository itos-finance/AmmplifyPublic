// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import { Test } from "forge-std/Test.sol";

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IUniswapV3Pool } from "lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { ITaker } from "../../src/interfaces/ITaker.sol";
import { TickMath } from "v3-core/libraries/TickMath.sol";
import { FullMath } from "v3-core/libraries/FullMath.sol";
import { FixedPoint96 } from "v3-core/libraries/FixedPoint96.sol";
import { LiquidityAmounts } from "../../test/utils/LiquidityAmounts.sol";

/**
 * @title Collateral
 * @notice Script to set up collateral for taker positions
 * @dev Run with: forge script script/actions/Collateral.s.sol --broadcast --rpc-url <RPC_URL>
 */
contract Collateral is Script, Test {
    // ============ CONFIGURATION - Set all variables here ============

    // Hardcoded addresses
    address public constant SIMPLEX_DIAMOND = address(0x5B5e9d616fAFCCC4865a6C29b6F89Ff3aAE7c892);
    address public constant POOL_ADDRESS = 0x659bD0BC4167BA25c62E05656F78043E7eD4a9da;
    address public constant TOKEN0 = 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A;
    address public constant TOKEN1 = 0x754704Bc059F8C67012fEd69BC8A327a5aafb603;
    address public constant PRANK_ADDRESS = 0x81785e00055159FCae25703D06422aBF5603f8A8;

    // Collateral percentage (5% = 500 basis points)
    uint256 public constant COLLATERAL_PERCENTAGE = 500; // 5% in basis points (500/10000)

    // Taker position configuration (for calculating required amounts)
    int24 public constant TICK_LOWER = type(int24).max; // Use type(int24).max to use current tick
    int24 public constant TICK_UPPER = type(int24).max; // Use type(int24).max to use current tick + tickSpacing
    uint128 public constant LIQUIDITY = 0; // Set to 0 to use liquidity from tick range, otherwise specify amount

    function run() public {
        // Load deployer addresses from .env file
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast();

        console2.log("=== Setting Up Taker Collateral ===");
        console2.log("Deployer address:", deployer);
        console2.log("Prank address:", PRANK_ADDRESS);

        // Use hardcoded addresses
        address poolAddress = POOL_ADDRESS;
        address token0 = TOKEN0;
        address token1 = TOKEN1;
        address simplexDiamond = SIMPLEX_DIAMOND;

        console2.log("Pool Address:", poolAddress);
        console2.log("Token0:", token0);
        console2.log("Token1:", token1);

        // Get current pool state
        _printPoolState(poolAddress);
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        (uint160 sqrtPriceX96, int24 currentTick, , , , , ) = pool.slot0();
        uint24 fee = pool.fee();
        int24 tickSpacing = pool.tickSpacing();

        console2.log("Current tick:", currentTick);
        console2.log("Current sqrt price:", sqrtPriceX96);
        console2.log("Pool fee:", fee);
        console2.log("Tick spacing:", vm.toString(tickSpacing));

        // Determine tick range
        int24 tickLower = TICK_LOWER == type(int24).max ? currentTick : TICK_LOWER;
        int24 tickUpper = TICK_UPPER == type(int24).max ? currentTick + int24(int256(tickSpacing)) : TICK_UPPER;

        // Ensure ticks are valid for the fee tier
        tickLower = _getValidTick(tickLower, fee);
        tickUpper = _getValidTick(tickUpper, fee);

        // Ensure tickLower < tickUpper
        require(tickLower < tickUpper, "Invalid tick range: tickLower must be less than tickUpper");

        console2.log("\n=== Taker Position Configuration ===");
        console2.log("Tick Lower:", vm.toString(tickLower));
        console2.log("Tick Upper:", vm.toString(tickUpper));

        // Get or determine liquidity
        uint128 liquidityToUse = LIQUIDITY;
        if (liquidityToUse == 0) {
            // Look up liquidity in the tick range
            liquidityToUse = _getLiquidityInTickRange(poolAddress, tickLower, tickUpper, currentTick);
            console2.log("Liquidity found in tick range:", liquidityToUse);

            if (liquidityToUse == 0) {
                revert("No liquidity found in specified tick range");
            }
        } else {
            console2.log("Using specified liquidity:", liquidityToUse);
        }

        // Calculate token amounts needed for this liquidity
        (uint256 amount0, uint256 amount1) = _calculateTokenAmounts(poolAddress, tickLower, tickUpper, liquidityToUse);

        console2.log("\n=== Token Amounts Required ===");
        console2.log("Amount0 needed:", amount0);
        console2.log("Amount1 needed:", amount1);

        // Calculate collateral amounts based on the greater amount
        // Take the greater of the two amounts, set 5% collateral for that,
        // convert it using sqrtPriceX96 to get the other token value,
        // and set 5% collateral for that converted amount too
        (uint256 collateral0, uint256 collateral1) = _calculateCollateralAmounts(amount0, amount1, sqrtPriceX96);

        console2.log("\n=== Collateralizing Tokens ===");
        console2.log("Collateral0:", collateral0);
        console2.log("Collateral1:", collateral1);

        // Collateralize tokens (mint to prank address)
        _collateralizeTaker(PRANK_ADDRESS, collateral0, collateral1, token0, token1, simplexDiamond);

        // Set up token approvals
        // _fundAccount(PRANK_ADDRESS, 1e20, 1e20, token0, token1);
        _setupApprovals(type(uint256).max, token0, token1, simplexDiamond);

        console2.log("\n=== Collateral Setup Complete ===");

        vm.stopBroadcast();
    }

    /**
     * @notice Calculate collateral amounts based on the greater token amount
     * @dev Takes the greater of two amounts, sets 5% collateral for that,
     *      converts it using sqrtPriceX96 to get the other token value,
     *      and sets 5% collateral for that converted amount too
     */
    function _calculateCollateralAmounts(
        uint256 amount0,
        uint256 amount1,
        uint160 sqrtPriceX96
    ) internal pure returns (uint256 collateral0, uint256 collateral1) {
        // Convert amount0 to amount1 using sqrtPriceX96 to compare values
        // price = (sqrtPriceX96 / 2^96)^2 = token1/token0
        // amount1Value = amount0 * price = amount0 * sqrtPriceX96^2 / 2^192
        uint256 amount1ValueFromAmount0 = FullMath.mulDiv(
            amount0,
            uint256(sqrtPriceX96) * uint256(sqrtPriceX96),
            FixedPoint96.Q96 * FixedPoint96.Q96
        );

        // Determine which has greater value
        uint256 greaterAmount;
        bool amount0IsGreater;

        if (amount1ValueFromAmount0 >= amount1) {
            // amount0 (converted to token1) is greater or equal
            greaterAmount = amount0;
            amount0IsGreater = true;
        } else {
            // amount1 is greater
            greaterAmount = amount1;
            amount0IsGreater = false;
        }

        // Set 5% collateral for the greater amount
        uint256 collateralForGreater = (greaterAmount * COLLATERAL_PERCENTAGE) / 10000;

        if (amount0IsGreater) {
            // amount0 is greater, so set collateral0 to 5% of greaterAmount
            collateral0 = collateralForGreater;

            // Convert the greater amount to token1 and set 5% collateral for that
            uint256 convertedAmount1 = FullMath.mulDiv(
                greaterAmount,
                uint256(sqrtPriceX96) * uint256(sqrtPriceX96),
                FixedPoint96.Q96 * FixedPoint96.Q96
            );
            collateral1 = (convertedAmount1 * COLLATERAL_PERCENTAGE) / 10000;
        } else {
            // amount1 is greater, so set collateral1 to 5% of greaterAmount
            collateral1 = collateralForGreater;

            // Convert the greater amount to token0 and set 5% collateral for that
            uint256 convertedAmount0 = FullMath.mulDiv(
                greaterAmount,
                FixedPoint96.Q96 * FixedPoint96.Q96,
                uint256(sqrtPriceX96) * uint256(sqrtPriceX96)
            );
            collateral0 = (convertedAmount0 * COLLATERAL_PERCENTAGE) / 10000;
        }

        return (collateral0, collateral1);
    }

    /**
     * @notice Calculate required token amounts for a liquidity position
     */
    function _calculateTokenAmounts(
        address pool,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) internal view returns (uint256 amount0, uint256 amount1) {
        uint160 sqrtPriceX96 = _getCurrentSqrtPrice(pool);

        // Convert ticks to sqrt prices
        uint160 sqrtPriceAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtPriceBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        // Use LiquidityAmounts library for precise calculation
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            sqrtPriceAX96,
            sqrtPriceBX96,
            liquidity
        );

        // Add small buffer for rounding
        amount0 = amount0 + 1;
        amount1 = amount1 + 1;
    }

    /**
     * @notice Get liquidity in a specific tick range
     * @dev If current tick is within the range, returns pool's active liquidity
     * @dev Otherwise, estimates liquidity by checking if ticks are initialized
     */
    function _getLiquidityInTickRange(
        address poolAddress,
        int24 tickLower,
        int24 tickUpper,
        int24 currentTick
    ) internal view returns (uint128) {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);

        // If current tick is within the range, the pool's active liquidity is what's in this range
        if (currentTick >= tickLower && currentTick < tickUpper) {
            return pool.liquidity();
        }

        // If current tick is outside the range, check if ticks are initialized
        (uint128 liquidityGrossLower, , , , , , , bool initializedLower) = pool.ticks(tickLower);
        (uint128 liquidityGrossUpper, , , , , , , bool initializedUpper) = pool.ticks(tickUpper);

        // If ticks are initialized, there's some liquidity in this range
        // Return a conservative estimate - use the smaller of the two gross values
        if (initializedLower || initializedUpper) {
            return liquidityGrossLower < liquidityGrossUpper ? liquidityGrossLower : liquidityGrossUpper;
        }

        // Default to 0 if ticks are not initialized
        return 0;
    }

    /**
     * @notice Get valid tick for a given tick spacing
     */
    function _getValidTick(int24 tick, uint24 fee) internal pure returns (int24) {
        int24 tickSpacing;

        if (fee == 500) {
            tickSpacing = 10;
        } else if (fee == 3000) {
            tickSpacing = 60;
        } else if (fee == 10000) {
            tickSpacing = 200;
        } else {
            tickSpacing = 60; // Default
        }

        return (tick / tickSpacing) * tickSpacing;
    }

    /**
     * @notice Get the current sqrt price of a pool
     */
    function _getCurrentSqrtPrice(address pool) internal view returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96, , , , , , ) = IUniswapV3Pool(pool).slot0();
    }

    /**
     * @notice Collateralize a taker position with specific token amounts
     */
    function _collateralizeTaker(
        address recipient,
        uint256 token0Amount,
        uint256 token1Amount,
        address token0,
        address token1,
        address simplexDiamond
    ) internal {
        ITaker taker = ITaker(simplexDiamond);

        if (token0Amount > 0) {
            IERC20(token0).approve(simplexDiamond, token0Amount);
            taker.collateralize(recipient, token0, token0Amount, "");
            console2.log("Collateralized token0:", token0Amount, "of", token0);
        }

        if (token1Amount > 0) {
            IERC20(token1).approve(simplexDiamond, token1Amount);
            taker.collateralize(recipient, token1, token1Amount, "");
            console2.log("Collateralized token1:", token1Amount, "of", token1);
        }
    }

    // ============ Utility Functions ============

    /**
     * @notice Fund the caller with tokens for testing
     */
    function _fundAccount(
        address account,
        uint256 token0Amount,
        uint256 token1Amount,
        address token0,
        address token1
    ) internal {
        // This assumes the tokens are MockERC20 with mint function
        // In production, you'd need to handle this differently
        if (token0Amount > 0) {
            deal(token0, account, token0Amount);
        }
        if (token1Amount > 0) {
            deal(token1, account, token1Amount);
        }
    }

    /**
     * @notice Set up token approvals for the diamond contracts
     */
    function _setupApprovals(uint256 amount, address token0, address token1, address simplexDiamond) internal {
        // Approve SimplexDiamond contract
        if (simplexDiamond != address(0)) {
            IERC20(token0).approve(simplexDiamond, amount);
            IERC20(token1).approve(simplexDiamond, amount);
            console2.log("Approved SimplexDiamond contract:", simplexDiamond);
        }

        console2.log("Token approvals setup complete");
    }

    /**
     * @notice Print current pool state
     */
    function _printPoolState(address pool) internal view {
        (uint160 sqrtPriceX96, int24 tick, , , , , ) = IUniswapV3Pool(pool).slot0();
        uint24 fee = IUniswapV3Pool(pool).fee();
        int24 tickSpacing = IUniswapV3Pool(pool).tickSpacing();

        console2.log("=== Pool State ===");
        console2.log("Pool:", pool);
        console2.log("Current sqrt price:", sqrtPriceX96);
        console2.log("Current tick:", tick);
        console2.log("Fee tier:", fee);
        console2.log("Tick spacing:", vm.toString(tickSpacing));
    }
}

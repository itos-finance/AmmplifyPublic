// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import { Test } from "forge-std/Test.sol";

import { IUniswapV3Pool } from "lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { TickMath } from "v3-core/libraries/TickMath.sol";
import { ITaker } from "../../src/interfaces/ITaker.sol";

/**
 * @title OpenTaker
 * @notice Script to open a taker position
 * @dev Run with: forge script script/actions/OpenTaker.s.sol --broadcast --rpc-url <RPC_URL>
 */
contract OpenTaker is Script, Test {
    // ============ CONFIGURATION - Set all variables here ============

    // Hardcoded addresses
    address public constant SIMPLEX_DIAMOND = address(0x5B5e9d616fAFCCC4865a6C29b6F89Ff3aAE7c892);
    address public constant POOL_ADDRESS = 0x659bD0BC4167BA25c62E05656F78043E7eD4a9da;
    address public constant PRANK_ADDRESS = 0x81785e00055159FCae25703D06422aBF5603f8A8;

    // Taker position configuration
    uint128 public constant LIQUIDITY = 149648364382606759;

    // Vault indices for taker positions
    uint8 public constant VAULT_INDEX_0 = 0;
    uint8 public constant VAULT_INDEX_1 = 0;

    // Constants for price limits
    uint160 public constant MIN_SQRT_RATIO = 4295128739;
    uint160 public constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    function run() public {
        vm.startBroadcast();

        console2.log("=== Opening Taker Position ===");
        console2.log("Prank address:", PRANK_ADDRESS);

        // Use hardcoded addresses
        address poolAddress = POOL_ADDRESS;
        address simplexDiamond = SIMPLEX_DIAMOND;

        console2.log("Pool Address:", poolAddress);

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
        int24 tickLower = -314040;
        int24 tickUpper = -312780;

        // Ensure ticks are valid for the fee tier
        tickLower = _getValidTick(tickLower, fee);
        tickUpper = _getValidTick(tickUpper, fee);

        // Ensure tickLower < tickUpper
        require(tickLower < tickUpper, "Invalid tick range: tickLower must be less than tickUpper");

        console2.log("\n=== Taker Position Configuration ===");
        console2.log("Tick Lower:", vm.toString(tickLower));
        console2.log("Tick Upper:", vm.toString(tickUpper));

        uint128 liquidityToUse = LIQUIDITY;

        // Open taker position
        console2.log("\n=== Opening Taker Position ===");
        uint256 assetId = _openTaker(
            PRANK_ADDRESS,
            poolAddress,
            [tickLower, tickUpper],
            liquidityToUse,
            simplexDiamond
        );

        console2.log("\n=== Taker Setup Complete ===");
        console2.log("Asset ID:", assetId);

        vm.stopBroadcast();
    }

    // ============ Taker Position Management ============

    /**
     * @notice Open a taker position
     */
    function _openTaker(
        address recipient,
        address poolAddr,
        int24[2] memory ticks,
        uint128 liquidity,
        address simplexDiamond
    ) internal returns (uint256 assetId) {
        // Determine freeze price based on position relative to current price
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddr);
        (, int24 currentTick, , , , , ) = pool.slot0();

        // If taker is below current price, freeze to prefer token0 (X)
        // If taker is above current price, freeze to prefer token1 (Y)
        uint160 freezeSqrtPriceX96 = MIN_SQRT_RATIO;

        console2.log("Pool:", poolAddr);
        console2.log("Tick Range:", vm.toString(ticks[0]), "to", vm.toString(ticks[1]));
        console2.log("Liquidity:", liquidity);
        console2.log("Vault Indices:", VAULT_INDEX_0, VAULT_INDEX_1);

        ITaker taker = ITaker(simplexDiamond);

        assetId = taker.newTaker(
            recipient,
            poolAddr,
            ticks,
            liquidity,
            [VAULT_INDEX_0, VAULT_INDEX_1],
            [MIN_SQRT_RATIO, MAX_SQRT_RATIO],
            freezeSqrtPriceX96,
            ""
        );

        console2.log("Taker Position Created - Asset ID:", assetId);

        return assetId;
    }

    // ============ Utility Functions ============

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

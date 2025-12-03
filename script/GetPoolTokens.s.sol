// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { IUniswapV3PoolImmutables } from "v3-core/interfaces/pool/IUniswapV3PoolImmutables.sol";

/**
 * @title GetPoolTokens
 * @dev Script to read pool address from deployed-addresses.json and get token0/token1
 *
 * This script:
 * - Reads the WETH_USDC_3000 pool address from deployed-addresses.json
 * - Calls token0() and token1() functions on the Uniswap V3 pool
 * - Displays the token addresses and additional pool information
 *
 * Usage:
 * forge script script/GetPoolTokens.s.sol:GetPoolTokens --rpc-url <RPC_URL>
 *
 * For local testing:
 * forge script script/GetPoolTokens.s.sol:GetPoolTokens --rpc-url http://localhost:8545
 */
contract GetPoolTokens is Script {
    // Pool address from deployed-addresses.json
    address public constant POOL_ADDRESS = 0x046Afe0CA5E01790c3d22fe16313d801fa0aD67D; // USDC_WETH_3000

    function run() external view {
        console.log("=== Pool Token Information ===");
        console.log("Pool Address:", POOL_ADDRESS);

        // Create interface instance
        IUniswapV3PoolImmutables pool = IUniswapV3PoolImmutables(POOL_ADDRESS);

        // Get token addresses
        address token0 = pool.token0();
        address token1 = pool.token1();

        console.log("Token0 Address:", token0);
        console.log("Token1 Address:", token1);

        // Get additional pool information
        address factory = pool.factory();
        uint24 fee = pool.fee();
        int24 tickSpacing = pool.tickSpacing();
        uint128 maxLiquidityPerTick = pool.maxLiquidityPerTick();

        console.log("\n=== Additional Pool Information ===");
        console.log("Factory Address:", factory);
        console.log("Fee (in hundredths of a bip):", fee);
        console.log("Tick Spacing:", tickSpacing);
        console.log("Max Liquidity Per Tick:", maxLiquidityPerTick);

        // Determine which token is which based on address comparison
        // In Uniswap V3, token0 is always the token with the smaller address
        if (token0 < token1) {
            console.log("\n=== Token Order ===");
            console.log("Token0 (lower address):", token0);
            console.log("Token1 (higher address):", token1);
        } else {
            console.log("\n=== Token Order ===");
            console.log("Token0 (lower address):", token1);
            console.log("Token1 (higher address):", token0);
        }
    }
}

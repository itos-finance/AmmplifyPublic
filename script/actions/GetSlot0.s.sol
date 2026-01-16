// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/console2.sol";

import { IUniswapV3Pool } from "lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

/**
 * @title GetSlot0
 * @notice Script to get slot0 information from a Uniswap V3 pool
 * @dev Run with: forge script script/actions/GetSlot0.s.sol --rpc-url <RPC_URL>
 */
contract GetSlot0 {
    function run() public {
        // Pool address - update this with the pool address you want to query
        address poolAddr = 0x659bD0BC4167BA25c62E05656F78043E7eD4a9da;

        console2.log("=== Getting Slot0 Info from Uniswap Pool ===");
        console2.log("Pool Address:", poolAddr);

        IUniswapV3Pool pool = IUniswapV3Pool(poolAddr);

        // Get slot0 information
        (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        ) = pool.slot0();

        console2.log("\n=== Slot0 Information ===");
        console2.log("sqrtPriceX96:", sqrtPriceX96);
        console2.log("tick:", tick);
        console2.log("observationIndex:", observationIndex);
        console2.log("observationCardinality:", observationCardinality);
        console2.log("observationCardinalityNext:", observationCardinalityNext);
        console2.log("feeProtocol:", feeProtocol);
        console2.log("unlocked:", unlocked);

        // Also get pool immutables for context
        address token0 = pool.token0();
        address token1 = pool.token1();
        uint24 fee = pool.fee();

        console2.log("\n=== Pool Immutables ===");
        console2.log("token0:", token0);
        console2.log("token1:", token1);
        console2.log("fee:", fee);
    }
}

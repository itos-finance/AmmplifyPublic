// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/console2.sol";
import { Test } from "forge-std/Test.sol";

import { IView } from "../../src/interfaces/IView.sol";
import { IUniswapV3Pool } from "lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

/**
 * @title QueryAssetBalances
 * @notice Script to query asset balances from the View facet
 * @dev Run with: forge script script/actions/QueryAssetBalances.s.sol --rpc-url <RPC_URL>
 */
contract QueryAssetBalances is Test {
    // Configuration - update these values
    address public constant SIMPLEX_DIAMOND = address(0x5B5e9d616fAFCCC4865a6C29b6F89Ff3aAE7c892);
    uint256 public constant ASSET_ID = 15; // Update with the asset ID you want to query

    function run() public {
        console2.log("=== Querying Asset Balances ===");
        console2.log("Diamond Address:", SIMPLEX_DIAMOND);
        console2.log("Asset ID:", ASSET_ID);

        IView viewer = IView(SIMPLEX_DIAMOND);

        // Get asset info first for context
        (address owner, address poolAddr, int24 lowTick, int24 highTick, , uint128 liq) = viewer.getAssetInfo(ASSET_ID);

        console2.log("\n=== Asset Information ===");
        console2.log("Owner:", owner);
        console2.log("Pool Address:", poolAddr);
        console2.log("Low Tick:", vm.toString(lowTick));
        console2.log("High Tick:", vm.toString(highTick));
        console2.log("Liquidity:", liq);

        // Get pool token addresses for context
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddr);
        address token0 = pool.token0();
        address token1 = pool.token1();

        console2.log("\n=== Pool Tokens ===");
        console2.log("Token0:", token0);
        console2.log("Token1:", token1);

        // Query asset balances
        console2.log("\n=== Asset Balances ===");
        (int256 netBalance0, int256 netBalance1, uint256 fees0, uint256 fees1) = viewer.queryAssetBalances(ASSET_ID);

        console2.log("Net Balance Token0:", netBalance0);
        console2.log("Net Balance Token1:", netBalance1);
        console2.log("Fees Token0:", fees0);
        console2.log("Fees Token1:", fees1);

        // Interpret the results
        console2.log("\n=== Balance Interpretation ===");
        if (netBalance0 >= 0) {
            console2.log("Token0: Position owns", uint256(netBalance0), "tokens");
        } else {
            console2.log("Token0: Position owes", uint256(-netBalance0), "tokens");
        }

        if (netBalance1 >= 0) {
            console2.log("Token1: Position owns", uint256(netBalance1), "tokens");
        } else {
            console2.log("Token1: Position owes", uint256(-netBalance1), "tokens");
        }

        console2.log("Token0 Fees:", fees0);
        console2.log("Token1 Fees:", fees1);
    }
}

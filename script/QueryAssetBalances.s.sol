// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/StdJson.sol";
import { IView } from "../src/interfaces/IView.sol";

/**
 * @title QueryAssetBalances
 * @notice Simple script to query asset balances for a given asset ID
 * @dev Run with: forge script script/QueryAssetBalances.s.sol --rpc-url <RPC_URL>
 * @dev Set ASSET_ID environment variable or modify the assetId in the script
 */
contract QueryAssetBalances is Script {
    using stdJson for string;

    function run() external {
        // Load SimplexDiamond address from deployed-addresses.json
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployed-uniswap.json");
        string memory json = vm.readFile(path);
        address simplexDiamond = json.readAddress(".ammplify.simplexDiamond");

        console.log("=== Query Asset Balances ===");
        console.log("SimplexDiamond:", simplexDiamond);

        // Get asset ID from environment variable or use default
        uint256 assetId;
        try vm.envUint("ASSET_ID") returns (uint256 _assetId) {
            assetId = _assetId;
        } catch {
            // Default to asset ID 1 if not provided
            assetId = 1;
            console.log("Note: ASSET_ID not set, using default asset ID:", assetId);
        }

        console.log("Asset ID:", assetId);

        // Get IView interface
        IView viewInterface = IView(simplexDiamond);

        // Get asset information first
        console.log("\n=== Asset Information ===");
        (address owner, address poolAddr, int24 lowTick, int24 highTick, , uint128 liq) = viewInterface
            .getAssetInfo(assetId);

        console.log("Owner:", owner);
        console.log("Pool Address:", poolAddr);
        console.log("Low Tick:", lowTick);
        console.log("High Tick:", highTick);
        console.log("Liquidity:", liq);

        // Query asset balances
        console.log("\n=== Asset Balances ===");
        (int256 netBalance0, int256 netBalance1, uint256 fees0, uint256 fees1) = viewInterface.queryAssetBalances(
            assetId
        );

        console.log("Net Balance Token0:", netBalance0);
        console.log("Net Balance Token1:", netBalance1);
        console.log("Fees Token0:", fees0);
        console.log("Fees Token1:", fees1);

        console.log("\n=== Query Complete ===");
    }
}


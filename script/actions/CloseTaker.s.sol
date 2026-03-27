// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import { Test } from "forge-std/Test.sol";

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IUniswapV3Pool } from "lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { ITaker } from "../../src/interfaces/ITaker.sol";
import { IView } from "../../src/interfaces/IView.sol";

/**
 * @title CloseTaker
 * @notice Script to close an existing taker position
 * @dev Run with: forge script script/actions/CloseTaker.s.sol --broadcast --rpc-url <RPC_URL>
 */
contract CloseTaker is Script, Test {
    // ============ CONFIGURATION - Set all variables here ============

    // Hardcoded addresses
    address public constant SIMPLEX_DIAMOND = address(0x5B5e9d616fAFCCC4865a6C29b6F89Ff3aAE7c892);
    address public constant POOL_ADDRESS = 0x659bD0BC4167BA25c62E05656F78043E7eD4a9da;
    address public constant PRANK_ADDRESS = 0x81785e00055159FCae25703D06422aBF5603f8A8;

    // Asset ID to close
    uint256 public constant ASSET_ID = 71;

    // Constants for price limits
    uint160 public constant MIN_SQRT_RATIO = 4295128739;
    uint160 public constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    function run() public {
        vm.startBroadcast();

        console2.log("=== Closing Taker Position ===");
        console2.log("Prank address:", PRANK_ADDRESS);

        // Use hardcoded addresses
        address simplexDiamond = SIMPLEX_DIAMOND;
        uint256 assetId = ASSET_ID;

        console2.log("Asset ID to close:", assetId);

        // Get interfaces
        ITaker taker = ITaker(simplexDiamond);
        IView viewInterface = IView(simplexDiamond);

        // Get asset information first
        console2.log("\n=== Getting Asset Information ===");
        (address owner, address poolAddr, int24 lowTick, int24 highTick, , uint128 currentLiq) = viewInterface
            .getAssetInfo(assetId);

        console2.log("Asset Owner:", owner);
        console2.log("Pool Address:", poolAddr);
        console2.log("Low Tick:", vm.toString(lowTick));
        console2.log("High Tick:", vm.toString(highTick));
        console2.log("Current Liquidity:", currentLiq);

        // Check if the prank address owns this asset
        require(owner == PRANK_ADDRESS, "Prank address does not own this asset");

        // Get token addresses
        address token0 = IUniswapV3Pool(poolAddr).token0();
        address token1 = IUniswapV3Pool(poolAddr).token1();

        console2.log("Token0:", token0);
        console2.log("Token1:", token1);

        // Query current token balances
        uint256 token0BalanceBefore = IERC20(token0).balanceOf(PRANK_ADDRESS);
        uint256 token1BalanceBefore = IERC20(token1).balanceOf(PRANK_ADDRESS);

        console2.log("\n=== Before Closing ===");
        console2.log("Token0 Balance:", token0BalanceBefore);
        console2.log("Token1 Balance:", token1BalanceBefore);

        // Query asset balances (net balances and fees)
        console2.log("\n=== Querying Asset Balances ===");
        (int256 net0, int256 net1, uint256 fee0, uint256 fee1) = viewInterface.queryAssetBalances(assetId);
        console2.log("Net Token0:", net0);
        console2.log("Net Token1:", net1);
        console2.log("Fee Token0:", fee0);
        console2.log("Fee Token1:", fee1);

        // Remove the taker position
        console2.log("\n=== Removing Taker Position ===");
        (address removedToken0, address removedToken1, int256 balance0, int256 balance1) = taker.removeTaker(
            assetId,
            MIN_SQRT_RATIO, // minSqrtPriceX96
            MAX_SQRT_RATIO, // maxSqrtPriceX96
            "" // rftData (empty for no additional data)
        );

        console2.log("Removed Token0:", removedToken0);
        console2.log("Removed Token1:", removedToken1);
        console2.log("Balance0 (from taker perspective):", balance0);
        console2.log("Balance1 (from taker perspective):", balance1);

        // Query balances after
        uint256 token0BalanceAfter = IERC20(token0).balanceOf(PRANK_ADDRESS);
        uint256 token1BalanceAfter = IERC20(token1).balanceOf(PRANK_ADDRESS);

        console2.log("\n=== After Closing ===");
        console2.log("Token0 Balance:", token0BalanceAfter);
        console2.log("Token1 Balance:", token1BalanceAfter);

        // Calculate the difference
        int256 token0Delta = int256(token0BalanceAfter) - int256(token0BalanceBefore);
        int256 token1Delta = int256(token1BalanceAfter) - int256(token1BalanceBefore);

        console2.log("\n=== Token Deltas ===");
        console2.log("Token0 Delta:", token0Delta);
        console2.log("Token1 Delta:", token1Delta);

        console2.log("\n=== Taker Position Closed Successfully ===");
        console2.log("Asset ID:", assetId);

        vm.stopBroadcast();
    }
}

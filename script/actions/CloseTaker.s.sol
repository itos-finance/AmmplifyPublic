// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { console2 } from "forge-std/console2.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { ITaker } from "../../src/interfaces/ITaker.sol";
import { IView } from "../../src/interfaces/IView.sol";

import { AmmplifyPositions } from "../AmmplifyPositions.s.sol";

/**
 * @title CloseTaker
 * @notice Script to close an existing taker position
 * @dev Run with: forge script script/actions/CloseTaker.s.sol --broadcast --rpc-url <RPC_URL>
 */
contract CloseTaker is AmmplifyPositions {
    function run() public override {
        // Load deployer addresses from .env file
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console2.log("=== Closing Taker Position ===");
        console2.log("Deployer address:", deployer);

        // Asset ID to close
        uint256 assetId = 1;
        console2.log("Asset ID to close:", assetId);

        // Get interfaces
        ITaker taker = ITaker(env.diamond);
        IView viewInterface = IView(env.diamond);

        // Get asset information first
        console2.log("=== Getting Asset Information ===");
        (address owner, address poolAddr, int24 lowTick, int24 highTick, , uint128 currentLiq) = viewInterface
            .getAssetInfo(assetId);

        console2.log("Asset Owner:", owner);
        console2.log("Pool Address:", poolAddr);
        console2.log("Low Tick:", lowTick);
        console2.log("High Tick:", highTick);
        console2.log("Current Liquidity:", currentLiq);

        // Check if the deployer owns this asset
        require(owner == deployer, "Deployer does not own this asset");

        // Get token addresses
        address token0 = getToken0(poolAddr);
        address token1 = getToken1(poolAddr);

        // Query current token balances
        uint256 token0BalanceBefore = IERC20(token0).balanceOf(deployer);
        uint256 token1BalanceBefore = IERC20(token1).balanceOf(deployer);

        console2.log("=== Before Closing ===");
        console2.log("Token0 Balance:", token0BalanceBefore);
        console2.log("Token1 Balance:", token1BalanceBefore);

        // Query asset balances (net balances and fees)
        console2.log("=== Querying Asset Balances ===");
        (int256 net0, int256 net1, uint256 fee0, uint256 fee1) = viewInterface.queryAssetBalances(assetId);
        console2.log("Net Token0:", net0);
        console2.log("Net Token1:", net1);
        console2.log("Fee Token0:", fee0);
        console2.log("Fee Token1:", fee1);

        // Remove the taker position
        console2.log("=== Removing Taker Position ===");
        // Taker positions don't have collectFees - fees are handled during removal
        taker.removeTaker(
            assetId,
            0, // minSqrtPriceX96 (use 0 for no limit)
            type(uint160).max, // maxSqrtPriceX96 (use max for no limit)
            "" // rftData (empty for no additional data)
        );

        // Query balances after
        uint256 token0BalanceAfter = IERC20(token0).balanceOf(deployer);
        uint256 token1BalanceAfter = IERC20(token1).balanceOf(deployer);

        console2.log("=== After Closing ===");
        console2.log("Token0 Balance:", token0BalanceAfter);
        console2.log("Token1 Balance:", token1BalanceAfter);

        // Calculate the difference
        int256 token0Delta = int256(token0BalanceAfter) - int256(token0BalanceBefore);
        int256 token1Delta = int256(token1BalanceAfter) - int256(token1BalanceBefore);

        console2.log("=== Token Deltas ===");
        console2.log("Token0 Delta:", token0Delta);
        console2.log("Token1 Delta:", token1Delta);

        console2.log("=== Taker Position Closed Successfully ===");
        console2.log("Asset ID:", assetId);

        vm.stopBroadcast();
    }
}

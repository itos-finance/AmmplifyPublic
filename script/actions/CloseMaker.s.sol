// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/console2.sol";

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { AmmplifyPositions } from "../AmmplifyPositions.s.sol";
import { IMaker } from "../../src/interfaces/IMaker.sol";
import { IView } from "../../src/interfaces/IView.sol";

/**
 * @title CloseMaker
 * @notice Script to close an existing maker position
 * @dev Run with: forge script script/actions/CloseMaker.s.sol --broadcast --rpc-url <RPC_URL>
 * @dev This script will close the maker position with asset ID 2
 */
contract CloseMaker is AmmplifyPositions {
    function run() public override {
        // Load deployer addresses from .env file
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console2.log("=== Closing Maker Position ===");
        console2.log("Deployer address:", deployer);

        // Asset ID to close
        uint256 assetId = 2;
        console2.log("Asset ID to close:", assetId);

        // Get interfaces
        IMaker maker = IMaker(env.diamond);
        IView viewInterface = IView(env.diamond);

        // Get asset information
        console2.log("=== Getting Asset Information ===");
        (address owner, address poolAddr, int24 lowTick, int24 highTick, , uint128 liq) = viewInterface.getAssetInfo(
            assetId
        );

        console2.log("Asset Owner:", owner);
        console2.log("Pool Address:", poolAddr);
        console2.log("Low Tick:", lowTick);
        console2.log("High Tick:", highTick);
        console2.log("Liquidity:", liq);

        // Check if the deployer owns this asset
        require(owner == deployer, "Deployer does not own this asset");

        // Get current balances before closing
        console2.log("=== Balances Before Closing ===");
        uint256 usdcBalanceBefore = IERC20(getTokenAddress("USDC")).balanceOf(deployer);
        uint256 wethBalanceBefore = IERC20(getTokenAddress("WETH")).balanceOf(deployer);
        console2.log("USDC Balance Before:", usdcBalanceBefore);
        console2.log("WETH Balance Before:", wethBalanceBefore);

        // Query asset balances to see fees and net balances
        console2.log("=== Querying Asset Balances ===");
        (int256 netBalance0, int256 netBalance1, uint256 fees0, uint256 fees1) = viewInterface.queryAssetBalances(
            assetId
        );
        console2.log("Net Balance 0:", netBalance0);
        console2.log("Net Balance 1:", netBalance1);
        console2.log("Fees 0:", fees0);
        console2.log("Fees 1:", fees1);

        // Collect fees first (if any)
        if (fees0 > 0 || fees1 > 0) {
            console2.log("=== Collecting Fees ===");
            try maker.collectFees(deployer, assetId, MIN_SQRT_RATIO, MAX_SQRT_RATIO, "") returns (
                uint256 collectedFees0,
                uint256 collectedFees1
            ) {
                console2.log("Collected Fees 0:", collectedFees0);
                console2.log("Collected Fees 1:", collectedFees1);
            } catch Error(string memory reason) {
                console2.log("Failed to collect fees:", reason);
            } catch {
                console2.log("Failed to collect fees: Unknown error");
            }
        }

        // Remove the maker position
        console2.log("=== Removing Maker Position ===");
        try maker.removeMaker(deployer, assetId, MIN_SQRT_RATIO, MAX_SQRT_RATIO, "") returns (
            address token0,
            address token1,
            uint256 removedX,
            uint256 removedY
        ) {
            console2.log("=== Maker Position Removed Successfully ===");
            console2.log("Token0:", token0);
            console2.log("Token1:", token1);
            console2.log("Removed X (token0):", removedX);
            console2.log("Removed Y (token1):", removedY);
        } catch Error(string memory reason) {
            console2.log("=== Failed to Remove Maker Position ===");
            console2.log("Reason:", reason);
            console2.log("This might be because:");
            console2.log("1. You don't own this asset");
            console2.log("2. The asset doesn't exist");
            console2.log("3. The asset is not a maker position");
        } catch {
            console2.log("=== Failed to Remove Maker Position ===");
            console2.log("Unknown error - check if you own the asset");
        }

        // Get final balances
        console2.log("=== Final Balances ===");
        uint256 usdcBalanceAfter = IERC20(getTokenAddress("USDC")).balanceOf(deployer);
        uint256 wethBalanceAfter = IERC20(getTokenAddress("WETH")).balanceOf(deployer);
        console2.log("USDC Balance After:", usdcBalanceAfter);
        console2.log("WETH Balance After:", wethBalanceAfter);

        // Show the difference
        int256 usdcDiff = int256(usdcBalanceAfter) - int256(usdcBalanceBefore);
        int256 wethDiff = int256(wethBalanceAfter) - int256(wethBalanceBefore);
        console2.log("USDC Difference:", usdcDiff);
        console2.log("WETH Difference:", wethDiff);

        vm.stopBroadcast();
    }
}

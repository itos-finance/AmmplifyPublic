// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/console2.sol";

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { AmmplifyPositions } from "../AmmplifyPositions.s.sol";
import { IMaker } from "../../src/interfaces/IMaker.sol";
import { IView } from "../../src/interfaces/IView.sol";

/**
 * @title AdjustMaker
 * @notice Script to adjust an existing maker position's liquidity
 * @dev Run with: forge script script/actions/AdjustMaker.s.sol --broadcast --rpc-url <RPC_URL>
 * @dev This script will adjust the maker position with asset ID 5
 * @dev Set targetLiq to increase or decrease liquidity
 */
contract AdjustMaker is AmmplifyPositions {
    function run() public override {
        // Load deployer addresses from .env file
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console2.log("=== Adjusting Maker Position ===");
        console2.log("Deployer address:", deployer);

        // Asset ID to adjust
        uint256 assetId = 1;
        console2.log("Asset ID to adjust:", assetId);

        // Get interfaces
        IMaker maker = IMaker(env.simplexDiamond);
        IView viewInterface = IView(env.simplexDiamond);

        // Get asset information first to determine current size
        console2.log("=== Getting Asset Information ===");
        (address owner, address poolAddr, int24 lowTick, int24 highTick, , uint128 currentLiq) = viewInterface
            .getAssetInfo(assetId);

        console2.log("Asset Owner:", owner);
        console2.log("Pool Address:", poolAddr);
        console2.log("Low Tick:", lowTick);
        console2.log("High Tick:", highTick);
        console2.log("Current Liquidity:", currentLiq);

        // Calculate target liquidity (reduce by half by default)
        uint128 targetLiq = currentLiq / 2;
        console2.log("Target liquidity (50% reduction):", targetLiq);

        // Check if the deployer owns this asset
        require(owner == deployer, "Deployer does not own this asset");

        // Calculate the difference
        int128 liqDiff = int128(targetLiq) - int128(currentLiq);
        console2.log("Liquidity Difference:", liqDiff);

        if (liqDiff > 0) {
            console2.log("Action: Adding liquidity");
        } else if (liqDiff < 0) {
            console2.log("Action: Removing liquidity");
        } else {
            console2.log("Action: No change needed");
        }

        // Get current balances before adjustment
        console2.log("=== Balances Before Adjustment ===");
        uint256 usdcBalanceBefore = IERC20(env.usdcToken).balanceOf(deployer);
        uint256 wethBalanceBefore = IERC20(env.wethToken).balanceOf(deployer);
        console2.log("USDC Balance Before:", usdcBalanceBefore);
        console2.log("WETH Balance Before:", wethBalanceBefore);

        // Query asset balances to see current state
        console2.log("=== Querying Current Asset Balances ===");
        (int256 netBalance0, int256 netBalance1, uint256 fees0, uint256 fees1) = viewInterface.queryAssetBalances(
            assetId
        );
        console2.log("Net Balance 0:", netBalance0);
        console2.log("Net Balance 1:", netBalance1);
        console2.log("Fees 0:", fees0);
        console2.log("Fees 1:", fees1);

        // If we're adding liquidity, ensure we have enough tokens
        if (liqDiff > 0) {
            console2.log("=== Ensuring Sufficient Token Balance ===");
            // Fund additional tokens if needed (this is for testing with mock tokens)
            fundAccount(deployer, 100000e6, 1e18); // 100000 USDC, 1 WETH

            // Set up token approvals for diamond contract
            setupApprovals(type(uint256).max);
        }

        // Adjust the maker position
        console2.log("=== Adjusting Maker Position ===");
        try maker.adjustMaker(deployer, assetId, targetLiq, MIN_SQRT_RATIO, MAX_SQRT_RATIO, "") returns (
            address token0,
            address token1,
            int256 delta0,
            int256 delta1
        ) {
            console2.log("=== Maker Position Adjusted Successfully ===");
            console2.log("Token0:", token0);
            console2.log("Token1:", token1);
            console2.log("Delta 0 (token0 change):", delta0);
            console2.log("Delta 1 (token1 change):", delta1);

            // Interpret the deltas
            if (delta0 > 0) {
                console2.log("Paid token0 to pool:", delta0);
            } else if (delta0 < 0) {
                console2.log("Received token0 from pool:", -delta0);
            } else {
                console2.log("No token0 change");
            }

            if (delta1 > 0) {
                console2.log("Paid token1 to pool:", delta1);
            } else if (delta1 < 0) {
                console2.log("Received token1 from pool:", -delta1);
            } else {
                console2.log("No token1 change");
            }
        } catch Error(string memory reason) {
            console2.log("=== Failed to Adjust Maker Position ===");
            console2.log("Reason:", reason);
            console2.log("This might be because:");
            console2.log("1. You don't own this asset");
            console2.log("2. The asset doesn't exist");
            console2.log("3. The asset is not a maker position");
            console2.log("4. Insufficient token balance for adding liquidity");
            console2.log("5. Target liquidity is below minimum required");
        } catch {
            console2.log("=== Failed to Adjust Maker Position ===");
            console2.log("Unknown error - check if you own the asset and have sufficient balance");
        }

        // Get final balances
        console2.log("=== Final Balances ===");
        uint256 usdcBalanceAfter = IERC20(env.usdcToken).balanceOf(deployer);
        uint256 wethBalanceAfter = IERC20(env.wethToken).balanceOf(deployer);
        console2.log("USDC Balance After:", usdcBalanceAfter);
        console2.log("WETH Balance After:", wethBalanceAfter);

        // Show the difference
        int256 usdcDiff = int256(usdcBalanceAfter) - int256(usdcBalanceBefore);
        int256 wethDiff = int256(wethBalanceAfter) - int256(wethBalanceBefore);
        console2.log("USDC Difference:", usdcDiff);
        console2.log("WETH Difference:", wethDiff);

        // Get updated asset information
        console2.log("=== Updated Asset Information ===");
        (, , , , , uint128 newLiq) = viewInterface.getAssetInfo(assetId);
        console2.log("New Liquidity:", newLiq);
        console2.log("Liquidity Change:", int128(newLiq) - int128(currentLiq));

        // Check updated asset balances to see if fees were collected
        console2.log("=== Updated Asset Balances ===");
        (int256 newNetBalance0, int256 newNetBalance1, uint256 newFees0, uint256 newFees1) = viewInterface
            .queryAssetBalances(assetId);
        console2.log("New Net Balance 0:", newNetBalance0);
        console2.log("New Net Balance 1:", newNetBalance1);
        console2.log("New Fees 0:", newFees0);
        console2.log("New Fees 1:", newFees1);

        vm.stopBroadcast();
    }
}

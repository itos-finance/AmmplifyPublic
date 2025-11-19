// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/console2.sol";

import { AmmplifyPositions } from "../AmmplifyPositions.s.sol";
import { IAdmin } from "../../src/interfaces/IAdmin.sol";
import { SmoothRateCurveConfig } from "Commons/Math/SmoothRateCurveLib.sol";

/**
 * @title UpdateFeeCurve
 * @notice Script to update the fee curve for a specific pool
 * @dev Money Market (SPR): base rate 0.5%, target rate 12%, target util 80%, max util 100%, max fee 9100% (as APRs)
 * @dev Run with: forge script script/actions/UpdateFeeCurve.s.sol --broadcast --rpc-url <RPC_URL>
 */
contract UpdateFeeCurve is AmmplifyPositions {
    function run() public override {
        // Load deployer addresses from .env file
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console2.log("=== Updating Fee Curve for Money Market (SPR) ===");
        console2.log("Deployer address:", deployer);

        IAdmin admin = IAdmin(env.simplexDiamond);

        // Money Market (SPR) fee curve configuration
        // Base rate 0.5%, target rate 12%, target util 80%, max util 100%, max fee 9100% (as APRs)
        SmoothRateCurveConfig memory mmSPR = SmoothRateCurveConfig({
            invAlphaX128: 310220638285672831737560825856,
            betaX64: 18446744059817169204, // BETA_OFFSET + betaX64 (where betaX64 = -13892382412)
            maxUtilX64: 18446744073709551616, // 100% utilization
            maxRateX64: 53229759979311 // translates to an APR of 90.99999999999905 instead of 91
        });

        console2.log("=== Fee Curve Configuration ===");
        console2.log("invAlphaX128:", mmSPR.invAlphaX128);
        console2.log("betaX64:", mmSPR.betaX64);
        console2.log("maxUtilX64:", mmSPR.maxUtilX64);
        console2.log("maxRateX64:", mmSPR.maxRateX64);

        // Get the pool address - you can modify this to target a specific pool
        address poolAddress = env.usdcWethPool; // Default to USDC/WETH pool
        console2.log("Target Pool:", poolAddress);

        // Get current fee configuration before update
        console2.log("=== Current Fee Configuration ===");
        try admin.getFeeConfig(poolAddress) returns (
            SmoothRateCurveConfig memory currentFeeCurve,
            SmoothRateCurveConfig memory currentSplitCurve,
            uint128 currentCompoundThreshold,
            uint32 currentTwapInterval
        ) {
            console2.log("Current Fee Curve - invAlphaX128:", currentFeeCurve.invAlphaX128);
            console2.log("Current Fee Curve - betaX64:", currentFeeCurve.betaX64);
            console2.log("Current Fee Curve - maxUtilX64:", currentFeeCurve.maxUtilX64);
            console2.log("Current Fee Curve - maxRateX64:", currentFeeCurve.maxRateX64);
            console2.log("Current Compound Threshold:", currentCompoundThreshold);
        } catch {
            console2.log("No existing fee configuration found for this pool");
        }

        // Update the fee curve
        console2.log("=== Setting New Fee Curve ===");
        try admin.setFeeCurve(poolAddress, mmSPR) {
            console2.log("Fee curve updated successfully for pool:", poolAddress);
        } catch Error(string memory reason) {
            console2.log("Failed to update fee curve:", reason);
        } catch {
            console2.log("Failed to update fee curve: Unknown error");
        }

        // Verify the update
        console2.log("=== Verifying Fee Curve Update ===");
        try admin.getFeeConfig(poolAddress) returns (
            SmoothRateCurveConfig memory updatedFeeCurve,
            SmoothRateCurveConfig memory updatedSplitCurve,
            uint128 updatedCompoundThreshold,
            uint32 updatedTwapInterval
        ) {
            console2.log("Updated Fee Curve - invAlphaX128:", updatedFeeCurve.invAlphaX128);
            console2.log("Updated Fee Curve - betaX64:", updatedFeeCurve.betaX64);
            console2.log("Updated Fee Curve - maxUtilX64:", updatedFeeCurve.maxUtilX64);
            console2.log("Updated Fee Curve - maxRateX64:", updatedFeeCurve.maxRateX64);
            console2.log("Updated Compound Threshold:", updatedCompoundThreshold);

            // Verify the values match what we set
            bool invAlphaMatch = updatedFeeCurve.invAlphaX128 == mmSPR.invAlphaX128;
            bool betaMatch = updatedFeeCurve.betaX64 == mmSPR.betaX64;
            bool maxUtilMatch = updatedFeeCurve.maxUtilX64 == mmSPR.maxUtilX64;
            bool maxRateMatch = updatedFeeCurve.maxRateX64 == mmSPR.maxRateX64;

            console2.log("=== Verification Results ===");
            console2.log("invAlphaX128 matches:", invAlphaMatch);
            console2.log("betaX64 matches:", betaMatch);
            console2.log("maxUtilX64 matches:", maxUtilMatch);
            console2.log("maxRateX64 matches:", maxRateMatch);

            if (invAlphaMatch && betaMatch && maxUtilMatch && maxRateMatch) {
                console2.log("Fee curve update verified successfully!");
            } else {
                console2.log("Fee curve update verification failed!");
            }
        } catch {
            console2.log("Failed to verify fee curve update");
        }

        console2.log("=== Fee Curve Update Complete ===");

        vm.stopBroadcast();
    }
}

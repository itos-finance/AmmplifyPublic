// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/console2.sol";

import { AmmplifyPositions } from "../AmmplifyPositions.s.sol";
import { IAdmin } from "../../src/interfaces/IAdmin.sol";
import { SmoothRateCurveConfig } from "Commons/Math/SmoothRateCurveLib.sol";

/**
 * @title GetFeeConfig
 * @notice Script to query the fee configuration for a specific pool
 * @dev Run with: forge script script/actions/GetFeeConfig.s.sol --rpc-url <RPC_URL>
 * @dev This is a view-only script, no broadcast needed
 */
contract GetFeeConfig is AmmplifyPositions {
    function run() public view override {
        console2.log("=== Querying Fee Configuration ===");
        console2.log("SimplexDiamond address:", env.simplexDiamond);

        IAdmin admin = IAdmin(env.simplexDiamond);

        // Default to USDC/WETH pool, can be modified
        address poolAddress = env.usdcWethPool;
        console2.log("Pool Address:", poolAddress);
        console2.log("");

        // Query fee configuration
        try admin.getFeeConfig(poolAddress) returns (
            SmoothRateCurveConfig memory feeCurve,
            SmoothRateCurveConfig memory splitCurve,
            uint128 compoundThreshold,
            uint32 twapInterval
        ) {
            console2.log("=== Fee Configuration ===");
            console2.log("");
            
            console2.log("Fee Curve:");
            console2.log("  invAlphaX128:", feeCurve.invAlphaX128);
            console2.log("  betaX64:", feeCurve.betaX64);
            console2.log("  maxUtilX64:", feeCurve.maxUtilX64);
            console2.log("  maxRateX64:", feeCurve.maxRateX64);
            console2.log("");
            
            console2.log("Split Curve:");
            console2.log("  invAlphaX128:", splitCurve.invAlphaX128);
            console2.log("  betaX64:", splitCurve.betaX64);
            console2.log("  maxUtilX64:", splitCurve.maxUtilX64);
            console2.log("  maxRateX64:", splitCurve.maxRateX64);
            console2.log("");
            
            console2.log("Compound Threshold:", compoundThreshold);
            console2.log("TWAP Interval:", twapInterval);
            console2.log("");
            
            console2.log("=== Query Complete ===");
        } catch Error(string memory reason) {
            console2.log("=== Error Querying Fee Configuration ===");
            console2.log("Reason:", reason);
        } catch {
            console2.log("=== Error Querying Fee Configuration ===");
            console2.log("Unknown error occurred");
        }
    }

    /**
     * @notice Query fee config for a specific pool address
     * @param poolAddress The pool address to query
     */
    function run(address poolAddress) public view {
        console2.log("=== Querying Fee Configuration ===");
        console2.log("SimplexDiamond address:", env.simplexDiamond);
        console2.log("Pool Address:", poolAddress);
        console2.log("");

        IAdmin admin = IAdmin(env.simplexDiamond);

        // Query fee configuration
        try admin.getFeeConfig(poolAddress) returns (
            SmoothRateCurveConfig memory feeCurve,
            SmoothRateCurveConfig memory splitCurve,
            uint128 compoundThreshold,
            uint32 twapInterval
        ) {
            console2.log("=== Fee Configuration ===");
            console2.log("");
            
            console2.log("Fee Curve:");
            console2.log("  invAlphaX128:", feeCurve.invAlphaX128);
            console2.log("  betaX64:", feeCurve.betaX64);
            console2.log("  maxUtilX64:", feeCurve.maxUtilX64);
            console2.log("  maxRateX64:", feeCurve.maxRateX64);
            console2.log("");
            
            console2.log("Split Curve:");
            console2.log("  invAlphaX128:", splitCurve.invAlphaX128);
            console2.log("  betaX64:", splitCurve.betaX64);
            console2.log("  maxUtilX64:", splitCurve.maxUtilX64);
            console2.log("  maxRateX64:", splitCurve.maxRateX64);
            console2.log("");
            
            console2.log("Compound Threshold:", compoundThreshold);
            console2.log("TWAP Interval:", twapInterval);
            console2.log("");
            
            console2.log("=== Query Complete ===");
        } catch Error(string memory reason) {
            console2.log("=== Error Querying Fee Configuration ===");
            console2.log("Reason:", reason);
        } catch {
            console2.log("=== Error Querying Fee Configuration ===");
            console2.log("Unknown error occurred");
        }
    }
}


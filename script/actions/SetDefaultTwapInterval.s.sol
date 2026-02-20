// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import { AdminFacet } from "../../src/facets/Admin.sol";
import { SmoothRateCurveConfig } from "Commons/Math/SmoothRateCurveLib.sol";

/**
 * @title SetDefaultTwapInterval
 * @notice Script to update the default TWAP interval for the Ammplify diamond
 * @dev Run with: forge script script/actions/SetDefaultTwapInterval.s.sol --broadcast --rpc-url <RPC_URL>
 * @dev Usage: forge script script/actions/SetDefaultTwapInterval.s.sol:SetDefaultTwapInterval --sig "run(address,uint32)" <DIAMOND_ADDRESS> <INTERVAL> --broadcast --rpc-url <RPC_URL>
 */
contract SetDefaultTwapInterval is Script {
    /**
     * @notice Main script execution
     * @param diamondAddress The address of the Ammplify diamond contract
     * @param interval The new default TWAP interval to set (must be > 0)
     */
    function run(address diamondAddress, uint32 interval) public {
        // Load deployer addresses from .env file
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console2.log("=== Setting Default TWAP Interval ===");
        console2.log("Diamond address:", diamondAddress);
        console2.log("New interval:", interval);
        console2.log("Deployer:", deployer);

        // Validate inputs
        require(diamondAddress != address(0), "Diamond address cannot be zero");
        require(interval > 0, "Interval must be greater than zero");

        // Get the admin facet
        AdminFacet adminFacet = AdminFacet(diamondAddress);

        // Get current default TWAP interval before update
        console2.log("=== Current Default TWAP Configuration ===");
        try adminFacet.getDefaultFeeConfig() returns (
            SmoothRateCurveConfig memory _feeCurve,
            SmoothRateCurveConfig memory _splitCurve,
            uint128 _compoundThreshold,
            uint32 currentTwapInterval,
            uint32 _jitLifetime,
            uint64 _jitPenaltyX64
        ) {
            console2.log("Current default TWAP interval:", currentTwapInterval);
        } catch {
            console2.log("Could not retrieve current default TWAP interval");
        }
        // Update the default TWAP interval
        console2.log("=== Setting New Default TWAP Interval ===");
        try adminFacet.setDefaultTwapInterval(interval) {
            console2.log("Default TWAP interval updated successfully");
            console2.log("New interval:", interval);
        } catch Error(string memory reason) {
            console2.log("Failed to update default TWAP interval:", reason);
            revert(reason);
        } catch {
            console2.log("Failed to update default TWAP interval: Unknown error");
            revert("Unknown error");
        }
        // Verify the update
        console2.log("=== Verifying Default TWAP Interval Update ===");
        try adminFacet.getDefaultFeeConfig() returns (
            SmoothRateCurveConfig memory _feeCurve,
            SmoothRateCurveConfig memory _splitCurve,
            uint128 _compoundThreshold,
            uint32 updatedTwapInterval,
            uint32 _jitLifetime,
            uint64 _jitPenaltyX64
        ) {
            console2.log("Updated default TWAP interval:", updatedTwapInterval);

            if (updatedTwapInterval == interval) {
                console2.log("=== Verification Successful ===");
                console2.log("Default TWAP interval update verified!");
            } else {
                console2.log("=== Verification Failed ===");
                console2.log("Expected interval:", interval);
                console2.log("Actual interval:", updatedTwapInterval);
                revert("Verification failed: interval mismatch");
            }
        } catch {
            console2.log("Failed to verify default TWAP interval update");
        }
        console2.log("=== Script Complete ===");

        vm.stopBroadcast();
    }

    /**
     * @notice Default run function that can be used with environment variables or JSON config
     * @dev You can override this or use the parameterized run function
     */
    function run() public {
        // Example: Load from environment or use defaults
        // This is a fallback - prefer using run(address, uint32) with explicit parameters
        address diamondAddress = vm.envOr("DIAMOND_ADDRESS", address(0x5B5e9d616fAFCCC4865a6C29b6F89Ff3aAE7c892));
        uint32 interval = uint32(vm.envOr("TWAP_INTERVAL", uint256(450)));

        if (diamondAddress == address(0)) {
            revert("DIAMOND_ADDRESS environment variable must be set, or use run(address, uint32)");
        }

        run(diamondAddress, interval);
    }
}

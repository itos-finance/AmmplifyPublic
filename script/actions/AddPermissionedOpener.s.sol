// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/console2.sol";

import { AmmplifyPositions } from "../AmmplifyPositions.s.sol";
import { AdminFacet } from "../../src/facets/Admin.sol";

/**
 * @title AddPermissionedOpener
 * @notice Script to add a permissioned opener to the Ammplify system
 * @dev Run with: forge script script/actions/AddPermissionedOpener.s.sol --broadcast --rpc-url <RPC_URL>
 * @dev Set PERMISSIONED_OPENER environment variable to specify the opener address
 */
contract AddPermissionedOpener is AmmplifyPositions {
    function run() public override {
        // Load deployer addresses from .env file
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console2.log("=== Adding Permissioned Opener ===");
        console2.log("Deployer address:", deployer);

        // Load the opener address from environment variable
        address opener = address(0x2a42bE604948c0cce8a1FCFC781089611E2a1ea0);
        console2.log("Opener address:", opener);

        // Get the AdminFacet interface to the diamond
        AdminFacet admin = AdminFacet(env.simplexDiamond);
        console2.log("SimplexDiamond:", env.simplexDiamond);

        // Add the permissioned opener
        console2.log("=== Adding Permissioned Opener ===");
        try admin.addPermissionedOpener(opener) {
            console2.log("Permissioned opener added successfully:", opener);
        } catch Error(string memory reason) {
            console2.log("Failed to add permissioned opener:", reason);
            revert(reason);
        } catch {
            console2.log("Failed to add permissioned opener: Unknown error");
            revert("Unknown error adding permissioned opener");
        }
        console2.log("=== Permissioned Opener Added Successfully ===");

        vm.stopBroadcast();
    }
}

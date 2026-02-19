// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/console2.sol";
import { AmmplifyPositions } from "../AmmplifyPositions.s.sol";
import { AmmplifyAdminRights, AdminFacet } from "../../src/facets/Admin.sol";

/**
 * @title AcceptTakerRights
 * @notice Script to accept previously submitted TAKER rights (after 3-day delay)
 * @dev Run with: forge script script/actions/AcceptTakerRights.s.sol --broadcast --rpc-url <RPC_URL>
 * @dev Run this 3+ days after running GrantTakerRights.s.sol
 */
contract AcceptTakerRights is AmmplifyPositions {
    function run() public override {
        // Load deployer addresses from .env file
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console2.log("=== Accepting TAKER Rights ===");
        console2.log("Target address:", deployer);
        console2.log("Diamond address:", env.diamond);

        // Get the admin facet
        AdminFacet adminFacet = AdminFacet(env.diamond);

        console2.log("=== Attempting to accept TAKER rights ===");

        try adminFacet.acceptRights() {
            console2.log("=== Rights acceptance successful ===");
            console2.log("=== SUCCESS: You can now create taker positions! ===");
        } catch Error(string memory reason) {
            console2.log("=== Failed to accept rights ===");
            console2.log("Reason:", reason);
            console2.log("Make sure:");
            console2.log("1. You previously called submitRights");
            console2.log("2. At least 3 days have passed");
            console2.log("3. You are calling from the same address");
        } catch {
            console2.log("=== Failed to accept rights ===");
            console2.log("Unknown error - check the above conditions");
        }

        vm.stopBroadcast();
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/console2.sol";
import { AmmplifyPositions } from "../AmmplifyPositions.s.sol";
import { AmmplifyAdminRights, AdminFacet } from "../../src/facets/Admin.sol";

/**
 * @title GrantTakerRights
 * @notice Script to grant TAKER rights to an address
 * @dev Run with: forge script script/actions/GrantTakerRights.s.sol --broadcast --rpc-url <RPC_URL>
 * @dev This requires owner privileges and has a 3-day time delay
 */
contract GrantTakerRights is AmmplifyPositions {
    function run() public override {
        // Load deployer addresses from .env file
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console2.log("=== Granting TAKER Rights ===");
        console2.log("Target address:", deployer);
        console2.log("SimplexDiamond address:", env.diamond);

        // Get the admin facet
        AdminFacet adminFacet = AdminFacet(env.diamond);

        console2.log("=== Submitting TAKER rights request ===");
        console2.log("Note: This has a 3-day time delay before you can accept the rights");

        try adminFacet.submitRights(deployer, AmmplifyAdminRights.TAKER, true) {
            console2.log("=== Rights submission successful ===");
            console2.log("Wait 3 days, then run AcceptTakerRights.s.sol to accept the rights");
        } catch Error(string memory reason) {
            console2.log("=== Failed to submit rights ===");
            console2.log("Reason:", reason);
            console2.log("Make sure you are the owner of the contract");
        } catch {
            console2.log("=== Failed to submit rights ===");
            console2.log("Unknown error - check if you are the contract owner");
        }

        vm.stopBroadcast();
    }
}

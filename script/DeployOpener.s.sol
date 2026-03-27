// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Script, console2 } from "forge-std/Script.sol";
import { Opener } from "../src/integrations/Opener.sol";
import { AdminFacet } from "../src/facets/Admin.sol";

/**
 * @title DeployOpener
 * @notice Deployment script for the Opener contract
 * @dev The Opener contract allows users to open maker positions with single-token input
 *      by performing swaps to acquire the missing token
 *
 * Usage:
 *   forge script script/DeployOpener.s.sol:DeployOpener \
 *       --rpc-url $RPC_URL \
 *       --broadcast \
 *       --private-key $DEPLOYER_PRIVATE_KEY
 */
contract DeployOpener is Script {
    Opener public opener;

    // Diamond addresses to register the Opener as permissioned opener
    address constant DIAMOND_1 = 0x5B5e9d616fAFCCC4865a6C29b6F89Ff3aAE7c892;
    address constant DIAMOND_2 = 0xEca6d8973238B71180327C0376c6495A2a29fDE9;

    function run() external {
        // Load configuration
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        console2.log("=== Deploying Opener ===");
        console2.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        opener = new Opener();
        console2.log("Opener deployed at:", address(opener));

        // Register as permissioned opener on both diamonds
        console2.log("=== Registering as Permissioned Opener ===");

        AdminFacet(DIAMOND_1).addPermissionedOpener(address(opener));
        console2.log("Registered on diamond 1:", DIAMOND_1);

        AdminFacet(DIAMOND_2).addPermissionedOpener(address(opener));
        console2.log("Registered on diamond 2:", DIAMOND_2);

        vm.stopBroadcast();

        console2.log("=== Deployment Complete ===");
    }
}

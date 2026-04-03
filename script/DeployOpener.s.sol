// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import { Opener } from "../src/integrations/Opener.sol";
import { AdminFacet } from "../src/facets/Admin.sol";

/**
 * @title DeployOpener
 * @notice Deploys the Opener contract and registers it as a permissioned opener
 * @dev Run with: forge script script/DeployOpener.s.sol --broadcast --rpc-url <RPC_URL>
 * @dev Requires DEPLOYER_PRIVATE_KEY and DIAMOND env vars
 */
contract DeployOpener is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address diamond = vm.envAddress("DIAMOND");

        console2.log("=== Deploying Opener ===");
        console2.log("Diamond:", diamond);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy Opener
        Opener opener = new Opener(diamond);
        console2.log("Opener deployed at:", address(opener));

        // Register as permissioned opener
        AdminFacet admin = AdminFacet(diamond);
        admin.addPermissionedOpener(address(opener));
        console2.log("Opener registered as permissioned opener");

        vm.stopBroadcast();

        console2.log("=== Deployment Complete ===");
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { UniV3Decomposer } from "../src/integrations/UniV3Decomposer.sol";
import { AdminFacet } from "../src/facets/Admin.sol";

/**
 * @title DeployUniV3Decomposer
 * @dev Deployment script for the UniV3Decomposer contract
 *
 * This script deploys the UniV3Decomposer which allows converting existing
 * Uniswap V3 position NFTs into Ammplify Maker positions.
 *
 * Prerequisites:
 * - SimplexDiamond must be deployed (MakerFacet address needed)
 * - Uniswap V3 NFPM must be deployed
 * - Set MAKER_FACET and NFPM environment variables or update the script
 *
 * Usage:
 * export MAKER_FACET=<maker_facet_address>
 * export NFPM=<nfpm_address>
 * forge script script/DeployUniV3Decomposer.s.sol:DeployUniV3Decomposer --rpc-url <RPC_URL> --broadcast
 *
 * For local testing:
 * forge script script/DeployUniV3Decomposer.s.sol:DeployUniV3Decomposer --rpc-url http://localhost:8545 --broadcast
 */
contract DeployUniV3Decomposer is Script {
    // Deployed contract
    UniV3Decomposer public decomposer;

    function run() external {
        // Get the deployer's address and private key from environment
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        address diamond = address(0xEca6d8973238B71180327C0376c6495A2a29fDE9);
        address nfpmAddress = address(0x4C02af995BB1f574c9bf31F43ddc112414aE0Ac7);

        console.log("Deploying UniV3Decomposer with deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy UniV3Decomposer
        decomposer = new UniV3Decomposer(nfpmAddress, diamond);

        // add it as a generically usable opener
        AdminFacet(diamond).addPermissionedOpener(address(decomposer));

        vm.stopBroadcast();
    }
}

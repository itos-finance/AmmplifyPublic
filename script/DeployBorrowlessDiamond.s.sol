// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { BorrowlessDiamond } from "../src/BorrowlessDiamond.sol";

/**
 * @title DeployBorrowlessDiamond
 * @dev Deployment script for the BorrowlessDiamond contract
 *
 * This script deploys the BorrowlessDiamond contract, which is a diamond proxy pattern implementation
 * that automatically registers all required facets during construction EXCEPT the Taker facet:
 * - DiamondCutFacet: For managing facets
 * - DiamondLoupeFacet: For inspecting facets
 * - AdminFacet: For administrative functions
 * - MakerFacet: For maker-related operations
 * - PoolFacet: For pool callback functions
 * - ViewFacet: For view/query functions
 *
 * Note: This diamond does NOT include the TakerFacet, making it a "borrowless" version
 * that only supports maker operations and not taker/borrowing operations.
 *
 */
contract DeployBorrowlessDiamond is Script {
    BorrowlessDiamond public diamond;

    function run() external {
        // Get the deployer's address and private key from environment
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        console.log("Deploying BorrowlessDiamond with deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the BorrowlessDiamond contract
        // The constructor will automatically:
        // 1. Initialize the owner (msg.sender)
        // 2. Initialize fee library
        // 3. Deploy and register all facets (DiamondCut, DiamondLoupe, Admin, Maker, Pool, View)
        // NOTE: TakerFacet is intentionally excluded
        address univ3Factory = address(0x2); // TODO:
        diamond = new BorrowlessDiamond(univ3Factory);

        vm.stopBroadcast();

        // Log deployment information
        console.log("BorrowlessDiamond deployed at:", address(diamond));

        // Cast diamond to access owner function
        IDiamondWithOwner diamondWithOwner = IDiamondWithOwner(address(diamond));
        console.log("Owner:", diamondWithOwner.owner());

        // Log all registered facets
        console.log("\n=== Registered Facets ===");
        logFacetInfo();
    }

    /**
     * @dev Helper function to log information about registered facets
     */
    function logFacetInfo() internal view {
        IDiamondLoupe loupe = IDiamondLoupe(address(diamond));

        // Get all facets
        IDiamondLoupe.Facet[] memory facets = loupe.facets();

        for (uint256 i = 0; i < facets.length; i++) {
            console.log("Facet", i, ":", facets[i].facetAddress);
            console.log("  Selectors:");
            for (uint256 j = 0; j < facets[i].functionSelectors.length; j++) {
                console.log("    ", uint32(facets[i].functionSelectors[j]));
            }
        }
    }
}

// Interface for accessing owner function
interface IDiamondWithOwner {
    function owner() external view returns (address);
}

// Interface for diamond loupe functionality
interface IDiamondLoupe {
    struct Facet {
        address facetAddress;
        bytes4[] functionSelectors;
    }

    function facets() external view returns (Facet[] memory);
}

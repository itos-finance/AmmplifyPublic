// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { SimplexDiamond } from "../src/Diamond.sol";
import { AdminFacet } from "../src/facets/Admin.sol";
import { MakerFacet } from "../src/facets/Maker.sol";
import { TakerFacet } from "../src/facets/Taker.sol";
// import { PoolFacet } from "../src/facets/Pool.sol";
import { PoolFacet } from "../src/facets/CapricornPool.sol";
import { ViewFacet } from "../src/facets/View.sol";

/**
 * @title DeployDiamond
 * @dev Deployment script for the SimplexDiamond contract
 *
 * This script deploys application facets separately, then deploys the SimplexDiamond contract
 * with the facet addresses. DiamondCutFacet and DiamondLoupeFacet are deployed inline
 * by the Diamond constructor as they are core infrastructure facets.
 *
 * This approach:
 * - Allows for independent application facet deployment and verification
 * - Reduces the Diamond contract's constructor size for application facets
 * - Makes it easier to track individual facet deployments
 *
 * Facets deployed separately:
 * - AdminFacet: For administrative functions
 * - MakerFacet: For maker-related operations
 * - TakerFacet: For taker-related operations
 * - PoolFacet: For pool callback functions
 * - ViewFacet: For view/query functions
 *
 * Facets deployed inline by Diamond:
 * - DiamondCutFacet: For managing facets
 * - DiamondLoupeFacet: For inspecting facets
 *
 * Usage Examples:
 *
 * 1. Local testnet (Anvil):
 * forge script script/DeployDiamond.s.sol:DeployDiamond --rpc-url http://localhost:8545 --broadcast
 *
 * 2. With specific private key:
 * forge script script/DeployDiamond.s.sol:DeployDiamond --rpc-url <RPC_URL> --private-key <PRIVATE_KEY> --broadcast
 *
 * 3. With environment variables:
 * export PRIVATE_KEY=<your_private_key>
 * forge script script/DeployDiamond.s.sol:DeployDiamond --rpc-url $RPC_URL --broadcast
 *
 * 4. With contract verification:
 * forge script script/DeployDiamond.s.sol:DeployDiamond --rpc-url <RPC_URL> --private-key <PRIVATE_KEY> --broadcast --verify
 *
 * 5. Dry run (simulation only):
 * forge script script/DeployDiamond.s.sol:DeployDiamond --rpc-url <RPC_URL>
 *
 * The script will output:
 * - Deployed diamond contract address
 * - Owner address
 * - List of all registered facets with their addresses and function selectors
 *
 * Gas Estimate: ~33.5M gas units
 */
contract DeployDiamond is Script {
    SimplexDiamond public diamond;

    // Facet addresses
    AdminFacet public adminFacet;
    MakerFacet public makerFacet;
    TakerFacet public takerFacet;
    PoolFacet public poolFacet;
    ViewFacet public viewFacet;

    function run() external {
        // Get the deployer's address and private key from environment
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        console.log("Deploying SimplexDiamond with deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy application facets first
        // Note: DiamondCutFacet and DiamondLoupeFacet are deployed inline by the Diamond constructor
        // console.log("\n=== Deploying Application Facets ===");

        // console.log("Deploying AdminFacet...");
        // adminFacet = new AdminFacet();
        // console.log("AdminFacet deployed at:", address(adminFacet));

        // console.log("Deploying MakerFacet...");
        // makerFacet = new MakerFacet();
        // console.log("MakerFacet deployed at:", address(makerFacet));

        // console.log("Deploying TakerFacet...");
        // takerFacet = new TakerFacet();
        // console.log("TakerFacet deployed at:", address(takerFacet));

        // console.log("Deploying ViewFacet...");
        // viewFacet = new ViewFacet();
        // console.log("ViewFacet deployed at:", address(viewFacet));

        // Deploy the Pool facet for the amm we are integrating with
        // console.log("Deploying PoolFacet...");
        // poolFacet = new PoolFacet();
        // console.log("PoolFacet deployed at:", address(poolFacet));

        // Re-use already deployed facets
        address adminFacetAddress = address(0x6E36dD75A4eb1b2A6F18C95812f8A060F17Ee2bf);
        address makerFacetAddress = address(0x04e970c764378DaC3DF29Fd6EFe062b05C6492D7);
        address takerFacetAddress = address(0x9e45Fe7A52aD9c45b6B154FafD36c8C08453583d);
        address viewFacetAddress = address(0x7bd548e7e488f103db9A15daDa73c89718AC146a);
        address poolFacetAddress = address(0x712850D636de7f0472567A2462407465fCB9661C);

        // Deploy the SimplexDiamond contract with application facet addresses
        // The constructor will:
        // 1. Deploy DiamondCutFacet and DiamondLoupeFacet inline
        // 2. Initialize the owner (msg.sender)
        // 3. Initialize fee library
        // 4. Register all facets (including inline-deployed ones)
        console.log("\n=== Deploying Diamond ===");
        console.log("(DiamondCutFacet and DiamondLoupeFacet will be deployed inline)");
        address univ3Factory = address(0x204FAca1764B154221e35c0d20aBb3c525710498);

        SimplexDiamond.FacetAddresses memory facetAddresses = SimplexDiamond.FacetAddresses({
            adminFacet: adminFacetAddress,
            makerFacet: makerFacetAddress,
            takerFacet: takerFacetAddress,
            poolFacet: poolFacetAddress,
            viewFacet: viewFacetAddress
        });

        diamond = new SimplexDiamond(univ3Factory, facetAddresses);

        vm.stopBroadcast();

        // Log deployment information
        console.log("\n=== Deployment Summary ===");
        console.log("SimplexDiamond deployed at:", address(diamond));

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
        // Cast diamond to access loupe functions
        IDiamondLoupe diamondLoupe = IDiamondLoupe(address(diamond));

        // Get all facets from the diamond
        IDiamondLoupe.Facet[] memory facets = diamondLoupe.facets();

        console.log("Total facets registered:", facets.length);

        for (uint256 i = 0; i < facets.length; i++) {
            console.log("Facet", i, "address:", facets[i].facetAddress);
            console.log("  Function selectors count:", facets[i].functionSelectors.length);

            // Log first few function selectors for reference
            uint256 selectorsToShow = facets[i].functionSelectors.length > 3 ? 3 : facets[i].functionSelectors.length;
            for (uint256 j = 0; j < selectorsToShow; j++) {
                console.log("    Selector", j, ":");
                console.logBytes4(facets[i].functionSelectors[j]);
            }
            if (facets[i].functionSelectors.length > 3) {
                console.log("    ... and", facets[i].functionSelectors.length - 3, "more selectors");
            }
        }
    }
}

// Import the diamond loupe interface for facet inspection
import { IDiamondLoupe } from "Commons/Diamond/interfaces/IDiamondLoupe.sol";
import { IERC173 } from "Commons/ERC/interfaces/IERC173.sol";

// Interface extensions for the deployed diamond to access owner and facet functions
interface IDiamondWithOwner is IDiamondLoupe, IERC173 {
    function owner() external view returns (address);
}

// Cast the diamond to the extended interface for easier access
library DiamondCast {
    function cast(SimplexDiamond diamond) internal pure returns (IDiamondWithOwner) {
        return IDiamondWithOwner(address(diamond));
    }
}

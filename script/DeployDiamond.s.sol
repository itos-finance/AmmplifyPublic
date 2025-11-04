// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { SimplexDiamond } from "../src/Diamond.sol";

/**
 * @title DeployDiamond
 * @dev Deployment script for the SimplexDiamond contract
 *
 * This script deploys the SimplexDiamond contract, which is a diamond proxy pattern implementation
 * that automatically registers all required facets during construction:
 * - DiamondCutFacet: For managing facets
 * - DiamondLoupeFacet: For inspecting facets
 * - AdminFacet: For administrative functions
 * - MakerFacet: For maker-related operations
 * - TakerFacet: For taker-related operations
 * - PoolFacet: For pool callback functions
 * - ViewFacet: For view/query functions
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

        function run() external {
        // Get the deployer's address and private key from environment
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        console.log("Deploying SimplexDiamond with deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the SimplexDiamond contract
        // The constructor will automatically:
        // 1. Initialize the owner (msg.sender)
        // 2. Initialize fee library
        // 3. Deploy and register all facets (DiamondCut, DiamondLoupe, Admin, Maker, Taker, Pool, View)
        diamond = new SimplexDiamond();

        vm.stopBroadcast();

        // Log deployment information
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

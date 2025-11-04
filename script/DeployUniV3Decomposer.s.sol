// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { UniV3Decomposer } from "../src/integrations/UniV3Decomposer.sol";

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

    // Configuration (loaded from environment)
    address public makerFacetAddress;
    address public nfpmAddress;

    function run() external {
        // Get the deployer's address and private key from environment
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        console.log("Deploying UniV3Decomposer with deployer:", deployer);

        // Load required addresses
        _loadAddresses();

        vm.startBroadcast(deployerPrivateKey);

        // Deploy UniV3Decomposer
        decomposer = new UniV3Decomposer(nfpmAddress, makerFacetAddress);

        vm.stopBroadcast();

        // Log deployment summary
        _logDeploymentSummary();
    }

    /**
     * @notice Load required contract addresses from environment variables
     */
    function _loadAddresses() internal {
        try vm.envAddress("MAKER_FACET") returns (address maker) {
            makerFacetAddress = maker;
        } catch {
            console.log("MAKER_FACET not set in environment, using zero address");
            makerFacetAddress = address(0);
        }

        try vm.envAddress("NFPM") returns (address nfpm) {
            nfpmAddress = nfpm;
        } catch {
            console.log("NFPM not set in environment, using zero address");
            nfpmAddress = address(0);
        }

        require(makerFacetAddress != address(0), "MAKER_FACET address required");
        require(nfpmAddress != address(0), "NFPM address required");

        console.log("Using MakerFacet at:", makerFacetAddress);
        console.log("Using NFPM at:", nfpmAddress);
    }

    /**
     * @notice Log deployment summary
     */
    function _logDeploymentSummary() internal view {
        console.log("\n=== UniV3Decomposer Deployment Summary ===");
        console.log("UniV3Decomposer:", address(decomposer));
        console.log("Configuration:");
        console.log("  NFPM:", address(decomposer.NFPM()));
        console.log("  MakerFacet:", address(decomposer.MAKER()));

        console.log("\nThe UniV3Decomposer can now:");
        console.log("- Convert Uniswap V3 position NFTs to Ammplify positions");
        console.log("- Handle token transfers via RFT callback mechanism");
        console.log("- Calculate dynamic liquidity offsets based on tick ranges");
    }

    /**
     * @notice Helper function to verify the deployment by checking configuration
     */
    function verifyDeployment() external view returns (bool) {
        if (address(decomposer) == address(0)) {
            console.log("ERROR: Decomposer not deployed");
            return false;
        }

        if (address(decomposer.NFPM()) != nfpmAddress) {
            console.log("ERROR: NFPM address mismatch");
            return false;
        }

        if (address(decomposer.MAKER()) != makerFacetAddress) {
            console.log("ERROR: MakerFacet address mismatch");
            return false;
        }

        console.log(unicode"✅ UniV3Decomposer deployment verified successfully");
        return true;
    }
}

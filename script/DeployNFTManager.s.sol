// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { NFTManager } from "../src/integrations/NFTManager.sol";

/**
 * @title DeployNFTManager
 * @dev Deployment script for the NFTManager contract
 *
 * This script deploys the NFTManager which provides ERC721 NFT functionality
 * for Ammplify positions, allowing users to:
 * - Mint NFTs representing Ammplify maker positions
 * - Decompose Uniswap V3 positions and mint corresponding NFTs
 * - Burn NFTs to withdraw liquidity and collect fees
 * - View position metadata and generate SVG representations
 *
 * Prerequisites:
 * - SimplexDiamond must be deployed (MakerFacet address needed)
 * - UniV3Decomposer must be deployed
 * - Uniswap V3 NFPM must be deployed
 * - Set MAKER_FACET, DECOMPOSER, and NFPM environment variables
 *
 * Usage:
 * export MAKER_FACET=<maker_facet_address>
 * export DECOMPOSER=<decomposer_address>
 * export NFPM=<nfpm_address>
 * forge script script/DeployNFTManager.s.sol:DeployNFTManager --rpc-url <RPC_URL> --broadcast
 *
 * For local testing:
 * forge script script/DeployNFTManager.s.sol:DeployNFTManager --rpc-url http://localhost:8545 --broadcast
 */
contract DeployNFTManager is Script {
    // Deployed contract
    NFTManager public nftManager;

    // Configuration (loaded from environment)
    address public makerFacetAddress;
    address public decomposerAddress;
    address public nfpmAddress;

    function run() external {
        // Get the deployer's address and private key from environment
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        console.log("Deploying NFTManager with deployer:", deployer);

        // Load required addresses
        _loadAddresses();

        vm.startBroadcast(deployerPrivateKey);

        // Deploy NFTManager
        nftManager = new NFTManager(makerFacetAddress, decomposerAddress, nfpmAddress);

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

        try vm.envAddress("DECOMPOSER") returns (address decomposer) {
            decomposerAddress = decomposer;
        } catch {
            console.log("DECOMPOSER not set in environment, using zero address");
            decomposerAddress = address(0);
        }

        try vm.envAddress("NFPM") returns (address nfpm) {
            nfpmAddress = nfpm;
        } catch {
            console.log("NFPM not set in environment, using zero address");
            nfpmAddress = address(0);
        }

        require(makerFacetAddress != address(0), "MAKER_FACET address required");
        require(decomposerAddress != address(0), "DECOMPOSER address required");
        require(nfpmAddress != address(0), "NFPM address required");

        console.log("Using MakerFacet at:", makerFacetAddress);
        console.log("Using Decomposer at:", decomposerAddress);
        console.log("Using NFPM at:", nfpmAddress);
    }

    /**
     * @notice Log deployment summary
     */
    function _logDeploymentSummary() internal view {
        console.log("\n=== NFTManager Deployment Summary ===");
        console.log("NFTManager:", address(nftManager));
        console.log("Configuration:");
        console.log("  Name:", nftManager.name());
        console.log("  Symbol:", nftManager.symbol());
        console.log("  Owner:", nftManager.owner());
        console.log("  MakerFacet:", address(nftManager.MAKER_FACET()));
        console.log("  Decomposer:", address(nftManager.DECOMPOSER()));
        console.log("  NFPM:", address(nftManager.NFPM()));
        console.log("  Total Supply:", nftManager.totalSupply());

        console.log("\nThe NFTManager supports:");
        console.log("- ERC721 NFT functionality for Ammplify positions");
        console.log("- Minting NFTs for new maker positions");
        console.log("- Decomposing Uniswap V3 positions into NFTs");
        console.log("- Burning NFTs to withdraw liquidity");
        console.log("- Collecting fees from positions");
        console.log("- Generating metadata and SVG images");
    }

    /**
     * @notice Helper function to verify the deployment by checking configuration
     */
    function verifyDeployment() external view returns (bool) {
        if (address(nftManager) == address(0)) {
            console.log("ERROR: NFTManager not deployed");
            return false;
        }

        if (address(nftManager.MAKER_FACET()) != makerFacetAddress) {
            console.log("ERROR: MakerFacet address mismatch");
            return false;
        }

        if (address(nftManager.DECOMPOSER()) != decomposerAddress) {
            console.log("ERROR: Decomposer address mismatch");
            return false;
        }

        if (address(nftManager.NFPM()) != nfpmAddress) {
            console.log("ERROR: NFPM address mismatch");
            return false;
        }

        // Check ERC721 functionality
        if (keccak256(bytes(nftManager.name())) != keccak256(bytes("Ammplify Position NFT"))) {
            console.log("ERROR: Incorrect NFT name");
            return false;
        }

        if (keccak256(bytes(nftManager.symbol())) != keccak256(bytes("APNFT"))) {
            console.log("ERROR: Incorrect NFT symbol");
            return false;
        }

        console.log(unicode"✅ NFTManager deployment verified successfully");
        return true;
    }
}

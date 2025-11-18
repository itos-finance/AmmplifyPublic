// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { UniswapV3Factory } from "v3-core/UniswapV3Factory.sol";
import { NonfungiblePositionManager } from "../test/mocks/nfpm/NonfungiblePositionManager.sol";
import { NonfungibleTokenPositionDescriptor } from "../test/mocks/nfpm/NonfungibleTokenPositionDescriptor.sol";
import { stdJson } from "forge-std/StdJson.sol";

/**
 * @title DeployNFPM
 * @dev Deployment script for NonfungiblePositionManager (NFPM)
 *
 * This script deploys:
 * - UniswapV3Factory (if not provided)
 * - NonfungibleTokenPositionDescriptor
 * - NonfungiblePositionManager (NFPM)
 *
 * Prerequisites:
 * - Set WETH9 address via environment variable or update the script
 * - Ensure deployed-addresses.json exists with uniswap.factory address (preferred)
 * - Optionally set FACTORY environment variable as fallback
 *
 * Usage:
 * export WETH9=<weth_address>
 * forge script script/actions/DeployNFPM.s.sol:DeployNFPM --rpc-url <RPC_URL> --broadcast
 *
 * For local testing:
 * forge script script/actions/DeployNFPM.s.sol:DeployNFPM --rpc-url http://localhost:8545 --broadcast
 *
 * Note: The script will automatically use the factory address from deployed-addresses.json
 * if available, falling back to environment variable or deploying new if neither exists.
 */
contract DeployNFPM is Script {
    // Deployed contracts
    UniswapV3Factory public factory;
    NonfungiblePositionManager public nfpm;
    NonfungibleTokenPositionDescriptor public descriptor;

    // Configuration
    address public weth9;
    address public factoryAddress;

    function run() external {
        // Get the deployer's address and private key from environment
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        console.log("============================================================");
        console.log("DEPLOYING NONFUNGIBLE POSITION MANAGER (NFPM)");
        console.log("============================================================");
        console.log("Deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);
        console.log("");

        // Load configuration
        _loadConfiguration();

        vm.startBroadcast(deployerPrivateKey);

        // Deploy or use existing UniswapV3Factory
        _deployFactory();

        // Deploy NonfungibleTokenPositionDescriptor
        _deployDescriptor();

        // Deploy NonfungiblePositionManager
        _deployNFPM();

        vm.stopBroadcast();

        // Log deployment summary
        _logDeploymentSummary();
    }

    /**
     * @notice Load configuration from deployed-addresses.json and environment variables
     */
    function _loadConfiguration() internal {
        // Load WETH9 address from environment (fallback to zero address)
        try vm.envAddress("WETH9") returns (address weth) {
            weth9 = weth;
        } catch {
            console.log("WETH9 not set in environment, using zero address");
            weth9 = address(0);
        }

        // Load factory address from deployed-addresses.json
        try vm.readFile("./deployed-addresses.json") returns (string memory jsonData) {
            // Parse the JSON to get the factory address directly
            factoryAddress = stdJson.readAddress(jsonData, ".uniswap.factory");
            console.log("Using factory from deployed-addresses.json at:", factoryAddress);
        } catch {
            // Fallback to environment variable if JSON file doesn't exist or is invalid
            try vm.envAddress("FACTORY") returns (address factoryAddr) {
                factoryAddress = factoryAddr;
                console.log("Using factory from environment variable at:", factoryAddress);
            } catch {
                console.log("No factory found in deployed-addresses.json or environment, will deploy new factory");
                factoryAddress = address(0);
            }
        }

        // require(weth9 != address(0), "WETH9 address required");

        console.log("Configuration:");
        console.log("  WETH9:", weth9);
        console.log("  Factory:", factoryAddress == address(0) ? "Will deploy new" : vm.toString(factoryAddress));
        console.log("");
    }

    /**
     * @notice Deploy or use existing UniswapV3Factory
     */
    function _deployFactory() internal {
        if (factoryAddress != address(0)) {
            // Use existing factory
            factory = UniswapV3Factory(factoryAddress);
            console.log("Using existing UniswapV3Factory at:", address(factory));
        } else {
            // Deploy new factory
            console.log("Deploying UniswapV3Factory...");
            factory = new UniswapV3Factory();
            console.log("UniswapV3Factory deployed at:", address(factory));
        }
    }

    /**
     * @notice Deploy NonfungibleTokenPositionDescriptor
     */
    function _deployDescriptor() internal {
        console.log("Deploying NonfungibleTokenPositionDescriptor...");
        descriptor = new NonfungibleTokenPositionDescriptor(
            weth9, // WETH9 address
            bytes32("ETH") // nativeCurrencyLabelBytes
        );
        console.log("NonfungibleTokenPositionDescriptor deployed at:", address(descriptor));
    }

    /**
     * @notice Deploy NonfungiblePositionManager
     */
    function _deployNFPM() internal {
        console.log("Deploying NonfungiblePositionManager...");
        nfpm = new NonfungiblePositionManager(
            address(factory), // factory address
            weth9, // WETH9 address
            address(descriptor) // token descriptor address
        );
        console.log("NonfungiblePositionManager deployed at:", address(nfpm));
    }

    /**
     * @notice Log deployment summary
     */
    function _logDeploymentSummary() internal view {
        console.log("============================================================");
        console.log("NFPM DEPLOYMENT COMPLETE!");
        console.log("============================================================");

        console.log(unicode"🏗️  DEPLOYED CONTRACTS:");
        console.log("   UniswapV3Factory:", address(factory));
        console.log("   NonfungibleTokenPositionDescriptor:", address(descriptor));
        console.log("   NonfungiblePositionManager:", address(nfpm));
        console.log("");

        console.log(unicode"🔧  CONFIGURATION:");
        console.log("   WETH9:", weth9);
        console.log("   Factory Owner:", factory.owner());
        console.log("");

        console.log(unicode"🚀  NEXT STEPS:");
        console.log("   1. Create pools using the factory:");
        console.log("      factory.createPool(token0, token1, fee)");
        console.log("");
        console.log("   2. Create positions using the NFPM:");
        console.log("      nfpm.mint(params)");
        console.log("");
        console.log("   3. View positions:");
        console.log("      nfpm.positions(tokenId)");
        console.log("");

        console.log("============================================================");
        console.log(unicode"NFPM deployed successfully! 🎉");
        console.log("============================================================");
    }

    /**
     * @notice Helper function to get deployment addresses as a JSON-like string
     * @dev Useful for frontend integration or other scripts
     */
    function getDeploymentAddresses() external view returns (string memory) {
        return
            string(
                abi.encodePacked(
                    "{\n",
                    '  "factory": "',
                    vm.toString(address(factory)),
                    '",\n',
                    '  "descriptor": "',
                    vm.toString(address(descriptor)),
                    '",\n',
                    '  "nfpm": "',
                    vm.toString(address(nfpm)),
                    '",\n',
                    '  "weth9": "',
                    vm.toString(weth9),
                    '"\n',
                    "}"
                )
            );
    }
}

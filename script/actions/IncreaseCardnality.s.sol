// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "forge-std/StdJson.sol";

// Uniswap V3 interfaces
import { UniswapV3Pool } from "v3-core/UniswapV3Pool.sol";

/**
 * @title IncreaseCardinality
 * @notice Script to increase observation cardinality for a Uniswap V3 pool
 * @dev Run with: forge script script/actions/IncreaseCardnality.s.sol --broadcast --rpc-url <RPC_URL>
 */
contract IncreaseCardinality is Script {
    using stdJson for string;

    // Constants
    uint16 public constant MIN_OBSERVATIONS = 32;

    // Environment configuration
    struct Environment {
        address deployer;
        address pool;
        string jsonPath;
    }

    Environment public env;

    function setUp() public {
        loadEnvironment();
    }

    /**
     * @notice Load environment configuration from JSON file
     */
    function loadEnvironment() public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployed-addresses.json");
        string memory json = vm.readFile(path);

        env.deployer = json.readAddress(".deployer");
        // Default to USDC/WETH pool, can be overridden
        env.pool = json.readAddress(".uniswap.pools.USDC_WETH_3000");
        env.jsonPath = path;

        console2.log("=== Environment Loaded ===");
        console2.log("Deployer:", env.deployer);
        console2.log("Pool:", env.pool);
    }

    /**
     * @notice Main script execution
     * @param poolAddress Optional pool address (uses default from JSON if not provided)
     */
    function run(address poolAddress) public {
        // Load deployer addresses from .env file
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        if (poolAddress == address(0)) {
            poolAddress = env.pool;
        }

        console2.log("=== Increasing Pool Cardinality ===");
        console2.log("Pool:", poolAddress);

        // Increase observation cardinality
        UniswapV3Pool(poolAddress).increaseObservationCardinalityNext(MIN_OBSERVATIONS);
        console2.log("Increased observation cardinality to:", MIN_OBSERVATIONS);

        console2.log("=== Script Complete ===");

        vm.stopBroadcast();
    }

    /**
     * @notice Default run function with default pool
     */
    function run() public {
        run(address(0x999Acd737b1EB0b545eeaab8fc0096626D49f0Fb));
    }
}

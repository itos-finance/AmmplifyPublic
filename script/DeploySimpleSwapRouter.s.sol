// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { console2 } from "forge-std/console2.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { SimpleSwapRouter } from "../test/mocks/router/SimpleSwapRouter.sol";

/**
 * @title DeploySimpleSwapRouter
 * @dev Deploys the simplified swap router for testing
 */
contract DeploySimpleSwapRouter is Script {
    address public simpleSwapRouter;
    address public factory;
    address public weth;
    address public deployer;

    /**
     * @notice Load environment configuration from addresses JSON
     */
    function loadEnvironment() public {
        string memory protocol = vm.envOr("AMMPLIFY_PROTOCOL", string("uniswapv3"));
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/addresses/", protocol, ".json");
        string memory json = vm.readFile(path);

        factory = stdJson.readAddress(json, ".factory");
        weth = address(0); // Set WETH to address(0) for testing
        deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");

        console2.log("=== Environment Loaded ===");
        console2.log("Deployer:", deployer);
        console2.log("Factory:", factory);
        console2.log("WETH:", weth);
    }

    function run() external {
        // Load addresses from addresses JSON
        loadEnvironment();

        console.log("============================================================");
        console.log("DEPLOYING SIMPLE SWAP ROUTER");
        console.log("============================================================");
        console.log("Deployer:", deployer);
        console.log("Factory:", factory);
        console.log("WETH:", weth);
        console.log("");

        // Get the deployer's private key from environment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy SimpleSwapRouter
        console.log("Deploying SimpleSwapRouter...");
        SimpleSwapRouter router = new SimpleSwapRouter(factory, weth);
        simpleSwapRouter = address(router);

        console.log(unicode"✅ SimpleSwapRouter deployed:");
        console.log("   SimpleSwapRouter:", simpleSwapRouter);
        console.log("");

        vm.stopBroadcast();

        // Log final summary
        _logFinalSummary();
    }

    /**
     * @notice Log final deployment summary
     */
    function _logFinalSummary() internal view {
        console.log("============================================================");
        console.log("SIMPLE SWAP ROUTER DEPLOYMENT COMPLETE!");
        console.log("============================================================");
        console.log(unicode"🔄  SIMPLE SWAP ROUTER:");
        console.log("   Deployer:", deployer);
        console.log("   SimpleSwapRouter:", simpleSwapRouter);
        console.log("   Factory:", factory);
        console.log("   WETH:", weth);
        console.log("");
        console.log("============================================================");
        console.log(unicode"SimpleSwapRouter deployed successfully! 🎉");
        console.log("============================================================");
    }
}

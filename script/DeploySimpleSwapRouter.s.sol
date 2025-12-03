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
     * @notice Load environment configuration from JSON file
     */
    function loadEnvironment() public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployed-addresses.json");
        string memory json = vm.readFile(path);

        factory = stdJson.readAddress(json, ".uniswap.factory");
        weth = address(0); // Set WETH to address(0) for testing
        deployer = stdJson.readAddress(json, ".deployer");

        console2.log("=== Environment Loaded ===");
        console2.log("Deployer:", deployer);
        console2.log("Factory:", factory);
        console2.log("WETH:", weth);
    }

    function run() external {
        // Load addresses from deployed-addresses.json
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

        // Update deployed-addresses.json
        console.log("Updating deployed-addresses.json...");
        _updateDeployedAddressesJson();

        // Log final summary
        _logFinalSummary();
    }

    /**
     * @notice Update deployed-addresses.json with SimpleSwapRouter address
     */
    function _updateDeployedAddressesJson() internal {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployed-addresses.json");
        string memory existingJson = vm.readFile(path);

        // Read existing data
        string memory network = stdJson.readString(existingJson, ".network");
        address existingDeployer = stdJson.readAddress(existingJson, ".deployer");
        address uniV3Factory = stdJson.readAddress(existingJson, ".uniswap.factory");

        // Build tokens JSON
        string memory tokensJson = _buildTokensJson(existingJson);

        // Build vaults JSON
        string memory vaultsJson = _buildVaultsJson(existingJson);

        // Build ammplify JSON
        string memory ammplifyJson = _buildAmmplifyJson(existingJson);

        // Build uniswap JSON (with updated simpleSwapRouter)
        string memory uniswapJson = _buildUniswapJson(existingJson, uniV3Factory);

        // Build integrations JSON
        string memory integrationsJson = _buildIntegrationsJson(existingJson);

        // Build complete JSON
        string memory jsonContent = string(
            abi.encodePacked(
                "{\n",
                '  "network": "',
                network,
                '",\n',
                '  "deployer": "',
                vm.toString(existingDeployer),
                '",\n',
                tokensJson,
                vaultsJson,
                ammplifyJson,
                uniswapJson,
                integrationsJson,
                "}"
            )
        );

        // Write to deployed-addresses.json
        vm.writeFile(path, jsonContent);

        console.log(unicode"📝 Updated deployed-addresses.json with SimpleSwapRouter address");
    }

    /**
     * @notice Build tokens JSON section
     */
    function _buildTokensJson(string memory json) internal view returns (string memory) {
        string memory result = '  "tokens": {\n';
        bool first = true;

        // Read all tokens
        string[7] memory tokenSymbols = ["USDC", "DAK", "CHOG", "USDT", "YAKI", "WMON", "WETH"];

        for (uint256 i = 0; i < tokenSymbols.length; i++) {
            string memory key = string.concat(".tokens.", tokenSymbols[i], ".address");
            if (stdJson.keyExists(json, key)) {
                address addr = stdJson.readAddress(json, key);
                if (addr != address(0)) {
                    string memory name = stdJson.readString(json, string.concat(".tokens.", tokenSymbols[i], ".name"));
                    string memory symbol = stdJson.readString(
                        json,
                        string.concat(".tokens.", tokenSymbols[i], ".symbol")
                    );
                    uint8 decimals = uint8(
                        stdJson.readUint(json, string.concat(".tokens.", tokenSymbols[i], ".decimals"))
                    );

                    if (!first) {
                        result = string(abi.encodePacked(result, ",\n"));
                    }
                    result = string(
                        abi.encodePacked(
                            result,
                            '    "',
                            symbol,
                            '": {\n',
                            '      "address": "',
                            vm.toString(addr),
                            '",\n',
                            '      "name": "',
                            name,
                            '",\n',
                            '      "symbol": "',
                            symbol,
                            '",\n',
                            '      "decimals": ',
                            vm.toString(decimals),
                            "\n",
                            "    }"
                        )
                    );
                    first = false;
                }
            }
        }

        return string(abi.encodePacked(result, "\n  },\n"));
    }

    /**
     * @notice Build vaults JSON section
     */
    function _buildVaultsJson(string memory json) internal view returns (string memory) {
        string memory result = '  "vaults": {\n';
        bool first = true;

        string[2] memory vaultSymbols = ["USDC", "WETH"];

        for (uint256 i = 0; i < vaultSymbols.length; i++) {
            string memory key = string.concat(".vaults.", vaultSymbols[i], ".address");
            if (stdJson.keyExists(json, key)) {
                address addr = stdJson.readAddress(json, key);
                if (addr != address(0)) {
                    string memory name = stdJson.readString(json, string.concat(".vaults.", vaultSymbols[i], ".name"));
                    string memory symbol = stdJson.readString(
                        json,
                        string.concat(".vaults.", vaultSymbols[i], ".symbol")
                    );
                    address asset = stdJson.readAddress(json, string.concat(".vaults.", vaultSymbols[i], ".asset"));

                    if (!first) {
                        result = string(abi.encodePacked(result, ",\n"));
                    }
                    result = string(
                        abi.encodePacked(
                            result,
                            '    "',
                            vaultSymbols[i],
                            '": {\n',
                            '      "address": "',
                            vm.toString(addr),
                            '",\n',
                            '      "name": "',
                            name,
                            '",\n',
                            '      "symbol": "',
                            symbol,
                            '",\n',
                            '      "asset": "',
                            vm.toString(asset),
                            '"\n',
                            "    }"
                        )
                    );
                    first = false;
                }
            }
        }

        return string(abi.encodePacked(result, "\n  },\n"));
    }

    /**
     * @notice Build ammplify JSON section
     */
    function _buildAmmplifyJson(string memory json) internal view returns (string memory) {
        if (!stdJson.keyExists(json, ".ammplify.simplexDiamond")) {
            return "";
        }

        address simplexDiamond = stdJson.readAddress(json, ".ammplify.simplexDiamond");
        address nftManager = stdJson.readAddress(json, ".ammplify.nftManager");

        string memory result = string(
            abi.encodePacked('  "ammplify": {\n', '    "simplexDiamond": "', vm.toString(simplexDiamond), '",\n')
        );

        // Try to read borrowlessDiamond if it exists
        if (stdJson.keyExists(json, ".ammplify.borrowlessDiamond")) {
            address borrowlessDiamond = stdJson.readAddress(json, ".ammplify.borrowlessDiamond");
            if (borrowlessDiamond != address(0)) {
                result = string(
                    abi.encodePacked(result, '    "borrowlessDiamond": "', vm.toString(borrowlessDiamond), '",\n')
                );
            }
        }

        result = string(abi.encodePacked(result, '    "nftManager": "', vm.toString(nftManager), '"\n', "  },\n"));

        return result;
    }

    /**
     * @notice Build uniswap JSON section (with updated simpleSwapRouter)
     */
    function _buildUniswapJson(string memory json, address uniV3Factory) internal view returns (string memory) {
        string memory result = string(
            abi.encodePacked('  "uniswap": {\n', '    "factory": "', vm.toString(uniV3Factory), '",\n')
        );

        // Preserve nfpm if it exists
        if (stdJson.keyExists(json, ".uniswap.nfpm")) {
            address nfpm = stdJson.readAddress(json, ".uniswap.nfpm");
            result = string(abi.encodePacked(result, '    "nfpm": "', vm.toString(nfpm), '",\n'));
        }

        // Update simpleSwapRouter with newly deployed address
        result = string(abi.encodePacked(result, '    "simpleSwapRouter": "', vm.toString(simpleSwapRouter), '",\n'));

        // Build pools JSON
        result = string(abi.encodePacked(result, '    "pools": {\n'));
        bool first = true;

        // Read all pools
        string[6] memory poolNames = [
            "USDC_WETH_3000",
            "WMON_USDC_500",
            "DAK_CHOG_10000",
            "YAKI_CHOG_10000",
            "DAK_YAKI_3000",
            "WMON_USDT_500"
        ];

        for (uint256 i = 0; i < poolNames.length; i++) {
            string memory key = string.concat(".uniswap.pools.", poolNames[i]);
            if (stdJson.keyExists(json, key)) {
                address poolAddr = stdJson.readAddress(json, key);
                if (poolAddr != address(0)) {
                    if (!first) {
                        result = string(abi.encodePacked(result, ",\n"));
                    }
                    result = string(
                        abi.encodePacked(result, '      "', poolNames[i], '": "', vm.toString(poolAddr), '"')
                    );
                    first = false;
                }
            }
        }

        result = string(abi.encodePacked(result, "\n    }\n  },\n"));

        return result;
    }

    /**
     * @notice Build integrations JSON section
     */
    function _buildIntegrationsJson(string memory json) internal view returns (string memory) {
        if (!stdJson.keyExists(json, ".integrations.decomposer")) {
            return "";
        }

        address decomposer = stdJson.readAddress(json, ".integrations.decomposer");
        return
            string(
                abi.encodePacked(
                    '  "integrations": {\n',
                    '    "decomposer": "',
                    vm.toString(decomposer),
                    '"\n',
                    "  }\n"
                )
            );
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

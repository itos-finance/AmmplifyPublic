// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { MockERC20 } from "../test/mocks/MockERC20.sol";
import { UniswapV3Factory } from "v3-core/UniswapV3Factory.sol";
import { UniswapV3Pool } from "v3-core/UniswapV3Pool.sol";

/**
 * @title DeployAdditionalTokensAndPools
 * @dev Deployment script for additional tokens and pools
 *
 * This script deploys:
 * - MockERC20 tokens: DAK, CHOG, USDT, YAKI, WMON
 * - Uniswap V3 pools for specified pairs
 * - Updates deployed-addresses.json with all new addresses
 *
 * Prerequisites:
 * - USDC must already be deployed (read from deployed-addresses.json)
 * - Uniswap V3 Factory must already be deployed (read from deployed-addresses.json)
 *
 * Usage:
 * forge script script/DeployAdditionalTokensAndPools.s.sol:DeployAdditionalTokensAndPools --rpc-url <RPC_URL> --broadcast
 */
contract DeployAdditionalTokensAndPools is Script {
    // Token contracts
    MockERC20 public dak;
    MockERC20 public chog;
    MockERC20 public usdt;
    MockERC20 public yaki;
    MockERC20 public wmon;

    // Pool contracts
    UniswapV3Pool public wmonUsdcPool;
    UniswapV3Pool public dakChogPool;
    UniswapV3Pool public yakiChogPool;
    UniswapV3Pool public dakYakiPool;
    UniswapV3Pool public wmonUsdtPool;

    // Existing addresses (loaded from JSON)
    address public usdcToken;
    address public uniV3Factory;
    address public deployer;

    // Configuration
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000e18; // 1B tokens
    uint256 public constant DEPLOYER_MINT = 100_000_000e18; // 100M tokens for deployer
    uint160 public constant INIT_SQRT_PRICE_X96 = 1 << 96; // 1:1 price ratio

    // Fee tiers: 500 (0.05%), 3000 (0.3%), 10000 (1%)
    uint24 public constant FEE_LOW = 500; // 0.05% - for stablecoin pairs
    uint24 public constant FEE_MEDIUM = 3000; // 0.3% - standard
    uint24 public constant FEE_HIGH = 10000; // 1% - for volatile pairs

    function run() external {
        // Get the deployer's private key from environment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        console.log("============================================================");
        console.log("DEPLOYING ADDITIONAL TOKENS AND POOLS");
        console.log("============================================================");

        // Load existing addresses from JSON
        _loadExistingAddresses();

        console.log("Deployer:", deployer);
        console.log("USDC Token:", usdcToken);
        console.log("Uniswap V3 Factory:", uniV3Factory);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy tokens
        console.log("Step 1/2: Deploying Tokens...");
        _deployTokens();

        // Step 2: Deploy pools
        console.log("Step 2/2: Deploying Pools...");
        _deployPools();

        vm.stopBroadcast();

        // Step 3: Update JSON file
        console.log("Step 3/3: Updating deployed-addresses.json...");
        _updateDeployedAddressesJson();

        // Final summary
        _logFinalSummary();
    }

    /**
     * @notice Load existing addresses from deployed-addresses.json
     */
    function _loadExistingAddresses() internal {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployed-addresses.json");
        string memory json = vm.readFile(path);

        usdcToken = stdJson.readAddress(json, ".tokens.USDC.address");
        uniV3Factory = stdJson.readAddress(json, ".uniswap.factory");
        deployer = stdJson.readAddress(json, ".deployer");

        require(usdcToken != address(0), "USDC token not found in deployed-addresses.json");
        require(uniV3Factory != address(0), "Uniswap V3 Factory not found in deployed-addresses.json");
        require(deployer != address(0), "Deployer not found in deployed-addresses.json");
    }

    /**
     * @notice Deploy all tokens
     */
    function _deployTokens() internal {
        // Deploy DAK (18 decimals)
        dak = new MockERC20("DAK Token", "DAK", 18);
        dak.mint(deployer, DEPLOYER_MINT);
        console.log(unicode"✅ DAK deployed at:", address(dak));

        // Deploy CHOG (18 decimals)
        chog = new MockERC20("CHOG Token", "CHOG", 18);
        chog.mint(deployer, DEPLOYER_MINT);
        console.log(unicode"✅ CHOG deployed at:", address(chog));

        // Deploy USDT (6 decimals, like USDC)
        usdt = new MockERC20("Tether USD", "USDT", 6);
        usdt.mint(deployer, DEPLOYER_MINT / 1e12); // Adjust for 6 decimals
        console.log(unicode"✅ USDT deployed at:", address(usdt));

        // Deploy YAKI (18 decimals)
        yaki = new MockERC20("YAKI Token", "YAKI", 18);
        yaki.mint(deployer, DEPLOYER_MINT);
        console.log(unicode"✅ YAKI deployed at:", address(yaki));

        // Deploy WMON (18 decimals)
        wmon = new MockERC20("WMON Token", "WMON", 18);
        wmon.mint(deployer, DEPLOYER_MINT);
        console.log(unicode"✅ WMON deployed at:", address(wmon));

        console.log("");
    }

    /**
     * @notice Deploy all pools
     */
    function _deployPools() internal {
        UniswapV3Factory factory = UniswapV3Factory(uniV3Factory);

        // WMON / USDC - LOW fee tier (500 = 0.05%)
        wmonUsdcPool = _createPool(factory, address(wmon), usdcToken, FEE_LOW, "WMON_USDC_500");
        console.log(unicode"✅ WMON/USDC pool (0.05% fee) deployed at:", address(wmonUsdcPool));

        // DAK / CHOG - HIGH fee tier (10000 = 1%)
        dakChogPool = _createPool(factory, address(dak), address(chog), FEE_HIGH, "DAK_CHOG_10000");
        console.log(unicode"✅ DAK/CHOG pool (1% fee) deployed at:", address(dakChogPool));

        // YAKI / CHOG - HIGH fee tier (10000 = 1%)
        yakiChogPool = _createPool(factory, address(yaki), address(chog), FEE_HIGH, "YAKI_CHOG_10000");
        console.log(unicode"✅ YAKI/CHOG pool (1% fee) deployed at:", address(yakiChogPool));

        // DAK / YAKI - MEDIUM fee tier (3000 = 0.3%)
        dakYakiPool = _createPool(factory, address(dak), address(yaki), FEE_MEDIUM, "DAK_YAKI_3000");
        console.log(unicode"✅ DAK/YAKI pool (0.3% fee) deployed at:", address(dakYakiPool));

        // WMON / USDT - LOW fee tier (500 = 0.05%)
        wmonUsdtPool = _createPool(factory, address(wmon), address(usdt), FEE_LOW, "WMON_USDT_500");
        console.log(unicode"✅ WMON/USDT pool (0.05% fee) deployed at:", address(wmonUsdtPool));

        console.log("");
    }

    /**
     * @notice Create and initialize a Uniswap V3 pool
     * @param factory The Uniswap V3 Factory contract
     * @param tokenA First token address
     * @param tokenB Second token address
     * @param fee Fee tier (500, 3000, or 10000)
     * @param poolName Name for logging
     * @return pool The deployed and initialized pool
     */
    function _createPool(
        UniswapV3Factory factory,
        address tokenA,
        address tokenB,
        uint24 fee,
        string memory poolName
    ) internal returns (UniswapV3Pool pool) {
        // Ensure token0 < token1 for Uniswap V3
        address token0 = tokenA < tokenB ? tokenA : tokenB;
        address token1 = tokenA < tokenB ? tokenB : tokenA;

        console.log("Creating pool:", poolName);
        console.log("  Token0:", token0);
        console.log("  Token1:", token1);
        console.log("  Fee:", fee);

        // Create the pool
        address poolAddress = factory.createPool(token0, token1, fee);
        pool = UniswapV3Pool(poolAddress);

        // Initialize the pool
        pool.initialize(INIT_SQRT_PRICE_X96);
        console.log("  Pool initialized at:", poolAddress);
    }

    /**
     * @notice Update deployed-addresses.json with all new tokens and pools
     */
    function _updateDeployedAddressesJson() internal {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployed-addresses.json");
        string memory existingJson = vm.readFile(path);

        // Read existing data
        string memory network = stdJson.readString(existingJson, ".network");
        address existingDeployer = stdJson.readAddress(existingJson, ".deployer");

        // Build new JSON with all tokens and pools
        string memory jsonContent = string(
            abi.encodePacked(
                "{\n",
                '  "network": "',
                network,
                '",\n',
                '  "deployer": "',
                vm.toString(existingDeployer),
                '",\n',
                '  "tokens": {\n',
                '    "USDC": {\n',
                '      "address": "',
                vm.toString(usdcToken),
                '",\n',
                '      "name": "USD Coin",\n',
                '      "symbol": "USDC",\n',
                '      "decimals": 6\n',
                "    },\n",
                _getTokenJson("DAK", address(dak), 18),
                _getTokenJson("CHOG", address(chog), 18),
                _getTokenJson("USDT", address(usdt), 6),
                _getTokenJson("YAKI", address(yaki), 18),
                _getTokenJson("WMON", address(wmon), 18),
                // Try to read WETH if it exists (last token, no comma)
                _tryGetExistingTokenJsonNoComma(existingJson, "WETH"),
                "  },\n",
                _tryGetExistingVaultsJson(existingJson),
                _tryGetExistingAmmplifyJson(existingJson),
                '  "uniswap": {\n',
                '    "factory": "',
                vm.toString(uniV3Factory),
                '",\n',
                _tryGetExistingUniswapFields(existingJson),
                '    "pools": {\n',
                _tryGetExistingPoolJson(existingJson, "USDC_WETH_3000"),
                _getPoolJson("WMON_USDC_500", address(wmonUsdcPool)),
                _getPoolJson("DAK_CHOG_10000", address(dakChogPool)),
                _getPoolJson("YAKI_CHOG_10000", address(yakiChogPool)),
                _getPoolJson("DAK_YAKI_3000", address(dakYakiPool)),
                _getPoolJsonNoComma("WMON_USDT_500", address(wmonUsdtPool)),
                "    }\n",
                "  },\n",
                _tryGetExistingIntegrationsJson(existingJson),
                "}"
            )
        );

        // Write to deployed-addresses.json
        vm.writeFile(path, jsonContent);

        console.log(unicode"📝 Updated deployed-addresses.json with all new tokens and pools");
    }

    /**
     * @notice Helper to generate token JSON entry
     */
    function _getTokenJson(
        string memory symbol,
        address tokenAddr,
        uint8 decimals
    ) internal view returns (string memory) {
        return
            string(
                abi.encodePacked(
                    '    "',
                    symbol,
                    '": {\n',
                    '      "address": "',
                    vm.toString(tokenAddr),
                    '",\n',
                    '      "name": "',
                    symbol,
                    ' Token",\n',
                    '      "symbol": "',
                    symbol,
                    '",\n',
                    '      "decimals": ',
                    vm.toString(decimals),
                    "\n",
                    "    },\n"
                )
            );
    }

    /**
     * @notice Helper to generate token JSON entry without trailing comma
     */
    function _getTokenJsonNoComma(
        string memory symbol,
        address tokenAddr,
        uint8 decimals
    ) internal view returns (string memory) {
        return
            string(
                abi.encodePacked(
                    '    "',
                    symbol,
                    '": {\n',
                    '      "address": "',
                    vm.toString(tokenAddr),
                    '",\n',
                    '      "name": "',
                    symbol,
                    ' Token",\n',
                    '      "symbol": "',
                    symbol,
                    '",\n',
                    '      "decimals": ',
                    vm.toString(decimals),
                    "\n",
                    "    }\n"
                )
            );
    }

    /**
     * @notice Helper to generate pool JSON entry
     */
    function _getPoolJson(string memory poolName, address poolAddr) internal view returns (string memory) {
        return string(abi.encodePacked('      "', poolName, '": "', vm.toString(poolAddr), '",\n'));
    }

    /**
     * @notice Helper to generate pool JSON entry without trailing comma
     */
    function _getPoolJsonNoComma(string memory poolName, address poolAddr) internal view returns (string memory) {
        return string(abi.encodePacked('      "', poolName, '": "', vm.toString(poolAddr), '"\n'));
    }

    /**
     * @notice Try to get existing token JSON (for WETH, etc.)
     */
    function _tryGetExistingTokenJson(string memory json, string memory symbol) internal view returns (string memory) {
        string memory key = string.concat(".tokens.", symbol, ".address");
        if (stdJson.keyExists(json, key)) {
            address addr = stdJson.readAddress(json, key);
            if (addr != address(0)) {
                uint8 decimals = uint8(stdJson.readUint(json, string.concat(".tokens.", symbol, ".decimals")));
                return _getTokenJson(symbol, addr, decimals);
            }
        }
        return "";
    }

    /**
     * @notice Try to get existing token JSON without trailing comma (for last token)
     */
    function _tryGetExistingTokenJsonNoComma(
        string memory json,
        string memory symbol
    ) internal view returns (string memory) {
        string memory key = string.concat(".tokens.", symbol, ".address");
        if (stdJson.keyExists(json, key)) {
            address addr = stdJson.readAddress(json, key);
            if (addr != address(0)) {
                uint8 decimals = uint8(stdJson.readUint(json, string.concat(".tokens.", symbol, ".decimals")));
                return _getTokenJsonNoComma(symbol, addr, decimals);
            }
        }
        return "";
    }

    /**
     * @notice Try to get existing vaults JSON
     */
    function _tryGetExistingVaultsJson(string memory json) internal view returns (string memory) {
        string memory vaultsJson = '  "vaults": {\n';
        bool hasVaults = false;

        // Try to read USDC vault
        if (stdJson.keyExists(json, ".vaults.USDC.address")) {
            address usdcVault = stdJson.readAddress(json, ".vaults.USDC.address");
            if (usdcVault != address(0)) {
                string memory name = stdJson.readString(json, ".vaults.USDC.name");
                string memory symbol = stdJson.readString(json, ".vaults.USDC.symbol");
                address asset = stdJson.readAddress(json, ".vaults.USDC.asset");
                vaultsJson = string(
                    abi.encodePacked(
                        vaultsJson,
                        '    "USDC": {\n',
                        '      "address": "',
                        vm.toString(usdcVault),
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
                        "    },\n"
                    )
                );
                hasVaults = true;
            }
        }

        // Try to read WETH vault
        if (stdJson.keyExists(json, ".vaults.WETH.address")) {
            address wethVault = stdJson.readAddress(json, ".vaults.WETH.address");
            if (wethVault != address(0)) {
                string memory name = stdJson.readString(json, ".vaults.WETH.name");
                string memory symbol = stdJson.readString(json, ".vaults.WETH.symbol");
                address asset = stdJson.readAddress(json, ".vaults.WETH.asset");
                vaultsJson = string(
                    abi.encodePacked(
                        vaultsJson,
                        '    "WETH": {\n',
                        '      "address": "',
                        vm.toString(wethVault),
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
                        "    }\n"
                    )
                );
                hasVaults = true;
            }
        }

        if (hasVaults) {
            return string(abi.encodePacked(vaultsJson, "  },\n"));
        }
        return "";
    }

    /**
     * @notice Try to get existing ammplify JSON
     */
    function _tryGetExistingAmmplifyJson(string memory json) internal view returns (string memory) {
        if (stdJson.keyExists(json, ".ammplify.simplexDiamond")) {
            address simplexDiamond = stdJson.readAddress(json, ".ammplify.simplexDiamond");
            address nftManager = stdJson.readAddress(json, ".ammplify.nftManager");
            string memory ammplifyJson = string(
                abi.encodePacked('  "ammplify": {\n', '    "simplexDiamond": "', vm.toString(simplexDiamond), '",\n')
            );

            // Try to read borrowlessDiamond if it exists
            if (stdJson.keyExists(json, ".ammplify.borrowlessDiamond")) {
                address borrowlessDiamond = stdJson.readAddress(json, ".ammplify.borrowlessDiamond");
                if (borrowlessDiamond != address(0)) {
                    ammplifyJson = string(
                        abi.encodePacked(
                            ammplifyJson,
                            '    "borrowlessDiamond": "',
                            vm.toString(borrowlessDiamond),
                            '",\n'
                        )
                    );
                }
            }

            ammplifyJson = string(
                abi.encodePacked(ammplifyJson, '    "nftManager": "', vm.toString(nftManager), '"\n', "  },\n")
            );
            return ammplifyJson;
        }
        return "";
    }

    /**
     * @notice Try to get existing uniswap fields (nfpm, simpleSwapRouter)
     */
    function _tryGetExistingUniswapFields(string memory json) internal view returns (string memory) {
        string memory result = "";
        if (stdJson.keyExists(json, ".uniswap.nfpm")) {
            address nfpm = stdJson.readAddress(json, ".uniswap.nfpm");
            result = string(abi.encodePacked(result, '    "nfpm": "', vm.toString(nfpm), '",\n'));
        }
        if (stdJson.keyExists(json, ".uniswap.simpleSwapRouter")) {
            address router = stdJson.readAddress(json, ".uniswap.simpleSwapRouter");
            result = string(abi.encodePacked(result, '    "simpleSwapRouter": "', vm.toString(router), '",\n'));
        }
        return result;
    }

    /**
     * @notice Try to get existing pool JSON
     */
    function _tryGetExistingPoolJson(string memory json, string memory poolName) internal view returns (string memory) {
        string memory key = string.concat(".uniswap.pools.", poolName);
        if (stdJson.keyExists(json, key)) {
            address poolAddr = stdJson.readAddress(json, key);
            if (poolAddr != address(0)) {
                return _getPoolJson(poolName, poolAddr);
            }
        }
        return "";
    }

    /**
     * @notice Try to get existing integrations JSON
     */
    function _tryGetExistingIntegrationsJson(string memory json) internal view returns (string memory) {
        if (stdJson.keyExists(json, ".integrations.decomposer")) {
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
        return "";
    }

    /**
     * @notice Log final deployment summary
     */
    function _logFinalSummary() internal view {
        console.log("============================================================");
        console.log("DEPLOYMENT COMPLETE!");
        console.log("============================================================");

        console.log(unicode"🪙  NEW TOKENS:");
        console.log("   DAK:", address(dak));
        console.log("   CHOG:", address(chog));
        console.log("   USDT:", address(usdt));
        console.log("   YAKI:", address(yaki));
        console.log("   WMON:", address(wmon));
        console.log("");

        console.log(unicode"🏊  NEW POOLS:");
        console.log("   WMON/USDC (0.05% fee):", address(wmonUsdcPool));
        console.log("   DAK/CHOG (1% fee):", address(dakChogPool));
        console.log("   YAKI/CHOG (1% fee):", address(yakiChogPool));
        console.log("   DAK/YAKI (0.3% fee):", address(dakYakiPool));
        console.log("   WMON/USDT (0.05% fee):", address(wmonUsdtPool));
        console.log("");

        console.log("============================================================");
        console.log(unicode"All tokens and pools deployed successfully! 🎉");
        console.log("============================================================");
    }
}

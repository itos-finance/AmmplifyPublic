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
 * - Updates addresses JSON with all new addresses
 *
 * Prerequisites:
 * - USDC must already be deployed (read from addresses JSON)
 * - Uniswap V3 Factory must already be deployed (read from addresses JSON)
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
        console.log("Step 3/3: Updating addresses JSON...");
        _updateDeployedAddressesJson();

        // Final summary
        _logFinalSummary();
    }

    /**
     * @notice Load existing addresses from addresses JSON
     */
    function _loadExistingAddresses() internal {
        string memory protocol = vm.envOr("AMMPLIFY_PROTOCOL", string("uniswapv3"));
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/addresses/", protocol, ".json");
        string memory json = vm.readFile(path);

        usdcToken = stdJson.readAddress(json, ".tokens.USDC.address");
        uniV3Factory = stdJson.readAddress(json, ".factory");
        deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");

        require(usdcToken != address(0), "USDC token not found in addresses JSON");
        require(uniV3Factory != address(0), "Uniswap V3 Factory not found in addresses JSON");
        require(deployer != address(0), "Deployer not found");
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
     * @notice Update addresses JSON with all new tokens and pools
     */
    function _updateDeployedAddressesJson() internal {
        string memory protocol = vm.envOr("AMMPLIFY_PROTOCOL", string("uniswapv3"));
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/addresses/", protocol, ".json");
        string memory existingJson = vm.readFile(path);

        // Read existing data
        string memory network = stdJson.readString(existingJson, ".network");

        // Build new JSON with flat schema
        string memory jsonContent = string(
            abi.encodePacked(
                "{\n",
                '  "network": "',
                network,
                '",\n',
                '  "tokens": {\n',
                '    "USDC": { "address": "', vm.toString(usdcToken), '", "decimals": 6 },\n',
                '    "DAK": { "address": "', vm.toString(address(dak)), '", "decimals": 18 },\n',
                '    "CHOG": { "address": "', vm.toString(address(chog)), '", "decimals": 18 },\n',
                '    "USDT": { "address": "', vm.toString(address(usdt)), '", "decimals": 6 },\n',
                '    "YAKI": { "address": "', vm.toString(address(yaki)), '", "decimals": 18 },\n',
                '    "WMON": { "address": "', vm.toString(address(wmon)), '", "decimals": 18 }',
                _tryGetExistingWethToken(existingJson),
                "\n  },\n"
            )
        );

        // Add protocol-level fields
        jsonContent = string(
            abi.encodePacked(
                jsonContent,
                _tryGetExistingField(existingJson, "diamond"),
                _tryGetExistingField(existingJson, "decomposer"),
                '  "factory": "', vm.toString(uniV3Factory), '",\n',
                _tryGetExistingField(existingJson, "nfpm"),
                _tryGetExistingField(existingJson, "router"),
                '  "pools": {\n',
                _tryGetExistingPoolJson(existingJson, "USDC_WETH_3000"),
                _getPoolJson("WMON_USDC_500", address(wmonUsdcPool)),
                _getPoolJson("DAK_CHOG_10000", address(dakChogPool)),
                _getPoolJson("YAKI_CHOG_10000", address(yakiChogPool)),
                _getPoolJson("DAK_YAKI_3000", address(dakYakiPool)),
                _getPoolJsonNoComma("WMON_USDT_500", address(wmonUsdtPool)),
                "  }\n",
                "}"
            )
        );

        vm.writeFile(path, jsonContent);

        console.log(unicode"📝 Updated addresses JSON with all new tokens and pools");
    }

    function _getPoolJson(string memory poolName, address poolAddr) internal view returns (string memory) {
        return string(abi.encodePacked('    "', poolName, '": "', vm.toString(poolAddr), '",\n'));
    }

    function _getPoolJsonNoComma(string memory poolName, address poolAddr) internal view returns (string memory) {
        return string(abi.encodePacked('    "', poolName, '": "', vm.toString(poolAddr), '"\n'));
    }

    function _tryGetExistingPoolJson(string memory json, string memory poolName) internal view returns (string memory) {
        string memory key = string.concat(".pools.", poolName);
        if (stdJson.keyExists(json, key)) {
            address poolAddr = stdJson.readAddress(json, key);
            if (poolAddr != address(0)) {
                return _getPoolJson(poolName, poolAddr);
            }
        }
        return "";
    }

    function _tryGetExistingWethToken(string memory json) internal view returns (string memory) {
        if (stdJson.keyExists(json, ".tokens.WETH.address")) {
            address addr = stdJson.readAddress(json, ".tokens.WETH.address");
            if (addr != address(0)) {
                uint8 decimals = uint8(stdJson.readUint(json, ".tokens.WETH.decimals"));
                return string(abi.encodePacked(',\n    "WETH": { "address": "', vm.toString(addr), '", "decimals": ', vm.toString(decimals), " }"));
            }
        }
        return "";
    }

    function _tryGetExistingField(string memory json, string memory field) internal view returns (string memory) {
        string memory key = string.concat(".", field);
        if (stdJson.keyExists(json, key)) {
            address addr = stdJson.readAddress(json, key);
            return string(abi.encodePacked('  "', field, '": "', vm.toString(addr), '",\n'));
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

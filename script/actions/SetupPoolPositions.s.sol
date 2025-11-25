// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/console2.sol";
import { AmmplifyPositions } from "../AmmplifyPositions.s.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { MockERC20 } from "../../test/mocks/MockERC20.sol";
import { IUniswapV3Pool } from "lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

/**
 * @title SetupPoolPositions
 * @notice Script to open maker and taker positions for all newly deployed pools
 * @dev Run with: forge script script/actions/SetupPoolPositions.s.sol --broadcast --rpc-url <RPC_URL>
 */
contract SetupPoolPositions is AmmplifyPositions {
    using stdJson for string;

    // Pool configuration
    struct PoolConfig {
        string poolName;
        address poolAddr;
        uint24 fee;
        address token0;
        address token1;
        uint8 decimals0;
        uint8 decimals1;
    }

    // Track created positions
    struct PositionResults {
        uint256 makerAssetId;
        uint256[] takerAssetIds;
    }

    mapping(address => PositionResults) public poolPositions;

    function run() public override {
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console2.log("============================================================");
        console2.log("SETTING UP MAKER AND TAKER POSITIONS FOR ALL POOLS");
        console2.log("============================================================");
        console2.log("Deployer:", deployer);
        console2.log("");

        // Load pool configurations from JSON
        PoolConfig[] memory pools = _loadPoolConfigs();

        // Fund deployer with all tokens
        console2.log("Step 1: Funding deployer with tokens...");
        _fundDeployerWithAllTokens(deployer, pools);
        console2.log("");

        // Setup approvals for all tokens
        console2.log("Step 2: Setting up token approvals...");
        _setupAllTokenApprovals(deployer, pools);
        console2.log("");

        // Open positions for each pool
        for (uint256 i = 0; i < pools.length; i++) {
            console2.log("============================================================");
            console2.log("Processing Pool:", pools[i].poolName);
            console2.log("============================================================");
            
            _setupPoolPositions(deployer, pools[i]);
            console2.log("");
        }

        // Final summary
        _logFinalSummary(pools);

        vm.stopBroadcast();
    }

    /**
     * @notice Load pool configurations from deployed-addresses.json
     */
    function _loadPoolConfigs() internal view returns (PoolConfig[] memory) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployed-addresses.json");
        string memory json = vm.readFile(path);

        // We'll create 5 pools
        PoolConfig[] memory pools = new PoolConfig[](5);
        uint256 index = 0;

        // WMON/USDC (500 fee)
        if (stdJson.keyExists(json, ".uniswap.pools.WMON_USDC_500")) {
            address poolAddr = stdJson.readAddress(json, ".uniswap.pools.WMON_USDC_500");
            pools[index] = _getPoolConfig("WMON/USDC", poolAddr, 500);
            index++;
        }

        // DAK/CHOG (10000 fee)
        if (stdJson.keyExists(json, ".uniswap.pools.DAK_CHOG_10000")) {
            address poolAddr = stdJson.readAddress(json, ".uniswap.pools.DAK_CHOG_10000");
            pools[index] = _getPoolConfig("DAK/CHOG", poolAddr, 10000);
            index++;
        }

        // YAKI/CHOG (10000 fee)
        if (stdJson.keyExists(json, ".uniswap.pools.YAKI_CHOG_10000")) {
            address poolAddr = stdJson.readAddress(json, ".uniswap.pools.YAKI_CHOG_10000");
            pools[index] = _getPoolConfig("YAKI/CHOG", poolAddr, 10000);
            index++;
        }

        // DAK/YAKI (3000 fee)
        if (stdJson.keyExists(json, ".uniswap.pools.DAK_YAKI_3000")) {
            address poolAddr = stdJson.readAddress(json, ".uniswap.pools.DAK_YAKI_3000");
            pools[index] = _getPoolConfig("DAK/YAKI", poolAddr, 3000);
            index++;
        }

        // WMON/USDT (500 fee)
        if (stdJson.keyExists(json, ".uniswap.pools.WMON_USDT_500")) {
            address poolAddr = stdJson.readAddress(json, ".uniswap.pools.WMON_USDT_500");
            pools[index] = _getPoolConfig("WMON/USDT", poolAddr, 500);
            index++;
        }

        // Resize array to actual length
        PoolConfig[] memory result = new PoolConfig[](index);
        for (uint256 i = 0; i < index; i++) {
            result[i] = pools[i];
        }

        return result;
    }

    /**
     * @notice Get pool configuration from pool address
     */
    function _getPoolConfig(string memory poolName, address poolAddr, uint24 fee) internal view returns (PoolConfig memory) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployed-addresses.json");
        string memory json = vm.readFile(path);
        
        address token0 = getToken0(poolAddr);
        address token1 = getToken1(poolAddr);
        
        // Get decimals from JSON or use defaults
        uint8 decimals0 = 18;
        uint8 decimals1 = 18;
        
        // Try to find token decimals in JSON
        if (stdJson.keyExists(json, ".tokens.USDC.address")) {
            address usdc = stdJson.readAddress(json, ".tokens.USDC.address");
            if (token0 == usdc || token1 == usdc) {
                if (token0 == usdc) decimals0 = uint8(stdJson.readUint(json, ".tokens.USDC.decimals"));
                if (token1 == usdc) decimals1 = uint8(stdJson.readUint(json, ".tokens.USDC.decimals"));
            }
        }
        
        if (stdJson.keyExists(json, ".tokens.USDT.address")) {
            address usdt = stdJson.readAddress(json, ".tokens.USDT.address");
            if (token0 == usdt || token1 == usdt) {
                if (token0 == usdt) decimals0 = uint8(stdJson.readUint(json, ".tokens.USDT.decimals"));
                if (token1 == usdt) decimals1 = uint8(stdJson.readUint(json, ".tokens.USDT.decimals"));
            }
        }
        
        // For other tokens, assume 18 decimals (WMON, DAK, CHOG, YAKI)
        
        return PoolConfig({
            poolName: poolName,
            poolAddr: poolAddr,
            fee: fee,
            token0: token0,
            token1: token1,
            decimals0: decimals0,
            decimals1: decimals1
        });
    }

    /**
     * @notice Fund deployer with all tokens needed for all pools
     */
    function _fundDeployerWithAllTokens(address deployer, PoolConfig[] memory /* pools */) internal {
        // Load token addresses from JSON
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployed-addresses.json");
        string memory json = vm.readFile(path);

        // Fund with all tokens
        address usdc = stdJson.readAddress(json, ".tokens.USDC.address");
        address usdt = stdJson.readAddress(json, ".tokens.USDT.address");
        address wmon = stdJson.readAddress(json, ".tokens.WMON.address");
        address dak = stdJson.readAddress(json, ".tokens.DAK.address");
        address chog = stdJson.readAddress(json, ".tokens.CHOG.address");
        address yaki = stdJson.readAddress(json, ".tokens.YAKI.address");

        // Mint large amounts for testing (adjust decimals appropriately)
        uint256 largeAmount18 = 100_000_000e18; // 100M tokens with 18 decimals
        uint256 largeAmount6 = 100_000_000e6;   // 100M tokens with 6 decimals

        MockERC20(usdc).mint(deployer, largeAmount6);
        console2.log("Minted USDC to deployer:", largeAmount6);
        
        if (usdt != address(0)) {
            MockERC20(usdt).mint(deployer, largeAmount6);
            console2.log("Minted USDT to deployer:", largeAmount6);
        }
        
        if (wmon != address(0)) {
            MockERC20(wmon).mint(deployer, largeAmount18);
            console2.log("Minted WMON to deployer:", largeAmount18);
        }
        
        if (dak != address(0)) {
            MockERC20(dak).mint(deployer, largeAmount18);
            console2.log("Minted DAK to deployer:", largeAmount18);
        }
        
        if (chog != address(0)) {
            MockERC20(chog).mint(deployer, largeAmount18);
            console2.log("Minted CHOG to deployer:", largeAmount18);
        }
        
        if (yaki != address(0)) {
            MockERC20(yaki).mint(deployer, largeAmount18);
            console2.log("Minted YAKI to deployer:", largeAmount18);
        }
    }

    /**
     * @notice Setup approvals for all tokens to diamond and NFT manager
     */
    function _setupAllTokenApprovals(address /* deployer */, PoolConfig[] memory pools) internal {
        uint256 maxApproval = type(uint256).max;

        // Approve SimplexDiamond
        for (uint256 i = 0; i < pools.length; i++) {
            IERC20(pools[i].token0).approve(env.simplexDiamond, maxApproval);
            IERC20(pools[i].token1).approve(env.simplexDiamond, maxApproval);
        }

        // Approve NFT Manager
        if (env.nftManager != address(0)) {
            for (uint256 i = 0; i < pools.length; i++) {
                IERC20(pools[i].token0).approve(env.nftManager, maxApproval);
                IERC20(pools[i].token1).approve(env.nftManager, maxApproval);
            }
        }

        console2.log("Approved all tokens for SimplexDiamond and NFT Manager");
    }

    /**
     * @notice Setup maker and taker positions for a single pool
     */
    function _setupPoolPositions(address deployer, PoolConfig memory pool) internal {
        console2.log("Pool Address:", pool.poolAddr);
        console2.log("Token0:", pool.token0);
        console2.log("Token1:", pool.token1);
        console2.log("Fee Tier:", pool.fee);

        // Print pool state
        printPoolState(pool.poolAddr);

        // Get current tick
        (uint160 sqrtPriceX96, int24 currentTick, , , , , ) = IUniswapV3Pool(pool.poolAddr).slot0();
        console2.log("Current tick:", currentTick);
        console2.log("Current sqrt price:", sqrtPriceX96);

        // Open maker position
        console2.log("--- Opening Maker Position ---");
        uint256 makerAssetId = _openMakerPosition(deployer, pool, currentTick);
        poolPositions[pool.poolAddr].makerAssetId = makerAssetId;

        // Skip taker positions for now - they require vaults to be set up first
        // TODO: Set up vaults for new tokens before creating taker positions
        console2.log("--- Skipping Taker Positions (vaults not set up) ---");
        uint256[] memory takerAssetIds = new uint256[](0);
        poolPositions[pool.poolAddr].takerAssetIds = takerAssetIds;

        console2.log(unicode"✅ Completed positions for", pool.poolName);
    }

    /**
     * @notice Open a maker position for a pool
     */
    function _openMakerPosition(address deployer, PoolConfig memory pool, int24 currentTick) internal returns (uint256 assetId) {
        // Create a range around current price
        // For different fee tiers, use appropriate tick spacing
        int24 tickRange;
        if (pool.fee == 500) {
            tickRange = 100; // Smaller range for stablecoin pairs
        } else if (pool.fee == 3000) {
            tickRange = 600; // Medium range
        } else { // 10000
            tickRange = 2000; // Larger range for volatile pairs
        }

        int24 lowTick = getValidTick(currentTick - tickRange, pool.fee);
        int24 highTick = getValidTick(currentTick + tickRange, pool.fee);

        // Use moderate liquidity
        uint128 liquidity = 1e15; // Adjust based on needs

        MakerParams memory params = MakerParams({
            recipient: deployer,
            poolAddr: pool.poolAddr,
            lowTick: lowTick,
            highTick: highTick,
            liquidity: liquidity,
            isCompounding: true,
            minSqrtPriceX96: MIN_SQRT_RATIO,
            maxSqrtPriceX96: MAX_SQRT_RATIO,
            rftData: ""
        });

        console2.log("Maker Parameters:");
        console2.log("  Low Tick:", lowTick);
        console2.log("  High Tick:", highTick);
        console2.log("  Liquidity:", liquidity);

        assetId = openMakerDirect(params);
        console2.log(unicode"✅ Maker position created with Asset ID:", assetId);

        return assetId;
    }

    /**
     * @notice Open a taker position for a pool
     * @param belowPrice If true, create range below current price, otherwise above
     */
    function _openTakerPosition(address deployer, PoolConfig memory pool, int24 currentTick, bool belowPrice) internal returns (uint256 assetId) {
        // Collateralize first
        uint256 collateral0;
        uint256 collateral1;
        
        // Adjust for token decimals
        if (pool.decimals0 == 6) {
            collateral0 = 10_000_000e6;
        } else {
            collateral0 = 10_000_000e18;
        }
        
        if (pool.decimals1 == 6) {
            collateral1 = 10_000_000e6;
        } else {
            collateral1 = 10_000_000e18;
        }

        collateralizeTaker(deployer, collateral0, collateral1, pool.poolAddr);

        // Create tick range
        int24 tickRange;
        if (pool.fee == 500) {
            tickRange = 50;
        } else if (pool.fee == 3000) {
            tickRange = 300;
        } else { // 10000
            tickRange = 1000;
        }

        int24 tick0;
        int24 tick1;
        
        if (belowPrice) {
            // Range below current price
            tick0 = getValidTick(currentTick - tickRange * 2, pool.fee);
            tick1 = getValidTick(currentTick - tickRange, pool.fee);
        } else {
            // Range above current price
            tick0 = getValidTick(currentTick + tickRange, pool.fee);
            tick1 = getValidTick(currentTick + tickRange * 2, pool.fee);
        }

        // Ensure tick0 < tick1
        if (tick0 > tick1) {
            (tick0, tick1) = (tick1, tick0);
        }

        TakerParams memory params = TakerParams({
            recipient: deployer,
            poolAddr: pool.poolAddr,
            ticks: [tick0, tick1],
            liquidity: 1e13, // Minimum taker liquidity
            vaultIndices: [0, 0], // Assuming vault indices 0 for both tokens
            sqrtPriceLimitsX96: [MIN_SQRT_RATIO, MAX_SQRT_RATIO],
            freezeSqrtPriceX96: belowPrice ? MIN_SQRT_RATIO : MAX_SQRT_RATIO,
            rftData: ""
        });

        console2.log("Taker Parameters:");
        console2.log("  Tick Range: tick0=", vm.toString(tick0), "tick1=", vm.toString(tick1));
        console2.log("  Liquidity:", params.liquidity);
        console2.log("  Below Price:", belowPrice);

        assetId = openTaker(params);
        console2.log(unicode"✅ Taker position created with Asset ID:", assetId);

        return assetId;
    }

    /**
     * @notice Log final summary of all created positions
     */
    function _logFinalSummary(PoolConfig[] memory pools) internal view {
        console2.log("============================================================");
        console2.log("POSITION SETUP COMPLETE!");
        console2.log("============================================================");

        for (uint256 i = 0; i < pools.length; i++) {
            PositionResults memory results = poolPositions[pools[i].poolAddr];
            
            console2.log(unicode"📊 Pool:", pools[i].poolName);
            console2.log("   Maker Asset ID:", results.makerAssetId);
            console2.log("   Taker Asset IDs:");
            for (uint256 j = 0; j < results.takerAssetIds.length; j++) {
                console2.log("     -", results.takerAssetIds[j]);
            }
            console2.log("");
        }

        console2.log("============================================================");
        console2.log(unicode"All positions created successfully! 🎉");
        console2.log("============================================================");
    }
}


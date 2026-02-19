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
 * @notice Script to open maker and taker positions for all pools in the addresses file
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
        _setupAllTokenApprovals(pools);
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
     * @notice Load pool configurations from the addresses JSON
     */
    function _loadPoolConfigs() internal view returns (PoolConfig[] memory) {
        // Read pool keys from the JSON - check which pools exist
        string memory json = env.jsonRaw;
        string[5] memory poolKeys = ["WMON_USDC_500", "WMON_USDC_3000", "WMON_USDC_10000", "USDC_WETH_3000", "WBTC_USDC_3000"];
        uint24[5] memory fees = [uint24(500), uint24(3000), uint24(10000), uint24(3000), uint24(3000)];

        PoolConfig[] memory pools = new PoolConfig[](5);
        uint256 index = 0;

        for (uint256 i = 0; i < poolKeys.length; i++) {
            string memory key = string.concat(".pools.", poolKeys[i]);
            if (stdJson.keyExists(json, key)) {
                address poolAddr = stdJson.readAddress(json, key);
                pools[index] = _getPoolConfig(poolKeys[i], poolAddr, fees[i]);
                index++;
            }
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
        address token0 = getToken0(poolAddr);
        address token1 = getToken1(poolAddr);

        // Get decimals - try to look up each token in the JSON
        uint8 decimals0 = _getDecimalsForToken(token0);
        uint8 decimals1 = _getDecimalsForToken(token1);

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
     * @notice Look up decimals for a token address from the JSON
     */
    function _getDecimalsForToken(address token) internal view returns (uint8) {
        string memory json = env.jsonRaw;
        string[7] memory symbols = ["USDC", "WETH", "WMON", "WBTC", "USDT0", "CHOG", "shMON"];

        for (uint256 i = 0; i < symbols.length; i++) {
            string memory addrKey = string.concat(".tokens.", symbols[i], ".address");
            if (stdJson.keyExists(json, addrKey)) {
                address tokenAddr = stdJson.readAddress(json, addrKey);
                if (tokenAddr == token) {
                    string memory decKey = string.concat(".tokens.", symbols[i], ".decimals");
                    return uint8(stdJson.readUint(json, decKey));
                }
            }
        }

        return 18; // default
    }

    /**
     * @notice Fund deployer with all tokens needed for all pools
     */
    function _fundDeployerWithAllTokens(address deployer, PoolConfig[] memory pools) internal {
        uint256 largeAmount18 = 100_000_000e18;
        uint256 largeAmount6 = 100_000_000e6;

        for (uint256 i = 0; i < pools.length; i++) {
            uint256 amt0 = pools[i].decimals0 == 6 ? largeAmount6 : largeAmount18;
            uint256 amt1 = pools[i].decimals1 == 6 ? largeAmount6 : largeAmount18;
            MockERC20(pools[i].token0).mint(deployer, amt0);
            MockERC20(pools[i].token1).mint(deployer, amt1);
        }
    }

    /**
     * @notice Setup approvals for all tokens to diamond and NFT manager
     */
    function _setupAllTokenApprovals(PoolConfig[] memory pools) internal {
        uint256 maxApproval = type(uint256).max;

        for (uint256 i = 0; i < pools.length; i++) {
            IERC20(pools[i].token0).approve(env.diamond, maxApproval);
            IERC20(pools[i].token1).approve(env.diamond, maxApproval);
            if (env.nfpm != address(0)) {
                IERC20(pools[i].token0).approve(env.nfpm, maxApproval);
                IERC20(pools[i].token1).approve(env.nfpm, maxApproval);
            }
        }

        console2.log("Approved all tokens for Diamond and NFPM");
    }

    /**
     * @notice Setup maker and taker positions for a single pool
     */
    function _setupPoolPositions(address deployer, PoolConfig memory pool) internal {
        console2.log("Pool Address:", pool.poolAddr);
        console2.log("Token0:", pool.token0);
        console2.log("Token1:", pool.token1);
        console2.log("Fee Tier:", pool.fee);

        printPoolState(pool.poolAddr);

        (uint160 sqrtPriceX96, int24 currentTick, , , , , ) = IUniswapV3Pool(pool.poolAddr).slot0();
        console2.log("Current tick:", currentTick);
        console2.log("Current sqrt price:", sqrtPriceX96);

        // Open maker position
        console2.log("--- Opening Maker Position ---");
        uint256 makerAssetId = _openMakerPosition(deployer, pool, currentTick);
        poolPositions[pool.poolAddr].makerAssetId = makerAssetId;

        console2.log("--- Skipping Taker Positions (vaults not set up) ---");
        uint256[] memory takerAssetIds = new uint256[](0);
        poolPositions[pool.poolAddr].takerAssetIds = takerAssetIds;

        console2.log(unicode"✅ Completed positions for", pool.poolName);
    }

    /**
     * @notice Open a maker position for a pool
     */
    function _openMakerPosition(address deployer, PoolConfig memory pool, int24 currentTick) internal returns (uint256 assetId) {
        int24 tickRange;
        if (pool.fee == 500) {
            tickRange = 100;
        } else if (pool.fee == 3000) {
            tickRange = 600;
        } else {
            tickRange = 2000;
        }

        int24 lowTick = getValidTick(currentTick - tickRange, pool.fee);
        int24 highTick = getValidTick(currentTick + tickRange, pool.fee);

        uint128 liquidity = 1e15;

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

        assetId = openMaker(params);
        console2.log(unicode"✅ Maker position created with Asset ID:", assetId);
    }

    /**
     * @notice Open a taker position for a pool
     */
    function _openTakerPosition(address deployer, PoolConfig memory pool, int24 currentTick, bool belowPrice) internal returns (uint256 assetId) {
        uint256 collateral0 = pool.decimals0 == 6 ? 10_000_000e6 : 10_000_000e18;
        uint256 collateral1 = pool.decimals1 == 6 ? 10_000_000e6 : 10_000_000e18;

        collateralizeTaker(deployer, collateral0, collateral1, pool.poolAddr);

        int24 tickRange;
        if (pool.fee == 500) {
            tickRange = 50;
        } else if (pool.fee == 3000) {
            tickRange = 300;
        } else {
            tickRange = 1000;
        }

        int24 tick0;
        int24 tick1;

        if (belowPrice) {
            tick0 = getValidTick(currentTick - tickRange * 2, pool.fee);
            tick1 = getValidTick(currentTick - tickRange, pool.fee);
        } else {
            tick0 = getValidTick(currentTick + tickRange, pool.fee);
            tick1 = getValidTick(currentTick + tickRange * 2, pool.fee);
        }

        if (tick0 > tick1) {
            (tick0, tick1) = (tick1, tick0);
        }

        TakerParams memory params = TakerParams({
            recipient: deployer,
            poolAddr: pool.poolAddr,
            ticks: [tick0, tick1],
            liquidity: 1e13,
            vaultIndices: [0, 0],
            sqrtPriceLimitsX96: [MIN_SQRT_RATIO, MAX_SQRT_RATIO],
            freezeSqrtPriceX96: belowPrice ? MIN_SQRT_RATIO : MAX_SQRT_RATIO,
            rftData: ""
        });

        assetId = openTaker(params);
        console2.log(unicode"✅ Taker position created with Asset ID:", assetId);
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
        }

        console2.log("============================================================");
        console2.log(unicode"All positions created successfully! 🎉");
        console2.log("============================================================");
    }
}

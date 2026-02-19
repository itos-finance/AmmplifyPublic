// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "forge-std/StdJson.sol";

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { TransferHelper } from "Commons/Util/TransferHelper.sol";

// Uniswap V3 libraries
import { TickMath } from "v3-core/libraries/TickMath.sol";
import { LiquidityAmounts } from "../test/utils/LiquidityAmounts.sol";

// Ammplify interfaces
import { IMaker } from "../src/interfaces/IMaker.sol";
import { ITaker } from "../src/interfaces/ITaker.sol";
import { IView } from "../src/interfaces/IView.sol";

// Integrations
import { NFTManager } from "../src/integrations/NFTManager.sol";

// Mock tokens for testing
import { MockERC20 } from "../test/mocks/MockERC20.sol";

// Uniswap V3 interfaces
import { IUniswapV3Pool } from "lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

/**
 * @title AmmplifyPositions
 * @notice Base script for Ammplify position management
 * @dev Loads addresses from addresses/<protocol>.json via AMMPLIFY_PROTOCOL env var (default: uniswapv3)
 */
contract AmmplifyPositions is Script {
    using stdJson for string;

    // Environment configuration
    struct Environment {
        address diamond;
        address opener;
        address decomposer;
        address factory;
        address nfpm;
        address router;
        string jsonRaw; // for dynamic token/pool lookups
    }

    // Position parameters
    struct MakerParams {
        address recipient;
        address poolAddr;
        int24 lowTick;
        int24 highTick;
        uint128 liquidity;
        bool isCompounding;
        uint160 minSqrtPriceX96;
        uint160 maxSqrtPriceX96;
        bytes rftData;
    }

    struct TakerParams {
        address recipient;
        address poolAddr;
        int24[2] ticks;
        uint128 liquidity;
        uint8[2] vaultIndices;
        uint160[2] sqrtPriceLimitsX96;
        uint160 freezeSqrtPriceX96;
        bytes rftData;
    }

    Environment public env;

    // Constants for price limits
    uint160 public constant MIN_SQRT_RATIO = 4295128739;
    uint160 public constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    function setUp() public {
        loadEnvironment();
    }

    /**
     * @notice Load environment configuration from JSON file based on AMMPLIFY_PROTOCOL
     */
    function loadEnvironment() public {
        string memory protocol = vm.envOr("AMMPLIFY_PROTOCOL", string("uniswapv3"));
        string memory path = string.concat(vm.projectRoot(), "/addresses/", protocol, ".json");
        string memory json = vm.readFile(path);

        env.diamond = json.readAddress(".diamond");
        env.decomposer = json.readAddress(".decomposer");
        env.factory = json.readAddress(".factory");
        env.nfpm = json.readAddress(".nfpm");
        env.jsonRaw = json;

        // opener and router may not exist in all files
        if (stdJson.keyExists(json, ".opener")) {
            env.opener = json.readAddress(".opener");
        }
        if (stdJson.keyExists(json, ".router")) {
            env.router = json.readAddress(".router");
        }

        console2.log("=== Environment Loaded ===");
        console2.log("Protocol:", protocol);
        console2.log("Diamond:", env.diamond);
        console2.log("NFPM:", env.nfpm);
    }

    // ============ Token/Pool Helpers ============

    /**
     * @notice Get a token address by symbol (e.g. "USDC", "WETH")
     */
    function getTokenAddress(string memory symbol) public view returns (address) {
        string memory key = string.concat(".tokens.", symbol, ".address");
        return env.jsonRaw.readAddress(key);
    }

    /**
     * @notice Get a token's decimals by symbol
     */
    function getTokenDecimals(string memory symbol) public view returns (uint8) {
        string memory key = string.concat(".tokens.", symbol, ".decimals");
        return uint8(env.jsonRaw.readUint(key));
    }

    /**
     * @notice Get a pool address by key (e.g. "USDC_WETH_3000")
     */
    function getPoolAddress(string memory poolKey) public view returns (address) {
        string memory key = string.concat(".pools.", poolKey);
        return env.jsonRaw.readAddress(key);
    }

    // ============ Position Functions ============

    /**
     * @notice Open a maker position using the NFT Manager
     */
    function openMakerWithNFT(MakerParams memory params) public returns (uint256 tokenId, uint256 assetId) {
        console2.log("=== Opening Maker Position with NFT ===");

        NFTManager nftMgr = NFTManager(env.nfpm);

        (uint256 amount0, uint256 amount1) = calculateTokenAmounts(
            params.poolAddr,
            params.lowTick,
            params.highTick,
            params.liquidity
        );

        address token0 = getToken0(params.poolAddr);
        address token1 = getToken1(params.poolAddr);

        IERC20(token0).approve(env.nfpm, amount0);
        IERC20(token1).approve(env.nfpm, amount1);

        (tokenId, assetId) = nftMgr.mintNewMaker(
            params.recipient,
            params.poolAddr,
            params.lowTick,
            params.highTick,
            params.liquidity,
            params.isCompounding,
            uint128(params.minSqrtPriceX96),
            uint128(params.maxSqrtPriceX96),
            params.rftData
        );

        console2.log("NFT Token ID:", tokenId);
        console2.log("Asset ID:", assetId);
    }

    /**
     * @notice Open a maker position directly through the diamond
     */
    function openMaker(MakerParams memory params) public returns (uint256 assetId) {
        console2.log("=== Opening Maker Position Direct ===");

        IMaker maker = IMaker(env.diamond);

        (uint256 amount0, uint256 amount1) = calculateTokenAmounts(
            params.poolAddr,
            params.lowTick,
            params.highTick,
            params.liquidity
        );

        console2.log("Required token0:", amount0);
        console2.log("Required token1:", amount1);

        assetId = maker.newMaker(
            params.recipient,
            params.poolAddr,
            params.lowTick,
            params.highTick,
            params.liquidity,
            params.isCompounding,
            params.minSqrtPriceX96,
            params.maxSqrtPriceX96,
            params.rftData
        );

        console2.log("Asset ID:", assetId);
    }

    /**
     * @notice Open a taker position
     */
    function openTaker(TakerParams memory params) internal returns (uint256 assetId) {
        console2.log("=== Opening Taker Position ===");

        ITaker taker = ITaker(env.diamond);

        assetId = taker.newTaker(
            params.recipient,
            params.poolAddr,
            params.ticks,
            params.liquidity,
            params.vaultIndices,
            params.sqrtPriceLimitsX96,
            params.freezeSqrtPriceX96,
            params.rftData
        );

        console2.log("Asset ID:", assetId);
    }

    function run() public virtual {
        revert("Override run() in your script");
    }

    // ============ Collateral Management ============

    /**
     * @notice Collateralize a taker position
     */
    function collateralizeTaker(address recipient, uint256 token0Amount, uint256 token1Amount, address pool) public {
        ITaker taker = ITaker(env.diamond);
        fundAccount(recipient, token0Amount, token1Amount, pool);

        if (token0Amount > 0) {
            address token0 = getToken0(pool);
            IERC20(token0).approve(env.diamond, token0Amount);
            taker.collateralize(recipient, token0, token0Amount, "");
        }

        if (token1Amount > 0) {
            address token1 = getToken1(pool);
            IERC20(token1).approve(env.diamond, token1Amount);
            taker.collateralize(recipient, token1, token1Amount, "");
        }
    }

    // ============ Utility Functions ============

    function getCurrentSqrtPrice(address pool) public view returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96, , , , , , ) = IUniswapV3Pool(pool).slot0();
    }

    function getToken0(address pool) public view returns (address) {
        return IUniswapV3Pool(pool).token0();
    }

    function getToken1(address pool) public view returns (address) {
        return IUniswapV3Pool(pool).token1();
    }

    function calculateTokenAmounts(
        address pool,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) public view returns (uint256 amount0, uint256 amount1) {
        uint160 sqrtPriceX96 = getCurrentSqrtPrice(pool);
        uint160 sqrtPriceAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtPriceBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            sqrtPriceAX96,
            sqrtPriceBX96,
            liquidity
        );

        // add one for opens
        amount0 = amount0 + 1;
        amount1 = amount1 + 1;
    }

    function getValidTick(int24 tick, uint24 fee) public pure returns (int24) {
        int24 tickSpacing;

        if (fee == 500) {
            tickSpacing = 10;
        } else if (fee == 3000) {
            tickSpacing = 60;
        } else if (fee == 10000) {
            tickSpacing = 200;
        } else {
            tickSpacing = 60;
        }

        return (tick / tickSpacing) * tickSpacing;
    }

    /**
     * @notice Fund account with tokens for testing (mock tokens)
     */
    function fundAccount(address account, uint256 amount0, uint256 amount1, address pool) public {
        if (amount0 > 0) {
            address token0 = getToken0(pool);
            MockERC20(token0).mint(account, amount0);
        }
        if (amount1 > 0) {
            address token1 = getToken1(pool);
            MockERC20(token1).mint(account, amount1);
        }
    }

    /**
     * @notice Set up token approvals for specified tokens and spenders
     */
    function setupApprovals(address[] memory tokens, address[] memory spenders, uint256 amount) public {
        for (uint256 i = 0; i < tokens.length; i++) {
            for (uint256 j = 0; j < spenders.length; j++) {
                if (spenders[j] != address(0)) {
                    IERC20(tokens[i]).approve(spenders[j], amount);
                }
            }
        }
    }

    function printPoolState(address pool) public view {
        (uint160 sqrtPriceX96, int24 tick, , , , , ) = IUniswapV3Pool(pool).slot0();
        uint24 fee = IUniswapV3Pool(pool).fee();
        int24 tickSpacing = IUniswapV3Pool(pool).tickSpacing();

        console2.log("=== Pool State ===");
        console2.log("Pool:", pool);
        console2.log("Current sqrt price:", sqrtPriceX96);
        console2.log("Current tick:", tick);
        console2.log("Fee tier:", fee);
        console2.log("Tick spacing:", vm.toString(tickSpacing));
    }
}

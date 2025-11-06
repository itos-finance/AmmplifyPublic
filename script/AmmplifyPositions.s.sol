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
 * @notice Script for opening maker and taker positions in Ammplify
 * @dev Supports both direct diamond calls and NFT-wrapped positions
 * @dev Loads SimplexDiamond from deployed-addresses.json
 * @dev SimplexDiamond: Full Ammplify system with maker and taker functionality
 */
contract AmmplifyPositions is Script {
    using stdJson for string;

    // Environment configuration
    struct Environment {
        address deployer;
        address usdcToken;
        address wethToken;
        address usdcVault;
        address wethVault;
        address simplexDiamond;
        address nftManager;
        address uniswapFactory;
        address uniswapNFPM;
        address usdcWethPool;
        address decomposer;
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
     * @notice Load environment configuration from JSON file
     */
    function loadEnvironment() public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployed-addresses.json");
        string memory json = vm.readFile(path);

        env.deployer = json.readAddress(".deployer");
        env.usdcToken = json.readAddress(".tokens.USDC.address");
        env.wethToken = json.readAddress(".tokens.WETH.address");
        env.usdcVault = json.readAddress(".vaults.USDC.address");
        env.wethVault = json.readAddress(".vaults.WETH.address");
        env.simplexDiamond = json.readAddress(".ammplify.simplexDiamond");
        env.nftManager = json.readAddress(".ammplify.nftManager");
        env.uniswapFactory = json.readAddress(".uniswap.factory");
        env.uniswapNFPM = json.readAddress(".uniswap.nfpm");
        env.usdcWethPool = json.readAddress(".uniswap.pools.USDC_WETH_3000");
        env.decomposer = json.readAddress(".integrations.decomposer");

        console2.log("=== Environment Loaded ===");
        console2.log("Deployer:", env.deployer);
        console2.log("USDC Token:", env.usdcToken);
        console2.log("WETH Token:", env.wethToken);
        console2.log("SimplexDiamond:", env.simplexDiamond);
        console2.log("NFT Manager:", env.nftManager);
        console2.log("USDC/WETH Pool:", env.usdcWethPool);
    }

    /**
     * @notice Open a maker position using the NFT Manager (recommended)
     * @param params Maker position parameters
     * @return tokenId The NFT token ID
     * @return assetId The asset ID in the diamond
     */
    function openMakerWithNFT(MakerParams memory params) public returns (uint256 tokenId, uint256 assetId) {
        console2.log("=== Opening Maker Position with NFT ===");
        console2.log("Pool:", params.poolAddr);
        console2.log("Tick Range:", vm.toString(params.lowTick), "to", vm.toString(params.highTick));
        console2.log("Liquidity:", params.liquidity);
        console2.log("Compounding:", params.isCompounding);

        NFTManager nftManager = NFTManager(env.nftManager);

        // Calculate required token amounts for this position
        (uint256 amount0, uint256 amount1) = calculateTokenAmounts(
            params.poolAddr,
            params.lowTick,
            params.highTick,
            params.liquidity
        );

        console2.log("Required token0:", amount0);
        console2.log("Required token1:", amount1);

        // Ensure we have sufficient token approvals
        address token0 = getToken0(params.poolAddr);
        address token1 = getToken1(params.poolAddr);

        IERC20(token0).approve(env.nftManager, amount0);
        IERC20(token1).approve(env.nftManager, amount1);

        // Open the maker position
        (tokenId, assetId) = nftManager.mintNewMaker(
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

        console2.log("=== Maker Position Created ===");
        console2.log("NFT Token ID:", tokenId);
        console2.log("Asset ID:", assetId);

        return (tokenId, assetId);
    }

    /**
     * @notice Open a maker position directly through the diamond
     * @param params Maker position parameters
     * @return assetId The asset ID in the diamond
     */
    function openMakerDirect(MakerParams memory params) public returns (uint256 assetId) {
        console2.log("=== Opening Maker Position Direct ===");
        console2.log("Pool:", params.poolAddr);
        console2.log("Tick Range:", vm.toString(params.lowTick), "to", vm.toString(params.highTick));
        console2.log("Liquidity:", params.liquidity);

        IMaker maker = IMaker(env.simplexDiamond);

        // Calculate and approve required tokens
        console2.log("=== Calculating Token Amounts ===");
        console2.log("Pool:", params.poolAddr);
        console2.log("Low tick:", params.lowTick);
        console2.log("High tick:", params.highTick);
        console2.log("Liquidity:", params.liquidity);

        // Validate tick range
        require(params.lowTick < params.highTick, "Invalid tick range: lowTick must be less than highTick");
        require(params.lowTick >= TickMath.MIN_TICK, "Invalid tick range: lowTick too low");
        require(params.highTick <= TickMath.MAX_TICK, "Invalid tick range: highTick too high");

        (uint256 amount0, uint256 amount1) = calculateTokenAmounts(
            params.poolAddr,
            params.lowTick,
            params.highTick,
            params.liquidity
        );

        console2.log("Calculated amount0:", amount0);
        console2.log("Calculated amount1:", amount1);

        address token0 = getToken0(params.poolAddr);
        address token1 = getToken1(params.poolAddr);

        console2.log("Token0:", token0);
        console2.log("Token1:", token1);

        // Check if we already have max approval, if not, approve the calculated amount with buffer
        // Use msg.sender (the deployer) instead of address(this) for allowance checks
        uint256 currentAllowance0 = IERC20(token0).allowance(msg.sender, env.simplexDiamond);
        uint256 currentAllowance1 = IERC20(token1).allowance(msg.sender, env.simplexDiamond);

        if (currentAllowance0 < amount0) {
            // Add a small buffer to avoid precision issues during transfer
            uint256 buffer0 = amount0 / 1000 + 1; // 0.1% buffer + 1
            IERC20(token0).approve(env.simplexDiamond, amount0 + buffer0);
        }

        if (currentAllowance1 < amount1) {
            // Add a small buffer to avoid precision issues during transfer
            uint256 buffer1 = amount1 / 1000 + 1; // 0.1% buffer + 1
            IERC20(token1).approve(env.simplexDiamond, amount1 + buffer1);
        }

        // Open the maker position
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

        console2.log("=== Maker Position Created ===");
        console2.log("Asset ID:", assetId);

        return assetId;
    }

    /**
     * @notice Open a taker position (requires admin rights)
     * @param params Taker position parameters
     * @return assetId The asset ID in the diamond
     */
    function openTaker(TakerParams memory params) internal returns (uint256 assetId) {
        console2.log("=== Opening Taker Position ===");
        console2.log("Pool:", params.poolAddr);
        console2.log("Tick Range:", vm.toString(params.ticks[0]), "to", vm.toString(params.ticks[1]));
        console2.log("Liquidity:", params.liquidity);
        console2.log("Vault Indices:", params.vaultIndices[0], params.vaultIndices[1]);
        console2.log(env.simplexDiamond);
        ITaker taker = ITaker(env.simplexDiamond);

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

        console2.log("=== Taker Position Created ===");
        console2.log("Asset ID:", assetId);

        return assetId;
    }

    /**
     * @notice Example: Open a basic USDC/WETH maker position
     */
    function run() public virtual {
        vm.startBroadcast();

        // Example maker position parameters
        MakerParams memory makerParams = MakerParams({
            recipient: msg.sender,
            poolAddr: env.usdcWethPool,
            lowTick: -600, // Adjust based on current price
            highTick: 600, // Adjust based on current price
            liquidity: 1e12, // Minimum liquidity
            isCompounding: true,
            minSqrtPriceX96: MIN_SQRT_RATIO,
            maxSqrtPriceX96: MAX_SQRT_RATIO,
            rftData: ""
        });

        // Open maker position with NFT
        (uint256 tokenId, uint256 assetId) = openMakerWithNFT(makerParams);

        console2.log("=== Transaction Complete ===");
        console2.log("Created NFT Token ID:", tokenId);
        console2.log("Created Asset ID:", assetId);

        vm.stopBroadcast();
    }

    // ============ Collateral Management Functions ============

    /**
     * @notice Collateralize a taker position with specific token amounts
     * @param recipient The address to collateralize for
     * @param token0Amount Amount of token0 to deposit as collateral
     * @param token1Amount Amount of token1 to deposit as collateral
     * @param pool The pool address to get token addresses from
     */
    function collateralizeTaker(address recipient, uint256 token0Amount, uint256 token1Amount, address pool) public {
        ITaker taker = ITaker(env.simplexDiamond);
        fundAccount(recipient, token0Amount, token1Amount);

        if (token0Amount > 0) {
            address token0 = getToken0(pool);
            IERC20(token0).approve(env.simplexDiamond, token0Amount);
            taker.collateralize(recipient, token0, token0Amount, "");
            console2.log("Collateralized token0:", token0Amount, "of", token0);
        }

        if (token1Amount > 0) {
            address token1 = getToken1(pool);
            IERC20(token1).approve(env.simplexDiamond, token1Amount);
            taker.collateralize(recipient, token1, token1Amount, "");
            console2.log("Collateralized token1:", token1Amount, "of", token1);
        }
    }

    // ============ Utility Functions ============

    /**
     * @notice Get the current sqrt price of a pool
     */
    function getCurrentSqrtPrice(address pool) public view returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96, , , , , , ) = IUniswapV3Pool(pool).slot0();
    }

    /**
     * @notice Get token0 address from a pool
     */
    function getToken0(address pool) public view returns (address) {
        return IUniswapV3Pool(pool).token0();
    }

    /**
     * @notice Get token1 address from a pool
     */
    function getToken1(address pool) public view returns (address) {
        return IUniswapV3Pool(pool).token1();
    }

    /**
     * @notice Calculate required token amounts for a liquidity position
     * @dev Uses the LiquidityAmounts library for precise calculation based on current price and tick range
     */
    function calculateTokenAmounts(
        address pool,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) public view returns (uint256 amount0, uint256 amount1) {
        uint160 sqrtPriceX96 = getCurrentSqrtPrice(pool);

        // Convert ticks to sqrt prices
        uint160 sqrtPriceAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtPriceBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        // Use LiquidityAmounts library for precise calculation
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

    /**
     * @notice Get valid tick for a given tick spacing
     */
    function getValidTick(int24 tick, uint24 fee) public pure returns (int24) {
        int24 tickSpacing;

        if (fee == 500) {
            tickSpacing = 10;
        } else if (fee == 3000) {
            tickSpacing = 60;
        } else if (fee == 10000) {
            tickSpacing = 200;
        } else {
            tickSpacing = 60; // Default
        }

        return (tick / tickSpacing) * tickSpacing;
    }

    /**
     * @notice Fund the caller with tokens for testing
     */
    function fundAccount(address account, uint256 usdcAmount, uint256 wethAmount) public {
        // This assumes the tokens are MockERC20 with mint function
        // In production, you'd need to handle this differently
        if (usdcAmount > 0) {
            MockERC20(env.usdcToken).mint(account, usdcAmount);
        }
        if (wethAmount > 0) {
            MockERC20(env.wethToken).mint(account, wethAmount);
        }
    }

    /**
     * @notice Set up token approvals for the diamond contracts and NFT manager
     * @param amount The amount to approve (use type(uint256).max for unlimited)
     */
    function setupApprovals(uint256 amount) public {
        // Approve SimplexDiamond contract
        if (env.simplexDiamond != address(0)) {
            IERC20(env.usdcToken).approve(env.simplexDiamond, amount);
            IERC20(env.wethToken).approve(env.simplexDiamond, amount);
            console2.log("Approved SimplexDiamond contract:", env.simplexDiamond);
        }

        // Approve NFT manager contract
        if (env.nftManager != address(0)) {
            IERC20(env.usdcToken).approve(env.nftManager, amount);
            IERC20(env.wethToken).approve(env.nftManager, amount);
            console2.log("Approved NFT manager contract:", env.nftManager);
        }

        console2.log("Token approvals setup complete");
    }

    /**
     * @notice Helper to create default maker parameters
     */
    function getDefaultMakerParams(address recipient) public view returns (MakerParams memory) {
        return
            MakerParams({
                recipient: recipient,
                poolAddr: env.usdcWethPool,
                lowTick: getValidTick(-600, 3000),
                highTick: getValidTick(600, 3000),
                liquidity: 1e12, // Minimum maker liquidity
                isCompounding: true,
                minSqrtPriceX96: MIN_SQRT_RATIO,
                maxSqrtPriceX96: MAX_SQRT_RATIO,
                rftData: ""
            });
    }

    /**
     * @notice Helper to create default taker parameters
     */
    function getDefaultTakerParams(address recipient) public view returns (TakerParams memory) {
        return
            TakerParams({
                recipient: recipient,
                poolAddr: env.usdcWethPool,
                ticks: [getValidTick(-1200, 3000), getValidTick(-600, 3000)],
                liquidity: 1e12, // Minimum taker liquidity
                vaultIndices: [0, 0], // Assuming USDC and WETH vaults are at indices 0 and 0
                sqrtPriceLimitsX96: [MIN_SQRT_RATIO, MAX_SQRT_RATIO],
                freezeSqrtPriceX96: MIN_SQRT_RATIO, // Above range - prefer token1 output
                rftData: ""
            });
    }

    /**
     * @notice Print current pool state
     */
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

    // ============ Diamond Access Helpers ============

    /**
     * @notice Get the SimplexDiamond address (main Ammplify system)
     */
    function getSimplexDiamond() public view returns (address) {
        return env.simplexDiamond;
    }

    /**
     * @notice Get the appropriate diamond for maker operations
     * @dev Returns SimplexDiamond for all operations
     */
    function getMakerDiamond() public view returns (address) {
        return env.simplexDiamond;
    }

    /**
     * @notice Get the appropriate diamond for taker operations
     * @dev Taker operations always use SimplexDiamond
     */
    function getTakerDiamond() public view returns (address) {
        return env.simplexDiamond;
    }
}

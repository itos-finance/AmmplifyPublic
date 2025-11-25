// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { UniswapV3Factory } from "v3-core/UniswapV3Factory.sol";
import { UniswapV3Pool } from "v3-core/UniswapV3Pool.sol";
import { TickMath } from "v3-core/libraries/TickMath.sol";
import { IUniswapV3MintCallback } from "v3-core/interfaces/callback/IUniswapV3MintCallback.sol";
import { TransferHelper } from "Commons/Util/TransferHelper.sol";
import { MockERC20 } from "../test/mocks/MockERC20.sol";
import { NonfungiblePositionManager } from "../test/mocks/nfpm/NonfungiblePositionManager.sol";
import { NonfungibleTokenPositionDescriptor } from "../test/mocks/nfpm/NonfungibleTokenPositionDescriptor.sol";

/**
 * @title DeployUniV3
 * @dev Deployment script for Uniswap V3 infrastructure
 *
 * This script deploys:
 * - UniswapV3Factory
 * - NonfungiblePositionManager (NFPM)
 * - Creates a USDC/WETH pool with initial liquidity
 * - Initializes the pool at 1:1 price ratio
 *
 * Prerequisites:
 * - Tokens must be deployed first (run DeployTokens.s.sol)
 * - Set TOKEN_USDC and TOKEN_WETH environment variables or update the script
 *
 * Usage:
 * export TOKEN_USDC=<usdc_address>
 * export TOKEN_WETH=<weth_address>
 * forge script script/DeployUniV3.s.sol:DeployUniV3 --rpc-url <RPC_URL> --broadcast
 */
contract DeployUniV3 is Script, IUniswapV3MintCallback {
    // Deployed contracts
    UniswapV3Factory public factory;
    NonfungiblePositionManager public nfpm;
    NonfungibleTokenPositionDescriptor public descriptor;
    UniswapV3Pool public usdcWethPool;

    // Configuration
    uint160 public constant INIT_SQRT_PRICE_X96 = 1 << 96; // 1:1 price ratio
    uint24 public constant POOL_FEE = 3000; // 0.3%
    uint128 public constant INITIAL_LIQUIDITY = 1000e18;

    // Tokens (will be loaded from environment or provided addresses)
    address public tokenUsdc;
    address public tokenWeth;

    // Current operation context for callbacks
    address private currentToken0;
    address private currentToken1;

    function run() external {
        // Get the deployer's address and private key from environment
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        console.log("Deploying Uniswap V3 with deployer:", deployer);

        // Load token addresses
        _loadTokenAddresses();

        vm.startBroadcast(deployerPrivateKey);

        // Deploy UniswapV3Factory
        factory = new UniswapV3Factory();
        console.log("UniswapV3Factory deployed at:", address(factory));

        // Deploy NonfungibleTokenPositionDescriptor
        descriptor = new NonfungibleTokenPositionDescriptor(
            address(tokenWeth), // WETH9 address
            bytes32("ETH") // nativeCurrencyLabelBytes
        );
        console.log("NonfungibleTokenPositionDescriptor deployed at:", address(descriptor));

        // Deploy NonfungiblePositionManager
        nfpm = new NonfungiblePositionManager(
            address(factory),
            address(tokenWeth), // WETH9
            address(descriptor)
        );
        console.log("NonfungiblePositionManager deployed at:", address(nfpm));

        // Create and initialize USDC/WETH pool
        _createAndInitializePool();

        vm.stopBroadcast();

        // Log deployment summary
        _logDeploymentSummary();
    }

    /**
     * @notice Load token addresses from environment variables or use defaults
     */
    function _loadTokenAddresses() internal {
        try vm.envAddress("TOKEN_USDC") returns (address usdc) {
            tokenUsdc = usdc;
        } catch {
            console.log("TOKEN_USDC not set in environment, using zero address");
            tokenUsdc = address(0);
        }

        try vm.envAddress("TOKEN_WETH") returns (address weth) {
            tokenWeth = weth;
        } catch {
            console.log("TOKEN_WETH not set in environment, using zero address");
            tokenWeth = address(0);
        }

        require(tokenUsdc != address(0), "TOKEN_USDC address required");
        require(tokenWeth != address(0), "TOKEN_WETH address required");

        console.log("Using USDC at:", tokenUsdc);
        console.log("Using WETH at:", tokenWeth);
    }

    /**
     * @notice Create and initialize the USDC/WETH pool
     */
    function _createAndInitializePool() internal {
        // Ensure token0 < token1 for Uniswap V3
        address token0 = tokenUsdc < tokenWeth ? tokenUsdc : tokenWeth;
        address token1 = tokenUsdc < tokenWeth ? tokenWeth : tokenUsdc;

        currentToken0 = token0;
        currentToken1 = token1;

        console.log("Creating pool for:");
        console.log("  Token0:", token0);
        console.log("  Token1:", token1);
        console.log("  Fee:", POOL_FEE);

        // Create the pool
        address poolAddress = factory.createPool(token0, token1, POOL_FEE);
        usdcWethPool = UniswapV3Pool(poolAddress);
        console.log("Pool created at:", poolAddress);

        // Initialize the pool
        usdcWethPool.initialize(INIT_SQRT_PRICE_X96);
        console.log("Pool initialized with sqrt price:", INIT_SQRT_PRICE_X96);

        // Add initial liquidity if requested
        // Note: Skipping initial liquidity for deployment script simplicity
        // if (INITIAL_LIQUIDITY > 0) {
        //     _addInitialLiquidity();
        // }
    }

    /**
     * @notice Add initial liquidity to the pool
     */
    function _addInitialLiquidity() internal {
        int24 tickSpacing = usdcWethPool.tickSpacing();
        int24 minTick = (TickMath.MIN_TICK / tickSpacing) * tickSpacing;
        int24 maxTick = (TickMath.MAX_TICK / tickSpacing) * tickSpacing;

        console.log("Adding initial liquidity:");
        console.log("  Amount:", INITIAL_LIQUIDITY);
        console.log("  Min tick:", minTick);
        console.log("  Max tick:", maxTick);

        // Mint some tokens to this contract for initial liquidity
        uint256 amount0Needed = 1000e6; // 1000 USDC (6 decimals)
        uint256 amount1Needed = 1000e18; // 1000 WETH (18 decimals)

        MockERC20(currentToken0).mint(address(this), amount0Needed);
        MockERC20(currentToken1).mint(address(this), amount1Needed);

        // Add liquidity to the pool
        usdcWethPool.mint(
            address(this), // recipient
            minTick, // tickLower
            maxTick, // tickUpper
            INITIAL_LIQUIDITY, // amount
            "" // data
        );

        console.log("Initial liquidity added successfully");
    }

    /**
     * @notice Uniswap V3 mint callback - provides tokens to the pool
     */
    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata /* data */
    ) external override {
        require(msg.sender == address(usdcWethPool), "Invalid callback caller");

        if (amount0Owed > 0) {
            TransferHelper.safeTransfer(currentToken0, msg.sender, amount0Owed);
        }
        if (amount1Owed > 0) {
            TransferHelper.safeTransfer(currentToken1, msg.sender, amount1Owed);
        }

        console.log("Mint callback executed:");
        console.log("  Amount0 owed:", amount0Owed);
        console.log("  Amount1 owed:", amount1Owed);
    }

    /**
     * @notice Log deployment summary
     */
    function _logDeploymentSummary() internal view {
        console.log("\n=== Uniswap V3 Deployment Summary ===");
        console.log("Factory:", address(factory));
        console.log("NFPM:", address(nfpm));
        console.log("Descriptor:", address(descriptor));
        console.log("USDC/WETH Pool:", address(usdcWethPool));

        if (address(usdcWethPool) != address(0)) {
            (uint160 sqrtPriceX96, int24 tick, , , , , ) = usdcWethPool.slot0();
            console.log("Pool State:");
            console.log("  Current sqrt price:", sqrtPriceX96);
            console.log("  Current tick:", tick);
            console.log("  Fee tier:", usdcWethPool.fee());
            console.log("  Tick spacing:", usdcWethPool.tickSpacing());
        }
    }
}

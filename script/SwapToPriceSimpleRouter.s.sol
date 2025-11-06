// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "forge-std/StdJson.sol";

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { TransferHelper } from "@Commons/Util/TransferHelper.sol";

// Uniswap V3 interfaces and libraries
import { IUniswapV3Pool } from "lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { ISwapRouter } from "../test/mocks/nfpm/interfaces/ISwapRouter.sol";
import { TickMath } from "v3-core/libraries/TickMath.sol";

// Mock tokens for testing
import { MockERC20 } from "../test/mocks/MockERC20.sol";

/**
 * @title SwapToPriceSimpleRouter
 * @notice Script for swapping a Uniswap V3 pool to a target price using SimpleSwapRouter
 * @dev Uses the simplified swap router for testing purposes
 */
contract SwapToPriceSimpleRouter is Script {
    using stdJson for string;

    // Environment configuration
    struct Environment {
        address deployer;
        address usdcToken;
        address wethToken;
        address uniswapFactory;
        address simpleSwapRouter;
        address usdcWethPool;
    }

    Environment public env;

    // Swap parameters
    struct SwapParams {
        address poolAddress;
        uint160 targetSqrtPriceX96;
        uint256 maxTokensToMint; // Safety limit for token minting
        uint24 poolFee; // Pool fee tier (e.g., 3000 for 0.3%)
    }

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
        env.wethToken = address(0); // Set WETH to address(0) as requested
        env.uniswapFactory = json.readAddress(".uniswap.factory");
        env.simpleSwapRouter = json.readAddress(".uniswap.simpleSwapRouter");
        env.usdcWethPool = json.readAddress(".uniswap.pools.USDC_WETH_3000");

        console2.log("=== Environment Loaded ===");
        console2.log("Deployer:", env.deployer);
        console2.log("USDC Token:", env.usdcToken);
        console2.log("WETH Token:", env.wethToken);
        console2.log("SimpleSwapRouter:", env.simpleSwapRouter);
        console2.log("USDC/WETH Pool:", env.usdcWethPool);
    }

    /**
     * @notice Swap pool to target price using SimpleSwapRouter
     * @param params Swap parameters including pool and target price
     */
    function swapToPrice(SwapParams memory params) public {
        console2.log("=== Swapping Pool to Target Price (Using SimpleSwapRouter) ===");
        console2.log("Pool:", params.poolAddress);
        console2.log("Target sqrt price:", params.targetSqrtPriceX96);
        console2.log("Pool fee:", params.poolFee);

        IUniswapV3Pool pool = IUniswapV3Pool(params.poolAddress);

        // Get current pool state
        (uint160 currentSqrtPriceX96, , , , , , ) = pool.slot0();
        console2.log("Current sqrt price:", currentSqrtPriceX96);

        // Check if swap is needed
        if (currentSqrtPriceX96 == params.targetSqrtPriceX96) {
            console2.log("Pool is already at target price, no swap needed");
            return;
        }

        // Get pool tokens
        address token0 = pool.token0();
        address token1 = pool.token1();

        console2.log("Token0:", token0);
        console2.log("Token1:", token1);

        // Mint tokens for the swap
        mintTokensForSwap(token0, token1, params.maxTokensToMint);
        console2.log("Finished minting");

        // Approve the swap router to spend deployer's tokens
        address deployer = vm.addr(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        approveTokensForSwap(token0, token1, params.maxTokensToMint, deployer, env.simpleSwapRouter);

        // Determine swap direction and execute using SimpleSwapRouter
        bool zeroForOne = currentSqrtPriceX96 > params.targetSqrtPriceX96;
        console2.log("Swap direction (zeroForOne):", zeroForOne);

        // Calculate the amount to swap (use a large amount to reach target price)
        uint256 amountIn = params.maxTokensToMint / 2; // Use half of minted tokens
        console2.log("Amount to swap:", amountIn);

        // Execute swap using SimpleSwapRouter
        ISwapRouter swapRouter = ISwapRouter(env.simpleSwapRouter);

        if (zeroForOne) {
            // Swap token0 for token1
            ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
                tokenIn: token0,
                tokenOut: token1,
                fee: params.poolFee,
                recipient: deployer,
                deadline: block.timestamp + 300, // 5 minutes
                amountIn: amountIn,
                amountOutMinimum: 0, // Accept any amount out
                sqrtPriceLimitX96: params.targetSqrtPriceX96
            });

            console2.log("Executing exactInputSingle swap...");
            uint256 amountOut = swapRouter.exactInputSingle(swapParams);
            console2.log("Amount out:", amountOut);
        } else {
            // Swap token1 for token0
            ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
                tokenIn: token1,
                tokenOut: token0,
                fee: params.poolFee,
                recipient: deployer,
                deadline: block.timestamp + 300, // 5 minutes
                amountIn: amountIn,
                amountOutMinimum: 0, // Accept any amount out
                sqrtPriceLimitX96: params.targetSqrtPriceX96
            });

            console2.log("Executing exactInputSingle swap...");
            uint256 amountOut = swapRouter.exactInputSingle(swapParams);
            console2.log("Amount out:", amountOut);
        }

        // Verify final price
        (uint160 finalSqrtPriceX96, , , , , , ) = pool.slot0();
        console2.log("Final sqrt price:", finalSqrtPriceX96);
    }

    /**
     * @notice Mint tokens needed for the swap
     * @param token0 First token address
     * @param token1 Second token address
     * @param amount Amount to mint for each token
     */
    function mintTokensForSwap(address token0, address token1, uint256 amount) internal {
        console2.log("Minting tokens for swap...");
        console2.log("Amount per token:", amount);

        // Mint tokens to the deployer (who is executing the script)
        address deployer = vm.addr(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        console2.log("Deployer:", deployer);

        // Try to mint tokens (assumes MockERC20 with mint function)
        try MockERC20(token0).mint(deployer, amount) {
            console2.log("Minted token0 to deployer:", token0);
            console2.log("Token0 balance:", MockERC20(token0).balanceOf(deployer));
        } catch Error(string memory reason) {
            console2.log("Failed to mint token0:", reason);
            revert(string(abi.encodePacked("Token0 mint failed: ", reason)));
        } catch {
            console2.log("Failed to mint token0: unknown error");
            revert("Token0 mint failed: unknown error");
        }
        try MockERC20(token1).mint(deployer, amount) {
            console2.log("Minted token1 to deployer:", token1);
            console2.log("Token1 balance:", MockERC20(token1).balanceOf(deployer));
        } catch Error(string memory reason) {
            console2.log("Failed to mint token1:", reason);
            revert(string(abi.encodePacked("Token1 mint failed: ", reason)));
        } catch {
            console2.log("Failed to mint token1: unknown error");
            revert("Token1 mint failed: unknown error");
        }
    }

    /**
     * @notice Approve tokens for the swap
     * @param token0 First token address
     * @param token1 Second token address
     * @param amount Amount to approve for each token
     * @param deployer Deployer address
     * @param routerAddress The router address to approve
     */
    function approveTokensForSwap(
        address token0,
        address token1,
        uint256 amount,
        address deployer,
        address routerAddress
    ) internal {
        console2.log("Approving tokens for swap...");
        console2.log("Amount per token:", amount);
        console2.log("Router address:", routerAddress);

        // Approve token0
        IERC20 token0Contract = IERC20(token0);
        token0Contract.approve(routerAddress, amount);
        console2.log("Approved token0 for router:", token0);
        console2.log("Token0 allowance:", token0Contract.allowance(deployer, routerAddress));

        // Approve token1
        IERC20 token1Contract = IERC20(token1);
        token1Contract.approve(routerAddress, amount);
        console2.log("Approved token1 for router:", token1);
        console2.log("Token1 allowance:", token1Contract.allowance(deployer, routerAddress));
    }

    /**
     * @notice Example run function - swap USDC/WETH pool to specific price
     */
    function run() public virtual {
        // Get the deployer's private key from environment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Example: Swap USDC/WETH pool to a specific price
        uint160 targetPrice = 4636912502154384835163855; // Example sqrt price

        SwapParams memory params = SwapParams({
            poolAddress: env.usdcWethPool,
            targetSqrtPriceX96: targetPrice,
            maxTokensToMint: 1e30, // 1M tokens each (adjust based on decimals)
            poolFee: 3000 // 0.3% fee tier
        });

        swapToPrice(params);

        vm.stopBroadcast();
    }

    // ============ Utility Functions ============

    /**
     * @notice Get current sqrt price of a pool
     */
    function getCurrentSqrtPrice(address pool) public view returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96, , , , , , ) = IUniswapV3Pool(pool).slot0();
    }

    /**
     * @notice Convert sqrt price to human-readable price
     * @param sqrtPriceX96 The sqrt price in X96 format
     * @param decimals0 Decimals of token0
     * @param decimals1 Decimals of token1
     * @return price The price as token1/token0
     */
    function sqrtPriceToPrice(
        uint160 sqrtPriceX96,
        uint8 decimals0,
        uint8 decimals1
    ) public pure returns (uint256 price) {
        // Price = (sqrtPriceX96 / 2^96)^2 * 10^(decimals0 - decimals1)
        uint256 priceX192 = uint256(sqrtPriceX96) * sqrtPriceX96;
        price = ((priceX192 >> 192) * (10 ** decimals0)) / (10 ** decimals1);
    }

    /**
     * @notice Convert human-readable price to sqrt price
     * @param price The price as token1/token0
     * @param decimals0 Decimals of token0
     * @param decimals1 Decimals of token1
     * @return sqrtPriceX96 The sqrt price in X96 format
     */
    function priceToSqrtPrice(
        uint256 price,
        uint8 decimals0,
        uint8 decimals1
    ) public pure returns (uint160 sqrtPriceX96) {
        // Adjust price for decimals difference
        uint256 adjustedPrice = (price * (10 ** decimals1)) / (10 ** decimals0);

        // Calculate sqrt price
        uint256 sqrtPrice = sqrt(adjustedPrice);
        sqrtPriceX96 = uint160(sqrtPrice << 96);
    }

    /**
     * @notice Calculate square root using Babylonian method
     */
    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    /**
     * @notice Print current pool state
     */
    function printPoolState(address pool) public view {
        (uint160 sqrtPriceX96, int24 tick, , , , , ) = IUniswapV3Pool(pool).slot0();
        uint24 fee = IUniswapV3Pool(pool).fee();
        int24 tickSpacing = IUniswapV3Pool(pool).tickSpacing();
        address token0 = IUniswapV3Pool(pool).token0();
        address token1 = IUniswapV3Pool(pool).token1();

        console2.log("=== Pool State ===");
        console2.log("Pool:", pool);
        console2.log("Token0:", token0);
        console2.log("Token1:", token1);
        console2.log("Current sqrt price:", sqrtPriceX96);
        console2.log("Current tick:", tick);
        console2.log("Fee tier:", fee);
        console2.log("Tick spacing:", vm.toString(tickSpacing));
    }
}

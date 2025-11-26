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
        address uniswapFactory;
        address simpleSwapRouter;
        string jsonPath;
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
        string memory path = string.concat(root, "/deployed-capricorn.json");
        string memory json = vm.readFile(path);

        env.deployer = json.readAddress(".deployer");
        env.uniswapFactory = json.readAddress(".uniswap.factory");
        env.simpleSwapRouter = json.readAddress(".uniswap.simpleSwapRouter");
        env.jsonPath = path;

        console2.log("=== Environment Loaded ===");
        console2.log("Deployer:", env.deployer);
        console2.log("Uniswap Factory:", env.uniswapFactory);
        console2.log("SimpleSwapRouter:", env.simpleSwapRouter);
        console2.log("JSON Path:", env.jsonPath);
    }

    /**
     * @notice Get pool address by key from deployed-addresses.json
     * @param poolKey The pool key (e.g., "USDC_WETH_3000", "WMON_USDC_500")
     * @return poolAddress The address of the pool
     */
    function getPoolAddress(string memory poolKey) public view returns (address poolAddress) {
        string memory json = vm.readFile(env.jsonPath);
        string memory key = string.concat(".uniswap.pools.", poolKey);
        poolAddress = json.readAddress(key);
    }

    /**
     * @notice Get pool fee from the pool contract
     * @param poolAddress The address of the pool
     * @return fee The fee tier of the pool
     */
    function getPoolFee(address poolAddress) public view returns (uint24 fee) {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        fee = pool.fee();
    }

    /**
     * @notice Swap pool to target price using SimpleSwapRouter
     * @param params Swap parameters including pool and target price
     */
    function swapToPrice(SwapParams memory params) public {
        // Auto-detect pool fee if not provided (0 means auto-detect)
        if (params.poolFee == 0) {
            params.poolFee = getPoolFee(params.poolAddress);
        }

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
        // mintTokensForSwap(token0, token1, params.maxTokensToMint);
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

        // Approve token1
        IERC20 token1Contract = IERC20(token1);
        token1Contract.approve(routerAddress, amount);
        console2.log("Approved token1 for router:", token1);
    }

    /**
     * @notice Generic run function - swap any pool to specific price or all pools
     * @dev Uses environment variables:
     *      - SWAP_ALL: If set to "true", swaps all pools back and forth; otherwise single pool mode
     *      - POOL_KEY: The pool key from deployed-addresses.json (e.g., "USDC_WETH_3000")
     *      - TARGET_PRICE: The target sqrt price X96 (optional, defaults to current price + 10%)
     *      - TARGET_PRICE_MULTIPLIER: Multiplier for target price (e.g., 110 = 1.1x = 10% increase)
     *      - MAX_TOKENS: Maximum tokens to mint (optional, defaults to 1e30)
     *      - SWAP_BACK: Whether to swap back to original (defaults to true when SWAP_ALL=true)
     */
    function run() public virtual {
        // Check if we should swap all pools
        string memory swapAll = vm.envOr("SWAP_ALL", string("false"));
        if (keccak256(bytes(swapAll)) == keccak256(bytes("true"))) {
            runAllPools();
            return;
        }

        // Single pool mode
        // Get the deployer's private key from environment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Get pool key from environment variable (defaults to USDC_WETH_3000 if not set)
        string memory poolKey = vm.envOr("POOL_KEY", string("USDC_WETH_3000"));
        address poolAddress = getPoolAddress(poolKey);

        console2.log("=== Pool Selection ===");
        console2.log("Pool Key:", poolKey);
        console2.log("Pool Address:", poolAddress);

        // Get target price from environment (optional)
        // (uint160 currentPrice, , , , , , ) = IUniswapV3Pool(poolAddress).slot0();
        // uint160 targetPrice = uint160((uint256(currentPrice) * 110) / 100);
        uint160 targetPrice = 15845632502852867518708;
        // Get max tokens from environment (optional)
        uint256 maxTokens = vm.envOr("MAX_TOKENS", uint256(1e30));

        SwapParams memory params = SwapParams({
            poolAddress: poolAddress,
            targetSqrtPriceX96: targetPrice,
            maxTokensToMint: maxTokens,
            poolFee: 0 // Auto-detect from pool
        });

        swapToPrice(params);

        vm.stopBroadcast();
    }

    /**
     * @notice Swap a specific pool to target price (alternative entry point)
     * @param poolKey The pool key from deployed-addresses.json
     * @param targetSqrtPriceX96 The target sqrt price in X96 format
     * @param maxTokensToMint Maximum tokens to mint for the swap
     */
    function swapPoolToPrice(string memory poolKey, uint160 targetSqrtPriceX96, uint256 maxTokensToMint) public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address poolAddress = getPoolAddress(poolKey);

        SwapParams memory params = SwapParams({
            poolAddress: poolAddress,
            targetSqrtPriceX96: targetSqrtPriceX96,
            maxTokensToMint: maxTokensToMint,
            poolFee: 0 // Auto-detect from pool
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
     * @param pool The pool address
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

    /**
     * @notice Print pool state by key
     * @param poolKey The pool key from deployed-addresses.json
     */
    function printPoolStateByKey(string memory poolKey) public view {
        address poolAddress = getPoolAddress(poolKey);
        console2.log("Pool Key:", poolKey);
        printPoolState(poolAddress);
    }

    /**
     * @notice List all available pools from deployed-addresses.json
     * @dev This is a helper function to see what pools are available
     * Note: Solidity doesn't support dynamic JSON key iteration, so this
     * function lists the known pools. Users can check deployed-addresses.json
     * for the full list.
     */
    function listAvailablePools() public view {
        console2.log("=== Available Pools ===");
        console2.log("USDC_WETH_3000");
        console2.log("WMON_USDC_500");
        console2.log("DAK_CHOG_10000");
        console2.log("YAKI_CHOG_10000");
        console2.log("DAK_YAKI_3000");
        console2.log("WMON_USDT_500");
        console2.log("");
        console2.log("Use POOL_KEY environment variable to select a pool");
        console2.log(
            "Example: POOL_KEY=WMON_USDC_500 forge script SwapToPriceSimpleRouter.s.sol:SwapToPriceSimpleRouter"
        );
    }

    /**
     * @notice Get all pool keys from deployed-addresses.json
     * @return poolKeys Array of all pool keys
     */
    function getAllPoolKeys() public pure returns (string[] memory poolKeys) {
        poolKeys = new string[](6);
        poolKeys[0] = "USDC_WETH_3000";
        poolKeys[1] = "WMON_USDC_500";
        poolKeys[2] = "DAK_CHOG_10000";
        poolKeys[3] = "YAKI_CHOG_10000";
        poolKeys[4] = "DAK_YAKI_3000";
        poolKeys[5] = "WMON_USDT_500";
    }

    /**
     * @notice Swap a pool back and forth between original price and target price
     * @param poolKey The pool key from deployed-addresses.json
     * @param targetSqrtPriceX96 The target sqrt price to swap to (if 0, uses current * 1.1)
     * @param maxTokensToMint Maximum tokens to mint for the swap
     * @param swapBack If true, swap back to original price after reaching target
     * @dev Note: This function does NOT start/stop broadcast. Caller must handle that.
     */
    function swapPoolBackAndForth(
        string memory poolKey,
        uint160 targetSqrtPriceX96,
        uint256 maxTokensToMint,
        bool swapBack
    ) internal {
        address poolAddress = getPoolAddress(poolKey);
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);

        // Get original price
        (uint160 originalPrice, , , , , , ) = pool.slot0();
        console2.log("=== Swapping Pool Back and Forth ===");
        console2.log("Pool Key:", poolKey);
        console2.log("Pool Address:", poolAddress);
        console2.log("Original sqrt price:", originalPrice);

        // If target price not provided, use current price * 1.1
        if (targetSqrtPriceX96 == 0) {
            targetSqrtPriceX96 = uint160((uint256(originalPrice) * 110) / 100);
            console2.log("Target price not provided, using original * 1.1");
        }
        console2.log("Target sqrt price:", targetSqrtPriceX96);

        // Swap to target price
        console2.log("\n--- Swapping TO target price ---");
        SwapParams memory params = SwapParams({
            poolAddress: poolAddress,
            targetSqrtPriceX96: targetSqrtPriceX96,
            maxTokensToMint: maxTokensToMint,
            poolFee: 0 // Auto-detect from pool
        });

        swapToPrice(params);

        // Verify we reached target
        (uint160 currentPriceAfterFirstSwap, , , , , , ) = pool.slot0();
        console2.log("\nPrice after first swap:", currentPriceAfterFirstSwap);

        // Swap back to original price if requested
        if (swapBack) {
            console2.log("\n--- Swapping BACK to original price ---");
            SwapParams memory backParams = SwapParams({
                poolAddress: poolAddress,
                targetSqrtPriceX96: originalPrice,
                maxTokensToMint: maxTokensToMint,
                poolFee: 0 // Auto-detect from pool
            });

            swapToPrice(backParams);

            // Verify we're back to original
            (uint160 finalPrice, , , , , , ) = pool.slot0();
            console2.log("\nFinal price (should match original):", finalPrice);
            console2.log("Original price:", originalPrice);
        }
    }

    /**
     * @notice Public entry point to swap a pool back and forth
     * @param poolKey The pool key from deployed-addresses.json
     * @param targetSqrtPriceX96 The target sqrt price to swap to (if 0, uses current * 1.1)
     * @param maxTokensToMint Maximum tokens to mint for the swap
     * @param swapBack If true, swap back to original price after reaching target
     */
    function swapPoolBackAndForthPublic(
        string memory poolKey,
        uint160 targetSqrtPriceX96,
        uint256 maxTokensToMint,
        bool swapBack
    ) public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        swapPoolBackAndForth(poolKey, targetSqrtPriceX96, maxTokensToMint, swapBack);

        vm.stopBroadcast();
    }

    /**
     * @notice Swap all pools back and forth
     * @param targetPriceMultiplier Multiplier for target price (e.g., 110 = 1.1x = 10% increase)
     * @param maxTokensToMint Maximum tokens to mint for each swap
     * @param swapBack If true, swap each pool back to original price after reaching target
     * @dev Note: This function does NOT start/stop broadcast. Caller must handle that.
     */
    function swapAllPoolsBackAndForth(uint256 targetPriceMultiplier, uint256 maxTokensToMint, bool swapBack) internal {
        string[] memory poolKeys = getAllPoolKeys();
        console2.log("=== Swapping All Pools Back and Forth ===");
        console2.log("Number of pools:", poolKeys.length);
        console2.log("Target price multiplier:", targetPriceMultiplier);
        console2.log("Max tokens to mint:", maxTokensToMint);
        console2.log("Swap back:", swapBack);
        console2.log("");

        for (uint256 i = 0; i < poolKeys.length; i++) {
            console2.log("\n========================================");
            console2.log("Processing pool", i + 1, "of", poolKeys.length);
            console2.log("========================================");

            address poolAddress = getPoolAddress(poolKeys[i]);
            IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);

            // Get original price
            (uint160 originalPrice, , , , , , ) = pool.slot0();
            uint160 targetPrice = uint160((uint256(originalPrice) * targetPriceMultiplier) / 100);

            console2.log("Pool Key:", poolKeys[i]);
            console2.log("Original price:", originalPrice);
            console2.log("Target price:", targetPrice);

            // Swap to target price
            console2.log("\n--- Swapping TO target price ---");
            SwapParams memory params = SwapParams({
                poolAddress: poolAddress,
                targetSqrtPriceX96: targetPrice,
                maxTokensToMint: maxTokensToMint,
                poolFee: 0 // Auto-detect from pool
            });

            swapToPrice(params);

            // Swap back to original if requested
            if (swapBack) {
                console2.log("\n--- Swapping BACK to original price ---");
                SwapParams memory backParams = SwapParams({
                    poolAddress: poolAddress,
                    targetSqrtPriceX96: originalPrice,
                    maxTokensToMint: maxTokensToMint,
                    poolFee: 0 // Auto-detect from pool
                });

                swapToPrice(backParams);
            }

            console2.log("\nCompleted pool:", poolKeys[i]);
        }

        console2.log("\n=== All Pools Processed ===");
    }

    /**
     * @notice Run function to swap all pools back and forth
     * @dev Uses environment variables:
     *      - TARGET_PRICE_MULTIPLIER: Multiplier for target price (defaults to 110 = 1.1x = 10% increase)
     *      - MAX_TOKENS: Maximum tokens to mint (defaults to 1e30)
     *      - SWAP_BACK: Whether to swap back to original (defaults to true)
     *      - SWAP_ALL: If set to "true", swaps all pools; otherwise uses single pool mode
     */
    function runAllPools() public virtual {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Get parameters from environment
        uint256 targetPriceMultiplier = vm.envOr("TARGET_PRICE_MULTIPLIER", uint256(110)); // 110 = 1.1x = 10% increase
        uint256 maxTokens = vm.envOr("MAX_TOKENS", uint256(1e30));
        bool swapBack = vm.envOr("SWAP_BACK", true);

        swapAllPoolsBackAndForth(targetPriceMultiplier, maxTokens, swapBack);

        vm.stopBroadcast();
    }
}

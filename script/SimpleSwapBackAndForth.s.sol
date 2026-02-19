// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "forge-std/StdJson.sol";

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// Uniswap V3 interfaces
import { IUniswapV3Pool } from "lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { ISwapRouter } from "../test/mocks/nfpm/interfaces/ISwapRouter.sol";

// Mock tokens for testing
import { MockERC20 } from "../test/mocks/MockERC20.sol";

/**
 * @title SimpleSwapBackAndForth
 * @notice Simple script to swap back and forth a couple times on a pool using SwapRouter
 */
contract SimpleSwapBackAndForth is Script {
    using stdJson for string;

    function run() public {
        // Get deployer private key
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Get pool address from environment (defaults to USDC_WETH_3000)
        address poolAddress;
        try vm.envAddress("POOL_ADDRESS") returns (address addr) {
            poolAddress = addr;
        } catch {
            // Try to get from pool key
            string memory poolKey = vm.envOr("POOL_KEY", string("USDC_WETH_3000"));
            poolAddress = getPoolAddress(poolKey);
        }
        // Get SwapRouter address from environment (defaults to simpleSwapRouter)
        address swapRouterAddress = vm.envOr("SWAP_ROUTER_ADDRESS", getSwapRouterAddress());

        // Get swap amount from environment (defaults to 1e18)
        uint256 swapAmount = vm.envOr("SWAP_AMOUNT", uint256(1e18));

        // Get number of swaps from environment (defaults to 2)
        uint256 numSwaps = vm.envOr("NUM_SWAPS", uint256(2));

        console2.log("=== Simple Swap Back and Forth ===");
        console2.log("Pool Address:", poolAddress);
        console2.log("SwapRouter Address:", swapRouterAddress);
        console2.log("Swap Amount:", swapAmount);
        console2.log("Number of swaps:", numSwaps);
        console2.log("Deployer:", deployer);

        // Get pool info
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        address token0 = pool.token0();
        address token1 = pool.token1();
        uint24 fee = pool.fee();

        console2.log("Token0:", token0);
        console2.log("Token1:", token1);
        console2.log("Pool Fee:", fee);

        // Get initial pool state
        (uint160 initialSqrtPriceX96, int24 initialTick, , , , , ) = pool.slot0();
        console2.log("Initial sqrt price:", initialSqrtPriceX96);
        console2.log("Initial tick:", initialTick);

        // Mint tokens if needed
        mintTokensIfNeeded(token0, token1, swapAmount * 2, deployer);

        // Approve router
        approveRouter(token0, token1, swapAmount * 2, deployer, swapRouterAddress);

        // Perform swaps back and forth
        ISwapRouter swapRouter = ISwapRouter(swapRouterAddress);
        bool swapToken0ForToken1 = true; // Start with token0 -> token1

        for (uint256 i = 0; i < numSwaps; i++) {
            console2.log("\n--- Swap");
            console2.log("Swap number:", i + 1);
            console2.log("Total swaps:", numSwaps);

            if (swapToken0ForToken1) {
                console2.log("Swapping token0 -> token1");
                swapExactInputSingle(swapRouter, token0, token1, fee, swapAmount, deployer);
            } else {
                console2.log("Swapping token1 -> token0");
                swapExactInputSingle(swapRouter, token1, token0, fee, swapAmount, deployer);
            }

            // Toggle direction for next swap
            swapToken0ForToken1 = !swapToken0ForToken1;

            // Check pool state after swap
            (uint160 currentSqrtPriceX96, int24 currentTick, , , , , ) = pool.slot0();
            console2.log("Current sqrt price:", currentSqrtPriceX96);
            console2.log("Current tick:", currentTick);
        }

        // Final pool state
        (uint160 finalSqrtPriceX96, int24 finalTick, , , , , ) = pool.slot0();
        console2.log("\n=== Final State ===");
        console2.log("Final sqrt price:", finalSqrtPriceX96);
        console2.log("Final tick:", finalTick);
        console2.log("Initial sqrt price:", initialSqrtPriceX96);
        console2.log("Initial tick:", initialTick);

        vm.stopBroadcast();
    }

    /**
     * @notice Perform an exact input single swap
     */
    function swapExactInputSingle(
        ISwapRouter swapRouter,
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        address recipient
    ) internal returns (uint256 amountOut) {
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: fee,
            recipient: recipient,
            deadline: block.timestamp + 300, // 5 minutes
            amountIn: amountIn,
            amountOutMinimum: 0, // Accept any amount out
            sqrtPriceLimitX96: 0 // No price limit
        });

        amountOut = swapRouter.exactInputSingle(params);
        console2.log("Amount in:", amountIn);
        console2.log("Amount out:", amountOut);
    }

    /**
     * @notice Mint tokens if needed (assumes MockERC20)
     */
    function mintTokensIfNeeded(address token0, address token1, uint256 amount, address to) internal {
        console2.log("\n--- Minting Tokens ---");

        // Try to mint token0
        try MockERC20(token0).mint(to, amount) {
            uint256 balance0 = IERC20(token0).balanceOf(to);
            console2.log("Token0 balance:", balance0);
        } catch {
            uint256 balance0 = IERC20(token0).balanceOf(to);
            console2.log("Token0 balance (no mint):", balance0);
            if (balance0 < amount) {
                revert("Insufficient token0 balance");
            }
        }
        // Try to mint token1
        try MockERC20(token1).mint(to, amount) {
            uint256 balance1 = IERC20(token1).balanceOf(to);
            console2.log("Token1 balance:", balance1);
        } catch {
            uint256 balance1 = IERC20(token1).balanceOf(to);
            console2.log("Token1 balance (no mint):", balance1);
            if (balance1 < amount) {
                revert("Insufficient token1 balance");
            }
        }
    }

    /**
     * @notice Approve router to spend tokens
     */
    function approveRouter(address token0, address token1, uint256 amount, address owner, address router) internal {
        console2.log("\n--- Approving Router ---");

        IERC20(token0).approve(router, amount);
        console2.log("Approved token0");

        IERC20(token1).approve(router, amount);
        console2.log("Approved token1");
    }

    /**
     * @notice Get pool address from pool key
     */
    function getPoolAddress(string memory poolKey) internal view returns (address) {
        string memory protocol = vm.envOr("AMMPLIFY_PROTOCOL", string("uniswapv3"));
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/addresses/", protocol, ".json");
        string memory json = vm.readFile(path);
        string memory key = string.concat(".pools.", poolKey);
        return json.readAddress(key);
    }

    /**
     * @notice Get SwapRouter address from addresses JSON
     */
    function getSwapRouterAddress() internal view returns (address) {
        string memory protocol = vm.envOr("AMMPLIFY_PROTOCOL", string("uniswapv3"));
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/addresses/", protocol, ".json");
        string memory json = vm.readFile(path);
        return json.readAddress(".router");
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "forge-std/StdJson.sol";

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// Uniswap V3 interfaces
import { IUniswapV3Pool } from "v3-core/interfaces/IUniswapV3Pool.sol";
import { ISwapRouter } from "../test/mocks/nfpm/interfaces/ISwapRouter.sol";
import { IUniswapV3Factory } from "v3-core/interfaces/IUniswapV3Factory.sol";

/**
 * @notice WMON interface - simple wrapper contract
 */
interface IWMON {
    function deposit() external payable;
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title WrapAndSwap
 * @notice Script to wrap native MON to WMON and then swap WMON for another token using Uniswap router
 */
contract WrapAndSwap is Script {
    using stdJson for string;

    // WMON contract address (Wrapped MON)
    address public constant WMON = 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A;

    // Target token to swap for
    address public constant TARGET_TOKEN = 0x754704Bc059F8C67012fEd69BC8A327a5aafb603;

    // Recipient address for WMON + USDC
    address public constant RECIPIENT = 0xbe7dC5cC7977ac378ead410869D6c96f1E6C773e;

    function run() public {
        // Get deployer private key
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Get amount to wrap from environment (defaults to 1 MON)
        uint256 wrapAmount = vm.envOr("WRAP_AMOUNT", uint256(5e17));

        // Get swap router address from environment or deployed-addresses.json
        address swapRouterAddress = vm.envOr("SWAP_ROUTER_ADDRESS", getSwapRouterAddress());

        // Get pool address from environment or find it
        address poolAddress = getPoolAddress();

        console2.log("=== Wrap and Swap ===");
        console2.log("Deployer:", deployer);
        console2.log("WMON Address:", WMON);
        console2.log("Target Token:", TARGET_TOKEN);
        console2.log("Wrap Amount:", wrapAmount);
        console2.log("SwapRouter Address:", swapRouterAddress);
        console2.log("Pool Address:", poolAddress);

        // Step 1: Wrap native MON to WMON
        console2.log("\n--- Step 1: Wrapping MON to WMON ---");
        uint256 nativeBalanceBefore = deployer.balance;
        uint256 wmonBalanceBefore = IWMON(WMON).balanceOf(deployer);
        console2.log("Native MON balance before:", nativeBalanceBefore);
        console2.log("WMON balance before:", wmonBalanceBefore);

        // Call deposit on WMON contract to wrap native token
        IWMON(WMON).deposit{ value: wrapAmount }();

        uint256 wmonBalanceAfter = IWMON(WMON).balanceOf(deployer);
        console2.log("WMON balance after:", wmonBalanceAfter);
        console2.log("Wrapped amount:", wmonBalanceAfter - wmonBalanceBefore);

        // Step 2: Get pool info
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        address token0 = pool.token0();
        address token1 = pool.token1();
        uint24 fee = pool.fee();

        console2.log("\n--- Pool Info ---");
        console2.log("Token0:", token0);
        console2.log("Token1:", token1);
        console2.log("Pool Fee:", fee);

        // Verify WMON is in the pool
        require(token0 == WMON || token1 == WMON, "WMON not found in pool");
        require(token0 == TARGET_TOKEN || token1 == TARGET_TOKEN, "Target token not found in pool");

        // Step 3: Approve router to spend WMON
        console2.log("\n--- Step 2: Approving Router ---");
        IERC20(WMON).approve(swapRouterAddress, type(uint256).max);
        console2.log("Approved WMON for router");

        // Step 4: Perform swap
        console2.log("\n--- Step 3: Swapping WMON for Target Token ---");
        uint256 swapAmount = wmonBalanceAfter - wmonBalanceBefore;
        console2.log("Swap amount (WMON):", swapAmount);

        ISwapRouter swapRouter = ISwapRouter(swapRouterAddress);

        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: WMON,
            tokenOut: TARGET_TOKEN,
            fee: fee,
            recipient: deployer,
            deadline: block.timestamp + 300, // 5 minutes
            amountIn: swapAmount,
            amountOutMinimum: 0, // Accept any amount out
            sqrtPriceLimitX96: 0 // No price limit
        });

        uint256 targetTokenBalanceBefore = IERC20(TARGET_TOKEN).balanceOf(deployer);
        console2.log("Target token balance before:", targetTokenBalanceBefore);

        uint256 amountOut = swapRouter.exactInputSingle(swapParams);

        uint256 targetTokenBalanceAfter = IERC20(TARGET_TOKEN).balanceOf(deployer);
        console2.log("Target token balance after:", targetTokenBalanceAfter);
        console2.log("Amount received:", amountOut);
        console2.log("Amount received (calculated):", targetTokenBalanceAfter - targetTokenBalanceBefore);

        // Final balances
        console2.log("\n=== Final Balances ===");
        console2.log("WMON balance:", IWMON(WMON).balanceOf(deployer));
        console2.log("Target token balance:", IERC20(TARGET_TOKEN).balanceOf(deployer));

        // Step 5: Transfer WMON + USDC to recipient
        // console2.log("\n--- Step 4: Transferring WMON + USDC to Recipient ---");
        // console2.log("Recipient address:", RECIPIENT);

        // uint256 wmonBalanceToSend = IWMON(WMON).balanceOf(deployer);
        // uint256 usdcBalanceToSend = IERC20(TARGET_TOKEN).balanceOf(deployer);

        // console2.log("WMON balance to send:", wmonBalanceToSend);
        // console2.log("USDC balance to send:", usdcBalanceToSend);

        // if (wmonBalanceToSend > 0) {
        //     IERC20(WMON).transfer(RECIPIENT, wmonBalanceToSend);
        //     console2.log("Transferred WMON to recipient");
        // }

        // if (usdcBalanceToSend > 0) {
        //     IERC20(TARGET_TOKEN).transfer(RECIPIENT, usdcBalanceToSend);
        //     console2.log("Transferred USDC to recipient");
        // }

        // Verify transfers
        console2.log("\n=== Recipient Balances ===");
        console2.log("Recipient WMON balance:", IWMON(WMON).balanceOf(RECIPIENT));
        console2.log("Recipient USDC balance:", IERC20(TARGET_TOKEN).balanceOf(RECIPIENT));

        // Final deployer balances
        console2.log("\n=== Final Deployer Balances ===");
        console2.log("Deployer WMON balance:", IWMON(WMON).balanceOf(deployer));
        console2.log("Deployer USDC balance:", IERC20(TARGET_TOKEN).balanceOf(deployer));

        vm.stopBroadcast();
    }

    /**
     * @notice Get pool address from environment or find it using factory
     */
    function getPoolAddress() internal view returns (address poolAddress) {
        // Try to get from environment variable first
        try vm.envAddress("POOL_ADDRESS") returns (address addr) {
            return addr;
        } catch {}
        // Try to get from pool key in environment
        try vm.envString("POOL_KEY") returns (string memory poolKey) {
            return getPoolAddressFromKey(poolKey);
        } catch {}
        // Try to find pool using factory
        address factory = getFactoryAddress();
        IUniswapV3Factory uniFactory = IUniswapV3Factory(factory);

        // Try common fee tiers
        uint24[3] memory fees = [uint24(500), uint24(3000), uint24(10000)];

        for (uint256 i = 0; i < fees.length; i++) {
            address pool = uniFactory.getPool(WMON, TARGET_TOKEN, fees[i]);
            if (pool != address(0)) {
                return pool;
            }
        }

        revert("Pool not found. Please set POOL_ADDRESS or POOL_KEY environment variable");
    }

    /**
     * @notice Get pool address from pool key in deployed-addresses.json
     */
    function getPoolAddressFromKey(string memory poolKey) internal view returns (address) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployed-uniswap.json");
        string memory json = vm.readFile(path);
        string memory key = string.concat(".uniswap.pools.", poolKey);
        return json.readAddress(key);
    }

    /**
     * @notice Get SwapRouter address from deployed-addresses.json
     */
    function getSwapRouterAddress() internal view returns (address) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployed-uniswap.json");
        string memory json = vm.readFile(path);
        return json.readAddress(".uniswap.simpleSwapRouter");
    }

    /**
     * @notice Get Factory address from deployed-addresses.json
     */
    function getFactoryAddress() internal view returns (address) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployed-uniswap.json");
        string memory json = vm.readFile(path);
        return json.readAddress(".uniswap.factory");
    }
}

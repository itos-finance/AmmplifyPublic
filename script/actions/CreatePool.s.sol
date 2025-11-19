// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { IUniswapV3Factory } from "v3-core/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "v3-core/interfaces/IUniswapV3Pool.sol";
import { TickMath } from "v3-core/libraries/TickMath.sol";

/**
 * @title CreatePool
 * @notice Script to create a Uniswap V3 pool given a factory address
 * @dev Run with: forge script script/actions/CreatePool.s.sol --broadcast --rpc-url <RPC_URL>
 *
 * Environment variables:
 * - FACTORY_ADDRESS: The Uniswap V3 Factory address (or will read from deployed-addresses.json)
 * - TOKEN_A: First token address
 * - TOKEN_B: Second token address
 * - FEE: Fee tier (500, 3000, or 10000)
 * - INITIAL_TICK: Optional initial tick for pool initialization (defaults to 0 for 1:1 price)
 */
contract CreatePool is Script {
    using stdJson for string;

    // Default sqrt price for 1:1 ratio (tick 0)
    uint160 public constant INIT_SQRT_PRICE_X96 = 1 << 96;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console2.log("============================================================");
        console2.log("CREATING UNISWAP V3 POOL");
        console2.log("============================================================");

        // Load factory address
        address factoryAddr = _getFactoryAddress();
        console2.log("Factory Address:", factoryAddr);

        // Load token addresses
        address tokenA = address(0xE9A9d13cB2deBd3dA91549cE7E462f181B58D13d);
        address tokenB = address(0x75a6952A5a263B960F0c07B5391D3537f5B35aE4);
        console2.log("Token A:", tokenA);
        console2.log("Token B:", tokenB);

        // Load fee tier
        uint24 fee = 3000;
        console2.log("Fee Tier:", fee);

        // Get initial sqrt price (optional, defaults to 1:1)
        uint160 sqrtPriceX96 = _getInitialSqrtPrice();

        // Create the pool
        address poolAddress = _createPool(factoryAddr, tokenA, tokenB, fee, sqrtPriceX96);

        console2.log("============================================================");
        console2.log(unicode"✅ Pool created successfully!");
        console2.log("Pool Address:", poolAddress);
        console2.log("============================================================");

        vm.stopBroadcast();
    }

    /**
     * @notice Get factory address from environment or JSON
     */
    function _getFactoryAddress() internal view returns (address) {
        // Try to get from environment variable first
        try vm.envAddress("FACTORY_ADDRESS") returns (address factoryAddr) {
            if (factoryAddr != address(0)) {
                return factoryAddr;
            }
        } catch {}
        // Fallback to reading from deployed-addresses.json
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployed-addresses.json");
        string memory json = vm.readFile(path);

        if (stdJson.keyExists(json, ".uniswap.factory")) {
            address factoryAddr = stdJson.readAddress(json, ".uniswap.factory");
            require(factoryAddr != address(0), "Factory address not found in deployed-addresses.json");
            return factoryAddr;
        }

        revert(
            "Factory address not found. Set FACTORY_ADDRESS env var or ensure .uniswap.factory exists in deployed-addresses.json"
        );
    }

    /**
     * @notice Get initial sqrt price from environment or use default
     */
    function _getInitialSqrtPrice() internal view returns (uint160) {
        // Try to get initial tick from environment
        try vm.envInt("INITIAL_TICK") returns (int256 tickValue) {
            int24 tick = int24(tickValue);
            // Validate tick is within bounds
            require(tick >= TickMath.MIN_TICK && tick <= TickMath.MAX_TICK, "Initial tick out of bounds");
            return TickMath.getSqrtRatioAtTick(tick);
        } catch {}
        // Default to 1:1 price (tick 0)
        return INIT_SQRT_PRICE_X96;
    }

    /**
     * @notice Create and initialize a Uniswap V3 pool
     * @param factoryAddr The Uniswap V3 Factory address
     * @param tokenA First token address
     * @param tokenB Second token address
     * @param fee Fee tier (500, 3000, or 10000)
     * @param sqrtPriceX96 Initial sqrt price for the pool
     * @return poolAddress The address of the created pool
     */
    function _createPool(
        address factoryAddr,
        address tokenA,
        address tokenB,
        uint24 fee,
        uint160 sqrtPriceX96
    ) internal returns (address poolAddress) {
        require(tokenA != address(0), "Token A cannot be zero address");
        require(tokenB != address(0), "Token B cannot be zero address");
        require(tokenA != tokenB, "Tokens must be different");
        require(fee > 0, "Fee must be greater than 0");

        IUniswapV3Factory factory = IUniswapV3Factory(factoryAddr);

        // Check if pool already exists
        address existingPool = factory.getPool(tokenA, tokenB, fee);
        if (existingPool != address(0)) {
            console2.log(unicode"⚠️  Pool already exists at:", existingPool);
            return existingPool;
        }

        // Ensure token0 < token1 for Uniswap V3
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        console2.log("Creating pool...");
        console2.log("  Token0:", token0);
        console2.log("  Token1:", token1);
        console2.log("  Fee:", fee);
        console2.log("  Initial sqrt price:", sqrtPriceX96);

        // Create the pool
        poolAddress = factory.createPool(token0, token1, fee);
        console2.log("  Pool deployed at:", poolAddress);

        // Initialize the pool
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        pool.initialize(sqrtPriceX96);
        console2.log("  Pool initialized");

        // Verify pool state
        (uint160 currentSqrtPriceX96, int24 currentTick, , , , , ) = pool.slot0();
        console2.log("  Current sqrt price:", currentSqrtPriceX96);
        console2.log("  Current tick:", currentTick);

        return poolAddress;
    }
}

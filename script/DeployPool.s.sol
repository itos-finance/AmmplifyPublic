// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { IUniswapV3Factory } from "v3-core/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "v3-core/interfaces/IUniswapV3Pool.sol";
import { TickMath } from "v3-core/libraries/TickMath.sol";

/**
 * @title DeployPool
 * @notice Script to deploy a new Uniswap V3 pool with specified tokens and fee tier
 * @dev Run with: forge script script/DeployPool.s.sol --broadcast --rpc-url <RPC_URL>
 *
 * Usage:
 * 1. Set FACTORY_ADDRESS below (or leave blank and set via environment variable)
 * 2. Set TOKEN_A and TOKEN_B addresses below
 * 3. Set FEE_TIER below (common values: 500, 3000, 10000)
 * 4. Optionally set INITIAL_TICK for initial price (defaults to 0 for 1:1 price)
 */
contract DeployPool is Script {
    // ============ CONFIGURATION ============
    // Paste your Uniswap factory address here, or leave blank to use FACTORY_ADDRESS env var
    address public constant FACTORY_ADDRESS = address(0x6B5F564339DbAD6b780249827f2198a841FEB7F3);

    // Token addresses - set these to the tokens you want to create a pool for
    address public constant TOKEN_A = address(0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A);
    address public constant TOKEN_B = address(0x754704Bc059F8C67012fEd69BC8A327a5aafb603); // TODO: Set token B address

    // Fee tier - common values: 500 (0.05%), 3000 (0.3%), 10000 (1%)
    uint24 public constant FEE_TIER = 3000; // TODO: Set your desired fee tier

    // Initial tick for pool initialization (defaults to 0 for 1:1 price ratio)
    // You can also set this via INITIAL_TICK environment variable
    int24 public constant INITIAL_TICK = 0;

    // Default sqrt price for 1:1 ratio (tick 0)
    uint160 public constant INIT_SQRT_PRICE_X96 = 1 << 96;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console2.log("============================================================");
        console2.log("DEPLOYING UNISWAP V3 POOL");
        console2.log("============================================================");

        // Get factory address
        address factoryAddr = _getFactoryAddress();
        require(factoryAddr != address(0), "Factory address cannot be zero");
        console2.log("Factory Address:", factoryAddr);

        // Get token addresses
        address tokenA = _getTokenA();
        address tokenB = _getTokenB();
        require(tokenA != address(0), "Token A cannot be zero address");
        require(tokenB != address(0), "Token B cannot be zero address");
        require(tokenA != tokenB, "Tokens must be different");
        console2.log("Token A:", tokenA);
        console2.log("Token B:", tokenB);

        // Get fee tier
        uint24 fee = _getFeeTier();
        require(fee > 0, "Fee tier must be greater than 0");
        console2.log("Fee Tier:", fee);

        // Get initial sqrt price
        uint160 sqrtPriceX96 = _getInitialSqrtPrice();
        console2.log("Initial sqrt price:", sqrtPriceX96);

        // Create the pool
        address poolAddress = _createPool(factoryAddr, tokenA, tokenB, fee, sqrtPriceX96);

        // Increase observation cardinality to 32
        _increaseCardinality(poolAddress);

        console2.log("============================================================");
        console2.log(unicode"✅ Pool deployed successfully!");
        console2.log("Pool Address:", poolAddress);
        console2.log("============================================================");

        vm.stopBroadcast();
    }

    /**
     * @notice Get factory address from constant or environment variable
     */
    function _getFactoryAddress() internal view returns (address) {
        if (FACTORY_ADDRESS != address(0)) {
            return FACTORY_ADDRESS;
        }

        // Try to get from environment variable
        try vm.envAddress("FACTORY_ADDRESS") returns (address factoryAddr) {
            if (factoryAddr != address(0)) {
                return factoryAddr;
            }
        } catch {}
        revert("Factory address not set. Set FACTORY_ADDRESS constant or FACTORY_ADDRESS env var");
    }

    /**
     * @notice Get token A address from constant or environment variable
     */
    function _getTokenA() internal view returns (address) {
        if (TOKEN_A != address(0)) {
            return TOKEN_A;
        }

        // Try to get from environment variable
        try vm.envAddress("TOKEN_A") returns (address tokenAddr) {
            if (tokenAddr != address(0)) {
                return tokenAddr;
            }
        } catch {}
        revert("Token A address not set. Set TOKEN_A constant or TOKEN_A env var");
    }

    /**
     * @notice Get token B address from constant or environment variable
     */
    function _getTokenB() internal view returns (address) {
        if (TOKEN_B != address(0)) {
            return TOKEN_B;
        }

        // Try to get from environment variable
        try vm.envAddress("TOKEN_B") returns (address tokenAddr) {
            if (tokenAddr != address(0)) {
                return tokenAddr;
            }
        } catch {}
        revert("Token B address not set. Set TOKEN_B constant or TOKEN_B env var");
    }

    /**
     * @notice Get fee tier from constant or environment variable
     */
    function _getFeeTier() internal view returns (uint24) {
        // Try to get from environment variable first (takes precedence)
        try vm.envUint("FEE_TIER") returns (uint256 feeValue) {
            if (feeValue > 0 && feeValue <= type(uint24).max) {
                return uint24(feeValue);
            }
        } catch {}
        // Fallback to constant
        if (FEE_TIER > 0) {
            return FEE_TIER;
        }

        revert("Fee tier not set. Set FEE_TIER constant or FEE_TIER env var");
    }

    /**
     * @notice Get initial sqrt price from constant or environment variable
     */
    function _getInitialSqrtPrice() internal view returns (uint160) {
        // Try to get initial tick from environment
        try vm.envInt("INITIAL_TICK") returns (int256 tickValue) {
            int24 tick = int24(tickValue);
            // Validate tick is within bounds
            require(tick >= TickMath.MIN_TICK && tick <= TickMath.MAX_TICK, "Initial tick out of bounds");
            return TickMath.getSqrtRatioAtTick(tick);
        } catch {}
        // Use constant if set to non-zero tick
        if (INITIAL_TICK != 0) {
            require(
                INITIAL_TICK >= TickMath.MIN_TICK && INITIAL_TICK <= TickMath.MAX_TICK,
                "Initial tick out of bounds"
            );
            return TickMath.getSqrtRatioAtTick(INITIAL_TICK);
        }

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

    /**
     * @notice Increase observation cardinality to 32
     * @param poolAddress The pool address
     */
    function _increaseCardinality(address poolAddress) internal {
        console2.log("Increasing observation cardinality to 32...");
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        pool.increaseObservationCardinalityNext(32);
        console2.log("  Cardinality increased to 32");
    }
}

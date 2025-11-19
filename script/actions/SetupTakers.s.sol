// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/console2.sol";
import "forge-std/StdJson.sol";
import { AmmplifyPositions } from "../AmmplifyPositions.s.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IUniswapV3Pool } from "lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { TickMath } from "v3-core/libraries/TickMath.sol";
import { IMaker } from "../../src/interfaces/IMaker.sol";

/**
 * @title SetupTakers
 * @notice Script to set up takers with decreasing liquidity as we move away from current tick
 * @dev Takes 65% of active liquidity at current tick, then reduces by 2% per tick spacing until 0%
 *
 * @dev Example Usage:
 * @dev
 * @dev Basic usage (uses defaults: 65% at current tick, 2% decay per tick spacing):
 * @dev   forge script script/actions/SetupTakers.s.sol:SetupTakers --broadcast --rpc-url $RPC_URL
 * @dev
 * @dev With custom pool (using pool key):
 * @dev   POOL_KEY=WMON_USDC_500 forge script script/actions/SetupTakers.s.sol:SetupTakers --broadcast --rpc-url $RPC_URL
 * @dev
 * @dev With custom pool address:
 * @dev   POOL_ADDRESS=0x... forge script script/actions/SetupTakers.s.sol:SetupTakers --broadcast --rpc-url $RPC_URL
 * @dev
 * @dev With custom percentage and decay:
 * @dev   BASE_PERCENTAGE=70 PERCENTAGE_DECAY=3 forge script script/actions/SetupTakers.s.sol:SetupTakers --broadcast --rpc-url $RPC_URL
 * @dev
 * @dev With custom start tick (instead of current tick):
 * @dev   START_TICK=0 forge script script/actions/SetupTakers.s.sol:SetupTakers --broadcast --rpc-url $RPC_URL
 * @dev
 * @dev Full example with all options:
 * @dev   POOL_KEY=USDC_WETH_3000 BASE_PERCENTAGE=65 PERCENTAGE_DECAY=2 START_TICK=0 forge script script/actions/SetupTakers.s.sol:SetupTakers --broadcast --rpc-url $RPC_URL
 * @dev
 *
 * @dev Environment Variables:
 * @dev   - POOL_ADDRESS: Direct pool address (optional, can use POOL_KEY instead)
 * @dev   - POOL_KEY: Pool key from deployed-addresses.json (default: "USDC_WETH_3000")
 * @dev   - BASE_PERCENTAGE: Starting percentage at current tick (default: 65)
 * @dev   - PERCENTAGE_DECAY: Percentage reduction per tick spacing (default: 2)
 * @dev   - START_TICK: Starting tick for takers (default: current pool tick)
 *
 * @dev How it works:
 * @dev   1. Gets current active liquidity from the pool
 * @dev   2. Creates a maker position to provide liquidity for takers to borrow from
 * @dev   3. Creates takers starting at START_TICK (or current tick):
 * @dev      - At start tick: takes BASE_PERCENTAGE% of active liquidity
 * @dev      - Each tick spacing away: reduces percentage by PERCENTAGE_DECAY%
 * @dev      - Continues until percentage reaches 0%
 * @dev   4. Each taker spans one tick spacing (from targetTick to targetTick + tickSpacing)
 */
contract SetupTakers is AmmplifyPositions {
    using stdJson for string;

    // Configuration for taker distribution
    struct TakerDistributionConfig {
        uint256 basePercentage; // Base percentage at current tick (default 65%)
        uint256 percentageDecay; // Percentage reduction per tick spacing (default 2%)
        uint24 poolFee; // Pool fee tier for tick spacing
    }

    function run() public override {
        // Load deployer addresses from .env file
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console2.log("=== Setting Up Takers Around Current Tick ===");
        console2.log("Deployer address:", deployer);

        // Get pool address from environment (defaults to USDC_WETH_3000)
        address poolAddress;
        try vm.envAddress("POOL_ADDRESS") returns (address addr) {
            poolAddress = addr;
        } catch {
            // Try to get from pool key
            string memory poolKey = vm.envOr("POOL_KEY", string("USDC_WETH_3000"));
            poolAddress = getPoolAddress(poolKey);
        }
        console2.log("Pool Address:", poolAddress);

        // Get current pool state
        printPoolState(poolAddress);
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        (uint160 sqrtPriceX96, int24 currentTick, , , , , ) = pool.slot0();
        uint24 fee = pool.fee();
        int24 tickSpacing = pool.tickSpacing();

        console2.log("Current tick:", currentTick);
        console2.log("Current sqrt price:", sqrtPriceX96);
        console2.log("Pool fee:", fee);
        console2.log("Tick spacing:", vm.toString(tickSpacing));

        // Get configuration from environment or use defaults
        TakerDistributionConfig memory config = TakerDistributionConfig({
            basePercentage: vm.envOr("BASE_PERCENTAGE", uint256(65)), // Default 65%
            percentageDecay: vm.envOr("PERCENTAGE_DECAY", uint256(2)), // Default 2% per tick spacing
            poolFee: fee
        });

        // Get optional start tick (defaults to current tick)
        int24 startTick = int24(vm.envOr("START_TICK", int256(currentTick)));
        if (startTick != currentTick) {
            console2.log("Using custom start tick:", vm.toString(startTick));
        } else {
            console2.log("Using current tick as start:", vm.toString(startTick));
        }

        // Get liquidity in the tick range [startTick, startTick + tickSpacing]
        // This is the range where we'll create the first taker
        int24 tickUpper = startTick + int24(int256(tickSpacing));
        uint128 currentActiveLiquidity = _getLiquidityInTickRange(poolAddress, startTick, tickUpper, currentTick, fee);
        console2.log("Liquidity in tick range:");
        console2.log("  Lower tick:", vm.toString(startTick));
        console2.log("  Upper tick:", vm.toString(tickUpper));
        console2.log("  Liquidity:", currentActiveLiquidity);

        console2.log("\n=== Taker Distribution Configuration ===");
        console2.log("Start tick:", vm.toString(startTick));
        console2.log("Base percentage at start tick:", config.basePercentage, "%");
        console2.log("Percentage decay per tick spacing:", config.percentageDecay, "%");
        console2.log("Tick spacing:", vm.toString(tickSpacing));
        console2.log("Current active liquidity:", currentActiveLiquidity);

        // Get pool tokens
        address token0 = getToken0(poolAddress);
        address token1 = getToken1(poolAddress);
        console2.log("Token0:", token0);
        console2.log("Token1:", token1);

        // Get token decimals from JSON
        uint8 decimals0 = _getTokenDecimals(token0);
        uint8 decimals1 = _getTokenDecimals(token1);
        console2.log("Token0 decimals:", decimals0);
        console2.log("Token1 decimals:", decimals1);

        // First, create makers to provide liquidity for takers to borrow from
        console2.log("\n=== Creating Maker Positions for Takers to Borrow From ===");
        _createMakerPositions(deployer, poolAddress, currentTick, fee, currentActiveLiquidity);

        // Update current active liquidity after creating maker (it will have increased)
        currentActiveLiquidity = pool.liquidity();
        console2.log("Updated active liquidity after maker creation:", currentActiveLiquidity);

        // Calculate total collateral needed using large fixed amounts based on decimals
        // Max takers = 65% / 2% = 32.5, so ~33 takers per side = 66 total + 1 at center = 67
        // Use very large amounts to ensure we have enough collateral
        uint256 totalCollateral0;
        uint256 totalCollateral1;

        if (decimals0 == 6) {
            totalCollateral0 = 100_000_000e6; // 100M tokens with 6 decimals
        } else {
            totalCollateral0 = 100_000_000e18; // 100M tokens with 18 decimals
        }

        if (decimals1 == 6) {
            totalCollateral1 = 100_000_000e6; // 100M tokens with 6 decimals
        } else {
            totalCollateral1 = 100_000_000e18; // 100M tokens with 18 decimals
        }

        console2.log("\n=== Collateralizing Tokens ===");
        console2.log("Total collateral0 needed:", totalCollateral0);
        console2.log("Total collateral1 needed:", totalCollateral1);

        // Collateralize tokens
        collateralizeTaker(deployer, totalCollateral0, totalCollateral1, poolAddress);

        // Set up token approvals
        setupApprovals(type(uint256).max);

        // Create takers starting from current tick, then expanding outward
        console2.log("\n=== Creating Takers ===");
        uint256[] memory takerAssetIds = new uint256[](100); // Max 100 takers
        uint256 assetIdIndex = 0;

        // Create taker at start tick (65% of active liquidity)
        // If pool has no liquidity, we can't calculate based on percentage, so skip takers
        if (currentActiveLiquidity == 0) {
            console2.log("\nWARNING: Pool has no active liquidity!");
            console2.log("Cannot create takers based on percentage of zero liquidity.");
            console2.log("Please add liquidity to the pool first, or create makers manually.");
            console2.log("Skipping taker creation.");
        } else {
            uint256 percentage = config.basePercentage;
            if (percentage > 0) {
                uint128 liquidityToTake = uint128((uint256(currentActiveLiquidity) * percentage) / 100);
                if (liquidityToTake >= 1e12) {
                    // Minimum taker liquidity
                    // Each taker spans one tick spacing: from startTick to startTick + tickSpacing
                    int24 tickLower = getValidTick(startTick, fee);
                    int24 tickUpper = getValidTick(startTick + int24(int256(tickSpacing)), fee);

                    console2.log("\n--- Taker at start tick (tick", vm.toString(startTick), ") ---");
                    console2.log("Percentage:", percentage, "%");
                    console2.log("Liquidity to take:", liquidityToTake);
                    console2.log("Tick range:", vm.toString(tickLower), "to", vm.toString(tickUpper));

                    uint256 assetId = _createTaker(deployer, poolAddress, [tickLower, tickUpper], liquidityToTake, fee);

                    takerAssetIds[assetIdIndex] = assetId;
                    assetIdIndex++;
                }
            }
        }

        // Create takers below start tick (moving left)
        // Only if pool has active liquidity
        if (currentActiveLiquidity > 0) {
            console2.log("\n=== Creating Takers Below Start Tick ===");
            for (uint256 step = 1; step <= 100; step++) {
                int24 tickOffset = int24(int256(step) * int256(tickSpacing));
                int24 targetTick = startTick - tickOffset;
                uint256 percentage = config.basePercentage - (step * config.percentageDecay);

                if (percentage == 0 || percentage > 100) {
                    break; // Stop when we hit 0% or go negative
                }

                uint128 liquidityToTake = uint128((uint256(currentActiveLiquidity) * percentage) / 100);
                if (liquidityToTake < 1e12) {
                    break; // Stop when liquidity is below minimum
                }

                // Each taker spans one tick spacing: from targetTick to targetTick + tickSpacing
                int24 tickLower = getValidTick(targetTick, fee);
                int24 tickUpper = getValidTick(targetTick + int24(int256(tickSpacing)), fee);

                console2.log("\n--- Taker at tick", vm.toString(targetTick), "---");
                console2.log("Steps away from start tick:", step);
                console2.log("Tick offset:", vm.toString(tickOffset));
                console2.log("Percentage:", percentage, "%");
                console2.log("Liquidity to take:", liquidityToTake);
                console2.log("Tick range:", vm.toString(tickLower), "to", vm.toString(tickUpper));

                uint256 assetId = _createTaker(deployer, poolAddress, [tickLower, tickUpper], liquidityToTake, fee);

                takerAssetIds[assetIdIndex] = assetId;
                assetIdIndex++;
            }

            // Create takers above start tick (moving right)
            console2.log("\n=== Creating Takers Above Start Tick ===");
            for (uint256 step = 1; step <= 100; step++) {
                int24 tickOffset = int24(int256(step) * int256(tickSpacing));
                int24 targetTick = startTick + tickOffset;
                uint256 percentage = config.basePercentage - (step * config.percentageDecay);

                if (percentage == 0 || percentage > 100) {
                    break; // Stop when we hit 0% or go negative
                }

                uint128 liquidityToTake = uint128((uint256(currentActiveLiquidity) * percentage) / 100);
                if (liquidityToTake < 1e12) {
                    break; // Stop when liquidity is below minimum
                }

                // Each taker spans one tick spacing: from targetTick to targetTick + tickSpacing
                int24 tickLower = getValidTick(targetTick, fee);
                int24 tickUpper = getValidTick(targetTick + int24(int256(tickSpacing)), fee);

                console2.log("\n--- Taker at tick", vm.toString(targetTick), "---");
                console2.log("Steps away from start tick:", step);
                console2.log("Tick offset:", vm.toString(tickOffset));
                console2.log("Percentage:", percentage, "%");
                console2.log("Liquidity to take:", liquidityToTake);
                console2.log("Tick range:", vm.toString(tickLower), "to", vm.toString(tickUpper));

                uint256 assetId = _createTaker(deployer, poolAddress, [tickLower, tickUpper], liquidityToTake, fee);

                takerAssetIds[assetIdIndex] = assetId;
                assetIdIndex++;
            }
        }

        console2.log("\n=== Taker Setup Complete ===");
        console2.log("Total takers created:", assetIdIndex);
        console2.log("Asset IDs:");
        for (uint256 i = 0; i < assetIdIndex; i++) {
            console2.log("  Taker", i + 1, ":", takerAssetIds[i]);
        }

        vm.stopBroadcast();
    }

    /**
     * @notice Create maker positions to provide liquidity for takers
     */
    function _createMakerPositions(
        address deployer,
        address poolAddress,
        int24 currentTick,
        uint24 fee,
        uint128 currentActiveLiquidity
    ) internal {
        // Calculate a wide range for makers (enough to cover all possible takers)
        // Max distance: 65% / 2% = 32.5 ticks, so ~35 ticks per side = 70 total
        // Use tick spacing to calculate range properly
        int24 totalRange = int24(int256(70) * int256(100)); // Wide range to cover all takers
        int24 tickLower = getValidTick(currentTick - totalRange, fee);
        int24 tickUpper = getValidTick(currentTick + totalRange, fee);

        // Determine maker liquidity
        // If pool has no liquidity, use a large default amount
        // Otherwise use 2x current liquidity or a minimum, whichever is larger
        uint128 makerLiquidity;
        if (currentActiveLiquidity == 0) {
            // Pool has no liquidity, use a large default amount
            // This should be enough for all takers we'll create
            makerLiquidity = 1e18; // Large default liquidity
            console2.log("Pool has no active liquidity, using default maker liquidity");
        } else {
            // Use 2x current liquidity, but ensure it's at least a reasonable amount
            makerLiquidity = currentActiveLiquidity * 2;
            if (makerLiquidity < 1e15) {
                makerLiquidity = 1e15; // Minimum reasonable liquidity
            }
        }

        console2.log("Creating maker position:");
        console2.log("  Tick range:", vm.toString(tickLower), "to", vm.toString(tickUpper));
        console2.log("  Liquidity:", makerLiquidity);

        IMaker maker = IMaker(env.simplexDiamond);
        maker.newMaker(
            deployer,
            poolAddress,
            tickLower,
            tickUpper,
            makerLiquidity,
            true, // compounding
            MIN_SQRT_RATIO,
            MAX_SQRT_RATIO,
            ""
        );

        console2.log("Maker position created successfully");
    }

    /**
     * @notice Create a single taker position
     */
    function _createTaker(
        address deployer,
        address poolAddress,
        int24[2] memory ticks,
        uint128 liquidity,
        uint24 fee
    ) internal returns (uint256 assetId) {
        // Determine freeze price based on position relative to current price
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        (, int24 currentTick, , , , , ) = pool.slot0();

        // If taker is below current price, freeze to prefer token1 (Y)
        // If taker is above current price, freeze to prefer token0 (X)
        uint160 freezeSqrtPriceX96;
        if (ticks[1] < currentTick) {
            // Below current price, freeze to prefer Y
            freezeSqrtPriceX96 = MIN_SQRT_RATIO + 1;
        } else if (ticks[0] > currentTick) {
            // Above current price, freeze to prefer X
            freezeSqrtPriceX96 = MAX_SQRT_RATIO - 1;
        } else {
            // Overlaps current price, use current price
            freezeSqrtPriceX96 = TickMath.getSqrtRatioAtTick(currentTick);
        }

        TakerParams memory params = TakerParams({
            recipient: deployer,
            poolAddr: poolAddress,
            ticks: ticks,
            liquidity: liquidity,
            vaultIndices: [0, 0], // Assuming vault indices 0 for both tokens
            sqrtPriceLimitsX96: [MIN_SQRT_RATIO, MAX_SQRT_RATIO],
            freezeSqrtPriceX96: freezeSqrtPriceX96,
            rftData: ""
        });

        assetId = openTaker(params);
        return assetId;
    }

    /**
     * @notice Get pool address from pool key
     */
    function getPoolAddress(string memory poolKey) internal view returns (address) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployed-addresses.json");
        string memory json = vm.readFile(path);
        string memory key = string.concat(".uniswap.pools.", poolKey);
        return json.readAddress(key);
    }

    /**
     * @notice Get liquidity in a specific tick range
     * @dev If current tick is within the range, returns pool's active liquidity
     * @dev Otherwise, estimates liquidity by checking if ticks are initialized
     */
    function _getLiquidityInTickRange(
        address poolAddress,
        int24 tickLower,
        int24 tickUpper,
        int24 currentTick,
        uint24 fee
    ) internal view returns (uint128) {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);

        // If current tick is within the range, the pool's active liquidity is what's in this range
        if (currentTick >= tickLower && currentTick < tickUpper) {
            return pool.liquidity();
        }

        // If current tick is outside the range, we need to estimate
        // Check if the ticks are initialized (have liquidity)
        // If both ticks are initialized, there might be liquidity in this range
        // But we can't easily calculate it without walking all positions

        // For now, if current tick is not in range, we'll use 0 or try to estimate
        // by checking if ticks have liquidityGross > 0
        try pool.ticks(tickLower) returns (
            uint128 liquidityGrossLower,
            int128,
            uint256,
            uint256,
            int56,
            uint160,
            uint32,
            bool initializedLower
        ) {
            try pool.ticks(tickUpper) returns (
                uint128 liquidityGrossUpper,
                int128,
                uint256,
                uint256,
                int56,
                uint160,
                uint32,
                bool initializedUpper
            ) {
                // If ticks are initialized, there's some liquidity in this range
                // But we can't know exactly how much without more complex calculations
                // For simplicity, if ticks are initialized, assume there's some liquidity
                // Otherwise return 0
                if (initializedLower || initializedUpper) {
                    // Return a conservative estimate - use the smaller of the two gross values
                    // This is not exact but gives us a rough idea
                    return liquidityGrossLower < liquidityGrossUpper ? liquidityGrossLower : liquidityGrossUpper;
                }
            } catch {
                // If we can't read upper tick, assume no liquidity
            }
        } catch {
            // If we can't read lower tick, assume no liquidity
        }
        // Default to 0 if we can't determine
        return 0;
    }

    /**
     * @notice Get token decimals from deployed-addresses.json
     */
    function _getTokenDecimals(address token) internal view returns (uint8) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployed-addresses.json");
        string memory json = vm.readFile(path);

        // Check common tokens
        string[7] memory tokenSymbols = ["USDC", "USDT", "WETH", "WMON", "DAK", "CHOG", "YAKI"];

        for (uint256 i = 0; i < tokenSymbols.length; i++) {
            string memory key = string.concat(".tokens.", tokenSymbols[i], ".address");
            if (stdJson.keyExists(json, key)) {
                address tokenAddr = json.readAddress(key);
                if (tokenAddr == token) {
                    string memory decimalsKey = string.concat(".tokens.", tokenSymbols[i], ".decimals");
                    return uint8(json.readUint(decimalsKey));
                }
            }
        }

        // Default to 18 decimals if not found
        return 18;
    }
}

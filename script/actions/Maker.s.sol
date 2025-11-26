// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/console2.sol";
import "forge-std/StdJson.sol";

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IUniswapV3Pool } from "lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import { AmmplifyPositions } from "../AmmplifyPositions.s.sol";
import { MockERC20 } from "../../test/mocks/MockERC20.sol";

/**
 * @title Maker
 * @notice Generalized script to open a maker position with configurable parameters
 * @dev Run with: forge script script/actions/Maker.s.sol --broadcast --rpc-url <RPC_URL>
 *
 * Configure the variables below with your desired values before running the script.
 */
contract Maker is AmmplifyPositions {
    using stdJson for string;

    function run() public override {
        // ============================================
        // CONFIGURATION - Edit these values as needed
        // ============================================
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address diamondAddress = address(0); // Set to address(0) to use env.simplexDiamond
        address poolAddress = address(0); // Set to address(0) to use env.usdcWethPool
        string memory poolKey = ""; // Set pool key (e.g., "USDC_WETH_3000") to lookup from JSON
        address recipient = address(0); // Set to address(0) to use deployer
        int24 lowTick = -491520; // Set to 0 to calculate from current tick
        int24 highTick = 491520; // Set to 0 to calculate from current tick
        int24 tickRange = 300; // Range around current tick (used if lowTick/highTick are 0)
        uint128 liquidity = 1e6; // Set to 0 to use default calculated value
        bool isCompounding = true; // Whether position is compounding
        uint256 fundToken0Amount = 0; // Amount of token0 to fund
        uint256 fundToken1Amount = 0; // Amount of token1 to fund
        bool useNFT = false; // Whether to use NFT wrapper
        // ============================================

        vm.startBroadcast(deployerPrivateKey);

        console2.log("=== Opening Maker Position ===");
        console2.log("Deployer address:", deployer);

        // Resolve diamond address
        if (diamondAddress == address(0)) {
            diamondAddress = env.simplexDiamond;
            console2.log("Using default diamond address from env:", diamondAddress);
        } else {
            console2.log("Using custom diamond address:", diamondAddress);
        }

        // Resolve pool address
        if (poolAddress == address(0)) {
            if (bytes(poolKey).length > 0) {
                poolAddress = getPoolAddress(poolKey);
                console2.log("Using pool from poolKey:", poolKey, "->", poolAddress);
            } else {
                poolAddress = env.usdcWethPool;
                console2.log("Using default pool address from env:", poolAddress);
            }
        } else {
            console2.log("Using custom pool address:", poolAddress);
        }

        // Resolve recipient
        if (recipient == address(0)) {
            recipient = deployer;
        }
        console2.log("Recipient:", recipient);

        // Get current pool state
        printPoolState(poolAddress);
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        (, int24 currentTick, , , , , ) = pool.slot0();
        uint24 fee = pool.fee();
        console2.log("Current tick from slot0:", currentTick);
        console2.log("Pool fee:", fee);

        // Resolve tick range
        if (lowTick == 0 && highTick == 0) {
            // Calculate from tick range
            lowTick = getValidTick(currentTick - tickRange, fee);
            highTick = getValidTick(currentTick + tickRange, fee);
            console2.log("Calculated LOW_TICK from TICK_RANGE:", lowTick);
            console2.log("Calculated HIGH_TICK from TICK_RANGE:", highTick);
        } else {
            if (lowTick == 0) {
                lowTick = getValidTick(currentTick - tickRange, fee);
                console2.log("Calculated LOW_TICK from TICK_RANGE:", lowTick);
            } else {
                console2.log("Using custom LOW_TICK:", lowTick);
            }
            if (highTick == 0) {
                highTick = getValidTick(currentTick + tickRange, fee);
                console2.log("Calculated HIGH_TICK from TICK_RANGE:", highTick);
            } else {
                console2.log("Using custom HIGH_TICK:", highTick);
            }
        }

        // Resolve liquidity
        if (liquidity == 0) {
            liquidity = 64861280439056 - 10_000;
            console2.log("Using default liquidity:", liquidity);
        } else {
            console2.log("Using custom liquidity:", liquidity);
        }

        console2.log("Is Compounding:", isCompounding);

        // Get token addresses from pool
        address token0 = getToken0(poolAddress);
        address token1 = getToken1(poolAddress);
        console2.log("Token0:", token0);
        console2.log("Token1:", token1);

        // Fund the account with tokens if amounts are specified
        if (fundToken0Amount > 0 || fundToken1Amount > 0) {
            console2.log("=== Funding Account ===");
            console2.log("Token0 amount:", fundToken0Amount);
            console2.log("Token1 amount:", fundToken1Amount);

            // For funding, we need to handle different token types
            // If using mock tokens, use fundAccount helper
            // Otherwise, user should have tokens already
            if (fundToken0Amount > 0) {
                try MockERC20(token0).mint(recipient, fundToken0Amount) {
                    console2.log("Minted token0 to recipient");
                } catch {
                    console2.log("Token0 is not a mock token, assuming user has balance");
                }
            }
            if (fundToken1Amount > 0) {
                try MockERC20(token1).mint(recipient, fundToken1Amount) {
                    console2.log("Minted token1 to recipient");
                } catch {
                    console2.log("Token1 is not a mock token, assuming user has balance");
                }
            }
        }

        // Set up token approvals for diamond contract (approve max to avoid allowance issues)
        console2.log("=== Setting Up Approvals ===");
        IERC20(token0).approve(diamondAddress, type(uint256).max);
        IERC20(token1).approve(diamondAddress, type(uint256).max);
        console2.log("Approved token0 and token1 for diamond");

        // Create maker parameters
        MakerParams memory params = MakerParams({
            recipient: recipient,
            poolAddr: poolAddress,
            lowTick: lowTick,
            highTick: highTick,
            liquidity: liquidity,
            isCompounding: isCompounding,
            minSqrtPriceX96: MIN_SQRT_RATIO,
            maxSqrtPriceX96: MAX_SQRT_RATIO,
            rftData: ""
        });

        console2.log("=== Maker Parameters ===");
        console2.log("Recipient:", params.recipient);
        console2.log("Pool:", params.poolAddr);
        console2.log("Low Tick:", params.lowTick);
        console2.log("High Tick:", params.highTick);
        console2.log("Liquidity:", params.liquidity);
        console2.log("Is Compounding:", params.isCompounding);

        // Temporarily override env.simplexDiamond for the openMakerDirect call
        // We'll need to modify the helper or call directly
        address originalDiamond = env.simplexDiamond;
        env.simplexDiamond = diamondAddress;

        uint256 assetId;
        if (useNFT) {
            console2.log("=== Opening Maker Position with NFT ===");
            (uint256 tokenId, uint256 assetIdResult) = openMakerWithNFT(params);
            assetId = assetIdResult;
            console2.log("NFT Token ID:", tokenId);
        } else {
            console2.log("=== Opening Maker Position Direct ===");
            assetId = openMakerDirect(params);
        }

        // Restore original diamond
        env.simplexDiamond = originalDiamond;

        console2.log("=== Position Created Successfully ===");
        console2.log("Asset ID:", assetId);

        // Check balances after
        uint256 token0Balance = IERC20(token0).balanceOf(recipient);
        uint256 token1Balance = IERC20(token1).balanceOf(recipient);

        console2.log("=== Final Balances ===");
        console2.log("Token0 Balance:", token0Balance);
        console2.log("Token1 Balance:", token1Balance);

        vm.stopBroadcast();
    }

    /**
     * @notice Get pool address from pool key (e.g., "USDC_WETH_3000")
     * @param poolKey The pool key to lookup
     * @return poolAddress The pool address
     */
    function getPoolAddress(string memory poolKey) public view returns (address poolAddress) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployed-uniswap.json");
        string memory json = vm.readFile(path);

        string memory jsonPath = string.concat(".pools.", poolKey);
        poolAddress = json.readAddress(jsonPath);
    }
}

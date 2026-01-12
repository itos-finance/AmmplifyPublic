// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/console2.sol";

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { AmmplifyPositions } from "../AmmplifyPositions.s.sol";
import { INonfungiblePositionManager } from "../../test/mocks/nfpm/interfaces/INonfungiblePositionManager.sol";
import { IUniswapV3Pool } from "lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

/**
 * @title CreateUniV3Position
 * @notice Helper script to create positions directly with Uniswap V3 Nonfungible Position Manager
 * @dev Uses the deployed Uniswap V3 NFPM at address: 0x05c180CB6E6d04452c1ce8D4CF5DcB0A0f052357
 *
 * USAGE EXAMPLES:
 *
 * 1. Basic position creation (default run function):
 *    forge script script/actions/CreateUniV3Position.s.sol --broadcast --rpc-url <RPC_URL>
 *
 * 2. Create custom position with specific parameters:
 *    - Call createCustomPosition() with your desired tick range and token amounts
 *
 * 3. Create full range position (maximum liquidity spread):
 *    - Call createFullRangePosition() with token amounts
 *
 * 4. Create narrow range position (concentrated liquidity):
 *    - Call createNarrowRangePosition() for higher capital efficiency
 *
 * 5. Manage existing positions:
 *    - increaseLiquidity(): Add more tokens to existing position
 *    - decreaseLiquidity(): Remove liquidity from position
 *    - collectFees(): Collect accumulated fees
 *    - burnPosition(): Remove position entirely (must have 0 liquidity)
 *
 * FUNCTIONS AVAILABLE:
 * - createBasicPosition(): Creates position around current price with ±600 tick range
 * - createCustomPosition(): Create position with specific tick range
 * - createFullRangePosition(): Maximum range position
 * - createNarrowRangePosition(): Concentrated liquidity position (±120 ticks)
 * - increaseLiquidity(): Add liquidity to existing position
 * - decreaseLiquidity(): Remove liquidity from position
 * - collectFees(): Collect fees from position
 * - burnPosition(): Burn NFT (requires 0 liquidity)
 * - setupUniswapApprovals(): Approve tokens for Uniswap NFPM
 * - printPositionInfo(): Display detailed position information
 */
contract CreateUniV3Position is AmmplifyPositions {
    /// @notice Error thrown when tick range is invalid
    error InvalidTickRange();

    /**
     * @notice Main execution function - creates a basic USDC/WETH position
     */
    function run() public override {
        // Load deployer addresses from .env file
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console2.log("=== Creating Uniswap V3 Position ===");
        console2.log("Deployer address:", deployer);
        console2.log("Uniswap NFPM address:", env.uniswapNFPM);

        // Get current pool state
        printPoolState(env.usdcWethPool);

        // Fund the account with tokens (if using mock tokens)
        fundAccount(deployer, 1000e6, 1e18); // 1000 USDC, 1 WETH

        // Set up token approvals for Uniswap NFPM
        setupUniswapApprovals(type(uint256).max);

        address recipient = address(0xbe7dC5cC7977ac378ead410869D6c96f1E6C773e);

        // Create a basic position around current price
        uint256 tokenId = createBasicPosition(
            recipient,
            env.usdcToken,
            env.wethToken,
            3000, // 0.3% fee tier
            500e6, // 500 USDC
            0.5e18 // 0.5 WETH
        );

        console2.log("=== Position Created Successfully ===");
        console2.log("NFT Token ID:", tokenId);

        // Verify NFT ownership
        INonfungiblePositionManager nfpm = INonfungiblePositionManager(env.uniswapNFPM);
        address nftOwner = nfpm.ownerOf(tokenId);
        console2.log("NFT Owner:", nftOwner);
        console2.log("Is owned by deployer:", nftOwner == deployer);

        // Get position info
        printPositionInfo(tokenId);

        vm.stopBroadcast();
    }

    /**
     * @notice Create a basic Uniswap V3 position with specified token amounts
     * @param recipient Address to receive the NFT
     * @param token0 Address of token0
     * @param token1 Address of token1
     * @param fee Pool fee tier (500, 3000, or 10000)
     * @param amount0Desired Desired amount of token0
     * @param amount1Desired Desired amount of token1
     * @return tokenId The NFT token ID of the created position
     */
    function createBasicPosition(
        address recipient,
        address token0,
        address token1,
        uint24 fee,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) public returns (uint256 tokenId) {
        INonfungiblePositionManager nfpm = INonfungiblePositionManager(env.uniswapNFPM);

        // Ensure token0 < token1 (Uniswap V3 requirement)
        if (token0 > token1) {
            (token0, token1) = (token1, token0);
            (amount0Desired, amount1Desired) = (amount1Desired, amount0Desired);
        }

        // Get current tick and create a position around it
        (, int24 currentTick, , , , , ) = IUniswapV3Pool(env.usdcWethPool).slot0();

        // Create a position with ±600 ticks around current price (10% range for 0.3% fee)
        int24 tickLower = getValidTick(currentTick - 600, fee);
        int24 tickUpper = getValidTick(currentTick + 600, fee);

        console2.log("=== Position Parameters ===");
        console2.log("Token0:", token0);
        console2.log("Token1:", token1);
        console2.log("Fee:", fee);
        console2.log("Current tick:", currentTick);
        console2.log("Tick lower:", tickLower);
        console2.log("Tick upper:", tickUpper);
        console2.log("Amount0 desired:", amount0Desired);
        console2.log("Amount1 desired:", amount1Desired);

        // Prepare mint parameters
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: fee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            amount0Min: 0, // Accept any amount of token0
            amount1Min: 0, // Accept any amount of token1
            recipient: recipient,
            deadline: block.timestamp + 300 // 5 minutes from now
        });

        // Mint the position
        uint128 liquidity;
        uint256 amount0;
        uint256 amount1;
        (tokenId, liquidity, amount0, amount1) = nfpm.mint(params);

        console2.log("=== Position Minted ===");
        console2.log("Token ID:", tokenId);
        console2.log("Liquidity:", liquidity);
        console2.log("Amount0 used:", amount0);
        console2.log("Amount1 used:", amount1);

        return tokenId;
    }

    /**
     * @notice Create a custom position with specific tick range
     * @param recipient Address to receive the NFT
     * @param token0 Address of token0
     * @param token1 Address of token1
     * @param fee Pool fee tier
     * @param tickLower Lower tick of the position
     * @param tickUpper Upper tick of the position
     * @param amount0Desired Desired amount of token0
     * @param amount1Desired Desired amount of token1
     * @return tokenId The NFT token ID of the created position
     */
    function createCustomPosition(
        address recipient,
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) public returns (uint256 tokenId) {
        INonfungiblePositionManager nfpm = INonfungiblePositionManager(env.uniswapNFPM);

        // Ensure token0 < token1 and adjust parameters accordingly
        if (token0 > token1) {
            (token0, token1) = (token1, token0);
            (amount0Desired, amount1Desired) = (amount1Desired, amount0Desired);
            (tickLower, tickUpper) = (-tickUpper, -tickLower);
        }

        // Validate and adjust ticks
        tickLower = getValidTick(tickLower, fee);
        tickUpper = getValidTick(tickUpper, fee);

        if (tickLower >= tickUpper) revert InvalidTickRange();

        console2.log("=== Custom Position Parameters ===");
        console2.log("Token0:", token0);
        console2.log("Token1:", token1);
        console2.log("Fee:", fee);
        console2.log("Tick lower:", tickLower);
        console2.log("Tick upper:", tickUpper);
        console2.log("Amount0 desired:", amount0Desired);
        console2.log("Amount1 desired:", amount1Desired);

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: fee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            amount0Min: 0,
            amount1Min: 0,
            recipient: recipient,
            deadline: block.timestamp + 300
        });

        uint128 liquidity;
        uint256 amount0;
        uint256 amount1;
        (tokenId, liquidity, amount0, amount1) = nfpm.mint(params);

        console2.log("=== Custom Position Minted ===");
        console2.log("Token ID:", tokenId);
        console2.log("Liquidity:", liquidity);
        console2.log("Amount0 used:", amount0);
        console2.log("Amount1 used:", amount1);

        return tokenId;
    }

    /**
     * @notice Increase liquidity in an existing position
     * @param tokenId The NFT token ID of the position
     * @param amount0Desired Additional amount of token0
     * @param amount1Desired Additional amount of token1
     * @return liquidity The additional liquidity added
     * @return amount0 The amount of token0 used
     * @return amount1 The amount of token1 used
     */
    function increaseLiquidity(
        uint256 tokenId,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) public returns (uint128 liquidity, uint256 amount0, uint256 amount1) {
        INonfungiblePositionManager nfpm = INonfungiblePositionManager(env.uniswapNFPM);

        console2.log("=== Increasing Liquidity ===");
        console2.log("Token ID:", tokenId);
        console2.log("Amount0 desired:", amount0Desired);
        console2.log("Amount1 desired:", amount1Desired);

        INonfungiblePositionManager.IncreaseLiquidityParams memory params = INonfungiblePositionManager
            .IncreaseLiquidityParams({
                tokenId: tokenId,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 300
            });

        (liquidity, amount0, amount1) = nfpm.increaseLiquidity(params);

        console2.log("=== Liquidity Increased ===");
        console2.log("Additional liquidity:", liquidity);
        console2.log("Amount0 used:", amount0);
        console2.log("Amount1 used:", amount1);

        return (liquidity, amount0, amount1);
    }

    /**
     * @notice Decrease liquidity in a position
     * @param tokenId The NFT token ID of the position
     * @param liquidityToRemove Amount of liquidity to remove
     * @return amount0 The amount of token0 received
     * @return amount1 The amount of token1 received
     */
    function decreaseLiquidity(
        uint256 tokenId,
        uint128 liquidityToRemove
    ) public returns (uint256 amount0, uint256 amount1) {
        INonfungiblePositionManager nfpm = INonfungiblePositionManager(env.uniswapNFPM);

        console2.log("=== Decreasing Liquidity ===");
        console2.log("Token ID:", tokenId);
        console2.log("Liquidity to remove:", liquidityToRemove);

        INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
            .DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: liquidityToRemove,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 300
            });

        (amount0, amount1) = nfpm.decreaseLiquidity(params);

        console2.log("=== Liquidity Decreased ===");
        console2.log("Amount0 received:", amount0);
        console2.log("Amount1 received:", amount1);

        return (amount0, amount1);
    }

    /**
     * @notice Collect fees from a position
     * @param tokenId The NFT token ID of the position
     * @param recipient Address to receive the fees
     * @return amount0 The amount of token0 fees collected
     * @return amount1 The amount of token1 fees collected
     */
    function collectFees(uint256 tokenId, address recipient) public returns (uint256 amount0, uint256 amount1) {
        INonfungiblePositionManager nfpm = INonfungiblePositionManager(env.uniswapNFPM);

        console2.log("=== Collecting Fees ===");
        console2.log("Token ID:", tokenId);
        console2.log("Recipient:", recipient);

        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
            tokenId: tokenId,
            recipient: recipient,
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        (amount0, amount1) = nfpm.collect(params);

        console2.log("=== Fees Collected ===");
        console2.log("Amount0 collected:", amount0);
        console2.log("Amount1 collected:", amount1);

        return (amount0, amount1);
    }

    /**
     * @notice Burn a position NFT (position must have 0 liquidity)
     * @param tokenId The NFT token ID to burn
     */
    function burnPosition(uint256 tokenId) public {
        INonfungiblePositionManager nfpm = INonfungiblePositionManager(env.uniswapNFPM);

        console2.log("=== Burning Position ===");
        console2.log("Token ID:", tokenId);

        // First collect any remaining fees
        collectFees(tokenId, msg.sender);

        // Then burn the NFT
        nfpm.burn(tokenId);

        console2.log("Position burned successfully");
    }

    /**
     * @notice Set up token approvals for Uniswap NFPM
     * @param amount The amount to approve (use type(uint256).max for unlimited)
     */
    function setupUniswapApprovals(uint256 amount) public {
        if (env.uniswapNFPM != address(0)) {
            IERC20(env.usdcToken).approve(env.uniswapNFPM, amount);
            IERC20(env.wethToken).approve(env.uniswapNFPM, amount);
            console2.log("Approved Uniswap NFPM contract:", env.uniswapNFPM);
        }
        console2.log("Uniswap token approvals setup complete");
    }

    /**
     * @notice Print detailed position information
     * @param tokenId The NFT token ID to query
     */
    function printPositionInfo(uint256 tokenId) public view {
        INonfungiblePositionManager nfpm = INonfungiblePositionManager(env.uniswapNFPM);

        (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = nfpm.positions(tokenId);

        console2.log("=== Position Info ===");
        console2.log("Token ID:", tokenId);
        console2.log("Nonce:", nonce);
        console2.log("Operator:", operator);
        console2.log("Token0:", token0);
        console2.log("Token1:", token1);
        console2.log("Fee:", fee);
        console2.log("Tick Lower:", tickLower);
        console2.log("Tick Upper:", tickUpper);
        console2.log("Liquidity:", liquidity);
        console2.log("Fee Growth Inside 0:", feeGrowthInside0LastX128);
        console2.log("Fee Growth Inside 1:", feeGrowthInside1LastX128);
        console2.log("Tokens Owed 0:", tokensOwed0);
        console2.log("Tokens Owed 1:", tokensOwed1);
    }

    /**
     * @notice Example function to create a wide range position (full range)
     * @param recipient Address to receive the NFT
     * @param amount0Desired Desired amount of token0
     * @param amount1Desired Desired amount of token1
     * @return tokenId The NFT token ID of the created position
     */
    function createFullRangePosition(
        address recipient,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) public returns (uint256 tokenId) {
        // Full range position uses the minimum and maximum ticks
        int24 tickLower = getValidTick(-887220, 3000); // Near minimum tick
        int24 tickUpper = getValidTick(887220, 3000); // Near maximum tick

        return
            createCustomPosition(
                recipient,
                env.usdcToken,
                env.wethToken,
                3000,
                tickLower,
                tickUpper,
                amount0Desired,
                amount1Desired
            );
    }

    /**
     * @notice Example function to create a narrow range position for concentrated liquidity
     * @param recipient Address to receive the NFT
     * @param amount0Desired Desired amount of token0
     * @param amount1Desired Desired amount of token1
     * @return tokenId The NFT token ID of the created position
     */
    function createNarrowRangePosition(
        address recipient,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) public returns (uint256 tokenId) {
        // Get current tick and create a narrow ±120 tick range (2% range for 0.3% fee)
        (, int24 currentTick, , , , , ) = IUniswapV3Pool(env.usdcWethPool).slot0();

        int24 tickLower = getValidTick(currentTick - 120, 3000);
        int24 tickUpper = getValidTick(currentTick + 120, 3000);

        return
            createCustomPosition(
                recipient,
                env.usdcToken,
                env.wethToken,
                3000,
                tickLower,
                tickUpper,
                amount0Desired,
                amount1Desired
            );
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/console2.sol";

import { IERC721 } from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

import { AmmplifyPositions } from "../AmmplifyPositions.s.sol";
import { UniV3Decomposer } from "../../src/integrations/UniV3Decomposer.sol";
import { INonfungiblePositionManager } from "../../test/mocks/nfpm/interfaces/INonfungiblePositionManager.sol";

/**
 * @title Decompose
 * @notice Script to decompose a Uniswap V3 position into an Ammplify Maker position
 * @dev Similar structure to UniV3Decomposer.t.sol test
 *
 * USAGE:
 *
 * 1. Decompose an existing position:
 *    export POSITION_ID=<token_id>
 *    forge script script/actions/Decompose.s.sol --broadcast --rpc-url <RPC_URL>
 *
 * 2. Or modify the run() function to specify the position ID directly
 */
contract Decompose is AmmplifyPositions {
    /// @notice Error thrown when position is not owned by caller
    error NotPositionOwner();

    /**
     * @notice Main execution function - decomposes a Uniswap V3 position
     */
    function run() public override {
        // Load deployer addresses from .env file
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        // vm.startBroadcast(deployerPrivateKey);

        console2.log("=== Decomposing Uniswap V3 Position ===");
        console2.log("Deployer address:", deployer);

        // Try to load position ID from environment, otherwise use a default
        uint256 positionId = 7529;
        // Verify position exists and ownership
        INonfungiblePositionManager nfpm = INonfungiblePositionManager(0x7197E214c0b767cFB76Fb734ab638E2c192F4E53);
        address owner = nfpm.ownerOf(positionId);

        vm.startPrank(owner);

        // Get position info before decomposition
        (
            ,
            ,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            ,
            ,
            ,

        ) = nfpm.positions(positionId);

        console2.log("=== Position Info ===");
        console2.log("Position ID:", positionId);
        console2.log("Token0:", token0);
        console2.log("Token1:", token1);
        console2.log("Fee:", fee);
        console2.log("Tick Lower:", tickLower);
        console2.log("Tick Upper:", tickUpper);
        console2.log("Liquidity:", liquidity);

        // Set approval for decomposer (similar to test)
        nfpm.setApprovalForAll(0x24d394d7b3BB8ef8f95A6c2363B6fc7Cb2b3CBC3, true);
        console2.log("Approved decomposer to transfer NFT");

        // Set reasonable price bounds - allowing full range to avoid slippage issues
        uint160 minSqrtPriceX96 = MIN_SQRT_RATIO; // Very low price
        uint160 maxSqrtPriceX96 = MAX_SQRT_RATIO; // Very high price

        // Decompose the position
        UniV3Decomposer decomposer = UniV3Decomposer(0x24d394d7b3BB8ef8f95A6c2363B6fc7Cb2b3CBC3);
        uint256 newAssetId = decomposer.decompose(
            positionId,
            false, // isCompounding
            minSqrtPriceX96,
            maxSqrtPriceX96,
            "" // rftData
        );

        console2.log("=== Decomposition Complete ===");
        console2.log("Original Position ID:", positionId);
        console2.log("New Ammplify Asset ID:", newAssetId);
        vm.stopPrank();
        // vm.stopBroadcast();
    }
}

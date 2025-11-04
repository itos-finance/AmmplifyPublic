// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/console2.sol";

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

import { AmmplifyPositions } from "../AmmplifyPositions.s.sol";

/**
 * @title OpenMakerNFT
 * @notice Example script to open a maker position wrapped as an NFT
 * @dev Run with: forge script script/actions/OpenMakerNFT.s.sol --broadcast --rpc-url <RPC_URL>
 */
contract OpenMakerNFT is AmmplifyPositions {
    function run() public override {
        // Load deployer addresses from .env file
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console2.log("=== Opening NFT-Wrapped Maker Position ===");
        console2.log("Deployer address:", deployer);

        // Get current pool state
        printPoolState(env.usdcWethPool);

        // Fund the account with tokens (if using mock tokens)
        // Note: Deployer should already have tokens from DeployTokens.s.sol
        fundAccount(deployer, 1000e6, 1e18); // 1000 USDC, 1 WETH

        // Set up token approvals for diamond and NFT manager contracts
        setupApprovals(type(uint256).max);

        // Create maker parameters for a position around current price
        MakerParams memory params = getDefaultMakerParams(deployer);

        // Adjust liquidity based on available tokens
        params.liquidity = 1e12; // Start with minimum

        console2.log("=== Maker Parameters ===");
        console2.log("Recipient:", params.recipient);
        console2.log("Pool:", params.poolAddr);
        console2.log("Low Tick:", params.lowTick);
        console2.log("High Tick:", params.highTick);
        console2.log("Liquidity:", params.liquidity);
        console2.log("Is Compounding:", params.isCompounding);

        // Open the position using NFT manager (recommended for transferability)
        (uint256 tokenId, uint256 assetId) = openMakerWithNFT(params);

        console2.log("=== NFT Position Created Successfully ===");
        console2.log("NFT Token ID:", tokenId);
        console2.log("Asset ID:", assetId);
        console2.log("NFT Contract:", env.nftManager);

        // Check balances after
        uint256 usdcBalance = IERC20(env.usdcToken).balanceOf(deployer);
        uint256 wethBalance = IERC20(env.wethToken).balanceOf(deployer);

        console2.log("=== Final Balances ===");
        console2.log("USDC Balance:", usdcBalance);
        console2.log("WETH Balance:", wethBalance);

        // Verify NFT ownership
        address nftOwner = IERC721(env.nftManager).ownerOf(tokenId);
        console2.log("NFT Owner:", nftOwner);
        console2.log("Is owned by sender:", nftOwner == msg.sender);

        vm.stopBroadcast();
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { LiqType } from "../walkers/Liq.sol";

/**
 * @title INFTManager
 * @notice Interface for the NFTManager contract that handles Ammplify position NFTs
 */
interface INFTManager {
    // Events
    event AssetMinted(uint256 indexed assetId, uint256 indexed tokenId, address indexed owner);
    event AssetBurned(uint256 indexed assetId, uint256 indexed tokenId, address indexed owner);
    event PositionDecomposed(uint256 indexed positionId, uint256 indexed tokenId, address indexed owner);

    // Custom errors
    error NotAssetOwner(uint256 assetId, address owner, address sender);
    error AssetNotMinted(uint256 tokenId);
    error OnlyMakerFacet(address caller);
    error NotPositionOwner(uint256 positionId, address owner, address sender);
    error NoActiveTokenRequest();

    /**
     * @notice Creates a new maker position and mints an NFT for it in one transaction
     * @param recipient The address to receive the NFT
     * @param poolAddr The address of the pool
     * @param lowTick The lower tick of the liquidity range
     * @param highTick The upper tick of the liquidity range
     * @param liq The amount of liquidity to provide
     * @param isCompounding Whether the position should compound fees
     * @param minSqrtPriceX96 For any price dependent operations, the actual price of the pool must be above this
     * @param maxSqrtPriceX96 For any price dependent operations, the actual price of the pool must be below this
     * @param rftData Data passed during RFT to the payer
     * @return tokenId The ID of the minted NFT
     * @return assetId The ID of the created asset
     */
    function mintNewMaker(
        address recipient,
        address poolAddr,
        int24 lowTick,
        int24 highTick,
        uint128 liq,
        bool isCompounding,
        uint128 minSqrtPriceX96,
        uint128 maxSqrtPriceX96,
        bytes calldata rftData
    ) external returns (uint256 tokenId, uint256 assetId);

    /**
     * @notice Decomposes an existing Uniswap V3 position and mints an NFT for the resulting Ammplify asset
     * @param positionId The ID of the Uniswap V3 position to decompose
     * @param isCompounding Whether the new position should compound fees
     * @param minSqrtPriceX96 For any price dependent operations, the actual price of the pool must be above this
     * @param maxSqrtPriceX96 For any price dependent operations, the actual price of the pool must be below this
     * @param rftData Data passed during RFT to the payer
     * @return tokenId The ID of the minted NFT
     * @return assetId The ID of the created asset
     */
    function decomposeAndMint(
        uint256 positionId,
        bool isCompounding,
        uint128 minSqrtPriceX96,
        uint128 maxSqrtPriceX96,
        bytes calldata rftData
    ) external returns (uint256 tokenId, uint256 assetId);

    /**
     * @notice Burns an NFT and removes the underlying position, collecting fees and returning tokens to the user
     * @param tokenId The ID of the NFT to burn
     * @param minSqrtPriceX96 For any price dependent operations, the actual price of the pool must be above this
     * @param maxSqrtPriceX96 For any price dependent operations, the actual price of the pool must be below this
     * @param rftData Data passed during RFT to the recipient
     * @return token0 The address of token0
     * @return token1 The address of token1
     * @return removedX The amount of token0 removed
     * @return removedY The amount of token1 removed
     * @return fees0 The amount of token0 fees collected
     * @return fees1 The amount of token1 fees collected
     */
    function burnAsset(
        uint256 tokenId,
        uint128 minSqrtPriceX96,
        uint128 maxSqrtPriceX96,
        bytes calldata rftData
    )
        external
        returns (address token0, address token1, uint256 removedX, uint256 removedY, uint256 fees0, uint256 fees1);

    /**
     * @notice Collects fees from a position without burning the NFT
     * @param tokenId The ID of the NFT representing the position
     * @param minSqrtPriceX96 For any price dependent operations, the actual price of the pool must be above this
     * @param maxSqrtPriceX96 For any price dependent operations, the actual price of the pool must be below this
     * @param rftData Data passed during RFT to the recipient
     * @return fees0 The amount of token0 fees collected
     * @return fees1 The amount of token1 fees collected
     */
    function collectFees(
        uint256 tokenId,
        uint128 minSqrtPriceX96,
        uint128 maxSqrtPriceX96,
        bytes calldata rftData
    ) external returns (uint256 fees0, uint256 fees1);

    /**
     * @notice Returns the position information associated with a given token ID
     * @param tokenId The ID of the token that represents the position
     * @return assetId The ID of the underlying asset
     * @return owner The address that owns the position
     * @return poolAddr The address of the pool
     * @return token0 The address of token0
     * @return token1 The address of token1
     * @return lowTick The lower end of the tick range
     * @return highTick The higher end of the tick range
     * @return liqType The liquidity type (MAKER, MAKER_NC, TAKER)
     * @return liquidity The liquidity of the position
     * @return timestamp The timestamp of when the asset was last modified
     */
    function positions(
        uint256 tokenId
    )
        external
        view
        returns (
            uint256 assetId,
            address owner,
            address poolAddr,
            address token0,
            address token1,
            int24 lowTick,
            int24 highTick,
            LiqType liqType,
            uint128 liquidity,
            uint128 timestamp
        );

    /**
     * @notice Returns the asset ID for a given token ID
     * @param tokenId The ID of the token
     * @return The asset ID
     */
    function getAssetId(uint256 tokenId) external view returns (uint256);

    /**
     * @notice Returns the token ID for a given asset ID
     * @param assetId The ID of the asset
     * @return The token ID, or 0 if not minted
     */
    function getTokenId(uint256 assetId) external view returns (uint256);

    /**
     * @notice Returns the total supply of minted NFTs
     * @return The total supply
     */
    function totalSupply() external view returns (uint256);
}

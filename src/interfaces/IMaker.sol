// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

interface IMaker {
    // Errors
    error NotMakerOwner(address owner, address sender);
    error NotMaker(uint256 assetId);

    /// @notice Creates a new maker position.
    /// @param recipient The recipient of the maker position.
    /// @param poolAddr The address of the pool.
    /// @param lowTick The lower tick of the liquidity range.
    /// @param highTick The upper tick of the liquidity range.
    /// @param liq The amount of liquidity to provide.
    /// @param isCompounding Whether the position is compounding.
    /// @param minSqrtPriceX96 For any price dependent operations, the actual price of the pool must be above this.
    /// @param maxSqrtPriceX96 For any price dependent operations, the actual price of the pool must be below this.
    /// @param rftData Data passed during RFT to the payer.
    function newMaker(
        address recipient,
        address poolAddr,
        int24 lowTick,
        int24 highTick,
        uint128 liq,
        bool isCompounding,
        uint160 minSqrtPriceX96,
        uint160 maxSqrtPriceX96,
        bytes calldata rftData
    ) external returns (uint256 _assetId);

    /// @notice Removes a maker position.
    /// @param recipient The recipient of the removed assets.
    /// @param assetId The ID of the asset to remove.
    /// @param minSqrtPriceX96 The minimum sqrt price for the operation.
    /// @param maxSqrtPriceX96 The maximum sqrt price for the operation.
    /// @param rftData Data passed during RFT to the recipient.
    function removeMaker(
        address recipient,
        uint256 assetId,
        uint128 minSqrtPriceX96,
        uint128 maxSqrtPriceX96,
        bytes calldata rftData
    ) external returns (address token0, address token1, uint256 removedX, uint256 removedY);

    /// @notice Collects fees from a maker position.
    /// @param recipient The recipient of the collected fees.
    /// @param assetId The ID of the asset to collect fees from.
    /// @param minSqrtPriceX96 The minimum sqrt price for the operation.
    /// @param maxSqrtPriceX96 The maximum sqrt price for the operation.
    /// @param rftData Data passed during RFT to the recipient.
    function collectFees(
        address recipient,
        uint256 assetId,
        uint160 minSqrtPriceX96,
        uint160 maxSqrtPriceX96,
        bytes calldata rftData
    ) external returns (uint256 fees0, uint256 fees1);
}

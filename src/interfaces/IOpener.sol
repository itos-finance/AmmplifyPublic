// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

interface IOpener {
    error InvalidCallbackSender();
    error SlippageTooHigh();
    error InvalidToken();

    /// @notice Opens a maker position by swapping for the missing token
    /// @param diamond The diamond contract that implements IMaker
    /// @param poolAddr The address of the pool
    /// @param tokenIn The token address that the user is providing
    /// @param amountIn The amount of tokenIn to swap for the other token
    /// @param lowTick The lower tick of the liquidity range
    /// @param highTick The upper tick of the liquidity range
    /// @param isCompounding Whether the position is compounding
    /// @param minSqrtPriceX96 Minimum sqrt price for the operation
    /// @param maxSqrtPriceX96 Maximum sqrt price for the operation
    /// @param amountOutMinimum Minimum amount of output token to receive (slippage protection)
    /// @param amountSwap The expected amount of output token from the exact output swap
    /// @param rftData Data passed during RFT to the payer
    /// @return assetId The ID of the created asset
    function openMaker(
        address diamond,
        address poolAddr,
        address tokenIn,
        uint256 amountIn,
        int24 lowTick,
        int24 highTick,
        bool isCompounding,
        uint160 minSqrtPriceX96,
        uint160 maxSqrtPriceX96,
        uint256 amountOutMinimum,
        uint256 amountSwap,
        bytes calldata rftData
    ) external returns (uint256 assetId);
}

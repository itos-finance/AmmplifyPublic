// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

interface IOpener {
    error InvalidToken();
    error InvalidCallbackSender();
    error SlippageTooHigh();
    error InsufficientOutput(uint256 received, uint256 minimum);

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

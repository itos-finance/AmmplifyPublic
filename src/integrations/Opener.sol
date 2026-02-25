// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { IUniswapV3Pool } from "v3-core/interfaces/IUniswapV3Pool.sol";
import { TickMath } from "v3-core/libraries/TickMath.sol";
import { PoolLib, PoolInfo } from "../Pool.sol";
import { IMaker } from "../interfaces/IMaker.sol";
import { LiquidityAmounts } from "./LiquidityAmounts.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

// solhint-disable func-name-mixedcase
interface ICapricornCLSwapCallback {
    function capricornCLSwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external;
}

/**
 * @title Opener
 * @notice Contract that opens maker positions by swapping for missing tokens
 * @dev Handles exact input swaps and Capricorn callbacks to acquire the token the user doesn't have
 */
contract Opener is ICapricornCLSwapCallback {
    using SafeERC20 for IERC20;

    /// @notice The diamond contract that implements IMaker
    address public immutable DIAMOND;

    /// @notice Error thrown when callback is from wrong pool
    error InvalidCallbackSender();
    /// @notice Error thrown when slippage is too high
    error SlippageTooHigh();
    /// @notice Error thrown when token is not part of the pool
    error InvalidToken();
    /// @notice Error thrown when computed liquidity is zero
    error InsufficientLiquidity();

    /// @notice Swap state stored during callback
    struct SwapState {
        address poolAddr;
        address tokenIn;
        address tokenOut;
        address payer;
        uint256 amountInMaximum;
    }

    /// @notice Temporary storage for swap state during callback
    SwapState private swapState;

    constructor(address diamond) {
        DIAMOND = diamond;
    }

    /**
     * @notice Opens a maker position by swapping for the missing token
     * @param poolAddr The address of the pool
     * @param tokenIn The token address that the user is providing
     * @param amountIn The amount of tokenIn to swap for the other token
     * @param lowTick The lower tick of the liquidity range
     * @param highTick The upper tick of the liquidity range
     * @param minSqrtPriceX96 Minimum sqrt price for the operation
     * @param maxSqrtPriceX96 Maximum sqrt price for the operation
     * @param amountOutMinimum Minimum amount of output token to receive (slippage protection)
     * @param amountSwap The expected amount of output token from the exact output swap
     * @param rftData Data passed during RFT to the payer
     * @return assetId The ID of the created asset
     */
    function openMaker(
        address poolAddr,
        address tokenIn,
        uint256 amountIn,
        int24 lowTick,
        int24 highTick,
        uint160 minSqrtPriceX96,
        uint160 maxSqrtPriceX96,
        uint256 amountOutMinimum,
        uint256 amountSwap,
        bytes calldata rftData
    ) external returns (uint256 assetId) {
        PoolInfo memory pInfo = PoolLib.getPoolInfo(poolAddr);
        address token0 = pInfo.token0;
        address token1 = pInfo.token1;

        if (tokenIn != token0 && tokenIn != token1) revert InvalidToken();

        address tokenOut = tokenIn == token0 ? token1 : token0;

        // Transfer user's tokenIn and swap for tokenOut
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        _swapExactOut(poolAddr, tokenIn, tokenOut, amountSwap, amountIn, amountOutMinimum);

        // Compute liquidity from post-swap balances
        uint128 liq = _computeLiquidity(poolAddr, lowTick, highTick, token0, token1);

        // Approve and open maker position
        _approveAndMint(token0, token1, poolAddr, lowTick, highTick, liq, minSqrtPriceX96, maxSqrtPriceX96, rftData);
        assetId = _lastAssetId;

        // Refund unused amounts to user
        _refundExcess(token0, token1);
    }

    /// @dev Stored after _approveAndMint to avoid stack-too-deep
    uint256 private _lastAssetId;

    /**
     * @notice Capricorn CL swap callback
     * @param amount0Delta The change in token0 balance
     * @param amount1Delta The change in token1 balance
     */
    // solhint-disable-next-line func-name-mixedcase
    function capricornCLSwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external override {
        require(amount0Delta > 0 || amount1Delta > 0, "Invalid swap callback");

        SwapState memory state = swapState;
        require(state.poolAddr != address(0), "Invalid swap state");
        require(msg.sender == state.poolAddr, InvalidCallbackSender());

        uint256 amountToPay = amount0Delta > 0 ? uint256(amount0Delta) : uint256(amount1Delta);
        require(amountToPay <= state.amountInMaximum, SlippageTooHigh());

        if (state.payer == address(this)) {
            IERC20(state.tokenIn).safeTransfer(msg.sender, amountToPay);
        } else {
            IERC20(state.tokenIn).safeTransferFrom(state.payer, msg.sender, amountToPay);
        }
    }

    /* ============ Internal Helpers ============ */

    function _computeLiquidity(
        address poolAddr,
        int24 lowTick,
        int24 highTick,
        address token0,
        address token1
    ) private view returns (uint128 liq) {
        uint160 sqrtPriceX96 = PoolLib.getSqrtPriceX96(poolAddr);
        uint160 sqrtRatioAx96 = TickMath.getSqrtRatioAtTick(lowTick);
        uint160 sqrtRatioBx96 = TickMath.getSqrtRatioAtTick(highTick);

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        liq = LiquidityAmounts.getLiquidityForAmounts(sqrtPriceX96, sqrtRatioAx96, sqrtRatioBx96, balance0, balance1);

        // Reduce liquidity by 2 to help with rounding
        if (liq >= 2) {
            liq -= 2;
        } else {
            liq = 0;
        }

        if (liq == 0) revert InsufficientLiquidity();
    }

    function _approveAndMint(
        address token0,
        address token1,
        address poolAddr,
        int24 lowTick,
        int24 highTick,
        uint128 liq,
        uint160 minSqrtPriceX96,
        uint160 maxSqrtPriceX96,
        bytes calldata rftData
    ) private {
        uint160 sqrtPriceX96 = PoolLib.getSqrtPriceX96(poolAddr);
        uint160 sqrtRatioAx96 = TickMath.getSqrtRatioAtTick(lowTick);
        uint160 sqrtRatioBx96 = TickMath.getSqrtRatioAtTick(highTick);

        (uint256 neededAmount0, uint256 neededAmount1) =
            LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, sqrtRatioAx96, sqrtRatioBx96, liq);

        if (neededAmount0 > 0) IERC20(token0).approve(DIAMOND, neededAmount0);
        if (neededAmount1 > 0) IERC20(token1).approve(DIAMOND, neededAmount1);

        _lastAssetId = IMaker(DIAMOND).newMaker(
            msg.sender, poolAddr, lowTick, highTick, liq, minSqrtPriceX96, maxSqrtPriceX96, rftData
        );
    }

    function _refundExcess(address token0, address token1) private {
        uint256 refund0 = IERC20(token0).balanceOf(address(this));
        uint256 refund1 = IERC20(token1).balanceOf(address(this));
        if (refund0 > 0) IERC20(token0).safeTransfer(msg.sender, refund0);
        if (refund1 > 0) IERC20(token1).safeTransfer(msg.sender, refund1);
    }

    function _swapExactOut(
        address poolAddr,
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 amountInMaximum,
        uint256 amountOutMinimum
    ) private returns (uint256 amountIn) {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddr);
        bool zeroForOne = tokenIn < tokenOut;

        require(amountOut >= amountOutMinimum, SlippageTooHigh());

        swapState = SwapState({
            poolAddr: poolAddr,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            payer: address(this),
            amountInMaximum: amountInMaximum
        });

        (int256 amount0Delta, int256 amount1Delta) = pool.swap(
            address(this),
            zeroForOne,
            -int256(amountOut),
            zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
            ""
        );

        amountIn = uint256(zeroForOne ? amount0Delta : amount1Delta);
        require(amountIn <= amountInMaximum, SlippageTooHigh());

        delete swapState;
    }
}

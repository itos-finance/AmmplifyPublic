// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { IUniswapV3Pool } from "v3-core/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3SwapCallback } from "v3-core/interfaces/callback/IUniswapV3SwapCallback.sol";
import { TickMath } from "v3-core/libraries/TickMath.sol";
import { PoolLib, PoolInfo } from "../Pool.sol";
import { IMaker } from "../interfaces/IMaker.sol";
import { IOpener } from "../interfaces/IOpener.sol";
import { LiquidityAmounts } from "./LiquidityAmounts.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

interface ICapricornCLSwapCallback {
    function capricornCLSwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external;
}

/**
 * @title Opener
 * @notice Contract that opens maker positions by swapping for missing tokens
 * @dev Handles exact input swaps and both Capricorn and Uniswap callbacks to acquire the token the user doesn't have
 */
contract Opener is IOpener, ICapricornCLSwapCallback, IUniswapV3SwapCallback {
    using SafeERC20 for IERC20;

    /// @notice Slippage discount in basis points (e.g., 100 = 1%)
    uint256 public constant LIQUIDITY_DISCOUNT_BPS = 100; // 1% discount
    uint256 private constant BPS_DENOMINATOR = 10000;

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

    /**
     * @notice Opens a maker position by swapping for the missing token
     * @param diamond The diamond contract that implements IMaker
     * @param poolAddr The address of the pool
     * @param tokenIn The token address that the user is providing
     * @param amountIn The amount of tokenIn to swap for the other token
     * @param lowTick The lower tick of the liquidity range
     * @param highTick The upper tick of the liquidity range
     * @param isCompounding Whether the position is compounding
     * @param minSqrtPriceX96 Minimum sqrt price for the operation
     * @param maxSqrtPriceX96 Maximum sqrt price for the operation
     * @param amountOutMinimum Minimum amount of output token to receive (slippage protection)
     * @param amountSwap The expected amount of output token from the exact output swap (based on original liquidity calculation)
     * @param rftData Data passed during RFT to the payer
     * @return assetId The ID of the created asset
     */
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
    ) external returns (uint256 assetId) {
        // Get pool info
        PoolInfo memory pInfo = PoolLib.getPoolInfo(poolAddr);
        address token0 = pInfo.token0;
        address token1 = pInfo.token1;

        // Validate tokenIn is part of the pool
        if (tokenIn != token0 && tokenIn != token1) {
            revert InvalidToken();
        }

        address tokenOut = tokenIn == token0 ? token1 : token0;

        // Calculate expected liquidity and token amounts upfront based on original liquidity calculation
        // This helps us determine the expected ratio when opening the position
        uint160 sqrtPriceX96 = PoolLib.getSqrtPriceX96(poolAddr);
        uint160 sqrtPriceAX96 = TickMath.getSqrtRatioAtTick(lowTick);
        uint160 sqrtPriceBX96 = TickMath.getSqrtRatioAtTick(highTick);

        // Transfer user's tokenIn to this contract
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // Only perform swap if amountSwap > 0 (skip for out-of-range positions that need no swap)
        if (amountSwap > 0) {
            // Perform exact output swap: swap to get exactly amountSwap of tokenOut
            _swapExactOut(poolAddr, tokenIn, tokenOut, pInfo.fee, amountSwap, amountIn, amountOutMinimum, msg.sender);

            // Re-fetch price after swap since it may have moved
            sqrtPriceX96 = PoolLib.getSqrtPriceX96(poolAddr);
        }

        // Get balances after swap
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        uint128 liq = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            sqrtPriceAX96,
            sqrtPriceBX96,
            balance0,
            balance1
        );

        // Apply percentage-based discount to handle slippage and rounding errors
        uint256 discountedLiq = (uint256(liq) * (BPS_DENOMINATOR - LIQUIDITY_DISCOUNT_BPS)) / BPS_DENOMINATOR;
        liq = uint128(discountedLiq);

        // If liquidity is too low, revert
        if (liq == 0) {
            revert("Insufficient liquidity");
        }

        // Approve entire balance to diamond (any unused will be refunded)
        // Using balance instead of neededAmount to avoid rounding issues
        if (balance0 > 0) {
            IERC20(token0).approve(diamond, balance0);
        }
        if (balance1 > 0) {
            IERC20(token1).approve(diamond, balance1);
        }

        // Open the maker position
        assetId = IMaker(diamond).newMaker(
            msg.sender, // recipient of the position
            poolAddr,
            lowTick,
            highTick,
            liq,
            isCompounding,
            minSqrtPriceX96,
            maxSqrtPriceX96,
            rftData
        );

        // Refund unused amounts to user
        uint256 refund0 = IERC20(token0).balanceOf(address(this));
        uint256 refund1 = IERC20(token1).balanceOf(address(this));

        if (refund0 > 0) {
            IERC20(token0).safeTransfer(msg.sender, refund0);
        }
        if (refund1 > 0) {
            IERC20(token1).safeTransfer(msg.sender, refund1);
        }
    }

    /**
     * @notice Internal handler for swap callbacks
     * @param amount0Delta The change in token0 balance
     * @param amount1Delta The change in token1 balance
     */
    function _handleSwapCallback(int256 amount0Delta, int256 amount1Delta) private {
        require(amount0Delta > 0 || amount1Delta > 0, "Invalid swap callback");

        SwapState memory state = swapState;
        require(state.poolAddr != address(0), "Invalid swap state");

        // Verify the callback is from the correct pool
        require(msg.sender == state.poolAddr, InvalidCallbackSender());

        // Determine which token we need to pay
        uint256 amountToPay = amount0Delta > 0 ? uint256(amount0Delta) : uint256(amount1Delta);

        // Verify slippage
        require(amountToPay <= state.amountInMaximum, SlippageTooHigh());

        // Transfer tokens to the pool
        // If payer is this contract, tokens are already here, just transfer
        if (state.payer == address(this)) {
            IERC20(state.tokenIn).safeTransfer(msg.sender, amountToPay);
        } else {
            // Otherwise transfer from payer
            IERC20(state.tokenIn).safeTransferFrom(state.payer, msg.sender, amountToPay);
        }
    }

    /**
     * @notice Capricorn CL swap callback
     * @param amount0Delta The change in token0 balance
     * @param amount1Delta The change in token1 balance
     */
    function capricornCLSwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external override {
        _handleSwapCallback(amount0Delta, amount1Delta);
    }

    /**
     * @notice Uniswap V3 swap callback
     * @param amount0Delta The change in token0 balance
     * @param amount1Delta The change in token1 balance
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external override {
        _handleSwapCallback(amount0Delta, amount1Delta);
    }

    /**
     * @notice Performs an exact output swap
     * @param poolAddr The pool address
     * @param tokenIn The input token
     * @param tokenOut The output token
     * @param amountOut The exact amount of output token to receive
     * @param amountInMaximum Maximum amount of input token to spend
     * @param amountOutMinimum Minimum amount of output token to receive (for validation)
     * @return amountIn The amount of input token spent
     */
    function _swapExactOut(
        address poolAddr,
        address tokenIn,
        address tokenOut,
        uint24 /* fee */,
        uint256 amountOut,
        uint256 amountInMaximum,
        uint256 amountOutMinimum,
        address /* payer */
    ) private returns (uint256 amountIn) {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddr);

        // Determine swap direction
        bool zeroForOne = tokenIn < tokenOut;

        // Verify amountOut meets minimum requirement
        require(amountOut >= amountOutMinimum, SlippageTooHigh());

        // Store swap state for callback (we use amountInMaximum as max since it's exact output)
        swapState = SwapState({
            poolAddr: poolAddr,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            payer: address(this), // tokens are already in this contract
            amountInMaximum: amountInMaximum
        });

        // Execute the swap (exact output - negative amount for exact output)
        (int256 amount0Delta, int256 amount1Delta) = pool.swap(
            address(this), // recipient
            zeroForOne,
            -int256(amountOut), // negative for exact output
            zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1, // no price limit
            "" // no callback data needed, we use storage
        );

        // Calculate amount in (positive delta for the input token)
        amountIn = uint256(zeroForOne ? amount0Delta : amount1Delta);

        // Verify we didn't exceed maximum input
        require(amountIn <= amountInMaximum, SlippageTooHigh());

        // Clear swap state
        delete swapState;
    }
}

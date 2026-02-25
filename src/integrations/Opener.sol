// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { IUniswapV3Pool } from "v3-core/interfaces/IUniswapV3Pool.sol";
import { TickMath } from "v3-core/libraries/TickMath.sol";
import { PoolLib, PoolInfo } from "../Pool.sol";
import { IMaker } from "../interfaces/IMaker.sol";
import { LiquidityAmounts } from "./LiquidityAmounts.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

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
    address public immutable diamond;

    /// @notice Error thrown when callback is from wrong pool
    error InvalidCallbackSender();
    /// @notice Error thrown when slippage is too high
    error SlippageTooHigh();
    /// @notice Error thrown when token is not part of the pool
    error InvalidToken();

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

    constructor(address _diamond) {
        diamond = _diamond;
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
     * @param amountSwap The expected amount of output token from the exact output swap (based on original liquidity calculation)
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

        // Calculate expected liquidity from the amountSwap and the user's tokenIn
        // We'll use amountSwap as the expected output, and calculate what liquidity we can get
        // First, estimate what we'll have after swap: amountSwap of tokenOut
        // We need to determine how much tokenIn will be used in the swap
        // For now, we'll swap to get exactly amountSwap of tokenOut

        // Transfer user's tokenIn to this contract
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // Perform exact output swap: swap to get exactly amountSwap of tokenOut
        _swapExactOut(poolAddr, tokenIn, tokenOut, pInfo.fee, amountSwap, amountIn, amountOutMinimum, msg.sender);

        // Get balances after swap
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        // Calculate liquidity from the token amounts we have
        uint128 liq = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            sqrtPriceAX96,
            sqrtPriceBX96,
            balance0,
            balance1
        );

        // Reduce liquidity by 2 to help with rounding
        if (liq >= 2) {
            liq -= 2;
        } else {
            liq = 0;
        }

        // If liquidity is too low, revert
        if (liq == 0) {
            revert("Insufficient liquidity");
        }

        // Calculate actual amounts needed for this liquidity
        (uint256 neededAmount0, uint256 neededAmount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            sqrtPriceAX96,
            sqrtPriceBX96,
            liq
        );

        // Approve tokens to diamond
        if (neededAmount0 > 0) {
            IERC20(token0).approve(diamond, neededAmount0);
        }
        if (neededAmount1 > 0) {
            IERC20(token1).approve(diamond, neededAmount1);
        }

        // Open the maker position
        assetId = IMaker(diamond).newMaker(
            msg.sender, // recipient of the position
            poolAddr,
            lowTick,
            highTick,
            liq,
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
     * @notice Capricorn CL swap callback
     * @param amount0Delta The change in token0 balance
     * @param amount1Delta The change in token1 balance
     */
    function capricornCLSwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external override {
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

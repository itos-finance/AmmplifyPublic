// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { IPoolManager } from "v4-core/interfaces/IPoolManager.sol";
import { IUnlockCallback } from "v4-core/interfaces/callback/IUnlockCallback.sol";
import { PoolKey } from "v4-core/types/PoolKey.sol";
import { Currency } from "v4-core/types/Currency.sol";
import { BalanceDelta } from "v4-core/types/BalanceDelta.sol";
import { SwapParams } from "v4-core/types/PoolOperation.sol";
import { TickMath } from "v4-core/libraries/TickMath.sol";
import { IMaker } from "../interfaces/IMaker.sol";
import { IView } from "../interfaces/IView.sol";
import { PoolInfo } from "../Pool.sol";
import { LiquidityAmounts } from "./LiquidityAmounts.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Opener
 * @notice Contract that opens maker positions by swapping for missing tokens via Uniswap V4
 * @dev Handles exact output swaps through the V4 PoolManager to acquire the token the user doesn't have
 */
contract Opener is IUnlockCallback {
    using SafeERC20 for IERC20;

    /// @notice The diamond contract that implements IMaker and IView
    address public immutable diamond;

    /// @notice The Uniswap V4 PoolManager
    IPoolManager public immutable poolManager;

    /// @notice Error thrown when callback is not from the PoolManager
    error InvalidCallbackSender();
    /// @notice Error thrown when slippage is too high
    error SlippageTooHigh();
    /// @notice Error thrown when token is not part of the pool
    error InvalidToken();

    /// @notice Swap state stored during callback
    struct SwapState {
        PoolKey poolKey;
        address tokenIn;
        address tokenOut;
        uint256 amountInMaximum;
    }

    /// @notice Temporary storage for swap state during callback
    SwapState private swapState;

    constructor(address _diamond, address _poolManager) {
        diamond = _diamond;
        poolManager = IPoolManager(_poolManager);
    }

    /**
     * @notice Opens a maker position by swapping for the missing token
     * @param poolKey The Uniswap V4 PoolKey for the swap pool
     * @param poolAddr The address of the Ammplify pool on the diamond
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
        PoolKey calldata poolKey,
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
        // Derive token addresses from the PoolKey currencies
        address token0 = Currency.unwrap(poolKey.currency0);
        address token1 = Currency.unwrap(poolKey.currency1);

        // Validate tokenIn is part of the pool
        if (tokenIn != token0 && tokenIn != token1) {
            revert InvalidToken();
        }

        address tokenOut = tokenIn == token0 ? token1 : token0;

        // Get current price from the diamond
        PoolInfo memory pInfo = IView(diamond).getPoolInfo(poolAddr);
        uint160 sqrtPriceX96 = pInfo.sqrtPriceX96;
        uint160 sqrtPriceAX96 = TickMath.getSqrtPriceAtTick(lowTick);
        uint160 sqrtPriceBX96 = TickMath.getSqrtPriceAtTick(highTick);

        // Transfer user's tokenIn to this contract
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // Perform exact output swap via V4 PoolManager
        _swapExactOut(poolKey, tokenIn, tokenOut, amountSwap, amountIn, amountOutMinimum);

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
     * @notice Callback from the PoolManager after unlock
     * @param data Encoded swap parameters
     * @return Encoded BalanceDelta result
     */
    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        require(msg.sender == address(poolManager), InvalidCallbackSender());

        (
            PoolKey memory poolKey,
            bool zeroForOne,
            int256 amountSpecified,
            uint160 sqrtPriceLimitX96
        ) = abi.decode(data, (PoolKey, bool, int256, uint160));

        // Execute the swap
        BalanceDelta delta = poolManager.swap(
            poolKey,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: amountSpecified,
                sqrtPriceLimitX96: sqrtPriceLimitX96
            }),
            ""
        );

        // Settle deltas
        int128 delta0 = delta.amount0();
        int128 delta1 = delta.amount1();

        // For negative deltas (we owe the manager): sync, transfer, settle
        if (delta0 < 0) {
            Currency currency0 = poolKey.currency0;
            poolManager.sync(currency0);
            IERC20(Currency.unwrap(currency0)).safeTransfer(address(poolManager), uint256(uint128(-delta0)));
            poolManager.settle();
        }
        if (delta1 < 0) {
            Currency currency1 = poolKey.currency1;
            poolManager.sync(currency1);
            IERC20(Currency.unwrap(currency1)).safeTransfer(address(poolManager), uint256(uint128(-delta1)));
            poolManager.settle();
        }

        // For positive deltas (manager owes us): take
        if (delta0 > 0) {
            poolManager.take(poolKey.currency0, address(this), uint256(uint128(delta0)));
        }
        if (delta1 > 0) {
            poolManager.take(poolKey.currency1, address(this), uint256(uint128(delta1)));
        }

        return abi.encode(delta);
    }

    /**
     * @notice Performs an exact output swap via V4 PoolManager
     * @param poolKey The V4 PoolKey
     * @param tokenIn The input token
     * @param tokenOut The output token
     * @param amountOut The exact amount of output token to receive
     * @param amountInMaximum Maximum amount of input token to spend
     * @param amountOutMinimum Minimum amount of output token to receive (for validation)
     * @return amountIn The amount of input token spent
     */
    function _swapExactOut(
        PoolKey calldata poolKey,
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 amountInMaximum,
        uint256 amountOutMinimum
    ) private returns (uint256 amountIn) {
        // Determine swap direction
        bool zeroForOne = tokenIn < tokenOut;

        // Verify amountOut meets minimum requirement
        require(amountOut >= amountOutMinimum, SlippageTooHigh());

        // Store swap state for post-swap validation
        swapState = SwapState({
            poolKey: poolKey,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountInMaximum: amountInMaximum
        });

        // Encode swap parameters for the unlock callback
        bytes memory callbackData = abi.encode(
            poolKey,
            zeroForOne,
            int256(amountOut), // positive amountSpecified = exact output
            zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        );

        // Call unlock, which triggers unlockCallback
        bytes memory result = poolManager.unlock(callbackData);
        BalanceDelta delta = abi.decode(result, (BalanceDelta));

        // Calculate amount in (the absolute value of the negative delta for the input token)
        int128 delta0 = delta.amount0();
        int128 delta1 = delta.amount1();
        amountIn = uint256(uint128(zeroForOne ? -delta0 : -delta1));

        // Verify we didn't exceed maximum input
        require(amountIn <= amountInMaximum, SlippageTooHigh());

        // Clear swap state
        delete swapState;
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { IUniswapV3Pool } from "v3-core/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3Factory } from "v3-core/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3SwapCallback } from "v3-core/interfaces/callback/IUniswapV3SwapCallback.sol";
import { TickMath } from "v3-core/libraries/TickMath.sol";
import { LiquidityAmounts } from "./LiquidityAmounts.sol";
import { INonfungiblePositionManager } from "./univ3-periphery/interfaces/INonfungiblePositionManager.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title UniV3PositionOpener
/// @notice Opens a Uniswap V3 NFPM position from a single token by swapping for the other
contract UniV3PositionOpener is IUniswapV3SwapCallback {
    using SafeERC20 for IERC20;

    /// @notice The NonfungiblePositionManager contract
    address public immutable nfpm;

    error InvalidCallbackSender();
    error SlippageTooHigh();
    error InvalidToken();
    error InvalidPool();

    struct SwapState {
        address poolAddr;
        address tokenIn;
        uint256 amountInMaximum;
    }

    SwapState private swapState;

    constructor(address _nfpm) {
        nfpm = _nfpm;
    }

    /// @notice Accept ETH refunds from NFPM.mint()
    receive() external payable {}

    /// @notice Opens a Uniswap V3 position from a single token
    /// @param poolAddr The address of the V3 pool
    /// @param tokenIn The token the user is providing
    /// @param amountIn Total amount of tokenIn to pull from the user
    /// @param lowTick Lower tick of the liquidity range
    /// @param highTick Upper tick of the liquidity range
    /// @param amountSwap Exact amount of the other token to receive from the swap
    /// @param amountOutMinimum Minimum output for slippage protection
    /// @param deadline Deadline for the NFPM mint
    /// @return tokenId The minted NFT position token ID
    function openPosition(
        address poolAddr,
        address tokenIn,
        uint256 amountIn,
        int24 lowTick,
        int24 highTick,
        uint256 amountSwap,
        uint256 amountOutMinimum,
        uint256 deadline
    ) external returns (uint256 tokenId) {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddr);
        address token0 = pool.token0();
        address token1 = pool.token1();
        uint24 fee = pool.fee();

        // Verify pool is deployed by its factory
        address factory = pool.factory();
        if (IUniswapV3Factory(factory).getPool(token0, token1, fee) != poolAddr) {
            revert InvalidPool();
        }

        if (tokenIn != token0 && tokenIn != token1) {
            revert InvalidToken();
        }

        address tokenOut = tokenIn == token0 ? token1 : token0;

        // Record pre-call balances for delta-based accounting
        uint256 balBefore0 = IERC20(token0).balanceOf(address(this));
        uint256 balBefore1 = IERC20(token1).balanceOf(address(this));

        // Pull tokens from user
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // Perform exact-output swap
        _swapExactOut(poolAddr, tokenIn, tokenOut, amountSwap, amountIn);

        // Delta-based accounting: only count tokens received during this call
        uint256 balance0 = IERC20(token0).balanceOf(address(this)) - balBefore0;
        uint256 balance1 = IERC20(token1).balanceOf(address(this)) - balBefore1;

        // Post-swap slippage check on actual received output
        uint256 actualOutput = tokenIn == token0 ? balance1 : balance0;
        if (actualOutput < amountOutMinimum) revert SlippageTooHigh();

        // Calculate liquidity from the balances
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        uint160 sqrtPriceAX96 = TickMath.getSqrtRatioAtTick(lowTick);
        uint160 sqrtPriceBX96 = TickMath.getSqrtRatioAtTick(highTick);

        uint128 liq = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96, sqrtPriceAX96, sqrtPriceBX96, balance0, balance1
        );

        // Reduce liquidity by 2 to avoid rounding issues
        if (liq >= 2) liq -= 2;
        else liq = 0;
        require(liq > 0, "Insufficient liquidity");

        // Derive exact amounts for this liquidity
        (uint256 amount0Desired, uint256 amount1Desired) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96, sqrtPriceAX96, sqrtPriceBX96, liq
        );

        // Approve tokens to NFPM
        if (amount0Desired > 0) IERC20(token0).approve(nfpm, amount0Desired);
        if (amount1Desired > 0) IERC20(token1).approve(nfpm, amount1Desired);

        // Mint the position NFT to the caller
        (tokenId, , , ) = INonfungiblePositionManager(nfpm).mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: fee,
                tickLower: lowTick,
                tickUpper: highTick,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: 0,
                amount1Min: 0,
                recipient: msg.sender,
                deadline: deadline
            })
        );

        // Refund unused tokens (delta-based)
        uint256 refund0 = IERC20(token0).balanceOf(address(this)) - balBefore0;
        uint256 refund1 = IERC20(token1).balanceOf(address(this)) - balBefore1;
        if (refund0 > 0) IERC20(token0).safeTransfer(msg.sender, refund0);
        if (refund1 > 0) IERC20(token1).safeTransfer(msg.sender, refund1);

        // Refund any ETH sent back by NFPM
        if (address(this).balance > 0) {
            (bool success, ) = payable(msg.sender).call{value: address(this).balance}("");
            require(success, "ETH refund failed");
        }
    }

    /// @inheritdoc IUniswapV3SwapCallback
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external override {
        require(amount0Delta > 0 || amount1Delta > 0, "Invalid swap callback");

        SwapState memory state = swapState;
        require(state.poolAddr != address(0), "Invalid swap state");
        require(msg.sender == state.poolAddr, "Invalid callback sender");

        uint256 amountToPay = amount0Delta > 0 ? uint256(amount0Delta) : uint256(amount1Delta);
        require(amountToPay <= state.amountInMaximum, "Slippage too high");

        IERC20(state.tokenIn).safeTransfer(msg.sender, amountToPay);
    }

    function _swapExactOut(
        address poolAddr,
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 amountInMaximum
    ) private returns (uint256 amountIn) {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddr);
        bool zeroForOne = tokenIn < tokenOut;

        swapState = SwapState({
            poolAddr: poolAddr,
            tokenIn: tokenIn,
            amountInMaximum: amountInMaximum
        });

        (int256 amount0Delta, int256 amount1Delta) = pool.swap(
            address(this),
            zeroForOne,
            -int256(amountOut), // negative for exact output in V3
            zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
            ""
        );

        amountIn = uint256(zeroForOne ? amount0Delta : amount1Delta);
        require(amountIn <= amountInMaximum, "Slippage too high");

        delete swapState;
    }
}

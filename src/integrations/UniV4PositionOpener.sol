// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { IPoolManager } from "v4-core/interfaces/IPoolManager.sol";
import { IUnlockCallback } from "v4-core/interfaces/callback/IUnlockCallback.sol";
import { PoolKey } from "v4-core/types/PoolKey.sol";
import { PoolId, PoolIdLibrary } from "v4-core/types/PoolId.sol";
import { Currency } from "v4-core/types/Currency.sol";
import { BalanceDelta } from "v4-core/types/BalanceDelta.sol";
import { SwapParams } from "v4-core/types/PoolOperation.sol";
import { TickMath } from "v4-core/libraries/TickMath.sol";
import { StateLibrary } from "v4-core/libraries/StateLibrary.sol";
import { IPositionManager } from "v4-periphery/interfaces/IPositionManager.sol";
import { Actions } from "v4-periphery/libraries/Actions.sol";
import { IAllowanceTransfer } from "permit2/src/interfaces/IAllowanceTransfer.sol";
import { LiquidityAmounts } from "./LiquidityAmounts.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title UniV4PositionOpener
/// @notice Opens a Uniswap V4 PositionManager position from a single token by swapping for the other
contract UniV4PositionOpener is IUnlockCallback {
    using SafeERC20 for IERC20;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    IPoolManager public immutable POOL_MANAGER;
    IPositionManager public immutable POSM;
    IAllowanceTransfer public immutable PERMIT2;

    error InvalidToken();
    error SlippageTooHigh();
    error InputSlippageTooHigh();
    error NotPoolManager();
    error InsufficientLiquidity();

    struct SwapCallbackData {
        PoolKey key;
        address tokenIn;
        address tokenOut;
        uint256 amountSwap;
        uint256 amountInMaximum;
    }

    constructor(IPoolManager poolManager, IPositionManager posm, IAllowanceTransfer permit2) {
        POOL_MANAGER = poolManager;
        POSM = posm;
        PERMIT2 = permit2;
    }

    /// @notice Opens a Uniswap V4 position from a single token
    /// @param key The PoolKey identifying the V4 pool
    /// @param tokenIn The token the user is providing
    /// @param amountIn Total amount of tokenIn to pull from the user
    /// @param tickLower Lower tick of the liquidity range
    /// @param tickUpper Upper tick of the liquidity range
    /// @param amountSwap Exact amount of the other token to receive from the swap
    /// @param amountOutMinimum Minimum output for slippage protection
    /// @param deadline Deadline for the position mint
    /// @return tokenId The minted NFT position token ID
    function openPosition(
        PoolKey calldata key,
        address tokenIn,
        uint256 amountIn,
        int24 tickLower,
        int24 tickUpper,
        uint256 amountSwap,
        uint256 amountOutMinimum,
        uint256 deadline
    ) external returns (uint256 tokenId) {
        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);

        if (tokenIn != token0 && tokenIn != token1) revert InvalidToken();

        address tokenOut = tokenIn == token0 ? token1 : token0;

        // Record pre-call balances for delta-based accounting
        uint256 balBefore0 = IERC20(token0).balanceOf(address(this));
        uint256 balBefore1 = IERC20(token1).balanceOf(address(this));

        // Pull tokens from user and swap via PoolManager
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        _executeSwap(key, tokenIn, tokenOut, amountSwap, amountIn);

        // Delta-based accounting: only count tokens received during this call
        uint256 balance0 = IERC20(token0).balanceOf(address(this)) - balBefore0;
        uint256 balance1 = IERC20(token1).balanceOf(address(this)) - balBefore1;

        // Post-swap slippage check on actual received output
        uint256 actualOutput = tokenIn == token0 ? balance1 : balance0;
        if (actualOutput < amountOutMinimum) revert SlippageTooHigh();

        // Compute liquidity and mint
        (uint128 liq, uint256 amount0Needed, uint256 amount1Needed) =
            _computeLiquidityAndAmounts(key, tickLower, tickUpper, balance0, balance1);

        tokenId = _mintPosition(key, tickLower, tickUpper, liq, amount0Needed, amount1Needed, deadline);

        // Refund unused tokens (delta-based)
        _refundExcess(token0, token1, balBefore0, balBefore1);
    }

    /// @inheritdoc IUnlockCallback
    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        if (msg.sender != address(POOL_MANAGER)) revert NotPoolManager();

        SwapCallbackData memory swapData = abi.decode(data, (SwapCallbackData));
        bool zeroForOne = swapData.tokenIn < swapData.tokenOut;

        BalanceDelta delta = POOL_MANAGER.swap(
            swapData.key,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: int256(swapData.amountSwap),
                sqrtPriceLimitX96: zeroForOne
                    ? TickMath.MIN_SQRT_PRICE + 1
                    : TickMath.MAX_SQRT_PRICE - 1
            }),
            ""
        );

        // Input-side slippage guard
        int128 delta0 = delta.amount0();
        int128 delta1 = delta.amount1();
        uint256 inputConsumed = uint256(int256(-(zeroForOne ? delta0 : delta1)));
        if (inputConsumed > swapData.amountInMaximum) revert InputSlippageTooHigh();

        // Settle input token (negative delta = we owe)
        _settleIfNegative(swapData.key.currency0, delta0);
        _settleIfNegative(swapData.key.currency1, delta1);

        // Take output token (positive delta = pool owes us)
        _takeIfPositive(swapData.key.currency0, delta0);
        _takeIfPositive(swapData.key.currency1, delta1);

        return "";
    }

    /* ============ Internal Helpers ============ */

    function _executeSwap(
        PoolKey calldata key,
        address tokenIn,
        address tokenOut,
        uint256 amountSwap,
        uint256 amountInMaximum
    ) private {
        bytes memory swapData = abi.encode(SwapCallbackData({
            key: key,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountSwap: amountSwap,
            amountInMaximum: amountInMaximum
        }));
        POOL_MANAGER.unlock(swapData);
    }

    function _computeLiquidityAndAmounts(
        PoolKey calldata key,
        int24 tickLower,
        int24 tickUpper,
        uint256 balance0,
        uint256 balance1
    ) private view returns (uint128 liq, uint256 amount0Needed, uint256 amount1Needed) {
        (uint160 sqrtPriceX96, , , ) = POOL_MANAGER.getSlot0(key.toId());
        uint160 sqrtRatioAx96 = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtRatioBx96 = TickMath.getSqrtPriceAtTick(tickUpper);

        liq = LiquidityAmounts.getLiquidityForAmounts(sqrtPriceX96, sqrtRatioAx96, sqrtRatioBx96, balance0, balance1);

        if (liq >= 2) liq -= 2;
        else liq = 0;
        if (liq == 0) revert InsufficientLiquidity();

        (amount0Needed, amount1Needed) =
            LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, sqrtRatioAx96, sqrtRatioBx96, liq);
    }

    function _mintPosition(
        PoolKey calldata key,
        int24 tickLower,
        int24 tickUpper,
        uint128 liq,
        uint256 amount0Needed,
        uint256 amount1Needed,
        uint256 deadline
    ) private returns (uint256 tokenId) {
        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);

        _ensureApproval(token0, address(PERMIT2), amount0Needed);
        _ensureApproval(token1, address(PERMIT2), amount1Needed);

        PERMIT2.approve(token0, address(POSM), uint160(amount0Needed + 1), uint48(block.timestamp + 3600));
        PERMIT2.approve(token1, address(POSM), uint160(amount1Needed + 1), uint48(block.timestamp + 3600));

        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(
            key, tickLower, tickUpper, uint256(liq),
            uint128(amount0Needed + 1), uint128(amount1Needed + 1),
            msg.sender, bytes("")
        );
        params[1] = abi.encode(key.currency0, key.currency1);

        tokenId = POSM.nextTokenId();
        POSM.modifyLiquidities(abi.encode(actions, params), deadline);
    }

    function _refundExcess(address token0, address token1, uint256 balBefore0, uint256 balBefore1) private {
        uint256 refund0 = IERC20(token0).balanceOf(address(this)) - balBefore0;
        uint256 refund1 = IERC20(token1).balanceOf(address(this)) - balBefore1;
        if (refund0 > 0) IERC20(token0).safeTransfer(msg.sender, refund0);
        if (refund1 > 0) IERC20(token1).safeTransfer(msg.sender, refund1);
    }

    function _settleIfNegative(Currency currency, int128 delta) private {
        if (delta < 0) {
            POOL_MANAGER.sync(currency);
            IERC20(Currency.unwrap(currency)).safeTransfer(address(POOL_MANAGER), uint256(int256(-delta)));
            POOL_MANAGER.settle();
        }
    }

    function _takeIfPositive(Currency currency, int128 delta) private {
        if (delta > 0) {
            POOL_MANAGER.take(currency, address(this), uint256(int256(delta)));
        }
    }

    function _ensureApproval(address token, address spender, uint256 amount) private {
        if (IERC20(token).allowance(address(this), spender) < amount) {
            IERC20(token).approve(spender, type(uint256).max);
        }
    }
}

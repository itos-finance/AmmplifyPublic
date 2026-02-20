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

    IPoolManager public immutable poolManager;
    IPositionManager public immutable posm;
    IAllowanceTransfer public immutable permit2;

    error InvalidToken();
    error SlippageTooHigh();
    error NotPoolManager();

    struct SwapCallbackData {
        PoolKey key;
        address tokenIn;
        address tokenOut;
        uint256 amountSwap;
    }

    constructor(IPoolManager _poolManager, IPositionManager _posm, IAllowanceTransfer _permit2) {
        poolManager = _poolManager;
        posm = _posm;
        permit2 = _permit2;
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

        // Pull tokens from user
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // Phase A: Swap via PoolManager unlock
        bytes memory swapData = abi.encode(SwapCallbackData({
            key: key,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountSwap: amountSwap
        }));
        poolManager.unlock(swapData);

        // Verify slippage on output
        uint256 outputBalance = IERC20(tokenOut).balanceOf(address(this));
        require(outputBalance >= amountOutMinimum, "Slippage too high");

        // Calculate liquidity from resulting balances
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(key.toId());
        uint160 sqrtPriceAX96 = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtPriceBX96 = TickMath.getSqrtPriceAtTick(tickUpper);

        uint128 liq = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96, sqrtPriceAX96, sqrtPriceBX96, balance0, balance1
        );

        // Reduce liquidity by 2 to avoid rounding issues
        if (liq >= 2) liq -= 2;
        else liq = 0;
        require(liq > 0, "Insufficient liquidity");

        (uint256 amount0Needed, uint256 amount1Needed) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96, sqrtPriceAX96, sqrtPriceBX96, liq
        );

        // Phase B: Mint position via PositionManager
        // Approve tokens to Permit2
        _ensureApproval(token0, address(permit2), amount0Needed);
        _ensureApproval(token1, address(permit2), amount1Needed);

        // Set Permit2 allowance for PositionManager
        permit2.approve(token0, address(posm), uint160(amount0Needed + 1), uint48(block.timestamp + 3600));
        permit2.approve(token1, address(posm), uint160(amount1Needed + 1), uint48(block.timestamp + 3600));

        // Encode mint actions: MINT_POSITION + SETTLE_PAIR
        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION),
            uint8(Actions.SETTLE_PAIR)
        );

        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(
            key,
            tickLower,
            tickUpper,
            uint256(liq),
            uint128(amount0Needed + 1),
            uint128(amount1Needed + 1),
            msg.sender,
            bytes("")
        );
        params[1] = abi.encode(key.currency0, key.currency1);

        bytes memory unlockData = abi.encode(actions, params);
        tokenId = posm.nextTokenId();
        posm.modifyLiquidities(unlockData, deadline);

        // Refund unused tokens
        uint256 refund0 = IERC20(token0).balanceOf(address(this));
        uint256 refund1 = IERC20(token1).balanceOf(address(this));
        if (refund0 > 0) IERC20(token0).safeTransfer(msg.sender, refund0);
        if (refund1 > 0) IERC20(token1).safeTransfer(msg.sender, refund1);
    }

    /// @inheritdoc IUnlockCallback
    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert NotPoolManager();

        SwapCallbackData memory swapData = abi.decode(data, (SwapCallbackData));

        bool zeroForOne = swapData.tokenIn < swapData.tokenOut;

        // V4: positive amountSpecified = exact output
        SwapParams memory swapParams = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: int256(swapData.amountSwap),
            sqrtPriceLimitX96: zeroForOne
                ? TickMath.MIN_SQRT_PRICE + 1
                : TickMath.MAX_SQRT_PRICE - 1
        });

        BalanceDelta delta = poolManager.swap(swapData.key, swapParams, "");

        // V4 delta convention: negative = must settle (pay to pool), positive = can take (receive from pool)
        int128 delta0 = delta.amount0();
        int128 delta1 = delta.amount1();

        // Settle input token (pay to pool) — negative delta means we owe
        if (delta0 < 0) {
            Currency currency0 = swapData.key.currency0;
            poolManager.sync(currency0);
            IERC20(Currency.unwrap(currency0)).safeTransfer(address(poolManager), uint256(int256(-delta0)));
            poolManager.settle();
        }

        if (delta1 < 0) {
            Currency currency1 = swapData.key.currency1;
            poolManager.sync(currency1);
            IERC20(Currency.unwrap(currency1)).safeTransfer(address(poolManager), uint256(int256(-delta1)));
            poolManager.settle();
        }

        // Take output token — positive delta means pool owes us
        if (delta0 > 0) {
            poolManager.take(swapData.key.currency0, address(this), uint256(int256(delta0)));
        }

        if (delta1 > 0) {
            poolManager.take(swapData.key.currency1, address(this), uint256(int256(delta1)));
        }

        return "";
    }

    function _ensureApproval(address token, address spender, uint256 amount) private {
        if (IERC20(token).allowance(address(this), spender) < amount) {
            IERC20(token).approve(spender, type(uint256).max);
        }
    }
}

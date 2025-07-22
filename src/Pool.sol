// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { IUniswapV3PoolImmutables } from "v3-core/contracts/interfaces/pool/IUniswapV3PoolImmutables.sol";
import { IUniswapV3Pool } from "v3-core/contracts/interfaces/uniswap/IUniswapV3Pool.sol";
import { TickMath } from "v3-core/contracts/libraries/TickMath.sol";
import { SqrtPriceMath } from "v3-core/contracts/libraries/SqrtPriceMath.sol";
import { msb } from "./tree/BitMath.sol";
import { Node } from "./visitors/Node.sol";
import { Key } from "./tree/Key.sol";
import { TreeTickLib } from "./tree/Tick.sol";

// In memory struct derived from a pool
struct PoolInfo {
    address poolAddr;
    address token0;
    address token1;
    uint24 tickSpacing;
    uint24 treeWidth;
}

using PoolInfoImpl for PoolInfo global;

library PoolInfoImpl {
    function tokens(PoolInfo memory self) internal view returns (address[] memory) {
        address[] memory tokens = new address[](2);
        tokens[0] = self.token0;
        tokens[1] = self.token1;
        return tokens;
    }

    function treeTick(PoolInfo memory self, int24 tick) internal view returns (uint24 treeTick) {
        return TreeTickLib.tickToTreeIndex(tick, self.treeWidth, self.tickSpacing);
    }
}

/// Internal storage bookkeeping for pools.
struct Pool {
    mapping(Key key => Node) nodes;
}

/// A helper library for accessing the underlying pool's ABI.
/// @dev This will have to change for each pool we integrate with.
library PoolLib {
    function getPoolInfo(address pool) internal view returns (PoolInfo memory pInfo) {
        pInfo.poolAddr = pool;
        IUniswapV3PoolImmutables poolImmutables = IUniswapV3PoolImmutables(pool);
        pInfo.token0 = poolImmutables.token0();
        pInfo.token1 = poolImmutables.token1();

        pInfo.tickSpacing = poolImmutables.tickSpacing();
        uint24 tickSpacing = uint24(pInfo.tickSpacing);
        uint24 numTicks = uint24(TickMath.MAX_TICK) + uint24(-TickMath.MIN_TICK);
        uint24 treeIndices = numTicks / tickSpacing + (numTicks % tickSpacing == 0 ? 0 : 1);
        // We find the first power of two that is greater than the number of tree indices to be the width.
        pInfo.treeWidth = msb(treeIndices) << 1;
        return pInfo;
    }

    /// Get the current sqrt price of the pool.
    function getSqrtPriceX96(address pool) internal view returns (uint160 sqrtPriceX96) {
        IUniswapV3Pool poolContract = IUniswapV3Pool(pool);
        (, int24 currentTick, , , , , ) = poolContract.slot0();
        sqrtPriceX96 = TickMath.getSqrtRatioAtTick(currentTick);
    }

    /// This assumes the position in the pool still exists, and queries how much fees are owed.
    function getFees(address pool, int24 lowerTick, int24 upperTick) internal view returns (uint128 x, uint128 y) {
        IUniswapV3Pool poolContract = IUniswapV3Pool(pool);
        bytes32 myKey = keccak256(abi.encodePacked(address(this), lowerTick, upperTick));
        uint128 liq;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        // The x and y here are the fees accumulated since the last poke, before the check was updated.
        (liq, feeGrowthInside0LastX128, feeGrowthInside1LastX128, x, y) = poolContract.positions(myKey);
        (uint256 feeGrowthInside0NowX128, uint256 feeGrowthInside1NowX128) = getInsideFees(pool, lowerTick, upperTick);
        unchecked {
            x += FullMath.mulX128(liq, feeGrowthInside0NowX128 - feeGrowthInside0LastX128, false);
            y += FullMath.mulX128(liq, feeGrowthInside1NowX128 - feeGrowthInside1LastX128, false);
        }
    }

    /// Get the fee checkpoint for a certain range. Does NOT assume the position exists.
    function getInsideFees(
        address pool,
        int24 lowerTick,
        int24 upperTick
    ) internal view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
        IUniswapV3Pool poolContract = IUniswapV3Pool(pool);
        (, int24 currentTick, , , , , ) = poolContract.slot0();
        (, , uint256 lowerFeeGrowthOutside0X128, uint256 lowerFeeGrowthOutside1X128, , , ) = poolContract.ticks(
            lowerTick
        );
        (, , uint256 upperFeeGrowthOutside0X128, uint256 upperFeeGrowthOutside1X128, , , ) = poolContract.ticks(
            upperTick
        );

        unchecked {
            if (currentTick < lowerTick) {
                feeGrowthInside0X128 = lowerFeeGrowthOutside0X128 - upperFeeGrowthOutside0X128;
                feeGrowthInside1X128 = lowerFeeGrowthOutside1X128 - upperFeeGrowthOutside1X128;
            } else if (currentTick >= upperTick) {
                feeGrowthInside0X128 = upperFeeGrowthOutside0X128 - lowerFeeGrowthOutside0X128;
                feeGrowthInside1X128 = upperFeeGrowthOutside1X128 - lowerFeeGrowthOutside1X128;
            } else {
                uint256 feeGrowthGlobal0X128 = poolContract.feeGrowthGlobal0X128();
                uint256 feeGrowthGlobal1X128 = poolContract.feeGrowthGlobal1X128();
                feeGrowthInside0X128 = feeGrowthGlobal0X128 - lowerFeeGrowthOutside0X128 - upperFeeGrowthOutside0X128;
                feeGrowthInside1X128 = feeGrowthGlobal1X128 - lowerFeeGrowthOutside1X128 - upperFeeGrowthOutside1X128;
            }
        }
    }

    /// Answers how much liquidity we can add from the given amounts for the given range, and
    /// how much is leftover.
    /// @dev Rounds liq down.
    function getAssignableLiq(
        address pool,
        int24 lowTick,
        int24 highTick,
        uint128 x,
        uint128 y,
        uint160 sqrtPriceX96
    ) internal view returns (uint128 assignableLiq, uint128 leftoverX, uint128 leftoverY) {
        IUniswapV3Pool poolContract = IUniswapV3Pool(pool);
        uint160 lowSqrtPriceX96 = TickMath.getSqrtRatioAtTick(lowTick);
        uint160 highSqrtPriceX96 = TickMath.getSqrtRatioAtTick(highTick);

        if (sqrtPriceX96 < lowSqrtPriceX96) {
            // We are below the range, so we can only add liquidity for token0.
            leftoverY = y;
            if (x == 0) {
                return (0, leftoverX, leftoverY);
            }
            // Round up to round liq down.
            uint256 unitX128 = SqrtPriceMath.getAmount0Delta(lowSqrtPriceX96, highSqrtPriceX96, 1 << 128, true);
            assignableLiq = uint128((uint256(x) << 128) / unitX128);
            // No leftover x, perhaps lose x dust here but it's okay.
        } else if (sqrtPriceX96 >= highSqrtPriceX96) {
            // We are above the range, so we can only add liquidity for token1.
            leftoverX = x;
            if (y == 0) {
                return (0, leftoverX, leftoverY);
            }
            // Round up to round liq down.
            uint256 unitX128 = SqrtPriceMath.getAmount1Delta(lowSqrtPriceX96, highSqrtPriceX96, 1 << 128, true);
            assignableLiq = uint128((uint256(y) << 128) / unitX128);
            // No leftover y, perhaps lose y dust here but it's okay.
        } else {
            uint160 currentSqrtPriceX96 = TickMath.getSqrtRatioAtTick(currentTick);
            uint256 reqXUnitX128 = SqrtPriceMath.getAmount0Delta(currentSqrtPriceX96, highSqrtPriceX96, 1 << 128, true);
            uint256 reqYUnitX128 = SqrtPriceMath.getAmount1Delta(lowSqrtPriceX96, currentSqrtPriceX96, 1 << 128, true);
            uint256 xLiq = (uint256(x) << 128) / reqXUnitX128;
            uint256 yLiq = (uint256(y) << 128) / reqYUnitX128;
            if (xLiq == yLiq) {
                assignableLiq = uint128(xLiq);
            } else if (xLiq < yLiq) {
                assignableLiq = uint128(xLiq);
                leftoverY = y - FullMath.mulX128(xLiq, reqYUnitX128, true);
            } else {
                assignableLiq = uint128(yLiq);
                leftoverX = x - FullMath.mulX128(yLiq, reqXUnitX128, true);
            }
        }
    }

    /// Get the amounts of each token for the liquidity in the given range.
    function getAmounts(
        uint160 sqrtPriceX96,
        int24 lowTick,
        int24 highTick,
        uint128 liq,
        bool roundUp
    ) internal view returns (uint256 x, uint256 y) {
        uint160 lowSqrtPriceX96 = TickMath.getSqrtRatioAtTick(lowTick);
        uint160 highSqrtPriceX96 = TickMath.getSqrtRatioAtTick(highTick);

        if (liq == 0) {
            return (0, 0);
        }

        if (sqrtPriceX96 < lowSqrtPriceX96) {
            // We are below the range, so we can only get token0.
            x = SqrtPriceMath.getAmount0Delta(lowSqrtPriceX96, highSqrtPriceX96, liq, roundUp);
            y = 0;
        } else if (sqrtPriceX96 >= highSqrtPriceX96) {
            // We are above the range, so we can only get token1.
            x = 0;
            y = SqrtPriceMath.getAmount1Delta(lowSqrtPriceX96, highSqrtPriceX96, liq, roundUp);
        } else {
            // We are in the range, so we can get both tokens.
            x = SqrtPriceMath.getAmount0Delta(sqrtPriceX96, highSqrtPriceX96, liq, roundUp);
            y = SqrtPriceMath.getAmount1Delta(lowSqrtPriceX96, sqrtPriceX96, liq, roundUp);
        }
    }
}

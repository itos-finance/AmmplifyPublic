// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { IUniswapV3PoolImmutables } from "v3-core/interfaces/pool/IUniswapV3PoolImmutables.sol";
import { IUniswapV3PoolDerivedState } from "v3-core/interfaces/pool/IUniswapV3PoolDerivedState.sol";
import { IUniswapV3Pool } from "v3-core/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3Factory } from "v3-core/interfaces/IUniswapV3Factory.sol";
import { TickMath } from "v4-core/libraries/TickMath.sol";
import { FullMath } from "./FullMath.sol";
import { SqrtPriceMath } from "v4-core/libraries/SqrtPriceMath.sol";
import { Node } from "./walkers/Node.sol";
import { Key } from "./tree/Key.sol";
import { TreeTickLib } from "./tree/Tick.sol";
import { TransientSlot } from "openzeppelin-contracts/contracts/utils/TransientSlot.sol";
import { SafeCast } from "Commons/Math/Cast.sol";
import { Store } from "./Store.sol";
import { FeeLib } from "./Fee.sol";

import {tuint256} from "transient-goodies/TransientPrimitives.sol";

// In memory struct derived from a pool
struct PoolInfo {
    // Immutables
    address poolAddr;
    address token0;
    address token1;
    int24 tickSpacing;
    uint24 fee;
    uint24 treeWidth;
    // Price info
    uint160 sqrtPriceX96; // Current price of the pool
    int24 currentTick; // Current tick of the pool
}

using PoolInfoImpl for PoolInfo global;

library PoolInfoImpl {
    function tokens(PoolInfo memory self) internal pure returns (address[] memory) {
        address[] memory _tokens = new address[](2);
        _tokens[0] = self.token0;
        _tokens[1] = self.token1;
        return _tokens;
    }

    function treeTick(PoolInfo memory self, int24 tick) internal pure returns (uint24) {
        return TreeTickLib.tickToTreeIndex(tick, self.treeWidth, self.tickSpacing);
    }

    function refreshPrice(PoolInfo memory self) internal view {
        (self.sqrtPriceX96, self.currentTick, , , , , ) = IUniswapV3Pool(self.poolAddr).slot0();
    }

    function getFeeGrowthGlobals(
        PoolInfo memory self
    ) internal view returns (uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128) {
        IUniswapV3Pool poolContract = IUniswapV3Pool(self.poolAddr);
        feeGrowthGlobal0X128 = poolContract.feeGrowthGlobal0X128();
        feeGrowthGlobal1X128 = poolContract.feeGrowthGlobal1X128();
    }

    function validate(PoolInfo memory self) internal view {
        PoolValidation.validate(self.poolAddr, self.token0, self.token1, self.fee);
    }
}

/// Internal persistent storage bookkeeping for pools.
struct Pool {
    mapping(Key key => Node) nodes;
    mapping(int24 tick => tuint256) tickInitialized;
    mapping(int24 tick => tuint256) feeGrowthsOutside0X128;
    mapping(int24 tick => tuint256) feeGrowthsOutside1X128;
    // The last time the pool was modified.
    // This is ONLY updated when a new Data struct is created.
    uint128 timestamp;
}

/// A helper library for accessing the underlying pool's ABI.
/// @dev This will have to change for each pool we integrate with.
library PoolLib {
    using TransientSlot for bytes32;
    using TransientSlot for TransientSlot.AddressSlot;

    // keccak256(abi.encode(uint256(keccak256("ammplify.pool.guard.20250804")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant POOL_GUARD_SLOT = 0x22683b50bc083c867d84f1a241821c03bdc9b99b2f4ba292e47bc4ea8ead2500;
    uint128 private constant X128 = type(uint128).max; // Off by 1 from x128, but will fit in 128 bits.
    uint96 private constant X96 = type(uint96).max; // Off by 1 from x96, but will fit in 96 bits.

    // How many observations we want from our pools for the twap calculations.
    uint16 public constant MIN_OBSERVATIONS = 32;

    function getPoolInfo(address pool) internal view returns (PoolInfo memory pInfo) {
        pInfo.poolAddr = pool;
        IUniswapV3Pool poolContract = IUniswapV3Pool(pool);
        pInfo.token0 = poolContract.token0();
        pInfo.token1 = poolContract.token1();

        pInfo.tickSpacing = poolContract.tickSpacing();
        pInfo.fee = poolContract.fee();
        // We find the first power of two that is less than the number of tree indices to be the width.
        pInfo.treeWidth = TreeTickLib.calcRootWidth(TickMath.MIN_TICK, TickMath.MAX_TICK, pInfo.tickSpacing);
        PoolInfoImpl.refreshPrice(pInfo);

        return pInfo;
    }

    function getSqrtPriceX96(address pool) internal view returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96, , , , , , ) = IUniswapV3Pool(pool).slot0();
    }

    /// Get a slower moving price metric for the given pool.
    /// @dev This is used for taker borrow cost calculations and equivalent liq calculations.
    function getTwapSqrtPriceX96(address pool) internal view returns (uint160 twapSqrtPriceX96) {
        uint32 interval = FeeLib.getTwapInterval(pool);
        IUniswapV3PoolDerivedState poolContract = IUniswapV3PoolDerivedState(pool);
        // Get the TWAP.
        uint32[] memory timepoints = new uint32[](2);
        timepoints[0] = 0;
        timepoints[1] = interval;
        (int56[] memory tickCumulatives, ) = poolContract.observe(timepoints);
        int56 tickCumulativeDelta = tickCumulatives[0] - tickCumulatives[1];
        // We don't mind rounding the twapTick to 0 (price to 1).
        int24 twapTick = int24(tickCumulativeDelta / int32(interval));
        twapSqrtPriceX96 = TickMath.getSqrtPriceAtTick(twapTick);
    }

    /*
    /// Currently unused
    /// This assumes the position in the pool still exists, and queries how much fees are owed.
    /// @dev A non-modifying way to get fees owed.
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
    */

    /**
     * @notice Wrapper around pool collect function.
     * Collects just fees if no liquidity has been burned, otherwise collects both.
     * @param pool to operate on
     * @param tickLower bound
     * @param tickUpper bound
     */
    function collect(
        address pool,
        int24 tickLower,
        int24 tickUpper,
        bool burnFirst
    ) internal returns (uint256 amount0, uint256 amount1) {
        if (burnFirst) {
            // First do an empty burn to trigger a fee calc.
            IUniswapV3Pool(pool).burn(tickLower, tickUpper, 0);
        }
        return IUniswapV3Pool(pool).collect(address(this), tickLower, tickUpper, type(uint128).max, type(uint128).max);
    }

    /// Get the fee checkpoint for a certain range. Does NOT assume the position exists.
    function getInsideFees(
        address pool,
        int24 currentTick,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128,
        int24 lowerTick,
        int24 upperTick
    ) internal returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
        (uint256 lowerFeeGrowthOutside0X128, uint256 lowerFeeGrowthOutside1X128) = getTickGrowthsOutside(pool, lowerTick, currentTick, feeGrowthGlobal0X128, feeGrowthGlobal1X128);
        (uint256 upperFeeGrowthOutside0X128, uint256 upperFeeGrowthOutside1X128) = getTickGrowthsOutside(pool, upperTick, currentTick, feeGrowthGlobal0X128, feeGrowthGlobal1X128);
        unchecked {
            if (currentTick < lowerTick) {
                feeGrowthInside0X128 = lowerFeeGrowthOutside0X128 - upperFeeGrowthOutside0X128;
                feeGrowthInside1X128 = lowerFeeGrowthOutside1X128 - upperFeeGrowthOutside1X128;
            } else if (currentTick >= upperTick) {
                feeGrowthInside0X128 = upperFeeGrowthOutside0X128 - lowerFeeGrowthOutside0X128;
                feeGrowthInside1X128 = upperFeeGrowthOutside1X128 - lowerFeeGrowthOutside1X128;
            } else {
                feeGrowthInside0X128 = feeGrowthGlobal0X128 - lowerFeeGrowthOutside0X128 - upperFeeGrowthOutside0X128;
                feeGrowthInside1X128 = feeGrowthGlobal1X128 - lowerFeeGrowthOutside1X128 - upperFeeGrowthOutside1X128;
            }
        }
    }

    function getTickGrowthsOutside(address pool, int24 tick, int24 currentTick, uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128) internal returns (uint256 feeGrowthOutside0X128, uint256 feeGrowthOutside1X128) {
        Pool storage pStore = Store.load().pools[pool];
        if (pStore.tickInitialized[tick].get() > 0) {
            feeGrowthOutside0X128 = pStore.feeGrowthsOutside0X128[tick].get();
            feeGrowthOutside1X128 = pStore.feeGrowthsOutside1X128[tick].get();
        } else {
            bool init;
            IUniswapV3Pool poolContract = IUniswapV3Pool(pool);
            (
                ,
                ,
                feeGrowthOutside0X128,
                feeGrowthOutside1X128,
            ,
            ,
            ,
            init
            ) = poolContract.ticks(tick);

            if (!init && currentTick >= tick) {
                feeGrowthOutside0X128 = feeGrowthGlobal0X128;
                feeGrowthOutside1X128 = feeGrowthGlobal1X128;
            }
            pStore.tickInitialized[tick].set(1);
            pStore.feeGrowthsOutside0X128[tick].set(feeGrowthOutside0X128);
            pStore.feeGrowthsOutside1X128[tick].set(feeGrowthOutside1X128);
        }
    }

    /// Get the liquidity specific to a particular range.
    function getLiq(address pool, int24 lowerTick, int24 upperTick) internal view returns (uint128 liq) {
        (liq, , , , ) = IUniswapV3Pool(pool).positions(
            keccak256(abi.encodePacked(address(this), lowerTick, upperTick))
        );
    }

    /**
     * @notice wrapper around pool mint function to handle callback verification
     * @param pool to operate on
     * @param tickLower bound
     * @param tickUpper bound
     * @param liquidity to mint
     */
    function mint(
        address pool,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) internal returns (uint256 amount0, uint256 amount1) {
        POOL_GUARD_SLOT.asAddress().tstore(pool);
        (amount0, amount1) = IUniswapV3Pool(pool).mint(address(this), tickLower, tickUpper, liquidity, "");
        POOL_GUARD_SLOT.asAddress().tstore(address(0));
    }

    /**
     * @notice wrapper around pool burn function
     * @param pool to operate on
     * @param tickLower bound
     * @param tickUpper bound
     * @param liquidity to burn
     */
    function burn(
        address pool,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) internal returns (uint256 amount0, uint256 amount1) {
        return IUniswapV3Pool(pool).burn(tickLower, tickUpper, liquidity);
    }

    function poolGuard() internal view returns (address) {
        return POOL_GUARD_SLOT.asAddress().tload();
    }

    /// Answers how much liquidity we can add from the given amounts for the given range, and
    /// how much is leftover.
    /// @dev Rounds liq down.
    function getAssignableLiq(
        int24 lowTick,
        int24 highTick,
        uint128 x,
        uint128 y,
        uint160 sqrtPriceX96
    ) internal pure returns (uint128 assignableLiq, uint128 leftoverX, uint128 leftoverY) {
        uint160 lowSqrtPriceX96 = TickMath.getSqrtPriceAtTick(lowTick);
        uint160 highSqrtPriceX96 = TickMath.getSqrtPriceAtTick(highTick);

        if (sqrtPriceX96 <= lowSqrtPriceX96) {
            // We are below the range, so we can only add liquidity for token0.
            leftoverY = y;
            if (x == 0) {
                return (0, leftoverX, leftoverY);
            }
            // Round up to round liq down.
            uint256 unitX128 = SqrtPriceMath.getAmount0Delta(lowSqrtPriceX96, highSqrtPriceX96, X128, true);
            assignableLiq = uint128((uint256(x) * X128) / unitX128);
            // No leftover x, perhaps lose x dust here but it's okay.
        } else if (sqrtPriceX96 >= highSqrtPriceX96) {
            // We are above the range, so we can only add liquidity for token1.
            leftoverX = x;
            if (y == 0) {
                return (0, leftoverX, leftoverY);
            }
            // Round up to round liq down.
            uint256 unitX128 = SqrtPriceMath.getAmount1Delta(lowSqrtPriceX96, highSqrtPriceX96, X128, true);
            assignableLiq = uint128((uint256(y) * X128) / unitX128);
            // No leftover y, perhaps lose y dust here but it's okay.
        } else {
            uint256 reqXUnitX128 = SqrtPriceMath.getAmount0Delta(sqrtPriceX96, highSqrtPriceX96, X128, true);
            uint256 reqYUnitX128 = SqrtPriceMath.getAmount1Delta(lowSqrtPriceX96, sqrtPriceX96, X128, true);
            uint256 xLiq = (uint256(x) * X128) / reqXUnitX128;
            uint256 yLiq = (uint256(y) * X128) / reqYUnitX128;
            if (xLiq == yLiq) {
                assignableLiq = uint128(xLiq);
            } else if (xLiq < yLiq) {
                assignableLiq = uint128(xLiq);
                leftoverY = y - uint128(FullMath.mulX128(xLiq, reqYUnitX128, true));
            } else {
                assignableLiq = uint128(yLiq);
                leftoverX = x - uint128(FullMath.mulX128(yLiq, reqXUnitX128, true));
            }
        }
    }

    /// How much liquidity is are these assets worth in the given range.
    /// We consider two prices, the current price and the twap price and use the one that produces more liquidity,
    /// which causes an underweighting of the newly added liquidity. This slippage protects existing depositors
    /// and new depositors can simply wait for low volatility moments to avoid slippage.
    /// This protects us from someone manipulating the pool price to get a more favorable mint.
    function getEquivalentLiq(
        int24 lowTick,
        int24 highTick,
        uint256 x,
        uint256 y,
        uint160 sqrtPriceX96,
        uint160 twapSqrtPriceX96,
        bool roundUp
    ) internal pure returns (uint128 equivLiq) {
        // Compute with the current price.
        (uint256 lxX96, uint256 lyX96) = getAmounts(sqrtPriceX96, lowTick, highTick, X96, roundUp);
        uint256 liqValueX96 = (FullMath.mulX64(lxX96, sqrtPriceX96, false) >> 32) + (lyX96 << 96) / sqrtPriceX96;
        uint256 myValue = FullMath.mulX128(x, uint256(sqrtPriceX96) << 32, false) + (y << 96) / sqrtPriceX96;
        // Compute with the twap price.
        (uint256 twapLxX96, uint256 twapLyX96) = getAmounts(twapSqrtPriceX96, lowTick, highTick, X96, roundUp);
        uint256 twapLiqValueX96 = (FullMath.mulX64(twapLxX96, twapSqrtPriceX96, false) >> 32) +
            (twapLyX96 << 96) /
            twapSqrtPriceX96;
        uint256 myTwapValue = FullMath.mulX128(x, uint256(twapSqrtPriceX96) << 32, false) +
            (y << 96) /
            twapSqrtPriceX96;

        if (roundUp) {
            uint128 liq = SafeCast.toUint128(FullMath.mulDivRoundingUp(myValue, X96, liqValueX96));
            uint128 twapLiq = SafeCast.toUint128(FullMath.mulDivRoundingUp(myTwapValue, X96, twapLiqValueX96));
            equivLiq = liq > twapLiq ? liq : twapLiq;
        } else {
            uint128 liq = SafeCast.toUint128(FullMath.mulDiv(myValue, X96, liqValueX96));
            uint128 twapLiq = SafeCast.toUint128(FullMath.mulDiv(myTwapValue, X96, twapLiqValueX96));
            equivLiq = liq > twapLiq ? liq : twapLiq;
        }
    }

    /// Get the amounts of each token for the liquidity in the given range.
    function getAmounts(
        uint160 sqrtPriceX96,
        int24 lowTick,
        int24 highTick,
        uint128 liq,
        bool roundUp
    ) internal pure returns (uint256 x, uint256 y) {
        if (liq == 0) {
            return (0, 0);
        }

        uint160 lowSqrtPriceX96 = TickMath.getSqrtPriceAtTick(lowTick);
        uint160 highSqrtPriceX96 = TickMath.getSqrtPriceAtTick(highTick);

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

library PoolValidation {
    // If you want to deploy a diamond for testing without validation, use this.
    // But NEVER use this in production as malicious pools can drain fee earnings without this validation guard.
    address public constant SKIP_VALIDATION_FACTORY = address(0xDEADDEADDEAD);

    // This pool cannot be used with this ammplify deployment as it's from a different factory.
    error UnrecognizedPool();
    // This pool needs more observations to be safely used.
    error PoolInsufficientObservations(uint16 observations, uint16 required);

    function initFactory(address factory) internal {
        Store.load().factory = factory;
    }

    function validate(address poolAddr, address token0, address token1, uint24 fee) internal view {
        address factory = Store.factory();
        if (factory == SKIP_VALIDATION_FACTORY) return;

        // We query the factory because we don't want to rely on the POOL_INIT_CODE_HASH
        // which varies from fork to fork.
        require(IUniswapV3Factory(factory).getPool(token0, token1, fee) == poolAddr, UnrecognizedPool());

        (, , , , uint16 obsCardinalityNext, , ) = IUniswapV3Pool(poolAddr).slot0();
        require(
            obsCardinalityNext >= PoolLib.MIN_OBSERVATIONS,
            PoolInsufficientObservations(obsCardinalityNext, PoolLib.MIN_OBSERVATIONS)
        );
    }
}

library PoolViewLib {
    /// Get the fee checkpoint for a certain range. Does NOT assume the position exists.
    function getInsideFees(
        address pool,
        int24 currentTick,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128,
        int24 lowerTick,
        int24 upperTick
    ) internal view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
        (uint256 lowerFeeGrowthOutside0X128, uint256 lowerFeeGrowthOutside1X128) = getTickGrowthsOutside(pool, lowerTick, currentTick, feeGrowthGlobal0X128, feeGrowthGlobal1X128);
        (uint256 upperFeeGrowthOutside0X128, uint256 upperFeeGrowthOutside1X128) = getTickGrowthsOutside(pool, upperTick, currentTick, feeGrowthGlobal0X128, feeGrowthGlobal1X128);
        unchecked {
            if (currentTick < lowerTick) {
                feeGrowthInside0X128 = lowerFeeGrowthOutside0X128 - upperFeeGrowthOutside0X128;
                feeGrowthInside1X128 = lowerFeeGrowthOutside1X128 - upperFeeGrowthOutside1X128;
            } else if (currentTick >= upperTick) {
                feeGrowthInside0X128 = upperFeeGrowthOutside0X128 - lowerFeeGrowthOutside0X128;
                feeGrowthInside1X128 = upperFeeGrowthOutside1X128 - lowerFeeGrowthOutside1X128;
            } else {
                feeGrowthInside0X128 = feeGrowthGlobal0X128 - lowerFeeGrowthOutside0X128 - upperFeeGrowthOutside0X128;
                feeGrowthInside1X128 = feeGrowthGlobal1X128 - lowerFeeGrowthOutside1X128 - upperFeeGrowthOutside1X128;
            }
        }
    }

    function getTickGrowthsOutside(address pool, int24 tick, int24 currentTick, uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128) internal view returns (uint256 feeGrowthOutside0X128, uint256 feeGrowthOutside1X128) {
        bool init;
        IUniswapV3Pool poolContract = IUniswapV3Pool(pool);
            (
                ,
                ,
                feeGrowthOutside0X128,
                feeGrowthOutside1X128,
            ,
            ,
            ,
            init
            ) = poolContract.ticks(tick);

            if (!init && currentTick >= tick) {
                feeGrowthOutside0X128 = feeGrowthGlobal0X128;
                feeGrowthOutside1X128 = feeGrowthGlobal1X128;
            }
    }
}
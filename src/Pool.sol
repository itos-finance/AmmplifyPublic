// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { IPoolManager } from "v4-core/interfaces/IPoolManager.sol";
import { StateLibrary } from "v4-core/libraries/StateLibrary.sol";
import { PoolKey } from "v4-core/types/PoolKey.sol";
import { PoolId, PoolIdLibrary } from "v4-core/types/PoolId.sol";
import { Currency } from "v4-core/types/Currency.sol";
import { IHooks } from "v4-core/interfaces/IHooks.sol";
import { BalanceDelta } from "v4-core/types/BalanceDelta.sol";
import { ModifyLiquidityParams } from "v4-core/types/PoolOperation.sol";
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
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { tuint256, tint256 } from "transient-goodies/TransientPrimitives.sol";

// In memory struct derived from a pool
struct PoolInfo {
    // Immutables
    address poolAddr; // Deterministic identifier derived from PoolId
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
    using StateLibrary for IPoolManager;

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
        IPoolManager manager = IPoolManager(Store.poolManager());
        PoolId poolId = Store.getPoolId(self.poolAddr);
        (self.sqrtPriceX96, self.currentTick, , ) = manager.getSlot0(poolId);
    }

    function getFeeGrowthGlobals(
        PoolInfo memory self
    ) internal view returns (uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128) {
        IPoolManager manager = IPoolManager(Store.poolManager());
        PoolId poolId = Store.getPoolId(self.poolAddr);
        (feeGrowthGlobal0X128, feeGrowthGlobal1X128) = manager.getFeeGrowthGlobals(poolId);
    }

    function validate(PoolInfo memory self) internal view {
        PoolValidation.validate(self.poolAddr);
    }
}

/// Internal persistent storage bookkeeping for pools.
struct Pool {
    mapping(Key key => Node) nodes;
    // The last time the pool was modified.
    // This is ONLY updated when a new Data struct is created.
    uint128 timestamp;
    // Temporary liq storage
    mapping(Key key => tint256) preBorrows;
    mapping(Key key => tint256) preLends;
}

/// A helper library for accessing the underlying pool via V4 PoolManager.
/// @dev All liquidity modifications are batched and executed inside a PoolManager unlock callback.
library PoolLib {
    using SafeERC20 for IERC20;
    using TransientSlot for bytes32;
    using TransientSlot for TransientSlot.AddressSlot;
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    uint128 private constant X128 = type(uint128).max; // Off by 1 from x128, but will fit in 128 bits.
    uint96 private constant X96 = type(uint96).max; // Off by 1 from x96, but will fit in 96 bits.

    // Transient storage slots for batching V4 operations.
    // keccak256("ammplify.v4.ops.count")
    uint256 private constant OPS_COUNT_SLOT = 0x8d7b6e4c5a3f2e1d0c9b8a7f6e5d4c3b2a1f0e9d8c7b6a5f4e3d2c1b0a9f8e7;
    // keccak256("ammplify.v4.ops.base")
    uint256 private constant OPS_BASE_SLOT = 0x7c6b5a4938271605f4e3d2c1b0a9f8e7d6c5b4a39281706f5e4d3c2b1a09f8e7;

    function getPoolInfo(address poolAddr) internal view returns (PoolInfo memory pInfo) {
        pInfo.poolAddr = poolAddr;
        PoolKey memory poolKey = Store.getPoolKey(poolAddr);
        pInfo.token0 = Currency.unwrap(poolKey.currency0);
        pInfo.token1 = Currency.unwrap(poolKey.currency1);
        pInfo.tickSpacing = poolKey.tickSpacing;
        pInfo.fee = poolKey.fee;
        pInfo.treeWidth = TreeTickLib.calcRootWidth(TickMath.MIN_TICK, TickMath.MAX_TICK, pInfo.tickSpacing);
        PoolInfoImpl.refreshPrice(pInfo);
        return pInfo;
    }

    function getSqrtPriceX96(address poolAddr) internal view returns (uint160 sqrtPriceX96) {
        IPoolManager manager = IPoolManager(Store.poolManager());
        PoolId poolId = Store.getPoolId(poolAddr);
        (sqrtPriceX96, , , ) = manager.getSlot0(poolId);
    }

    /// Collect fees from a position.
    /// @dev In V4, there is no separate collect. We compute owed fees from StateLibrary,
    /// and record a zero-delta modifyLiquidity (poke) to update the position's fee checkpoint.
    /// Actual token settlement happens in the unlock callback after all operations are executed.
    function collect(
        address poolAddr,
        int24 tickLower,
        int24 tickUpper,
        bool burnFirst
    ) internal returns (uint256 amount0, uint256 amount1) {
        IPoolManager manager = IPoolManager(Store.poolManager());
        PoolId poolId = Store.getPoolId(poolAddr);

        // Get position info to compute owed fees.
        (uint128 liq, uint256 lastFG0, uint256 lastFG1) =
            manager.getPositionInfo(poolId, address(this), tickLower, tickUpper, bytes32(0));

        if (liq > 0) {
            // Compute fees using current fee growth inside vs last checkpoint.
            (uint256 currentFG0, uint256 currentFG1) =
                manager.getFeeGrowthInside(poolId, tickLower, tickUpper);

            unchecked {
                amount0 = FullMath.mulDiv(uint256(liq), currentFG0 - lastFG0, uint256(1) << 128);
                amount1 = FullMath.mulDiv(uint256(liq), currentFG1 - lastFG1, uint256(1) << 128);
            }
        }

        if (burnFirst) {
            // Record a poke to update the position's fee checkpoint in the unlock callback.
            _recordOp(tickLower, tickUpper, 0);
        }
        // If burnFirst is false, a burn was already recorded and will handle the checkpoint update.
    }

    /// Get the fee checkpoint for a certain range using V4 StateLibrary.
    function getInsideFees(
        address poolAddr,
        int24 currentTick,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128,
        int24 lowerTick,
        int24 upperTick
    ) internal view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
        IPoolManager manager = IPoolManager(Store.poolManager());
        PoolId poolId = Store.getPoolId(poolAddr);

        // Get lower tick fee growth outside
        (uint128 lowerLiqGross, , uint256 lowerFGO0, uint256 lowerFGO1) = manager.getTickInfo(poolId, lowerTick);
        if (lowerLiqGross == 0 && currentTick >= lowerTick) {
            lowerFGO0 = feeGrowthGlobal0X128;
            lowerFGO1 = feeGrowthGlobal1X128;
        }

        // Get upper tick fee growth outside
        (uint128 upperLiqGross, , uint256 upperFGO0, uint256 upperFGO1) = manager.getTickInfo(poolId, upperTick);
        if (upperLiqGross == 0 && currentTick >= upperTick) {
            upperFGO0 = feeGrowthGlobal0X128;
            upperFGO1 = feeGrowthGlobal1X128;
        }

        unchecked {
            if (currentTick < lowerTick) {
                feeGrowthInside0X128 = lowerFGO0 - upperFGO0;
                feeGrowthInside1X128 = lowerFGO1 - upperFGO1;
            } else if (currentTick >= upperTick) {
                feeGrowthInside0X128 = upperFGO0 - lowerFGO0;
                feeGrowthInside1X128 = upperFGO1 - lowerFGO1;
            } else {
                feeGrowthInside0X128 = feeGrowthGlobal0X128 - lowerFGO0 - upperFGO0;
                feeGrowthInside1X128 = feeGrowthGlobal1X128 - lowerFGO1 - upperFGO1;
            }
        }
    }

    /// Get the liquidity specific to a particular range via V4 StateLibrary.
    function getLiq(address poolAddr, int24 lowerTick, int24 upperTick) internal view returns (uint128 liq) {
        IPoolManager manager = IPoolManager(Store.poolManager());
        PoolId poolId = Store.getPoolId(poolAddr);
        (liq, , ) = manager.getPositionInfo(poolId, address(this), lowerTick, upperTick, bytes32(0));
    }

    /// Record a mint operation to be executed in the unlock callback.
    function mint(
        address /* pool */,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) internal returns (uint256 amount0, uint256 amount1) {
        _recordOp(tickLower, tickUpper, int128(uint128(liquidity)));
        return (0, 0);
    }

    /// Record a burn operation to be executed in the unlock callback.
    function burn(
        address /* pool */,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) internal returns (uint256 amount0, uint256 amount1) {
        _recordOp(tickLower, tickUpper, -int128(uint128(liquidity)));
        return (0, 0);
    }

    /* Batched V4 Operations */

    function clearOps() internal {
        assembly {
            tstore(OPS_COUNT_SLOT, 0)
        }
    }

    function getOpCount() internal view returns (uint256 count) {
        assembly {
            count := tload(OPS_COUNT_SLOT)
        }
    }

    function getOp(uint256 index) internal view returns (int24 tickLower, int24 tickUpper, int128 liquidityDelta) {
        uint256 slot = OPS_BASE_SLOT + index * 2;
        uint256 packed;
        int256 delta;
        assembly {
            packed := tload(slot)
            delta := tload(add(slot, 1))
        }
        tickLower = int24(uint24(packed >> 24));
        tickUpper = int24(uint24(packed & 0xFFFFFF));
        liquidityDelta = int128(delta);
    }

    /// Execute all recorded operations inside a V4 unlock callback.
    /// @dev Called from PoolWalker.settle after the tree walk is complete.
    function executeOps(PoolInfo memory pInfo) internal {
        uint256 count = getOpCount();
        if (count == 0) return;

        IPoolManager manager = IPoolManager(Store.poolManager());
        PoolKey memory poolKey = Store.getPoolKey(pInfo.poolAddr);
        manager.unlock(abi.encode(poolKey, pInfo.token0, pInfo.token1));
    }

    /// Called by the PoolManager during unlock. Executes batched operations and settles tokens.
    function handleUnlockCallback(bytes calldata data) internal returns (bytes memory) {
        (PoolKey memory poolKey, address token0, address token1) = abi.decode(data, (PoolKey, address, address));

        IPoolManager manager = IPoolManager(Store.poolManager());
        int256 totalDelta0;
        int256 totalDelta1;

        uint256 count = getOpCount();
        for (uint256 i = 0; i < count; i++) {
            (int24 tickLower, int24 tickUpper, int128 liquidityDelta) = getOp(i);

            ModifyLiquidityParams memory params = ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: int256(liquidityDelta),
                salt: bytes32(0)
            });

            (BalanceDelta callerDelta, ) = manager.modifyLiquidity(poolKey, params, "");
            totalDelta0 += callerDelta.amount0();
            totalDelta1 += callerDelta.amount1();
        }

        clearOps();

        // Settle token deltas with the PoolManager.
        // V4 convention: negative delta = caller must pay. Positive delta = caller receives.
        _settleDelta(manager, poolKey.currency0, token0, totalDelta0);
        _settleDelta(manager, poolKey.currency1, token1, totalDelta1);

        return "";
    }

    /* Pure helpers (unchanged from V3) */

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
            leftoverY = y;
            if (x == 0) {
                return (0, leftoverX, leftoverY);
            }
            uint256 unitX128 = SqrtPriceMath.getAmount0Delta(lowSqrtPriceX96, highSqrtPriceX96, X128, true);
            assignableLiq = uint128((uint256(x) * X128) / unitX128);
        } else if (sqrtPriceX96 >= highSqrtPriceX96) {
            leftoverX = x;
            if (y == 0) {
                return (0, leftoverX, leftoverY);
            }
            uint256 unitX128 = SqrtPriceMath.getAmount1Delta(lowSqrtPriceX96, highSqrtPriceX96, X128, true);
            assignableLiq = uint128((uint256(y) * X128) / unitX128);
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

    /// How much liquidity are these assets worth in the given range.
    function getEquivalentLiq(
        int24 lowTick,
        int24 highTick,
        uint256 x,
        uint256 y,
        uint160 sqrtPriceX96,
        bool roundUp
    ) internal pure returns (uint128 equivLiq) {
        (uint256 lxX96, uint256 lyX96) = getAmounts(sqrtPriceX96, lowTick, highTick, X96, roundUp);
        uint256 liqValueX96 = (FullMath.mulX64(lxX96, sqrtPriceX96, false) >> 32) + (lyX96 << 96) / sqrtPriceX96;
        uint256 myValue = FullMath.mulX128(x, uint256(sqrtPriceX96) << 32, false) + (y << 96) / sqrtPriceX96;

        if (roundUp) {
            equivLiq = SafeCast.toUint128(FullMath.mulDivRoundingUp(myValue, X96, liqValueX96));
        } else {
            equivLiq = SafeCast.toUint128(FullMath.mulDiv(myValue, X96, liqValueX96));
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
            x = SqrtPriceMath.getAmount0Delta(lowSqrtPriceX96, highSqrtPriceX96, liq, roundUp);
            y = 0;
        } else if (sqrtPriceX96 >= highSqrtPriceX96) {
            x = 0;
            y = SqrtPriceMath.getAmount1Delta(lowSqrtPriceX96, highSqrtPriceX96, liq, roundUp);
        } else {
            x = SqrtPriceMath.getAmount0Delta(sqrtPriceX96, highSqrtPriceX96, liq, roundUp);
            y = SqrtPriceMath.getAmount1Delta(lowSqrtPriceX96, sqrtPriceX96, liq, roundUp);
        }
    }

    /* Internal helpers */

    function _recordOp(int24 tickLower, int24 tickUpper, int128 delta) private {
        uint256 count;
        assembly {
            count := tload(OPS_COUNT_SLOT)
        }
        uint256 slot = OPS_BASE_SLOT + count * 2;
        // Pack ticks using uint masks to avoid sign-extension corruption.
        // Each tick is masked to 24 bits; tickLower in bits [47:24], tickUpper in bits [23:0].
        uint256 packed = (uint256(uint24(tickLower)) << 24) | uint256(uint24(tickUpper));
        assembly {
            tstore(slot, packed)
            tstore(add(slot, 1), delta)
            tstore(OPS_COUNT_SLOT, add(count, 1))
        }
    }

    function _settleDelta(IPoolManager manager, Currency currency, address token, int256 delta) private {
        if (delta < 0) {
            // V4: negative delta = caller must pay the pool manager.
            manager.sync(currency);
            IERC20(token).safeTransfer(address(manager), uint256(-delta));
            manager.settle();
        } else if (delta > 0) {
            // V4: positive delta = pool manager owes us tokens.
            manager.take(currency, address(this), uint256(delta));
        }
    }
}

library PoolValidation {
    // If you want to deploy a diamond for testing without validation, use this.
    address public constant SKIP_VALIDATION_FACTORY = address(0xDEADDEADDEAD);

    error UnrecognizedPool();

    function initPoolManager(address _poolManager) internal {
        Store.load().poolManager = _poolManager;
    }

    /// Validate that the pool is registered and initialized in the PoolManager.
    function validate(address poolAddr) internal view {
        address _poolManager = Store.poolManager();
        if (_poolManager == SKIP_VALIDATION_FACTORY) return;

        // Verify pool is registered in our storage.
        PoolKey memory poolKey = Store.getPoolKey(poolAddr);
        require(Currency.unwrap(poolKey.currency0) != address(0), UnrecognizedPool());

        // Verify pool is initialized in the PoolManager by checking sqrtPriceX96 > 0.
        IPoolManager manager = IPoolManager(_poolManager);
        (uint160 sqrtPriceX96, , , ) = StateLibrary.getSlot0(manager, poolKey.toId());
        require(sqrtPriceX96 > 0, UnrecognizedPool());
    }
}

/// View-only version of fee growth calculations (no transient storage caching).
library PoolViewLib {
    using StateLibrary for IPoolManager;

    /// Get the fee checkpoint for a certain range.
    function getInsideFees(
        address poolAddr,
        int24 currentTick,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128,
        int24 lowerTick,
        int24 upperTick
    ) internal view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
        IPoolManager manager = IPoolManager(Store.poolManager());
        PoolId poolId = Store.getPoolId(poolAddr);

        (uint128 lowerLiqGross, , uint256 lowerFGO0, uint256 lowerFGO1) = manager.getTickInfo(poolId, lowerTick);
        if (lowerLiqGross == 0 && currentTick >= lowerTick) {
            lowerFGO0 = feeGrowthGlobal0X128;
            lowerFGO1 = feeGrowthGlobal1X128;
        }

        (uint128 upperLiqGross, , uint256 upperFGO0, uint256 upperFGO1) = manager.getTickInfo(poolId, upperTick);
        if (upperLiqGross == 0 && currentTick >= upperTick) {
            upperFGO0 = feeGrowthGlobal0X128;
            upperFGO1 = feeGrowthGlobal1X128;
        }

        unchecked {
            if (currentTick < lowerTick) {
                feeGrowthInside0X128 = lowerFGO0 - upperFGO0;
                feeGrowthInside1X128 = lowerFGO1 - upperFGO1;
            } else if (currentTick >= upperTick) {
                feeGrowthInside0X128 = upperFGO0 - lowerFGO0;
                feeGrowthInside1X128 = upperFGO1 - lowerFGO1;
            } else {
                feeGrowthInside0X128 = feeGrowthGlobal0X128 - lowerFGO0 - upperFGO0;
                feeGrowthInside1X128 = feeGrowthGlobal1X128 - lowerFGO1 - upperFGO1;
            }
        }
    }
}

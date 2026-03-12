// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { Store } from "../src/Store.sol";
import { SqrtPriceMath } from "v4-core/libraries/SqrtPriceMath.sol";
import { TickMath } from "v4-core/libraries/TickMath.sol";
import { StateLibrary } from "v4-core/libraries/StateLibrary.sol";
import { PoolKey } from "v4-core/types/PoolKey.sol";
import { PoolId, PoolIdLibrary } from "v4-core/types/PoolId.sol";
import { IPoolManager } from "v4-core/interfaces/IPoolManager.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { LiquidityAmounts } from "./utils/LiquidityAmounts.sol";
import { SafeCast } from "Commons/Math/Cast.sol";
import { UniV4IntegrationSetup } from "./UniV4.u.sol";
import { PoolLib, PoolInfo, PoolInfoImpl, PoolValidation } from "../src/Pool.sol";

contract PoolInfoImplTest is Test {
    function testTokens() public pure {
        PoolInfo memory pInfo;
        pInfo.token0 = address(0x0);
        pInfo.token1 = address(0x1);

        address[] memory tokens = PoolInfoImpl.tokens(pInfo);
        assertEq(tokens[0], address(0x0));
        assertEq(tokens[1], address(0x1));
    }
}

contract PoolTest is Test, UniV4IntegrationSetup {
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    function _manager() internal view returns (IPoolManager) {
        return IPoolManager(address(manager));
    }

    address poolAddr;

    function setUp() public {
        setUpPool();
        PoolValidation.initPoolManager(address(manager));
        Store.registerPoolKey(poolKeys[0]);

        poolAddr = pools[0];
    }

    function testGetPoolInfo() public {
        PoolInfo memory pInfo = PoolLib.getPoolInfo(poolAddr);
        assertEq(pInfo.poolAddr, poolAddr);
        assertEq(pInfo.token0, poolToken0s[0]);
        assertEq(pInfo.token1, poolToken1s[0]);
        assertEq(pInfo.tickSpacing, tickSpacings[0]);
        assertEq(pInfo.tickSpacing, 60, "tickSpacing.fee.3000");
        assertEq(pInfo.treeWidth, 2 ** 14, "treeWidth.fee.3000");

        setUpPool(500);
        Store.registerPoolKey(poolKeys[1]);
        pInfo = PoolLib.getPoolInfo(pools[1]);
        assertEq(pInfo.tickSpacing, 10, "tickSpacing.fee.500");
        assertEq(pInfo.treeWidth, 2 ** 17, "treeWidth.fee.500");

        setUpPool(10000);
        Store.registerPoolKey(poolKeys[2]);
        pInfo = PoolLib.getPoolInfo(pools[2]);
        assertEq(pInfo.tickSpacing, 200, "tickSpacing.fee.10000");
        assertEq(pInfo.treeWidth, 2 ** 13, "treeWidth.fee.10000");
    }

    function testGetSqrtPriceX96() public {
        PoolInfo memory pInfo = PoolLib.getPoolInfo(poolAddr);

        (uint160 slot0SqrtPriceX96, int24 slot0Tick, , ) = _manager().getSlot0(poolKeys[0].toId());
        assertEq(slot0SqrtPriceX96, pInfo.sqrtPriceX96);
        assertEq(slot0Tick, pInfo.currentTick);

        uint160 currentTickSqrtPriceX96 = TickMath.getSqrtPriceAtTick(slot0Tick);
        uint160 nextTickSqrtPriceX96 = TickMath.getSqrtPriceAtTick(slot0Tick + tickSpacings[0]);
        uint160 middleSqrtPriceX96 = currentTickSqrtPriceX96 + (nextTickSqrtPriceX96 - currentTickSqrtPriceX96) / 2;

        // verify assumptions
        assertLt(currentTickSqrtPriceX96, nextTickSqrtPriceX96);
        assertLt(middleSqrtPriceX96, nextTickSqrtPriceX96);
        assertGt(middleSqrtPriceX96, currentTickSqrtPriceX96);

        // swap to price between ticks
        swapTo(0, middleSqrtPriceX96);

        // verify reported sqrt price is between ticks
        pInfo.refreshPrice();
        (slot0SqrtPriceX96, , , ) = _manager().getSlot0(poolKeys[0].toId());
        assertEq(slot0SqrtPriceX96, pInfo.sqrtPriceX96);
        assertEq(slot0SqrtPriceX96, middleSqrtPriceX96);
    }

    function testGetLiq() public {
        // In V4, PoolLib.mint() only records ops for batch execution.
        // Use addPoolLiq() from UniV4IntegrationSetup for actual liquidity addition.
        int24 tickLower = tickSpacings[0] * -10;
        int24 tickUpper = tickSpacings[0] * 10;

        uint128 liq = PoolLib.getLiq(poolAddr, tickLower, tickUpper);
        assertEq(liq, 0, "liq.position1.noLiq");

        addPoolLiq(0, tickLower, tickUpper, 1e20);
        liq = PoolLib.getLiq(poolAddr, tickLower, tickUpper);
        assertEq(liq, 1e20, "liq.position1.mint1");

        addPoolLiq(0, tickLower, tickUpper, 2e20);
        liq = PoolLib.getLiq(poolAddr, tickLower, tickUpper);
        assertEq(liq, 3e20, "liq.position1.mint2");

        // Position 2
        tickUpper = tickSpacings[0] * 20;

        liq = PoolLib.getLiq(poolAddr, tickLower, tickUpper);
        assertEq(liq, 0, "liq.position2.noLiq");

        addPoolLiq(0, tickLower, tickUpper, 1e5);
        liq = PoolLib.getLiq(poolAddr, tickLower, tickUpper);
        assertEq(liq, 1e5, "liq.position2.mint1");
    }

    // TODO: V4 migration - PoolLib.mint/burn/collect now record batch ops instead of executing immediately.
    // These unit tests need reworking to use the full diamond + unlock callback pattern.

    function testMint() public {
        // In V4, PoolLib.mint() records ops for batch execution and returns (0,0).
        // Verify that mint records an op correctly.
        int24 tickSpacing = tickSpacings[0];
        int24 tickLower = tickSpacing * -10;
        int24 tickUpper = tickSpacing * 10;
        uint128 liq = 1e20;

        PoolLib.clearOps();
        PoolLib.mint(poolAddr, tickLower, tickUpper, liq);
        assertEq(PoolLib.getOpCount(), 1, "should have 1 op recorded");
    }

    function testBurn() public {
        // Verify that burn records an op correctly.
        int24 tickSpacing = tickSpacings[0];
        int24 tickLower = tickSpacing * -10;
        int24 tickUpper = tickSpacing * 10;
        uint128 liq = 1e20;

        PoolLib.clearOps();
        PoolLib.burn(poolAddr, tickLower, tickUpper, liq);
        assertEq(PoolLib.getOpCount(), 1, "should have 1 op recorded");
    }

    function testCollect() public {
        // In V4, collect computes expected fees rather than collecting tokens.
        // Use addPoolLiq + swap to generate fees and verify collect works.
        int24 tickSpacing = tickSpacings[0];
        int24 tickLower = tickSpacing * -10;
        int24 tickUpper = tickSpacing * 10;
        uint128 liq = 1e20;

        addPoolLiq(0, tickLower, tickUpper, liq);

        // Swap to generate fees
        swap(0, 1e18, true);
        swap(0, 1e18, false);

        // Collect should compute expected fees
        (uint256 collect0, uint256 collect1) = PoolLib.collect(poolAddr, tickLower, tickUpper, false);
        assertTrue(collect0 > 0 || collect1 > 0, "should have some fees");
    }

    function testGetInsideFees() public {
        int24 tickSpacing = tickSpacings[0];
        addPoolLiq(0, tickSpacing * -1000, tickSpacing * 1000, 1e20);

        // verify starting tick is 0
        (, int24 currentTick, , ) = _manager().getSlot0(poolKeys[0].toId());
        assertEq(currentTick, 0, "currentTick.equals.0");

        // create position
        int24 tickLower = tickSpacing * -10;
        int24 tickUpper = tickSpacing * 10;
        uint128 liq = 1e20;

        addPoolLiq(0, tickLower, tickUpper, liq);

        // get global fee growth.
        PoolInfo memory pInfo = PoolLib.getPoolInfo(poolAddr);
        (uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128) = pInfo.getFeeGrowthGlobals();

        // verify fees are 0
        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = PoolLib.getInsideFees(
            poolAddr,
            currentTick,
            feeGrowthGlobal0X128,
            feeGrowthGlobal1X128,
            tickLower,
            tickUpper
        );
        assertEq(feeGrowthInside0X128, 0, "feeGrowthInside0X128.equals.0");
        assertEq(feeGrowthInside1X128, 0, "feeGrowthInside1X128.equals.0");

        // swap through range to generate fees
        swapTo(0, TickMath.getSqrtPriceAtTick(tickLower - (tickSpacing * 10)));
        swapTo(0, TickMath.getSqrtPriceAtTick(tickUpper + (tickSpacing * 10)));
        swapTo(0, TickMath.getSqrtPriceAtTick(tickLower + (tickSpacing * 5)));

        // move price below range
        swapTo(0, TickMath.getSqrtPriceAtTick(tickLower - (tickSpacing * 10)));
        (, currentTick, , ) = _manager().getSlot0(poolKeys[0].toId());
        assertLt(currentTick, tickLower, "currentTick.lt.tickLower");

        (feeGrowthGlobal0X128, feeGrowthGlobal1X128) = pInfo.getFeeGrowthGlobals();
        (feeGrowthInside0X128, feeGrowthInside1X128) = PoolLib.getInsideFees(
            poolAddr,
            currentTick,
            feeGrowthGlobal0X128,
            feeGrowthGlobal1X128,
            tickLower,
            tickUpper
        );
        // After swapping through range, inside fees should be non-zero
        assertGt(feeGrowthInside0X128, 0, "feeGrowthInside0X128.gt.0.belowRange");
        assertGt(feeGrowthInside1X128, 0, "feeGrowthInside1X128.gt.0.belowRange");

        // move price above range
        swapTo(0, TickMath.getSqrtPriceAtTick(tickUpper + (tickSpacing * 10)));
        (, currentTick, , ) = _manager().getSlot0(poolKeys[0].toId());
        assertGt(currentTick, tickUpper, "currentTick.gt.tickUpper");

        (feeGrowthGlobal0X128, feeGrowthGlobal1X128) = pInfo.getFeeGrowthGlobals();
        (uint256 feeAbove0, uint256 feeAbove1) = PoolLib.getInsideFees(
            poolAddr,
            currentTick,
            feeGrowthGlobal0X128,
            feeGrowthGlobal1X128,
            tickLower,
            tickUpper
        );
        // Fees should have increased from the swap through
        assertGe(feeAbove0, feeGrowthInside0X128, "feeGrowthInside0X128.ge.aboveRange");
        assertGt(feeAbove1, feeGrowthInside1X128, "feeGrowthInside1X128.gt.aboveRange");

        // move price in range
        swapTo(0, TickMath.getSqrtPriceAtTick(tickLower + (tickSpacing * 5)));
        (, currentTick, , ) = _manager().getSlot0(poolKeys[0].toId());
        assertLt(currentTick, tickUpper, "currentTick.lt.tickUpper");
        assertGt(currentTick, tickLower, "currentTick.gt.tickLower");

        (feeGrowthGlobal0X128, feeGrowthGlobal1X128) = pInfo.getFeeGrowthGlobals();
        (uint256 feeInRange0, uint256 feeInRange1) = PoolLib.getInsideFees(
            poolAddr,
            currentTick,
            feeGrowthGlobal0X128,
            feeGrowthGlobal1X128,
            tickLower,
            tickUpper
        );
        assertGt(feeInRange0, 0, "feeGrowthInside0X128.gt.0.inRange");
        assertGt(feeInRange1, 0, "feeGrowthInside1X128.gt.0.inRange");
    }

    /// Test inside fees remains zero when uninitialized.
    /// And once initialized collects fees.
    function testInsideFeesUninitialized() public {
        int24 tickSpacing = tickSpacings[0];
        addPoolLiq(0, tickSpacing * -1000, tickSpacing * 1000, 1e20);

        // verify starting tick is 0
        (, int24 currentTick, , ) = _manager().getSlot0(poolKeys[0].toId());
        assertEq(currentTick, 0, "currentTick.equals.0");

        // create position
        int24 tickLower = tickSpacing * -10;
        int24 tickUpper = tickSpacing * 10;

        // The current inside fees is zero.
        PoolInfo memory pInfo = PoolLib.getPoolInfo(poolAddr);
        (uint256 global00, uint256 global10) = pInfo.getFeeGrowthGlobals();

        // verify fees are 0
        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = PoolLib.getInsideFees(
            poolAddr,
            currentTick,
            global00,
            global10,
            tickLower,
            tickUpper
        );
        assertEq(feeGrowthInside0X128, 0, "uninit.starts.0");
        assertEq(feeGrowthInside1X128, 0, "uninit.starts.0");

        // Even swapping up nothing.
        swapTo(0, TickMath.getSqrtPriceAtTick(tickUpper + (tickSpacing * 10)));
        // Global goes up.
        (uint256 global01, uint256 global11) = pInfo.getFeeGrowthGlobals();
        (, currentTick, , ) = _manager().getSlot0(poolKeys[0].toId());
        assertGt(global11, global01, "y goes up");
        assertEq(global01, global00, "x stays same");
        (feeGrowthInside0X128, feeGrowthInside1X128) = PoolLib.getInsideFees(
            poolAddr,
            currentTick,
            global01,
            global11,
            tickLower,
            tickUpper
        );
        assertEq(feeGrowthInside0X128, 0, "uninit.still.0");
        assertEq(feeGrowthInside1X128, 0, "uninit.still.0");

        // Swap down, nothing.
        swapTo(0, TickMath.getSqrtPriceAtTick(tickLower - (tickSpacing * 10)));
        // Global goes up.
        (uint256 global02, uint256 global12) = pInfo.getFeeGrowthGlobals();
        (, currentTick, , ) = _manager().getSlot0(poolKeys[0].toId());
        assertEq(global12, global11, "y stays same");
        assertGt(global02, global10, "x goes up");
        (feeGrowthInside0X128, feeGrowthInside1X128) = PoolLib.getInsideFees(
            poolAddr,
            currentTick,
            global02,
            global12,
            tickLower,
            tickUpper
        );
        assertEq(feeGrowthInside0X128, 0, "uninit.still.0.1");
        assertEq(feeGrowthInside1X128, 0, "uninit.still.0.1");

        // Now we init the ticks
        addPoolLiq(0, tickLower, tickUpper, 1);
        // Still zero.
        (global02, global12) = pInfo.getFeeGrowthGlobals();
        (, currentTick, , ) = _manager().getSlot0(poolKeys[0].toId());
        (feeGrowthInside0X128, feeGrowthInside1X128) = PoolLib.getInsideFees(
            poolAddr,
            currentTick,
            global02,
            global12,
            tickLower,
            tickUpper
        );
        assertEq(feeGrowthInside0X128, 0, "uninit.still.0.2");
        assertEq(feeGrowthInside1X128, 0, "uninit.still.0.2");

        // Swap up in range.
        swapTo(0, 1 << 96);
        // Global goes up.
        (uint256 global03, uint256 global13) = pInfo.getFeeGrowthGlobals();
        (, currentTick, , ) = _manager().getSlot0(poolKeys[0].toId());
        assertGt(global03 + global13, global02 + global12, "global goes up");
        (feeGrowthInside0X128, feeGrowthInside1X128) = PoolLib.getInsideFees(
            poolAddr,
            currentTick,
            global03,
            global13,
            tickLower,
            tickUpper
        );
        assertGt(feeGrowthInside1X128, 0, "now inside y goes up");
        assertEq(feeGrowthInside0X128, 0, "inside x still 0");
        assertLt(feeGrowthInside1X128, global13, "inside y less than global");

        // Swap down
        swapTo(0, TickMath.getSqrtPriceAtTick(tickLower));
        (global03, global13) = pInfo.getFeeGrowthGlobals();
        (, currentTick, , ) = _manager().getSlot0(poolKeys[0].toId());
        (feeGrowthInside0X128, feeGrowthInside1X128) = PoolLib.getInsideFees(
            poolAddr,
            currentTick,
            global03,
            global13,
            tickLower,
            tickUpper
        );
        assertGt(feeGrowthInside0X128, 0, "now inside x goes up");
        assertGt(feeGrowthInside1X128, 0, "inside y still up");
        assertLt(feeGrowthInside0X128, global03, "inside x less than global");
        assertLt(feeGrowthInside1X128, global13, "inside y less than global");
    }

    // Assignable Liq

    function testGetAssignableLiqBelowRange() public pure {
        int24 lowTick = -2000;
        int24 highTick = 2000;
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(-3000);
        uint128 x = 200e18;
        uint128 y = 100e6;

        (uint128 assignableLiq, uint128 leftoverX, uint128 leftoverY) = PoolLib.getAssignableLiq(
            lowTick,
            highTick,
            x,
            y,
            sqrtPriceX96
        );

        uint128 expectedLiq = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(lowTick),
            TickMath.getSqrtPriceAtTick(highTick),
            uint256(x),
            uint256(y)
        );
        (uint256 usedX, uint256 usedY) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(lowTick),
            TickMath.getSqrtPriceAtTick(highTick),
            expectedLiq
        );

        assertEq(assignableLiq, expectedLiq, "assignableLiq.equals.expectedLiq");
        assertApproxEqAbs(leftoverX, x - uint128(usedX), 1, "leftoverX.equals.x.minus.usedX"); // 1 x lost to dust
        assertEq(leftoverX, 0, "leftoverX.equals.0");
        assertEq(leftoverY, y - uint128(usedY), "leftoverY.equals.y.minus.usedY");
    }

    function testGetAssignableLiqBelowRangeZeroX() public pure {
        (uint128 assignableLiq, uint128 leftoverX, uint128 leftoverY) = PoolLib.getAssignableLiq(
            -2000,
            2000,
            0,
            100e6,
            TickMath.getSqrtPriceAtTick(-3000)
        );
        assertEq(assignableLiq, 0, "assignableLiq.equals.0");
        assertEq(leftoverX, 0, "leftoverX.equals.0");
        assertEq(leftoverY, 100e6, "leftoverY.equals.y");
    }

    // verify we can pass max values w/o overflowing
    function testGetAssignableLiqBelowRangeOverflowCheck() public pure {
        PoolLib.getAssignableLiq(
            TickMath.MIN_TICK + 1,
            TickMath.MAX_TICK,
            type(uint128).max,
            type(uint128).max,
            TickMath.getSqrtPriceAtTick(TickMath.MIN_TICK)
        );
        PoolLib.getAssignableLiq(0, 1, type(uint128).max, type(uint128).max, TickMath.getSqrtPriceAtTick(-1));
    }

    function testGetAssignableLiqAboveRange() public pure {
        int24 lowTick = -2000;
        int24 highTick = 2000;
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(3000);
        uint128 x = 200e18;
        uint128 y = 100e6;

        (uint128 assignableLiq, uint128 leftoverX, uint128 leftoverY) = PoolLib.getAssignableLiq(
            lowTick,
            highTick,
            x,
            y,
            sqrtPriceX96
        );

        uint128 expectedLiq = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(lowTick),
            TickMath.getSqrtPriceAtTick(highTick),
            uint256(x),
            uint256(y)
        );
        (uint256 usedX, uint256 usedY) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(lowTick),
            TickMath.getSqrtPriceAtTick(highTick),
            expectedLiq
        );

        assertEq(assignableLiq, expectedLiq, "assignableLiq.equals.expectedLiq");
        assertEq(leftoverX, x - uint128(usedX), "leftoverX.equals.x.minus.usedX");
        assertApproxEqAbs(leftoverY, y - uint128(usedY), 1, "leftoverY.equals.y.minus.usedY"); // 1 y lost to dust
        assertEq(leftoverY, 0, "leftoverY.equals.0");
    }

    function testGetAssignableLiqAboveRangeZeroY() public pure {
        (uint128 assignableLiq, uint128 leftoverX, uint128 leftoverY) = PoolLib.getAssignableLiq(
            -2000,
            2000,
            200e18,
            0,
            TickMath.getSqrtPriceAtTick(3000)
        );
        assertEq(assignableLiq, 0, "assignableLiq.equals.0");
        assertEq(leftoverX, 200e18, "leftoverX.equals.x");
        assertEq(leftoverY, 0, "leftoverY.equals.0");
    }

    // verify we can pass max values w/o overflowing
    function testGetAssignableLiqAboveRangeOverflowCheck() public pure {
        PoolLib.getAssignableLiq(
            TickMath.MIN_TICK,
            TickMath.MAX_TICK,
            type(uint128).max,
            type(uint128).max,
            TickMath.getSqrtPriceAtTick(TickMath.MAX_TICK)
        );
        PoolLib.getAssignableLiq(0, 1, type(uint128).max, type(uint128).max, TickMath.getSqrtPriceAtTick(2));
    }

    function testGetAssignableLiqInRangeXLiqEqualsYLiq() public pure {
        int24 lowTick = -2000;
        int24 highTick = 2000;
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(0);
        uint128 x = 200e18;
        uint128 y = 200e18;

        (uint128 assignableLiq, uint128 leftoverX, uint128 leftoverY) = PoolLib.getAssignableLiq(
            lowTick,
            highTick,
            x,
            y,
            sqrtPriceX96
        );

        uint128 expectedLiq = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(lowTick),
            TickMath.getSqrtPriceAtTick(highTick),
            uint256(x),
            uint256(y)
        );
        (uint256 usedX, uint256 usedY) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(lowTick),
            TickMath.getSqrtPriceAtTick(highTick),
            expectedLiq
        );

        assertEq(assignableLiq, expectedLiq, "assignableLiq.equals.expectedLiq");
        assertApproxEqAbs(leftoverX, x - uint128(usedX), 1, "leftoverX.equals.x.minus.usedX");
        assertLt(leftoverX, x - uint128(usedX), "leftoverX.lt.x.minus.usedX");
        assertApproxEqAbs(leftoverY, y - uint128(usedY), 1, "leftoverY.equals.y.minus.usedY");
        assertLt(leftoverY, y - uint128(usedY), "leftoverY.lt.y.minus.usedY");
    }

    function testGetAssignableLiqInRangeXLiqLessThanYLiq() public pure {
        int24 lowTick = -2000;
        int24 highTick = 2000;
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(0);
        uint128 x = 100e6;
        uint128 y = 200e18;

        (uint128 assignableLiq, uint128 leftoverX, uint128 leftoverY) = PoolLib.getAssignableLiq(
            lowTick,
            highTick,
            x,
            y,
            sqrtPriceX96
        );

        uint128 expectedLiq = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(lowTick),
            TickMath.getSqrtPriceAtTick(highTick),
            uint256(x),
            uint256(y)
        );
        (uint256 usedX, uint256 usedY) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(lowTick),
            TickMath.getSqrtPriceAtTick(highTick),
            expectedLiq
        );

        assertEq(assignableLiq, expectedLiq, "assignableLiq.equals.expectedLiq");
        assertApproxEqAbs(leftoverX, x - uint128(usedX), 1, "leftoverX.equals.x.minus.usedX");
        assertLt(leftoverX, x - uint128(usedX), "leftoverX.lt.x.minus.usedX");
        assertApproxEqAbs(leftoverY, y - uint128(usedY), 1, "leftoverY.equals.y.minus.usedY");
        assertLt(leftoverY, y - uint128(usedY), "leftoverY.lt.y.minus.usedY");
    }

    function testGetAssignableLiqInRangeXLiqGreaterThanYLiq() public pure {
        int24 lowTick = -2000;
        int24 highTick = 2000;
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(0);
        uint128 x = 200e18;
        uint128 y = 100e6;

        (uint128 assignableLiq, uint128 leftoverX, uint128 leftoverY) = PoolLib.getAssignableLiq(
            lowTick,
            highTick,
            x,
            y,
            sqrtPriceX96
        );

        uint128 expectedLiq = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(lowTick),
            TickMath.getSqrtPriceAtTick(highTick),
            uint256(x),
            uint256(y)
        );
        (uint256 usedX, uint256 usedY) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(lowTick),
            TickMath.getSqrtPriceAtTick(highTick),
            expectedLiq
        );

        assertEq(assignableLiq, expectedLiq, "assignableLiq.equals.expectedLiq");
        assertApproxEqAbs(leftoverX, x - uint128(usedX), 1, "leftoverX.equals.x.minus.usedX");
        assertLt(leftoverX, x - uint128(usedX), "leftoverX.lt.x.minus.usedX");
        assertApproxEqAbs(leftoverY, y - uint128(usedY), 1, "leftoverY.equals.y.minus.usedY");
        assertLt(leftoverY, y - uint128(usedY), "leftoverY.lt.y.minus.usedY");
    }

    // verify we can pass max values w/o overflowing
    function testGetAssignableLiqInRangeOverflowCheckXLiqLessThanYLiq() public pure {
        PoolLib.getAssignableLiq(-10, 10, type(uint128).max, type(uint128).max, TickMath.getSqrtPriceAtTick(-3));
    }

    // verify we can pass max values w/o overflowing
    function testGetAssignableLiqInRangeOverflowCheckXLiqGreaterThanYLiq() public pure {
        PoolLib.getAssignableLiq(-10, 10, type(uint128).max, type(uint128).max, TickMath.getSqrtPriceAtTick(3));
    }

    // verify we can pass max values w/o overflowing
    function testGetAssignableLiqInRangeOverflowCheckXLiqEqualsYLiq() public pure {
        // note: difficult to hit xLiq == yLiq with larger values for x and y
        // hover logic in the other two cases covers logic in this case sufficiently
        PoolLib.getAssignableLiq(-10, 10, 1e21, 1e21, TickMath.getSqrtPriceAtTick(0));
    }

    // Equivalent Liq

    // TODO: double check conversion
    function testGetEquivalentLiqBelowRangeConvertingY() public pure {
        int24 lowTick = -2000;
        int24 highTick = 2000;
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(-3000);
        uint128 x = 200e18;
        uint128 y = 200e18;

        uint128 equivLiqRoundingDown = PoolLib.getEquivalentLiq(
            lowTick,
            highTick,
            x,
            y,
            sqrtPriceX96,
            false
        );
        uint128 equivLiqRoundingUp = PoolLib.getEquivalentLiq(
            lowTick,
            highTick,
            x,
            y,
            sqrtPriceX96,
            true
        );

        assertEq(equivLiqRoundingDown, 2346044413003865165004, "equivLiqRoundingDown");
        assertEq(equivLiqRoundingUp, 2346044413003865165005, "equivLiqRoundingUp");
    }

    function testGetEquivalentLiqBelowRangeNoY() public pure {
        int24 lowTick = -2000;
        int24 highTick = 2000;
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(-3000);
        uint128 x = 200e18;
        uint128 y = 0;

        uint128 equivLiqRoundingDown = PoolLib.getEquivalentLiq(
            lowTick,
            highTick,
            x,
            y,
            sqrtPriceX96,
            false
        );
        uint128 equivLiqRoundingUp = PoolLib.getEquivalentLiq(
            lowTick,
            highTick,
            x,
            y,
            sqrtPriceX96,
            true
        );

        uint128 actualLiq = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(lowTick),
            TickMath.getSqrtPriceAtTick(highTick),
            uint256(x),
            uint256(y)
        );

        assertApproxEqAbs(
            equivLiqRoundingDown,
            equivLiqRoundingUp,
            1,
            "equivLiqRoundingDown.equals.equivLiqRoundingUp"
        );
        assertLt(equivLiqRoundingDown, equivLiqRoundingUp, "equivLiqRoundingDown.lt.equivLiqRoundingUp");
        assertEq(equivLiqRoundingUp, actualLiq, "equivLiqRoundingUp.equals.actualLiq");
    }

    function testFullRangeEquivLiq() public pure {
        int24 lowTick = TickMath.MIN_TICK;
        int24 highTick = TickMath.MAX_TICK;
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(0);
        uint128 x = 1 << 127;
        uint128 y = 1 << 127;

        // Should not revert.
        PoolLib.getEquivalentLiq(lowTick, highTick, x, y, sqrtPriceX96, true);
        console.log("MIN_SQRT_PRICE");
        PoolLib.getEquivalentLiq(lowTick, highTick, x, 1 << 64, TickMath.MIN_SQRT_PRICE, true);
        console.log("MAX_SQRT_PRICE");
        PoolLib.getEquivalentLiq(lowTick, highTick, 1 << 64, y, TickMath.MAX_SQRT_PRICE, true);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testRevertGetEquivalentLiqBelowRangeLiqOverMaxRoundingDown() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeCast.UnsafeUCast.selector,
                13612996131207439090653231373011924683379703,
                type(uint128).max
            )
        );
        PoolLib.getEquivalentLiq(
            0,
            1,
            type(uint128).max,
            type(uint128).max,
            TickMath.getSqrtPriceAtTick(-1),
            false
        );
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testRevertGetEquivalentLiqBelowRangeLiqOverMaxRoundingUp() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeCast.UnsafeUCast.selector,
                13612996131207439090653227936179023555179201,
                type(uint128).max
            )
        );
        PoolLib.getEquivalentLiq(
            0,
            1,
            type(uint128).max,
            type(uint128).max,
            TickMath.getSqrtPriceAtTick(-1),
            true
        );
    }

    // TODO: double check conversion
    function testGetEquivalentLiqAboveRangeConvertingX() public pure {
        int24 lowTick = -2000;
        int24 highTick = 2000;
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(3000);
        uint128 x = 200e18;
        uint128 y = 200e18;

        uint128 equivLiqRoundingDown = PoolLib.getEquivalentLiq(
            lowTick,
            highTick,
            x,
            y,
            sqrtPriceX96,
            false
        );
        uint128 equivLiqRoundingUp = PoolLib.getEquivalentLiq(
            lowTick,
            highTick,
            x,
            y,
            sqrtPriceX96,
            true
        );

        assertEq(equivLiqRoundingDown, 2346044413003865165004, "equivLiqRoundingDown");
        assertEq(equivLiqRoundingUp, 2346044413003865165005, "equivLiqRoundingUp");
    }

    function testGetEquivalentLiqAboveRangeNoX() public pure {
        int24 lowTick = -2000;
        int24 highTick = 2000;
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(3000);
        uint128 x = 0;
        uint128 y = 200e18;

        uint128 equivLiqRoundingDown = PoolLib.getEquivalentLiq(
            lowTick,
            highTick,
            x,
            y,
            sqrtPriceX96,
            false
        );
        uint128 equivLiqRoundingUp = PoolLib.getEquivalentLiq(
            lowTick,
            highTick,
            x,
            y,
            sqrtPriceX96,
            true
        );

        uint128 actualLiq = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(lowTick),
            TickMath.getSqrtPriceAtTick(highTick),
            uint256(x),
            uint256(y)
        );

        // TODO: why is roundingUp equal to actualLiq?
        assertApproxEqAbs(
            equivLiqRoundingDown,
            equivLiqRoundingUp,
            1,
            "equivLiqRoundingDown.equals.equivLiqRoundingUp"
        );
        assertLt(equivLiqRoundingDown, equivLiqRoundingUp, "equivLiqRoundingDown.lt.equivLiqRoundingUp");
        assertEq(equivLiqRoundingUp, actualLiq, "equivLiqRoundingUp.equals.actualLiq");
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testRevertGetEquivalentLiqAboveRangeLiqOverMaxRoundingDown() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeCast.UnsafeUCast.selector,
                13612996182251070166403103976120440650812069,
                type(uint128).max
            )
        );
        PoolLib.getEquivalentLiq(
            0,
            1,
            type(uint128).max,
            type(uint128).max,
            TickMath.getSqrtPriceAtTick(2),
            false
        );
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testRevertGetEquivalentLiqAboveRangeLiqOverMaxRoundingUp() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeCast.UnsafeUCast.selector,
                13612996182251070166403100539287526635776885,
                type(uint128).max
            )
        );
        PoolLib.getEquivalentLiq(
            0,
            1,
            type(uint128).max,
            type(uint128).max,
            TickMath.getSqrtPriceAtTick(2),
            true
        );
    }

    function testGetEquivalentLiqInRangeNoConversion() public pure {
        int24 lowTick = -2000;
        int24 highTick = 2000;
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(0);
        uint128 x = 200e18;
        uint128 y = 200e18;

        uint128 equivLiqRoundingDown = PoolLib.getEquivalentLiq(
            lowTick,
            highTick,
            x,
            y,
            sqrtPriceX96,
            false
        );
        uint128 equivLiqRoundingUp = PoolLib.getEquivalentLiq(
            lowTick,
            highTick,
            x,
            y,
            sqrtPriceX96,
            true
        );

        uint128 actualLiq = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(lowTick),
            TickMath.getSqrtPriceAtTick(highTick),
            uint256(x),
            uint256(y)
        );

        assertApproxEqAbs(
            equivLiqRoundingDown,
            equivLiqRoundingUp,
            1,
            "equivLiqRoundingDown.equals.equivLiqRoundingUp"
        );
        assertLt(equivLiqRoundingDown, equivLiqRoundingUp, "equivLiqRoundingDown.lt.equivLiqRoundingUp");
        assertEq(equivLiqRoundingDown, actualLiq, "equivLiqRoundingDown.equals.actualLiq");
    }

    // TODO: double check conversion
    function testGetEquivalentLiqInRangeConvertingX() public pure {
        int24 lowTick = -2000;
        int24 highTick = 2000;
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(1000);
        uint128 x = 200e18;
        uint128 y = 200e18;

        uint128 equivLiqRoundingDown = PoolLib.getEquivalentLiq(
            lowTick,
            highTick,
            x,
            y,
            sqrtPriceX96,
            false
        );
        uint128 equivLiqRoundingUp = PoolLib.getEquivalentLiq(
            lowTick,
            highTick,
            x,
            y,
            sqrtPriceX96,
            true
        );

        assertEq(equivLiqRoundingDown, 2129710359649553392551, "equivLiqRoundingDown");
        assertEq(equivLiqRoundingUp, 2129710359649553392552, "equivLiqRoundingUp");
    }

    // TODO: double check conversion
    function testGetEquivalentLiqInRangeConvertingY() public pure {
        int24 lowTick = -2000;
        int24 highTick = 2000;
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(-1000);
        uint128 x = 200e18;
        uint128 y = 200e18;

        uint128 equivLiqRoundingDown = PoolLib.getEquivalentLiq(
            lowTick,
            highTick,
            x,
            y,
            sqrtPriceX96,
            false
        );
        uint128 equivLiqRoundingUp = PoolLib.getEquivalentLiq(
            lowTick,
            highTick,
            x,
            y,
            sqrtPriceX96,
            true
        );

        assertEq(equivLiqRoundingDown, 2129710359649553392551, "equivLiqRoundingDown");
        assertEq(equivLiqRoundingUp, 2129710359649553392552, "equivLiqRoundingUp");
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testRevertGetEquivalentLiqInRangeLiqOverMaxRoundingDown() public {
        // Rounding down
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeCast.UnsafeUCast.selector,
                680768916872643588502673350572968592538008,
                type(uint128).max
            )
        );
        PoolLib.getEquivalentLiq(
            -10,
            10,
            type(uint128).max,
            type(uint128).max,
            TickMath.getSqrtPriceAtTick(0),
            false
        );
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testRevertGetEquivalentLiqInRangeLiqOverMaxRoundingUp() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeCast.UnsafeUCast.selector,
                680768916872643588502673333382789253472821,
                type(uint128).max
            )
        );
        PoolLib.getEquivalentLiq(
            -10,
            10,
            type(uint128).max,
            type(uint128).max,
            TickMath.getSqrtPriceAtTick(0),
            true
        );
    }

    function testEquivalentLiqAtDifferentPrices() public pure {
        uint128 liq = PoolLib.getEquivalentLiq(
            -300,
            20,
            123456789,
            987654321,
            TickMath.getSqrtPriceAtTick(-100),
            true
        );

        // If we lower the price, the value of the liq goes down
        uint128 higherLiq = PoolLib.getEquivalentLiq(
            -300,
            20,
            123456789,
            987654321,
            TickMath.getSqrtPriceAtTick(-200),
            true
        );

        assertGt(higherLiq, liq, "higherLiq.gt.liq");
    }

    // Get Amounts

    function testGetAmounts() public pure {
        // No liq
        (uint256 x, uint256 y) = PoolLib.getAmounts(0, 0, 0, 0, false);
        assertEq(x, 0, "x.noLiq");
        assertEq(y, 0, "y.noLiq");

        int24 lowTick = -2000;
        int24 highTick = 2000;

        uint160 sqrtPriceX96;
        uint160 lowSqrtPriceX96 = TickMath.getSqrtPriceAtTick(lowTick);
        uint160 highSqrtPriceX96 = TickMath.getSqrtPriceAtTick(highTick);

        uint256 expectedXRoundingDown;
        uint256 expectedXRoundingUp;
        uint256 expectedYRoundingDown;
        uint256 expectedYRoundingUp;

        uint128 liq = 1000000000000000000;

        // Price below range
        sqrtPriceX96 = TickMath.getSqrtPriceAtTick(lowTick - 2000);

        expectedXRoundingDown = SqrtPriceMath.getAmount0Delta(lowSqrtPriceX96, highSqrtPriceX96, liq, false);
        expectedXRoundingUp = SqrtPriceMath.getAmount0Delta(lowSqrtPriceX96, highSqrtPriceX96, liq, true);

        assertNotEq(expectedXRoundingDown, expectedXRoundingUp, "x.belowRange.roundingDirection.notEqual");

        (x, y) = PoolLib.getAmounts(sqrtPriceX96, lowTick, highTick, liq, false);
        assertEq(x, expectedXRoundingDown, "x.belowRange.roundingDown");
        assertEq(y, 0, "y.belowRange.roundingDown");

        (x, y) = PoolLib.getAmounts(sqrtPriceX96, lowTick, highTick, liq, true);
        assertEq(x, expectedXRoundingUp, "x.belowRange.roundingUp");
        assertEq(y, 0, "y.belowRange.roundingUp");

        // Price above range
        sqrtPriceX96 = TickMath.getSqrtPriceAtTick(highTick + 2000);

        expectedYRoundingDown = SqrtPriceMath.getAmount1Delta(lowSqrtPriceX96, highSqrtPriceX96, liq, false);
        expectedYRoundingUp = SqrtPriceMath.getAmount1Delta(lowSqrtPriceX96, highSqrtPriceX96, liq, true);

        (x, y) = PoolLib.getAmounts(sqrtPriceX96, lowTick, highTick, liq, false);
        (x, y) = PoolLib.getAmounts(sqrtPriceX96, lowTick, highTick, liq, false);
        assertEq(x, 0, "x.aboveRange.roundingDown");
        assertEq(y, expectedYRoundingDown, "y.aboveRange.roundingDown");

        (x, y) = PoolLib.getAmounts(sqrtPriceX96, lowTick, highTick, liq, true);
        assertEq(x, 0, "x.aboveRange.roundingUp");
        assertEq(y, expectedYRoundingUp, "y.aboveRange.roundingUp");

        // Price in range
        sqrtPriceX96 = TickMath.getSqrtPriceAtTick(lowTick + (highTick - lowTick) / 2);

        expectedXRoundingDown = SqrtPriceMath.getAmount0Delta(sqrtPriceX96, highSqrtPriceX96, liq, false);
        expectedXRoundingUp = SqrtPriceMath.getAmount0Delta(sqrtPriceX96, highSqrtPriceX96, liq, true);
        expectedYRoundingDown = SqrtPriceMath.getAmount1Delta(lowSqrtPriceX96, sqrtPriceX96, liq, false);
        expectedYRoundingUp = SqrtPriceMath.getAmount1Delta(lowSqrtPriceX96, sqrtPriceX96, liq, true);

        (x, y) = PoolLib.getAmounts(sqrtPriceX96, lowTick, highTick, liq, false);
        assertEq(x, expectedXRoundingDown, "x.inRange.roundingDown");
        assertEq(y, expectedYRoundingDown, "y.inRange.roundingDown");

        (x, y) = PoolLib.getAmounts(sqrtPriceX96, lowTick, highTick, liq, true);
        assertEq(x, expectedXRoundingUp, "x.inRange.roundingUp");
        assertEq(y, expectedYRoundingUp, "y.inRange.roundingUp");
    }

}

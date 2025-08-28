// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { IUniswapV3Pool } from "v3-core/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3MintCallback } from "v3-core/interfaces/callback/IUniswapV3MintCallback.sol";
import { TransferHelper } from "Commons/Util/TransferHelper.sol";
import { SqrtPriceMath } from "v4-core/libraries/SqrtPriceMath.sol";
import { TickMath } from "v4-core/libraries/TickMath.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { UniV3IntegrationSetup } from "./UniV3.u.sol";
import { PoolLib, PoolInfo } from "../src/Pool.sol";

contract PoolTest is Test, UniV3IntegrationSetup {
    address poolAddr;
    IUniswapV3Pool pool;
    bool bypassPoolGuardAssert;

    function setUp() public {
        setUpPool();

        poolAddr = pools[0];
        pool = IUniswapV3Pool(poolAddr);
    }

    function testGetPoolInfo() public {
        PoolInfo memory pInfo = PoolLib.getPoolInfo(poolAddr);
        assertEq(pInfo.poolAddr, poolAddr);
        assertEq(pInfo.token0, pool.token0());
        assertEq(pInfo.token1, pool.token1());
        assertEq(pInfo.tickSpacing, pool.tickSpacing());
        // assertEq(pInfo.treeWidth, pool.treeWidth());

        console.log("pInfo.tickSpacing", pInfo.tickSpacing);
    }

    function testGetSqrtPriceX96() public {
        (uint160 slot0SqrtPriceX96, int24 slot0Tick, , , , , ) = pool.slot0();
        assertEq(slot0SqrtPriceX96, PoolLib.getSqrtPriceX96(poolAddr));

        uint160 currentTickSqrtPriceX96 = TickMath.getSqrtPriceAtTick(slot0Tick);
        uint160 nextTickSqrtPriceX96 = TickMath.getSqrtPriceAtTick(slot0Tick + pool.tickSpacing());
        uint160 middleSqrtPriceX96 = currentTickSqrtPriceX96 + (nextTickSqrtPriceX96 - currentTickSqrtPriceX96) / 2;

        // verify assumptions 
        assertLt(currentTickSqrtPriceX96, nextTickSqrtPriceX96);
        assertLt(middleSqrtPriceX96, nextTickSqrtPriceX96);
        assertGt(middleSqrtPriceX96, currentTickSqrtPriceX96);

        // swap to price between ticks
        swapTo(0, middleSqrtPriceX96);

        (slot0SqrtPriceX96, , , , , , ) = pool.slot0();
        assertEq(slot0SqrtPriceX96, PoolLib.getSqrtPriceX96(poolAddr));
        assertEq(slot0SqrtPriceX96, middleSqrtPriceX96);


        // Verify reported sqrt price can lie between ticks
        // console.log("currentTickSqrtPriceX96", currentTickSqrtPriceX96);
        // console.log("nextTickSqrtPriceX96", nextTickSqrtPriceX96);
        // console.log("middleSqrtPriceX96", middleSqrtPriceX96);
        // uint160 sqrtPriceX96 = PoolLib.getSqrtPriceX96(poolAddr);
        // console.log("sqrtPriceX96", sqrtPriceX96);
        // assertEq(sqrtPriceX96, slot0SqrtPriceX96);
    }

    function testGetLiq() public {
        // Position 1
        int24 tickLower = pool.tickSpacing() * -10;
        int24 tickUpper = pool.tickSpacing() * 10;

        uint128 liq = PoolLib.getLiq(poolAddr, tickLower, tickUpper);
        assertEq(liq, 0, "liq.position1.noLiq");

        PoolLib.mint(poolAddr, tickLower, tickUpper, 1e20);
        liq = PoolLib.getLiq(poolAddr, tickLower, tickUpper);
        assertEq(liq, 1e20, "liq.position1.mint1");

        PoolLib.mint(poolAddr, tickLower, tickUpper, 2e20);
        liq = PoolLib.getLiq(poolAddr, tickLower, tickUpper);
        assertEq(liq, 3e20, "liq.position1.mint2");

        // Position 1
        tickUpper = pool.tickSpacing() * 20;

        liq = PoolLib.getLiq(poolAddr, tickLower, tickUpper);
        assertEq(liq, 0, "liq.position2.noLiq");

        PoolLib.mint(poolAddr, tickLower, tickUpper, 1e5);
        liq = PoolLib.getLiq(poolAddr, tickLower, tickUpper);
        assertEq(liq, 1e5, "liq.position2.mint1");
    }

    function testMint() public {
        int24 tickSpacing = pool.tickSpacing();
        int24 tickLower = tickSpacing * -10;
        int24 tickUpper = tickSpacing * 10;
        uint128 liq = 1e20;

        uint256 balance0 = IERC20(pool.token0()).balanceOf(address(this));
        uint256 balance1 = IERC20(pool.token1()).balanceOf(address(this));

        bypassPoolGuardAssert = true;
        (uint256 directMint0, uint256 directMint1) = pool.mint(address(this), tickLower, tickUpper, liq, "");
        bypassPoolGuardAssert = false;

        vm.expectCall(
            poolAddr, abi.encodeCall(pool.mint, (address(this), tickLower, tickUpper, liq, ""))
        );
        (uint256 mint0, uint256 mint1) = PoolLib.mint(poolAddr, tickLower, tickUpper, liq);

        assertEq(mint0, directMint0, "mint0");
        assertEq(mint1, directMint1, "mint1");

        assertEq(balance0 - directMint0 - mint0, IERC20(pool.token0()).balanceOf(address(this)), "recieved.token0");
        assertEq(balance1 - directMint1 - mint1, IERC20(pool.token1()).balanceOf(address(this)), "recieved.token1");
    }

    function testBurn() public {
        int24 tickSpacing = pool.tickSpacing();
        int24 tickLower = tickSpacing * -10;
        int24 tickUpper = tickSpacing * 10;
        uint128 liq = 1e20;

        (uint256 mint0, uint256 mint1) = PoolLib.mint(poolAddr, tickLower, tickUpper, liq);

        vm.expectCall(
            poolAddr, abi.encodeCall(pool.burn, (tickLower, tickUpper, liq))
        );
        (uint256 burn0, uint256 burn1) = PoolLib.burn(poolAddr, tickLower, tickUpper, liq);
        
        assertApproxEqAbs(mint0, burn0, 1, "mint0.equals.burn0");
        assertApproxEqAbs(mint1, burn1, 1, "mint1.equals.burn1");
    }

    function testCollect() public {
        int24 tickSpacing = pool.tickSpacing();
        int24 tickLower = tickSpacing * -10;
        int24 tickUpper = tickSpacing * 10;
        uint128 liq = 1e20;

        PoolLib.mint(poolAddr, tickLower, tickUpper, liq);
        (uint256 burn0, uint256 burn1) = PoolLib.burn(poolAddr, tickLower, tickUpper, liq);

        uint256 balance0 = IERC20(pool.token0()).balanceOf(address(this));
        uint256 balance1 = IERC20(pool.token1()).balanceOf(address(this));

        vm.expectCall(
            poolAddr, abi.encodeCall(pool.collect, (address(this), tickLower, tickUpper, type(uint128).max, type(uint128).max))
        );
        (uint256 collect0, uint256 collect1) = PoolLib.collect(poolAddr, tickLower, tickUpper);

        assertEq(collect0, burn0, "collect0.equals.burn0");
        assertEq(collect1, burn1, "collect1.equals.burn1");

        assertEq(balance0 + collect0, IERC20(pool.token0()).balanceOf(address(this)), "recieved.token0");
        assertEq(balance1 + collect1, IERC20(pool.token1()).balanceOf(address(this)), "recieved.token1");
    }

    // Get Amounts 

    function testGetAmounts() public {
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

    // Mint Callback 

    function uniswapV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata) external override {
        if (!bypassPoolGuardAssert) {
            assertEq(PoolLib.poolGuard(), msg.sender, "poolGuard.mintCallback");
        }

        TransferHelper.safeTransfer(pool.token0(), msg.sender, amount0Owed);
        TransferHelper.safeTransfer(pool.token1(), msg.sender, amount1Owed);
    }
    
}
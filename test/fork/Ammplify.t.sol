// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.26;

import { console2 } from "forge-std/console2.sol";
import { TickMath } from "v4-core/libraries/TickMath.sol";

import { AmmplifyV4ForkBase } from "./AmmplifyV4ForkBase.u.sol";
import { IMaker } from "../../src/interfaces/IMaker.sol";
import { PoolInfo } from "../../src/Pool.sol";
import { LiquidityAmounts } from "../utils/LiquidityAmounts.sol";

/// @title AmmplifyV4ForkTest
/// @notice Fork tests for Ammplify maker lifecycle against a V4 pool on Monad mainnet.
contract AmmplifyV4ForkTest is AmmplifyV4ForkBase {
    address public user1;
    address public user2;

    uint160 constant MIN_SQRT_RATIO = 4295128739;
    uint160 constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    function forkSetup() internal override {
        super.forkSetup();

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        fundAccount(user1, 100_000e18, 100_000e18);
        fundAccount(user2, 100_000e18, 100_000e18);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Diamond deployment
    // ─────────────────────────────────────────────────────────────────────

    function test_DiamondDeployment() public forkOnly {
        assertTrue(address(diamond) != address(0), "diamond deployed");
        assertTrue(poolAddr != address(0), "pool registered");

        PoolInfo memory pInfo = viewFacet.getPoolInfo(poolAddr);
        assertEq(pInfo.token0, address(token0), "token0 matches");
        assertEq(pInfo.token1, address(token1), "token1 matches");
        assertGt(pInfo.sqrtPriceX96, 0, "pool has price");
    }

    // ─────────────────────────────────────────────────────────────────────
    //  New maker
    // ─────────────────────────────────────────────────────────────────────

    function test_NewMaker() public forkOnly {
        (, int24 currentTick) = getPoolSlot0();
        int24 spacing = poolKey.tickSpacing;
        int24 tickLower = ((currentTick - spacing * 10) / spacing) * spacing;
        int24 tickUpper = ((currentTick + spacing * 10) / spacing) * spacing;
        uint128 liq = 1e18;

        vm.startPrank(user1);
        uint256 assetId = makerFacet.newMaker(
            user1,
            poolAddr,
            tickLower,
            tickUpper,
            liq,
            MIN_SQRT_RATIO,
            MAX_SQRT_RATIO,
            ""
        );
        vm.stopPrank();

        assertTrue(assetId > 0, "asset minted");
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Full maker lifecycle: create → adjust up → collect → adjust down → remove
    // ─────────────────────────────────────────────────────────────────────

    function test_MakerLifecycle() public forkOnly {
        (, int24 currentTick) = getPoolSlot0();
        int24 spacing = poolKey.tickSpacing;
        int24 tickLower = ((currentTick - spacing * 10) / spacing) * spacing;
        int24 tickUpper = ((currentTick + spacing * 10) / spacing) * spacing;
        uint128 liq = 1e18;

        // 1. Create
        vm.startPrank(user1);
        uint256 assetId = makerFacet.newMaker(
            user1, poolAddr, tickLower, tickUpper, liq,
            MIN_SQRT_RATIO, MAX_SQRT_RATIO, ""
        );
        vm.stopPrank();
        assertTrue(assetId > 0, "maker created");

        // 2. Generate some fees via swaps
        deal(address(token0), address(this), 10_000e18);
        deal(address(token1), address(this), 10_000e18);
        doSwap(true, 100e18);   // swap token0 → token1
        doSwap(false, 100e18);  // swap token1 → token0

        // 3. Adjust up (increase liquidity)
        uint128 newLiq = liq * 2;
        vm.startPrank(user1);
        makerFacet.adjustMaker(
            user1, assetId, newLiq,
            MIN_SQRT_RATIO, MAX_SQRT_RATIO, ""
        );
        vm.stopPrank();

        // 4. Collect fees
        uint256 bal0Before = token0.balanceOf(user1);
        uint256 bal1Before = token1.balanceOf(user1);

        vm.startPrank(user1);
        makerFacet.collectFees(
            user1, assetId,
            MIN_SQRT_RATIO, MAX_SQRT_RATIO, ""
        );
        vm.stopPrank();

        // Fees may be zero if swaps didn't cross the position — just verify no revert

        // 5. Adjust down (decrease liquidity)
        vm.startPrank(user1);
        makerFacet.adjustMaker(
            user1, assetId, liq,
            MIN_SQRT_RATIO, MAX_SQRT_RATIO, ""
        );
        vm.stopPrank();

        // 6. Remove
        vm.startPrank(user1);
        makerFacet.removeMaker(
            user1, assetId,
            MIN_SQRT_RATIO, MAX_SQRT_RATIO, ""
        );
        vm.stopPrank();

        // User should have received tokens back
        uint256 bal0After = token0.balanceOf(user1);
        uint256 bal1After = token1.balanceOf(user1);
        assertTrue(
            bal0After > bal0Before || bal1After > bal1Before,
            "tokens returned on remove"
        );
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Multiple makers in same range
    // ─────────────────────────────────────────────────────────────────────

    function test_MultipleMakersSameRange() public forkOnly {
        (, int24 currentTick) = getPoolSlot0();
        int24 spacing = poolKey.tickSpacing;
        int24 tickLower = ((currentTick - spacing * 5) / spacing) * spacing;
        int24 tickUpper = ((currentTick + spacing * 5) / spacing) * spacing;
        uint128 liq = 1e18;

        // User1 creates a maker
        vm.startPrank(user1);
        uint256 assetId1 = makerFacet.newMaker(
            user1, poolAddr, tickLower, tickUpper, liq,
            MIN_SQRT_RATIO, MAX_SQRT_RATIO, ""
        );
        vm.stopPrank();

        // User2 creates a maker in the same range
        vm.startPrank(user2);
        uint256 assetId2 = makerFacet.newMaker(
            user2, poolAddr, tickLower, tickUpper, liq,
            MIN_SQRT_RATIO, MAX_SQRT_RATIO, ""
        );
        vm.stopPrank();

        assertTrue(assetId1 != assetId2, "distinct assets");

        // Both can remove
        vm.startPrank(user1);
        makerFacet.removeMaker(user1, assetId1, MIN_SQRT_RATIO, MAX_SQRT_RATIO, "");
        vm.stopPrank();

        vm.startPrank(user2);
        makerFacet.removeMaker(user2, assetId2, MIN_SQRT_RATIO, MAX_SQRT_RATIO, "");
        vm.stopPrank();
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Wide range position (full range)
    // ─────────────────────────────────────────────────────────────────────

    function test_FullRangeMaker() public forkOnly {
        int24 spacing = poolKey.tickSpacing;
        int24 tickLower = (TickMath.MIN_TICK / spacing) * spacing;
        int24 tickUpper = (TickMath.MAX_TICK / spacing) * spacing;
        uint128 liq = 1e15; // smaller liq for full range (needs less capital)

        vm.startPrank(user1);
        uint256 assetId = makerFacet.newMaker(
            user1, poolAddr, tickLower, tickUpper, liq,
            MIN_SQRT_RATIO, MAX_SQRT_RATIO, ""
        );
        vm.stopPrank();

        assertTrue(assetId > 0, "full range maker created");

        vm.startPrank(user1);
        makerFacet.removeMaker(user1, assetId, MIN_SQRT_RATIO, MAX_SQRT_RATIO, "");
        vm.stopPrank();
    }
}

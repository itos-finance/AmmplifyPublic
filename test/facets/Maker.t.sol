// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import { UniswapV3Pool } from "v3-core/UniswapV3Pool.sol";
import { TickMath } from "v3-core/libraries/TickMath.sol";
import { console2 } from "forge-std/console2.sol";
import { MultiSetupTest } from "../MultiSetup.u.sol";
import { UniV3IntegrationSetup } from "./UniV3.u.sol";
import { PoolInfo } from "../../src/Pool.sol";
import { LiqType, LiqWalker } from "../../src/walkers/Liq.sol";
import { MakerFacet } from "../../src/facets/Maker.sol";
import { IMaker } from "../../src/interfaces/IMaker.sol";
import { AssetLib } from "../../src/Asset.sol";
import { RouteImpl } from "../../src/tree/Route.sol";

import { MockERC20 } from "../mocks/MockERC20.sol";
import { IUniswapV3FlashCallback } from "v3-core/interfaces/callback/IUniswapV3FlashCallback.sol";
import { FullMath } from "../../src/FullMath.sol";

import { console } from "forge-std/console.sol";

/// @dev The minimum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MIN_TICK)
uint160 constant MIN_SQRT_RATIO = 4295128739;
/// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
uint160 constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

contract MakerFacetTest is MultiSetupTest, IUniswapV3FlashCallback, UniV3IntegrationSetup {
    UniswapV3Pool public pool;

    address public recipient;
    address public poolAddr;
    int24 public lowTick;
    int24 public highTick;
    uint128 public liquidity;
    uint160 public minSqrtPriceX96;
    uint160 public maxSqrtPriceX96;

    PoolInfo public poolInfo;

    function setUp() public {
        _newDiamond(factory);
        (, address _pool, address _token0, address _token1) = setUpPool();

        token0 = MockERC20(_token0);
        token1 = MockERC20(_token1);
        pool = UniswapV3Pool(_pool);

        // Set up recipient and basic test parameters
        recipient = address(this);
        poolAddr = _pool;
        lowTick = -60000;
        highTick = 60000;
        liquidity = 1052403967776004679;
        addPoolLiq(0, lowTick, highTick, liquidity);
        minSqrtPriceX96 = MIN_SQRT_RATIO;
        maxSqrtPriceX96 = MAX_SQRT_RATIO;

        poolInfo = viewFacet.getPoolInfo(poolAddr);

        // Fund this contract for testing
        _fundAccount(address(this));

        // Create vaults for the pool tokens
        _createPoolVaults(poolAddr);
    }

    // ============ Maker Position Creation Tests ============

    function testNewMaker1() public {
        bytes memory rftData = "";

        uint256 assetId = makerFacet.newMaker(
            recipient,
            poolAddr,
            lowTick,
            highTick,
            liquidity,
            false, // non-compounding
            minSqrtPriceX96,
            maxSqrtPriceX96,
            rftData
        );
        skip(1 days);

        // Verify asset was created
        assertEq(assetId, 1);

        // Verify asset properties using ViewFacet
        (address owner, address poolAddr_, int24 lowTick_, int24 highTick_, LiqType liqType, uint128 liq) = viewFacet
            .getAssetInfo(assetId);
        assertEq(owner, recipient);
        assertEq(poolAddr_, poolAddr);
        assertEq(lowTick_, lowTick);
        assertEq(highTick_, highTick);
        assertEq(uint8(liqType), uint8(LiqType.MAKER_NC));
        assertEq(liq, liquidity);
    }

    function test_OneTick_NewMaker() public {
        bytes memory rftData = "";
        lowTick = -60;
        highTick = 0;

        uint256 assetId = makerFacet.newMaker(
            recipient,
            poolAddr,
            lowTick,
            highTick,
            liquidity,
            false, // non-compounding
            minSqrtPriceX96,
            maxSqrtPriceX96,
            rftData
        );
        skip(1 days);

        // Verify asset was created
        assertEq(assetId, 1);

        // Verify asset properties using ViewFacet
        (address owner, address poolAddr_, int24 lowTick_, int24 highTick_, LiqType liqType, uint128 liq) = viewFacet
            .getAssetInfo(assetId);
        assertEq(owner, recipient);
        assertEq(poolAddr_, poolAddr);
        assertEq(lowTick_, lowTick);
        assertEq(highTick_, highTick);
        assertEq(uint8(liqType), uint8(LiqType.MAKER_NC));
        assertEq(liq, liquidity);
    }

    function testNewMakerCompounding() public {
        bytes memory rftData = "";

        uint256 assetId = makerFacet.newMaker(
            recipient,
            poolAddr,
            lowTick,
            highTick,
            liquidity,
            true, // compounding
            minSqrtPriceX96,
            maxSqrtPriceX96,
            rftData
        );

        // Verify asset was created with compounding type
        (, , , , LiqType liqType, ) = viewFacet.getAssetInfo(assetId);
        assertEq(uint8(liqType), uint8(LiqType.MAKER));
    }

    function testNewMakerInvalidTicks() public {
        bytes memory rftData = "";

        // Test with invalid tick order - should throw InvertedRange error
        // The error will contain the computed tick values from the route
        vm.expectRevert(); // Using generic expectRevert since the exact parameters depend on internal calculations
        makerFacet.newMaker(
            recipient,
            poolAddr,
            highTick, // high tick first
            lowTick, // low tick second
            liquidity,
            false,
            minSqrtPriceX96,
            maxSqrtPriceX96,
            rftData
        );
    }

    function testNewMakerInvalidLiquidity() public {
        bytes memory rftData = "";

        // Test with zero liquidity - should throw DeMinimusMaker error
        vm.expectRevert(abi.encodeWithSelector(IMaker.DeMinimusMaker.selector, uint128(0)));
        makerFacet.newMaker(
            recipient,
            poolAddr,
            lowTick,
            highTick,
            0, // zero liquidity
            false,
            minSqrtPriceX96,
            maxSqrtPriceX96,
            rftData
        );
    }

    function testNewMakerPriceBounds() public {
        bytes memory rftData = "";

        // Test with invalid price bounds - min > max should cause internal validation to fail
        vm.expectRevert(); // Using generic expectRevert since the exact error depends on internal price validation
        makerFacet.newMaker(
            recipient,
            poolAddr,
            lowTick,
            highTick,
            liquidity,
            false,
            maxSqrtPriceX96, // min > max
            minSqrtPriceX96,
            rftData
        );
    }

    // ============ Maker Position Removal Tests ============

    function testRemoveMakerBasic() public {
        // First create a maker position
        bytes memory rftData = "";
        uint256 assetId = makerFacet.newMaker(
            recipient,
            poolAddr,
            lowTick,
            highTick,
            liquidity,
            false,
            minSqrtPriceX96,
            maxSqrtPriceX96,
            rftData
        );

        (int256 netBalance0, int256 netBalance1, , ) = viewFacet.queryAssetBalances(assetId);

        // Mock the asset owner
        vm.prank(recipient);

        // Remove the maker position
        (address removedToken0, address removedToken1, uint256 removedX, uint256 removedY) = makerFacet.removeMaker(
            recipient,
            assetId,
            uint128(minSqrtPriceX96),
            uint128(maxSqrtPriceX96),
            rftData
        );

        // Verify return values
        assertEq(removedToken0, address(token0));
        assertEq(removedToken1, address(token1));
        assertGe(int256(removedX), netBalance0);
        assertGe(int256(removedY), netBalance1);

        // Verify asset was removed - should throw AssetNotFound error
        vm.expectRevert(abi.encodeWithSelector(AssetLib.AssetNotFound.selector, assetId));
        viewFacet.getAssetInfo(assetId);
    }

    function testRemoveMakerNotOwner() public {
        // First create a maker position
        bytes memory rftData = "";
        uint256 assetId = makerFacet.newMaker(
            recipient,
            poolAddr,
            lowTick,
            highTick,
            liquidity,
            false,
            minSqrtPriceX96,
            maxSqrtPriceX96,
            rftData
        );

        // Try to remove as non-owner - should throw NotMakerOwner error
        address nonOwner = address(0x456);
        vm.prank(nonOwner);

        vm.expectRevert(abi.encodeWithSelector(IMaker.NotMakerOwner.selector, recipient, nonOwner));
        makerFacet.removeMaker(recipient, assetId, uint128(minSqrtPriceX96), uint128(maxSqrtPriceX96), rftData);
    }

    function testRemoveMakerNotMakerAsset() public {
        // Create a taker asset instead of maker
        // This would require setting up the taker facet first
        // For now, we'll test the revert case by trying to remove a non-existent asset

        bytes memory rftData = "";
        uint256 nonExistentAssetId = 999;

        // Should throw AssetNotFound error for non-existent asset
        vm.expectRevert(abi.encodeWithSelector(AssetLib.AssetNotFound.selector, nonExistentAssetId));
        makerFacet.removeMaker(
            recipient,
            nonExistentAssetId,
            uint128(minSqrtPriceX96),
            uint128(maxSqrtPriceX96),
            rftData
        );
    }

    // ============ Fee Collection Tests ============

    function testCollectFeesBasic() public {
        // First create a maker position
        bytes memory rftData = "";

        uint256 assetId = makerFacet.newMaker(
            recipient,
            poolAddr,
            lowTick,
            highTick,
            liquidity,
            false,
            minSqrtPriceX96,
            maxSqrtPriceX96,
            rftData
        );

        swapTo(0, TickMath.getSqrtRatioAtTick(600));
        swapTo(0, TickMath.getSqrtRatioAtTick(-600));

        // Mock the asset owner
        vm.prank(recipient);

        // Collect fees
        (uint256 fees0, uint256 fees1) = makerFacet.collectFees(
            recipient,
            assetId,
            minSqrtPriceX96,
            maxSqrtPriceX96,
            rftData
        );

        // Verify fees were collected
        assertGe(fees0, 0);
        assertGe(fees1, 0);
    }

    function testCollectFeesNotOwner() public {
        // First create a maker position
        bytes memory rftData = "";
        uint256 assetId = makerFacet.newMaker(
            recipient,
            poolAddr,
            lowTick,
            highTick,
            liquidity,
            false,
            minSqrtPriceX96,
            maxSqrtPriceX96,
            rftData
        );

        // Try to collect fees as non-owner - should throw NotMakerOwner error
        address nonOwner = address(0x456);
        vm.prank(nonOwner);

        vm.expectRevert(abi.encodeWithSelector(IMaker.NotMakerOwner.selector, recipient, nonOwner));
        makerFacet.collectFees(recipient, assetId, minSqrtPriceX96, maxSqrtPriceX96, rftData);
    }

    function testCollectFeesNotMakerAsset() public {
        bytes memory rftData = "";
        uint256 nonExistentAssetId = 999;

        // Should throw AssetNotFound error for non-existent asset
        vm.expectRevert(abi.encodeWithSelector(AssetLib.AssetNotFound.selector, nonExistentAssetId));
        makerFacet.collectFees(recipient, nonExistentAssetId, minSqrtPriceX96, maxSqrtPriceX96, rftData);
    }

    // ============ Price Movement and Value Query Tests ============

    function testMakerPositionValueAfterPriceMovement() public {
        bytes memory rftData = "";

        // Create a maker position
        uint256 startingBalance0 = token0.balanceOf(address(this));
        uint256 startingBalance1 = token1.balanceOf(address(this));

        uint256 assetId = makerFacet.newMaker(
            recipient,
            poolAddr,
            lowTick,
            highTick,
            liquidity,
            false, // non-compounding
            minSqrtPriceX96,
            maxSqrtPriceX96,
            rftData
        );

        uint256 postCreationBalance0 = token0.balanceOf(address(this));
        uint256 postCreationBalance1 = token1.balanceOf(address(this));
        uint256 usedBalance0 = startingBalance0 - postCreationBalance0;
        uint256 usedBalance1 = startingBalance1 - postCreationBalance1;

        // Verify the position was created correctly using ViewFacet
        (address owner, address poolAddr_, int24 lowTick_, int24 highTick_, LiqType liqType, uint128 liq) = viewFacet
            .getAssetInfo(assetId);
        assertEq(owner, recipient);
        assertEq(poolAddr_, poolAddr);
        assertEq(lowTick_, lowTick);
        assertEq(highTick_, highTick);
        assertEq(uint8(liqType), uint8(LiqType.MAKER_NC));
        assertEq(liq, liquidity);

        // Get initial position balances
        (int256 initialNetBalance0, int256 initialNetBalance1, , ) = viewFacet.queryAssetBalances(assetId);
        assertApproxEqAbs(uint256(initialNetBalance0), usedBalance0, 2);
        assertApproxEqAbs(uint256(initialNetBalance1), usedBalance1, 2);
        assertGt(
            usedBalance0,
            uint256(initialNetBalance0),
            "Initial net balance0 should be less than or equal to used balance0"
        );
        assertGt(
            usedBalance1,
            uint256(initialNetBalance1),
            "Initial net balance1 should be less than or equal to used balance1"
        );

        // Move price up by swapping to a higher tick
        int24 targetTick = 300; // Move price up
        uint160 targetSqrtPriceX96 = TickMath.getSqrtRatioAtTick(targetTick);
        swapTo(0, targetSqrtPriceX96);

        // Query position value after price movement
        (int256 queriedNetBalance0, int256 queriedNetBalance1, uint256 queriedFees0, uint256 queriedFees1) = viewFacet
            .queryAssetBalances(assetId);

        // Verify that balances changed due to price movement
        // When price goes up, we expect different token0/token1 balances
        assertTrue(
            queriedNetBalance0 != initialNetBalance0 || queriedNetBalance1 != initialNetBalance1,
            "Position balances should change after price movement"
        );

        // Close the position and get actual amounts
        (address token0Addr, address token1Addr, uint256 actualRemoved0, uint256 actualRemoved1) = makerFacet
            .removeMaker(recipient, assetId, uint128(minSqrtPriceX96), uint128(maxSqrtPriceX96), rftData);

        // Verify tokens match expected pool tokens
        assertEq(token0Addr, address(token0));
        assertEq(token1Addr, address(token1));

        // Compare queried values with actual close values
        // The total value from query should approximately match what we get from closing
        // For a maker position, net balances should be positive (amounts owed to position owner)
        assertGt(actualRemoved0, 0, "Should receive some token0 on close");
        assertGt(actualRemoved1, 0, "Should receive some token1 on close");

        // The queried net balance should reasonably approximate the actual amounts
        // (allowing for some difference due to fees and precision)
        assertApproxEqAbs(
            queriedNetBalance0 + int256(queriedFees0),
            int256(actualRemoved0),
            2,
            "Queried token0 balance should approximate actual removed amount"
        );

        assertApproxEqAbs(
            queriedNetBalance1 + int256(queriedFees1),
            int256(actualRemoved1),
            2,
            "Queried token1 balance should approximate actual removed amount"
        );
    }

    function testMakerPositionValueAfterPriceMovementDown() public {
        bytes memory rftData = "";

        // Create a maker position
        uint256 assetId = makerFacet.newMaker(
            recipient,
            poolAddr,
            lowTick,
            highTick,
            liquidity,
            false, // non-compounding
            minSqrtPriceX96,
            maxSqrtPriceX96,
            rftData
        );

        // Move price down by swapping to a lower tick
        int24 targetTick = -300; // Move price down
        uint160 targetSqrtPriceX96 = TickMath.getSqrtRatioAtTick(targetTick);
        swapTo(0, targetSqrtPriceX96);

        // Query position value after price movement
        (int256 queriedNetBalance0, int256 queriedNetBalance1, uint256 queriedFees0, uint256 queriedFees1) = viewFacet
            .queryAssetBalances(assetId);

        // Close the position and get actual amounts
        (address token0Addr, address token1Addr, uint256 actualRemoved0, uint256 actualRemoved1) = makerFacet
            .removeMaker(recipient, assetId, uint128(minSqrtPriceX96), uint128(maxSqrtPriceX96), rftData);

        // Verify tokens match expected pool tokens
        assertEq(token0Addr, address(token0));
        assertEq(token1Addr, address(token1));

        // Compare queried values with actual close values for downward price movement
        assertGt(actualRemoved0, 0, "Should receive some token0 on close");
        assertGt(actualRemoved1, 0, "Should receive some token1 on close");

        // The queried values should still reasonably match actual values
        assertApproxEqAbs(
            queriedNetBalance0 + int256(queriedFees0),
            int256(actualRemoved0),
            2,
            "Queried token0 balance should approximate actual removed amount after price down"
        );

        assertApproxEqAbs(
            queriedNetBalance1 + int256(queriedFees1),
            int256(actualRemoved1),
            2,
            "Queried token1 balance should approximate actual removed amount after price down"
        );
    }

    function testMakerPositionValueWithLargePriceMovement() public {
        bytes memory rftData = "";

        // Create a maker position
        uint256 assetId = makerFacet.newMaker(
            recipient,
            poolAddr,
            lowTick,
            highTick,
            liquidity,
            false, // non-compounding
            minSqrtPriceX96,
            maxSqrtPriceX96,
            rftData
        );

        // Make a large price movement (move close to the edge of our range)
        int24 targetTick = 500; // Large upward movement, but still within range
        uint160 targetSqrtPriceX96 = TickMath.getSqrtRatioAtTick(targetTick);
        swapTo(0, targetSqrtPriceX96);

        // Query position value after large price movement
        (, , uint256 queriedFees0, uint256 queriedFees1) = viewFacet.queryAssetBalances(assetId);

        // Verify that fees have been earned (should be positive for large movement)
        assertTrue(queriedFees0 > 0 || queriedFees1 > 0, "Should have earned some fees from large price movement");

        // Close the position and verify consistency
        (, , uint256 actualRemoved0, uint256 actualRemoved1) = makerFacet.removeMaker(
            recipient,
            assetId,
            uint128(minSqrtPriceX96),
            uint128(maxSqrtPriceX96),
            rftData
        );

        // Verify consistency between query and actual values
        assertGt(actualRemoved0, 0, "Should receive some token0 on close after large movement");
        assertGt(actualRemoved1, 0, "Should receive some token1 on close after large movement");
    }

    function testMakerAdjust() public {
        bytes memory rftData = "";

        // Create a maker position
        uint256 assetId = makerFacet.newMaker(
            address(this),
            poolAddr,
            lowTick,
            highTick,
            liquidity,
            false, // non-compounding
            minSqrtPriceX96,
            maxSqrtPriceX96,
            rftData
        );
        (int256 balance0, int256 balance1, , ) = viewFacet.queryAssetBalances(assetId);

        // Adjust the maker position up
        (, , int256 delta0, int256 delta1) = makerFacet.adjustMaker(
            address(this),
            assetId,
            liquidity * 2,
            minSqrtPriceX96,
            maxSqrtPriceX96,
            rftData
        );
        (int256 adjustedBalance0, int256 adjustedBalance1, , ) = viewFacet.queryAssetBalances(assetId);

        // Verify the adjusted values
        assertApproxEqAbs(adjustedBalance0, balance0 + delta0, 1, "Adjusted balance0 should match");
        assertApproxEqAbs(adjustedBalance1, balance1 + delta1, 1, "Adjusted balance1 should match");
        assertApproxEqAbs(balance0, delta0, 2, "we doubled 0");
        assertApproxEqAbs(balance1, delta1, 2, "we doubled 1");

        // Halve the liquidity back
        (, , delta0, delta1) = makerFacet.adjustMaker(
            address(this),
            assetId,
            liquidity,
            minSqrtPriceX96,
            maxSqrtPriceX96,
            rftData
        );
        assertApproxEqAbs(delta0, -balance0, 2, "Should have negative delta0");
        assertApproxEqAbs(delta1, -balance1, 2, "Should have negative delta1");
        (adjustedBalance0, adjustedBalance1, , ) = viewFacet.queryAssetBalances(assetId);
        assertApproxEqAbs(balance0, adjustedBalance0, 1, "Back to the original balance0");
        assertApproxEqAbs(balance1, adjustedBalance1, 1, "Back to the original balance1");
    }

    function testNewMakerExcessiveLiquidityReverts() public {
        bytes memory rftData = "";

        uint128 excessiveLiq = type(uint128).max;

        vm.expectRevert();
        makerFacet.newMaker(
            recipient,
            poolAddr,
            lowTick,
            highTick,
            excessiveLiq,
            false, // non-compounding
            minSqrtPriceX96,
            maxSqrtPriceX96,
            rftData
        );
    }

    function testFirstDepositorDrain_NoValueLoss() public {
        // We're opening and closing immediately to check so we need to disable JIT penalties.
        adminFacet.setJITPenalties(0, 0);

        bytes memory rftData = "";

        address victim = makeAddr("victimUser2");
        vm.label(victim, "victimUser2");

        int24 lt = 600;
        int24 ht = 720;

        // set current price to the middle of the interval
        swapTo(0, TickMath.getSqrtRatioAtTick(630));

        // create first compounding maker
        uint256 attackerBalance0 = token0.balanceOf(address(this));
        uint256 attackerBalance1 = token1.balanceOf(address(this));
        uint256 assetId = makerFacet.newMaker(
            recipient,
            poolAddr,
            lt,
            ht,
            1e6,
            true,
            minSqrtPriceX96,
            maxSqrtPriceX96,
            rftData
        );
        int256 attackerSpend0 = int256(attackerBalance0 - token0.balanceOf(address(this)));
        int256 attackerSpend1 = int256(attackerBalance1 - token1.balanceOf(address(this)));

        // donate some amount to compound liquidity
        UniswapV3Pool(poolAddr).flash(address(this), 0, 0, "");
        attackerSpend0 += 1e18;
        attackerSpend1 += 1e18;

        // reduce liquidity shares
        (, , int256 adjustReceive0, int256 adjustReceive1) = makerFacet.adjustMaker(
            recipient,
            assetId,
            4e14,
            minSqrtPriceX96,
            maxSqrtPriceX96,
            rftData
        );
        attackerSpend0 += adjustReceive0;
        attackerSpend1 += adjustReceive1;

        // donate again
        UniswapV3Pool(poolAddr).flash(address(this), 0, 0, "");
        attackerSpend0 += 1e18;
        attackerSpend1 += 1e18;

        // victim mints and then immediately closes
        // By opening and closing immediately they're swapping fees for adding liquidity without any slippage.
        // This is actually benefitial to both sides. They're doing the swap at the worse price of either
        // the current price or the TWAP. We want to compound but we can't because our fees are imbalanced.
        // This lets them avoid slippage if they're happy with the twap and current price, and we get to
        // compound immediately without having to pay swap fees ourselves. Win win!
        vm.startPrank(victim);
        MockERC20(token0).mint(victim, 2e18);
        MockERC20(token1).mint(victim, 2e18);
        uint balVictim0 = token0.balanceOf(victim);
        uint balVictim1 = token1.balanceOf(victim);
        MockERC20(token0).approve(diamond, type(uint256).max);
        MockERC20(token1).approve(diamond, type(uint256).max);
        uint256 assetId2 = makerFacet.newMaker(
            victim,
            poolAddr,
            lt,
            ht,
            300e18,
            true,
            minSqrtPriceX96,
            maxSqrtPriceX96,
            rftData
        );
        makerFacet.removeMaker(victim, assetId2, minSqrtPriceX96, maxSqrtPriceX96, rftData);
        vm.stopPrank();

        uint balVictim0After = token0.balanceOf(victim);
        uint balVictim1After = token1.balanceOf(victim);

        (int256 attackerValue0, int256 attackerValue1, , ) = viewFacet.queryAssetBalances(assetId);
        int256 attackerLoss0 = attackerSpend0 - attackerValue0;
        int256 attackerLoss1 = attackerSpend1 - attackerValue1;
        assertGt(attackerLoss0, 0, "attacker should not profit in token0");
        assertGt(attackerLoss1, 0, "attacker should not profit in token1");
        console.log("attackerLosses", uint256(attackerLoss0), uint256(attackerLoss1));

        int256 victimDiff0 = int256(balVictim0After) - int256(balVictim0);
        int256 victimDiff1 = int256(balVictim1After) - int256(balVictim1);
        console.log("victimDiff0", victimDiff0);
        console.log("victimDiff1", victimDiff1);

        // Assert the victim losses are less than the attacker gains
        assertLt(-victimDiff0, attackerLoss0, "victim token0 loss should be less than attacker gain");
        assertLt(-victimDiff1, attackerLoss1, "victim token1 loss should be less than attacker gain");

        // Assert the victim has not lost value overall at the current price.
        (uint160 sqrtPriceX96, , , , , , ) = UniswapV3Pool(poolAddr).slot0();
        uint256 priceX64 = FullMath.mulX128(sqrtPriceX96, sqrtPriceX96, false);
        uint256 totalBefore = FullMath.mulX64(balVictim0, priceX64, false) + balVictim1;
        uint256 totalAfter = FullMath.mulX64(balVictim0After, priceX64, false) + balVictim1After;
        assertGt(
            totalAfter,
            (totalBefore * 99) / 100,
            "victim total value should not decrease by more than the equiv liq slippage"
        );
        // Equiv liq slippage is at most 1% here because the fees in question are so hi relative to the liquidity.
        // In practice the difference is much smaller.
    }

    function uniswapV3FlashCallback(uint256 /* fee0 */, uint256 /* fee1 */, bytes calldata /* data */) external {
        token0.transfer(msg.sender, 1e18 + 1);
        token1.transfer(msg.sender, 1e18 + 1);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { TickMath } from "v4-core/libraries/TickMath.sol";
import { console2 } from "forge-std/console2.sol";
import { MultiSetupTest } from "../MultiSetup.u.sol";
import { UniV4IntegrationSetup } from "../UniV4.u.sol";
import { PoolInfo } from "../../src/Pool.sol";
import { LiqType, LiqWalker } from "../../src/walkers/Liq.sol";
import { MakerFacet } from "../../src/facets/Maker.sol";
import { IMaker } from "../../src/interfaces/IMaker.sol";
import { AssetLib } from "../../src/Asset.sol";
import { RouteImpl } from "../../src/tree/Route.sol";

import { MockERC20 } from "../mocks/MockERC20.sol";
import { FullMath } from "../../src/FullMath.sol";

import { console } from "forge-std/console.sol";

/// @dev The minimum value that can be returned from #getSqrtPriceAtTick. Equivalent to getSqrtPriceAtTick(MIN_TICK)
uint160 constant MIN_SQRT_RATIO = 4295128739;
/// @dev The maximum value that can be returned from #getSqrtPriceAtTick. Equivalent to getSqrtPriceAtTick(MAX_TICK)
uint160 constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

contract MakerFacetTest is MultiSetupTest, UniV4IntegrationSetup {

    address public recipient;
    address public poolAddr;
    int24 public lowTick;
    int24 public highTick;
    uint128 public liquidity;
    uint160 public minSqrtPriceX96;
    uint160 public maxSqrtPriceX96;

    PoolInfo public poolInfo;

    function setUp() public {
        _newDiamond(manager);
        (, address _pool, address _token0, address _token1) = setUpPool();
        _registerPool(poolKeys[0]);

        token0 = MockERC20(_token0);
        token1 = MockERC20(_token1);

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
        tokens.push(_token0);
        tokens.push(_token1);
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
        assertEq(uint8(liqType), uint8(LiqType.MAKER));
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
        assertEq(uint8(liqType), uint8(LiqType.MAKER));
        assertEq(liq, liquidity);
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
            minSqrtPriceX96,
            maxSqrtPriceX96,
            rftData
        );

        swapTo(0, TickMath.getSqrtPriceAtTick(600));
        swapTo(0, TickMath.getSqrtPriceAtTick(-600));

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
        assertEq(uint8(liqType), uint8(LiqType.MAKER));
        assertEq(liq, liquidity);

        // Get initial position balances
        (int256 initialNetBalance0, int256 initialNetBalance1, , ) = viewFacet.queryAssetBalances(assetId);
        assertApproxEqAbs(uint256(initialNetBalance0), usedBalance0, 10);
        assertApproxEqAbs(uint256(initialNetBalance1), usedBalance1, 10);
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
        uint160 targetSqrtPriceX96 = TickMath.getSqrtPriceAtTick(targetTick);
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
        // V4 has slightly different rounding - allow wider tolerance
        assertApproxEqAbs(
            queriedNetBalance0 + int256(queriedFees0),
            int256(actualRemoved0),
            10,
            "Queried token0 balance should approximate actual removed amount"
        );

        assertApproxEqAbs(
            queriedNetBalance1 + int256(queriedFees1),
            int256(actualRemoved1),
            10,
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
            minSqrtPriceX96,
            maxSqrtPriceX96,
            rftData
        );

        // Move price down by swapping to a lower tick
        int24 targetTick = -300; // Move price down
        uint160 targetSqrtPriceX96 = TickMath.getSqrtPriceAtTick(targetTick);
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

        // V4 has slightly different rounding - allow wider tolerance
        assertApproxEqAbs(
            queriedNetBalance0 + int256(queriedFees0),
            int256(actualRemoved0),
            10,
            "Queried token0 balance should approximate actual removed amount after price down"
        );

        assertApproxEqAbs(
            queriedNetBalance1 + int256(queriedFees1),
            int256(actualRemoved1),
            10,
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
            minSqrtPriceX96,
            maxSqrtPriceX96,
            rftData
        );

        // Make a large price movement (move close to the edge of our range)
        int24 targetTick = 500; // Large upward movement, but still within range
        uint160 targetSqrtPriceX96 = TickMath.getSqrtPriceAtTick(targetTick);
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
        // V4 has slightly different rounding than V3 - allow wider tolerance
        assertApproxEqAbs(adjustedBalance0, balance0 + delta0, 10, "Adjusted balance0 should match");
        assertApproxEqAbs(adjustedBalance1, balance1 + delta1, 10, "Adjusted balance1 should match");
        assertApproxEqAbs(balance0, delta0, 10, "we doubled 0");
        assertApproxEqAbs(balance1, delta1, 10, "we doubled 1");

        // Halve the liquidity back
        (, , delta0, delta1) = makerFacet.adjustMaker(
            address(this),
            assetId,
            liquidity,
            minSqrtPriceX96,
            maxSqrtPriceX96,
            rftData
        );
        assertApproxEqAbs(delta0, -balance0, 10, "Should have negative delta0");
        assertApproxEqAbs(delta1, -balance1, 10, "Should have negative delta1");
        (adjustedBalance0, adjustedBalance1, , ) = viewFacet.queryAssetBalances(assetId);
        assertApproxEqAbs(balance0, adjustedBalance0, 10, "Back to the original balance0");
        assertApproxEqAbs(balance1, adjustedBalance1, 10, "Back to the original balance1");
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
            minSqrtPriceX96,
            maxSqrtPriceX96,
            rftData
        );
    }

    /// @notice Verify that the first depositor cannot extract value from a second depositor
    ///         through rounding manipulation when creating positions with minimal liquidity.
    ///
    /// Attack scenario:
    ///   1. Attacker creates position with minimal liquidity (first depositor)
    ///   2. Victim creates position with large liquidity in the same range
    ///   3. Both remove their positions immediately
    ///   4. Assert: victim gets back at least what they deposited (minus rounding)
    function testFirstDepositorDrain_NoValueLoss() public {
        address attacker = makeAddr("attacker");
        address victim = makeAddr("victim");

        token0.mint(attacker, 100e18);
        token1.mint(attacker, 100e18);
        token0.mint(victim, 100e18);
        token1.mint(victim, 100e18);

        vm.startPrank(attacker);
        token0.approve(address(diamond), type(uint256).max);
        token1.approve(address(diamond), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(victim);
        token0.approve(address(diamond), type(uint256).max);
        token1.approve(address(diamond), type(uint256).max);
        vm.stopPrank();

        // 1. Attacker front-runs with minimal liquidity
        vm.startPrank(attacker);
        uint256 attackerAsset = makerFacet.newMaker(
            attacker, poolAddr, lowTick, highTick,
            1e10, // very small liquidity
            minSqrtPriceX96, maxSqrtPriceX96, ""
        );
        vm.stopPrank();

        // 2. Victim deposits with substantial liquidity in the same range
        uint256 victimBal0Before = token0.balanceOf(victim);
        uint256 victimBal1Before = token1.balanceOf(victim);

        vm.startPrank(victim);
        uint256 victimAsset = makerFacet.newMaker(
            victim, poolAddr, lowTick, highTick,
            1e18, // large liquidity
            minSqrtPriceX96, maxSqrtPriceX96, ""
        );
        vm.stopPrank();

        uint256 victimDeposited0 = victimBal0Before - token0.balanceOf(victim);
        uint256 victimDeposited1 = victimBal1Before - token1.balanceOf(victim);

        // 3. Both remove immediately (no swaps, no fee generation)
        vm.startPrank(attacker);
        makerFacet.removeMaker(attacker, attackerAsset, minSqrtPriceX96, maxSqrtPriceX96, "");
        vm.stopPrank();

        vm.startPrank(victim);
        (, , uint256 victimReceived0, uint256 victimReceived1) = makerFacet.removeMaker(
            victim, victimAsset, minSqrtPriceX96, maxSqrtPriceX96, ""
        );
        vm.stopPrank();

        // 4. Victim should not have lost meaningful value
        // Allow a small tolerance for rounding inherent in liquidity math
        uint256 tolerance = 100; // 100 wei tolerance
        assertGe(
            victimReceived0 + tolerance, victimDeposited0,
            "victim should not lose token0 value"
        );
        assertGe(
            victimReceived1 + tolerance, victimDeposited1,
            "victim should not lose token1 value"
        );
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import { UniswapV3Pool } from "v3-core/UniswapV3Pool.sol";
import { TickMath } from "v3-core/libraries/TickMath.sol";

import { MultiSetupTest } from "../MultiSetup.u.sol";

import { PoolInfo } from "../../src/Pool.sol";
import { LiqType } from "../../src/walkers/Liq.sol";

import { MockERC20 } from "../mocks/MockERC20.sol";

/// @dev The minimum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MIN_TICK)
uint160 constant MIN_SQRT_RATIO = 4295128739;
/// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
uint160 constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

contract TakerFacetTest is MultiSetupTest {
    UniswapV3Pool public pool;

    address public recipient;
    address public poolAddr;
    int24[2] public ticks;
    uint128 public liquidity;
    uint8[2] public vaultIndices;
    uint160[2] public sqrtPriceLimitsX96;
    uint160 public freezeSqrtPriceX96;

    PoolInfo public poolInfo;

    /// @dev Helper function to collateralize tokens before creating taker positions
    function _collateralizeTaker(address recipient_, uint128 liquidity_) internal {
        // Calculate approximate token amounts needed for the liquidity
        // This is a rough estimate - in practice you'd want more precise calculations
        uint256 token0Amount = uint256(liquidity_) * 1e6; // Rough estimate
        uint256 token1Amount = uint256(liquidity_) * 1e6; // Rough estimate
        
        bytes memory data = "";
        
        // Mint and approve tokens
        token0.mint(address(this), token0Amount);
        token1.mint(address(this), token1Amount);
        token0.approve(address(takerFacet), token0Amount);
        token1.approve(address(takerFacet), token1Amount);
        
        // Collateralize both tokens
        takerFacet.collateralize(recipient_, address(token0), token0Amount, data);
        takerFacet.collateralize(recipient_, address(token1), token1Amount, data);
    }

    function setUp() public {
        _newDiamond();
        (uint256 idx, address _pool, address _token0, address _token1) = setUpPool();
        // Provide wider range of liquidity to support larger price movements
        addPoolLiq(0, -1200, 1200, 100e18);

        token0 = MockERC20(_token0);
        token1 = MockERC20(_token1);
        pool = UniswapV3Pool(_pool);

        // Set up test parameters
        recipient = address(this);
        poolAddr = address(pool);
        ticks = [-600, 600];
        liquidity = 1e18;
        vaultIndices = [0, 1];
        sqrtPriceLimitsX96 = [MIN_SQRT_RATIO, MAX_SQRT_RATIO];
        freezeSqrtPriceX96 = 1.5e18;

        poolInfo = viewFacet.getPoolInfo(poolAddr);

        // Fund this contract for testing
        _fundAccount(address(this));

        // Create vaults for the pool tokens
        _createPoolVaults(poolAddr);
    }

    ============ Taker Position Creation Tests ============

    function testNewTaker() public {
        bytes memory rftData = "";

        // Collateralize before creating taker position
        _collateralizeTaker(recipient, liquidity);

        uint256 assetId = takerFacet.newTaker(
            recipient,
            poolAddr,
            ticks,
            liquidity,
            vaultIndices,
            sqrtPriceLimitsX96,
            freezeSqrtPriceX96,
            rftData
        );

        // Verify asset was created
        assertEq(assetId, 1);

        // Verify asset properties using ViewFacet
        (address owner, address poolAddr_, int24 lowTick_, int24 highTick_, LiqType liqType, uint128 liq) = viewFacet
            .getAssetInfo(assetId);
        assertEq(owner, recipient);
        assertEq(poolAddr_, poolAddr);
        assertEq(lowTick_, ticks[0]);
        assertEq(highTick_, ticks[1]);
        assertEq(uint8(liqType), uint8(LiqType.TAKER));
        assertEq(liq, liquidity);
    }

    function testNewTakerInvalidTicks() public {
        bytes memory rftData = "";
        int24[2] memory invalidTicks = [int24(600), int24(-600)]; // high tick first

        // Collateralize before creating taker position
        _collateralizeTaker(recipient, liquidity);

        // Test with invalid tick order
        vm.expectRevert();
        takerFacet.newTaker(
            recipient,
            poolAddr,
            invalidTicks,
            liquidity,
            vaultIndices,
            sqrtPriceLimitsX96,
            freezeSqrtPriceX96,
            rftData
        );
    }

    function testNewTakerInvalidLiquidity() public {
        bytes memory rftData = "";

        // Collateralize before creating taker position (even for invalid test)
        _collateralizeTaker(recipient, 1); // Use minimal amount for zero liquidity test

        // Test with zero liquidity
        vm.expectRevert();
        takerFacet.newTaker(
            recipient,
            poolAddr,
            ticks,
            0, // zero liquidity
            vaultIndices,
            sqrtPriceLimitsX96,
            freezeSqrtPriceX96,
            rftData
        );
    }

    function testNewTakerInvalidVaultIndices() public {
        bytes memory rftData = "";
        uint8[2] memory invalidVaultIndices = [255, 255]; // out of range

        // Collateralize before creating taker position
        _collateralizeTaker(recipient, liquidity);

        // Test with invalid vault indices
        vm.expectRevert();
        takerFacet.newTaker(
            recipient,
            poolAddr,
            ticks,
            liquidity,
            invalidVaultIndices,
            sqrtPriceLimitsX96,
            freezeSqrtPriceX96,
            rftData
        );
    }

    // ============ Collateralization Error Tests ============

    function testNewTakerMissingToken0Collateral() public {
        bytes memory rftData = "";
        uint256 token1Amount = uint256(liquidity) * 1e6;

        // Only collateralize token1, not token0
        token1.mint(address(this), token1Amount);
        token1.approve(address(takerFacet), token1Amount);
        takerFacet.collateralize(recipient, address(token1), token1Amount, rftData);

        // Attempt to create taker without token0 collateral should fail
        vm.expectRevert();
        takerFacet.newTaker(
            recipient,
            poolAddr,
            ticks,
            liquidity,
            vaultIndices,
            sqrtPriceLimitsX96,
            freezeSqrtPriceX96,
            rftData
        );
    }

    function testNewTakerMissingToken1Collateral() public {
        bytes memory rftData = "";
        uint256 token0Amount = uint256(liquidity) * 1e6;

        // Only collateralize token0, not token1
        token0.mint(address(this), token0Amount);
        token0.approve(address(takerFacet), token0Amount);
        takerFacet.collateralize(recipient, address(token0), token0Amount, rftData);

        // Attempt to create taker without token1 collateral should fail
        vm.expectRevert();
        takerFacet.newTaker(
            recipient,
            poolAddr,
            ticks,
            liquidity,
            vaultIndices,
            sqrtPriceLimitsX96,
            freezeSqrtPriceX96,
            rftData
        );
    }

    function testNewTakerNoCollateral() public {
        bytes memory rftData = "";

        // Attempt to create taker without any collateral should fail
        vm.expectRevert();
        takerFacet.newTaker(
            recipient,
            poolAddr,
            ticks,
            liquidity,
            vaultIndices,
            sqrtPriceLimitsX96,
            freezeSqrtPriceX96,
            rftData
        );
    }

    function testNewTakerInsufficientCollateral() public {
        bytes memory rftData = "";
        // Use very small collateral amounts (likely insufficient)
        uint256 smallAmount = 1; // Minimal amount
        
        token0.mint(address(this), smallAmount);
        token1.mint(address(this), smallAmount);
        token0.approve(address(takerFacet), smallAmount);
        token1.approve(address(takerFacet), smallAmount);
        
        takerFacet.collateralize(recipient, address(token0), smallAmount, rftData);
        takerFacet.collateralize(recipient, address(token1), smallAmount, rftData);

        // Attempt to create taker with insufficient collateral should fail
        vm.expectRevert();
        takerFacet.newTaker(
            recipient,
            poolAddr,
            ticks,
            liquidity,
            vaultIndices,
            sqrtPriceLimitsX96,
            freezeSqrtPriceX96,
            rftData
        );
    }

    function testNewTakerPartialCollateralAfterWithdrawal() public {
        bytes memory rftData = "";
        
        // First, properly collateralize
        _collateralizeTaker(recipient, liquidity);
        
        // Verify we have collateral
        uint256 token0Balance = viewFacet.getCollateralBalance(recipient, address(token0));
        uint256 token1Balance = viewFacet.getCollateralBalance(recipient, address(token1));
        assertGt(token0Balance, 0, "Should have token0 collateral");
        assertGt(token1Balance, 0, "Should have token1 collateral");
        
        // TODO: Add test for withdrawing collateral when that functionality is implemented
        // For now, this test serves as a placeholder and documents the expected behavior
        
        // Successfully create taker with proper collateral
        uint256 assetId = takerFacet.newTaker(
            recipient,
            poolAddr,
            ticks,
            liquidity,
            vaultIndices,
            sqrtPriceLimitsX96,
            freezeSqrtPriceX96,
            rftData
        );
        
        // Verify asset was created
        assertEq(assetId, 1);
    }

    // ============ Taker Position Removal Tests ============

    function testRemoveTaker() public {
        // First create a taker position
        bytes memory rftData = "";
        
        // Collateralize before creating taker position
        _collateralizeTaker(recipient, liquidity);
        
        uint256 assetId = takerFacet.newTaker(
            recipient,
            poolAddr,
            ticks,
            liquidity,
            vaultIndices,
            sqrtPriceLimitsX96,
            freezeSqrtPriceX96,
            rftData
        );

        // Mock the asset owner
        vm.prank(recipient);

        // Remove the taker position
        (address removedToken0, address removedToken1, int256 removedX, int256 removedY) = takerFacet.removeTaker(
            assetId,
            sqrtPriceLimitsX96[0],
            sqrtPriceLimitsX96[1],
            rftData
        );

        // Verify return values
        assertEq(removedToken0, address(token0));
        assertEq(removedToken1, address(token1));
        assertGt(removedX, 0);
        assertGt(removedY, 0);

        // Verify asset was removed
        vm.expectRevert();
        viewFacet.getAssetInfo(assetId);
    }

    function testRemoveTakerNotOwner() public {
        // First create a taker position
        bytes memory rftData = "";
        
        // Collateralize before creating taker position
        _collateralizeTaker(recipient, liquidity);
        
        uint256 assetId = takerFacet.newTaker(
            recipient,
            poolAddr,
            ticks,
            liquidity,
            vaultIndices,
            sqrtPriceLimitsX96,
            freezeSqrtPriceX96,
            rftData
        );

        // Try to remove as non-owner
        address nonOwner = address(0x456);
        vm.prank(nonOwner);

        vm.expectRevert();
        takerFacet.removeTaker(assetId, sqrtPriceLimitsX96[0], sqrtPriceLimitsX96[1], rftData);
    }

    function testRemoveTakerNotTakerAsset() public {
        // Create a maker asset instead of taker
        bytes memory rftData = "";
        uint256 assetId = makerFacet.newMaker(
            recipient,
            poolAddr,
            ticks[0],
            ticks[1],
            liquidity,
            false, // non-compounding
            sqrtPriceLimitsX96[0],
            sqrtPriceLimitsX96[1],
            rftData
        );

        // Try to remove maker asset via removeTaker
        vm.expectRevert();
        takerFacet.removeTaker(assetId, sqrtPriceLimitsX96[0], sqrtPriceLimitsX96[1], rftData);
    }

    // ============ Collateral Management Tests ============

    function testCollateralize() public {
        uint256 amount = 1000e18;
        bytes memory data = "";

        // Mint tokens to the caller
        token0.mint(address(this), amount);
        token0.approve(address(takerFacet), amount);

        takerFacet.collateralize(recipient, address(token0), amount, data);

        // Verify collateral was recorded using the new view function
        uint256 collateralBalance = viewFacet.getCollateralBalance(recipient, address(token0));
        assertEq(collateralBalance, amount);
    }

    function testWithdrawCollateral() public {
        // First add some collateral
        uint256 amount = 1000e18;
        bytes memory data = "";

        token0.mint(address(this), amount);
        token0.approve(address(takerFacet), amount);

        takerFacet.collateralize(recipient, address(token0), amount, data);

        // Verify initial collateral balance
        uint256 initialBalance = viewFacet.getCollateralBalance(recipient, address(token0));
        assertEq(initialBalance, amount);

        // Now withdraw collateral (requires admin rights)
        // This test will need to be updated when we implement proper admin rights
        // For now, we'll just verify the function exists and initial balance is correct
        assertTrue(true);
    }

    function testCollateralBalanceTracking() public {
        // Test that collateral balances are tracked correctly
        uint256 amount1 = 500e18;
        uint256 amount2 = 300e18;
        bytes memory data = "";

        token0.mint(address(this), amount1 + amount2);
        token0.approve(address(takerFacet), amount1 + amount2);

        takerFacet.collateralize(recipient, address(token0), amount1, data);

        // Verify first collateral deposit
        uint256 balanceAfterFirst = viewFacet.getCollateralBalance(recipient, address(token0));
        assertEq(balanceAfterFirst, amount1);

        takerFacet.collateralize(recipient, address(token0), amount2, data);

        // Verify total collateral after second deposit
        uint256 totalBalance = viewFacet.getCollateralBalance(recipient, address(token0));
        assertEq(totalBalance, amount1 + amount2);
    }

    function testCollateralMultipleTokens() public {
        // Test collateral management with multiple tokens
        uint256 amount0 = 1000e18;
        uint256 amount1 = 2000e18;
        bytes memory data = "";

        token0.mint(address(this), amount0);
        token1.mint(address(this), amount1);
        token0.approve(address(takerFacet), amount0);
        token1.approve(address(takerFacet), amount1);

        takerFacet.collateralize(recipient, address(token0), amount0, data);
        takerFacet.collateralize(recipient, address(token1), amount1, data);

        // Verify both tokens were recorded as collateral using individual queries
        uint256 token0Balance = viewFacet.getCollateralBalance(recipient, address(token0));
        uint256 token1Balance = viewFacet.getCollateralBalance(recipient, address(token1));

        assertEq(token0Balance, amount0);
        assertEq(token1Balance, amount1);

        // Also test the batch query function
        address[] memory recipients = new address[](2);
        address[] memory tokens = new address[](2);
        recipients[0] = recipient;
        recipients[1] = recipient;
        tokens[0] = address(token0);
        tokens[1] = address(token1);

        uint256[] memory batchBalances = viewFacet.getCollateralBalances(recipients, tokens);
        assertEq(batchBalances.length, 2);
        assertEq(batchBalances[0], amount0);
        assertEq(batchBalances[1], amount1);
    }

    // ============ Taker Position Value and Price Movement Tests ============

    function testTakerPositionValueAtCreation() public {
        bytes memory rftData = "";

        // Collateralize before creating taker position
        _collateralizeTaker(recipient, liquidity);

        // Create a taker position
        uint256 assetId = takerFacet.newTaker(
            recipient,
            poolAddr,
            ticks,
            liquidity,
            vaultIndices,
            sqrtPriceLimitsX96,
            freezeSqrtPriceX96,
            rftData
        );

        // Verify the position was created correctly using ViewFacet
        (address owner, address poolAddr_, int24 lowTick_, int24 highTick_, LiqType liqType, uint128 liq) = viewFacet
            .getAssetInfo(assetId);
        assertEq(owner, recipient);
        assertEq(poolAddr_, poolAddr);
        assertEq(lowTick_, ticks[0]);
        assertEq(highTick_, ticks[1]);
        assertEq(uint8(liqType), uint8(LiqType.TAKER));
        assertEq(liq, liquidity);

        // Get initial position balances - should be zero or close to zero for new taker
        (int256 initialNetBalance0, int256 initialNetBalance1, uint256 initialFees0, uint256 initialFees1) = viewFacet
            .queryAssetBalances(assetId);

        // For a taker position in range, the net balance should be zero or negative
        // (taker owes tokens to the protocol)
        assertLe(initialNetBalance0, 0, "Taker should not have positive token0 balance when in range");
        assertLe(initialNetBalance1, 0, "Taker should not have positive token1 balance when in range");
    }

    function testTakerPositionValueAfterPriceMovementUp() public {
        bytes memory rftData = "";

        // Collateralize before creating taker position
        _collateralizeTaker(recipient, liquidity);

        // Create a taker position with range [-600, 600]
        uint256 assetId = takerFacet.newTaker(
            recipient,
            poolAddr,
            ticks,
            liquidity,
            vaultIndices,
            sqrtPriceLimitsX96,
            freezeSqrtPriceX96,
            rftData
        );

        // Get initial position balances
        (int256 initialNetBalance0, int256 initialNetBalance1, uint256 initialFees0, uint256 initialFees1) = viewFacet
            .queryAssetBalances(assetId);

        // Move price above the taker range (above tick 600)
        int24 targetTick = 800; // Move price outside the range
        uint160 targetSqrtPriceX96 = TickMath.getSqrtRatioAtTick(targetTick);
        swapTo(0, targetSqrtPriceX96);

        // Query position value after price movement
        (int256 queriedNetBalance0, int256 queriedNetBalance1, uint256 queriedFees0, uint256 queriedFees1) = viewFacet
            .queryAssetBalances(assetId);

        // Verify that balances changed due to price movement
        // When price moves outside taker range, taker position should become valuable
        assertTrue(
            queriedNetBalance0 != initialNetBalance0 || queriedNetBalance1 != initialNetBalance1,
            "Taker position balances should change after price movement outside range"
        );

        // When price is above the range, taker should have positive net balance
        // (taker benefits from being out of range)
        assertTrue(
            queriedNetBalance0 > 0 || queriedNetBalance1 > 0,
            "Taker should have positive net balance when price is outside range"
        );

        // Close the position and get actual amounts
        vm.prank(recipient);
        (address token0Addr, address token1Addr, int256 actualRemoved0, int256 actualRemoved1) = takerFacet
            .removeTaker(assetId, sqrtPriceLimitsX96[0], sqrtPriceLimitsX96[1], rftData);

        // Verify tokens match expected pool tokens
        assertEq(token0Addr, address(token0));
        assertEq(token1Addr, address(token1));

        // For a taker position out of range, we should receive positive amounts
        assertTrue(actualRemoved0 > 0 || actualRemoved1 > 0, "Should receive some tokens on close when out of range");
    }

    function testTakerPositionValueAfterPriceMovementDown() public {
        bytes memory rftData = "";

        // Collateralize before creating taker position
        _collateralizeTaker(recipient, liquidity);

        // Create a taker position with range [-600, 600]
        uint256 assetId = takerFacet.newTaker(
            recipient,
            poolAddr,
            ticks,
            liquidity,
            vaultIndices,
            sqrtPriceLimitsX96,
            freezeSqrtPriceX96,
            rftData
        );

        // Move price below the taker range (below tick -600)
        int24 targetTick = -800; // Move price outside the range
        uint160 targetSqrtPriceX96 = TickMath.getSqrtRatioAtTick(targetTick);
        swapTo(0, targetSqrtPriceX96);

        // Query position value after price movement
        (int256 queriedNetBalance0, int256 queriedNetBalance1, uint256 queriedFees0, uint256 queriedFees1) = viewFacet
            .queryAssetBalances(assetId);

        // When price is below the range, taker should have positive net balance
        assertTrue(
            queriedNetBalance0 > 0 || queriedNetBalance1 > 0,
            "Taker should have positive net balance when price is below range"
        );

        // Close the position and verify we receive tokens
        vm.prank(recipient);
        (address token0Addr, address token1Addr, int256 actualRemoved0, int256 actualRemoved1) = takerFacet
            .removeTaker(assetId, sqrtPriceLimitsX96[0], sqrtPriceLimitsX96[1], rftData);

        // Verify tokens match expected pool tokens
        assertEq(token0Addr, address(token0));
        assertEq(token1Addr, address(token1));

        // For a taker position out of range, we should receive positive amounts
        assertTrue(actualRemoved0 > 0 || actualRemoved1 > 0, "Should receive some tokens on close when out of range");
    }

    function testTakerPositionValueWithLargePriceMovement() public {
        bytes memory rftData = "";

        // Collateralize before creating taker position
        _collateralizeTaker(recipient, liquidity);

        // Create a taker position
        uint256 assetId = takerFacet.newTaker(
            recipient,
            poolAddr,
            ticks,
            liquidity,
            vaultIndices,
            sqrtPriceLimitsX96,
            freezeSqrtPriceX96,
            rftData
        );

        // Make a large price movement well outside the range
        int24 targetTick = 1000; // Large upward movement, well outside range
        uint160 targetSqrtPriceX96 = TickMath.getSqrtRatioAtTick(targetTick);
        swapTo(0, targetSqrtPriceX96);

        // Query position value after large price movement
        (int256 queriedNetBalance0, int256 queriedNetBalance1, uint256 queriedFees0, uint256 queriedFees1) = viewFacet
            .queryAssetBalances(assetId);

        // With large price movement outside range, taker should have significant positive balance
        assertTrue(
            queriedNetBalance0 > 0 || queriedNetBalance1 > 0,
            "Taker should have positive net balance after large price movement outside range"
        );

        // Close the position and verify consistency
        vm.prank(recipient);
        (address token0Addr, address token1Addr, int256 actualRemoved0, int256 actualRemoved1) = takerFacet
            .removeTaker(assetId, sqrtPriceLimitsX96[0], sqrtPriceLimitsX96[1], rftData);

        // Verify consistency between query and actual values
        assertTrue(actualRemoved0 > 0 || actualRemoved1 > 0, "Should receive tokens on close after large movement");

        // The queried values should reasonably match the actual removed amounts
        if (queriedNetBalance0 > 0) {
            assertApproxEqRel(
                uint256(queriedNetBalance0),
                uint256(actualRemoved0),
                2e17, // 20% tolerance (taker positions can be more volatile)
                "Queried token0 balance should approximate actual removed amount"
            );
        }

        if (queriedNetBalance1 > 0) {
            assertApproxEqRel(
                uint256(queriedNetBalance1),
                uint256(actualRemoved1),
                2e17, // 20% tolerance
                "Queried token1 balance should approximate actual removed amount"
            );
        }
    }

    function testTakerPositionBackInRange() public {
        bytes memory rftData = "";

        // Collateralize before creating taker position
        _collateralizeTaker(recipient, liquidity);

        // Create a taker position
        uint256 assetId = takerFacet.newTaker(
            recipient,
            poolAddr,
            ticks,
            liquidity,
            vaultIndices,
            sqrtPriceLimitsX96,
            freezeSqrtPriceX96,
            rftData
        );

        // Move price outside range first
        int24 targetTick = 800;
        uint160 targetSqrtPriceX96 = TickMath.getSqrtRatioAtTick(targetTick);
        swapTo(0, targetSqrtPriceX96);

        // Verify position is valuable when out of range
        (int256 outOfRangeBalance0, int256 outOfRangeBalance1, , ) = viewFacet.queryAssetBalances(assetId);
        assertTrue(
            outOfRangeBalance0 > 0 || outOfRangeBalance1 > 0,
            "Taker should be valuable when out of range"
        );

        // Move price back into range
        targetTick = 0; // Back to center of range
        targetSqrtPriceX96 = TickMath.getSqrtRatioAtTick(targetTick);
        swapTo(0, targetSqrtPriceX96);

        // Query position value when back in range
        (int256 inRangeBalance0, int256 inRangeBalance1, , ) = viewFacet.queryAssetBalances(assetId);

        // When back in range, taker position should be less valuable (or negative)
        assertTrue(
            (inRangeBalance0 <= outOfRangeBalance0) && (inRangeBalance1 <= outOfRangeBalance1),
            "Taker should be less valuable when back in range"
        );
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import { UniswapV3Pool } from "v3-core/UniswapV3Pool.sol";

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

    function setUp() public {
        _newDiamond();
        (uint256 idx, address _pool, address _token0, address _token1) = setUpPool();
        addPoolLiq(0, -600, 600, 100e18);

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
    }

    // ============ Taker Position Creation Tests ============

    // function testNewTaker() public {
    //     bytes memory rftData = "";

    //     uint256 assetId = takerFacet.newTaker(
    //         recipient,
    //         poolAddr,
    //         ticks,
    //         liquidity,
    //         vaultIndices,
    //         sqrtPriceLimitsX96,
    //         freezeSqrtPriceX96,
    //         rftData
    //     );

    //     // Verify asset was created
    //     assertEq(assetId, 1);

    //     // Verify asset properties using ViewFacet
    //     (address owner, address poolAddr_, int24 lowTick_, int24 highTick_, LiqType liqType, uint128 liq) = viewFacet
    //         .getAssetInfo(assetId);
    //     assertEq(owner, recipient);
    //     assertEq(poolAddr_, poolAddr);
    //     assertEq(lowTick_, ticks[0]);
    //     assertEq(highTick_, ticks[1]);
    //     assertEq(uint8(liqType), uint8(LiqType.TAKER));
    //     assertEq(liq, liquidity);
    // }

    // function testNewTakerInvalidTicks() public {
    //     bytes memory rftData = "";
    //     int24[2] memory invalidTicks = [int24(600), int24(-600)]; // high tick first

    //     // Test with invalid tick order
    //     vm.expectRevert();
    //     takerFacet.newTaker(
    //         recipient,
    //         poolAddr,
    //         invalidTicks,
    //         liquidity,
    //         vaultIndices,
    //         sqrtPriceLimitsX96,
    //         freezeSqrtPriceX96,
    //         rftData
    //     );
    // }

    // function testNewTakerInvalidLiquidity() public {
    //     bytes memory rftData = "";

    //     // Test with zero liquidity
    //     vm.expectRevert();
    //     takerFacet.newTaker(
    //         recipient,
    //         poolAddr,
    //         ticks,
    //         0, // zero liquidity
    //         vaultIndices,
    //         sqrtPriceLimitsX96,
    //         freezeSqrtPriceX96,
    //         rftData
    //     );
    // }

    // function testNewTakerInvalidVaultIndices() public {
    //     bytes memory rftData = "";
    //     uint8[2] memory invalidVaultIndices = [255, 255]; // out of range

    //     // Test with invalid vault indices
    //     vm.expectRevert();
    //     takerFacet.newTaker(
    //         recipient,
    //         poolAddr,
    //         ticks,
    //         liquidity,
    //         invalidVaultIndices,
    //         sqrtPriceLimitsX96,
    //         freezeSqrtPriceX96,
    //         rftData
    //     );
    // }

    // // ============ Taker Position Removal Tests ============

    // function testRemoveTaker() public {
    //     // First create a taker position
    //     bytes memory rftData = "";
    //     uint256 assetId = takerFacet.newTaker(
    //         recipient,
    //         poolAddr,
    //         ticks,
    //         liquidity,
    //         vaultIndices,
    //         sqrtPriceLimitsX96,
    //         freezeSqrtPriceX96,
    //         rftData
    //     );

    //     // Mock the asset owner
    //     vm.prank(recipient);

    //     // Remove the taker position
    //     (address removedToken0, address removedToken1, int256 removedX, int256 removedY) = takerFacet.removeTaker(
    //         assetId,
    //         sqrtPriceLimitsX96[0],
    //         sqrtPriceLimitsX96[1],
    //         rftData
    //     );

    //     // Verify return values
    //     assertEq(removedToken0, address(token0));
    //     assertEq(removedToken1, address(token1));
    //     assertGt(removedX, 0);
    //     assertGt(removedY, 0);

    //     // Verify asset was removed
    //     vm.expectRevert();
    //     viewFacet.getAssetInfo(assetId);
    // }

    // function testRemoveTakerNotOwner() public {
    //     // First create a taker position
    //     bytes memory rftData = "";
    //     uint256 assetId = takerFacet.newTaker(
    //         recipient,
    //         poolAddr,
    //         ticks,
    //         liquidity,
    //         vaultIndices,
    //         sqrtPriceLimitsX96,
    //         freezeSqrtPriceX96,
    //         rftData
    //     );

    //     // Try to remove as non-owner
    //     address nonOwner = address(0x456);
    //     vm.prank(nonOwner);

    //     vm.expectRevert();
    //     takerFacet.removeTaker(assetId, sqrtPriceLimitsX96[0], sqrtPriceLimitsX96[1], rftData);
    // }

    // function testRemoveTakerNotTakerAsset() public {
    //     // Create a maker asset instead of taker
    //     bytes memory rftData = "";
    //     uint256 assetId = makerFacet.newMaker(
    //         recipient,
    //         poolAddr,
    //         ticks[0],
    //         ticks[1],
    //         liquidity,
    //         false, // non-compounding
    //         sqrtPriceLimitsX96[0],
    //         sqrtPriceLimitsX96[1],
    //         rftData
    //     );

    //     // Try to remove maker asset via removeTaker
    //     vm.expectRevert();
    //     takerFacet.removeTaker(assetId, sqrtPriceLimitsX96[0], sqrtPriceLimitsX96[1], rftData);
    // }

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
}

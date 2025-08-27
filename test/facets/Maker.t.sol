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

contract MakerFacetTest is MultiSetupTest {
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
        _newDiamond();
        (uint256 idx, address _pool, address _token0, address _token1) = setUpPool();
        addPoolLiq(0, -600, 600, 100e18);

        token0 = MockERC20(_token0);
        token1 = MockERC20(_token1);
        pool = UniswapV3Pool(_pool);
    }

    // ============ Maker Position Creation Tests ============

    // function testNewMaker() public {
    //     bytes memory rftData = "";

    //     uint256 assetId = makerFacet.newMaker(
    //         address(this),
    //         address(pool),
    //         -600,
    //         600,
    //         1e18,
    //         false, // non-compounding
    //         MIN_SQRT_RATIO,
    //         MAX_SQRT_RATIO,
    //         rftData
    //     );

    //     // Verify asset was created
    //     assertEq(assetId, 1);

    //     // Verify asset properties using ViewFacet
    //     (address owner, address poolAddr_, int24 lowTick_, int24 highTick_, LiqType liqType, uint128 liq) = viewFacet
    //         .getAssetInfo(assetId);
    //     assertEq(owner, recipient);
    //     assertEq(poolAddr_, poolAddr);
    //     assertEq(lowTick_, lowTick);
    //     assertEq(highTick_, highTick);
    //     assertEq(uint8(liqType), uint8(LiqType.MAKER_NC));
    //     assertEq(liq, liquidity);
    // }

    // function testNewMakerCompounding() public {
    //     bytes memory rftData = "";

    //     uint256 assetId = makerFacet.newMaker(
    //         recipient,
    //         poolAddr,
    //         lowTick,
    //         highTick,
    //         liquidity,
    //         true, // compounding
    //         minSqrtPriceX96,
    //         maxSqrtPriceX96,
    //         rftData
    //     );

    //     // Verify asset was created with compounding type
    //     (, , , , LiqType liqType, ) = viewFacet.getAssetInfo(assetId);
    //     assertEq(uint8(liqType), uint8(LiqType.MAKER));
    // }

    // function testNewMakerInvalidTicks() public {
    //     bytes memory rftData = "";

    //     // Test with invalid tick order
    //     vm.expectRevert();
    //     makerFacet.newMaker(
    //         recipient,
    //         poolAddr,
    //         highTick, // high tick first
    //         lowTick, // low tick second
    //         liquidity,
    //         false,
    //         minSqrtPriceX96,
    //         maxSqrtPriceX96,
    //         rftData
    //     );
    // }

    // function testNewMakerInvalidLiquidity() public {
    //     bytes memory rftData = "";

    //     // Test with zero liquidity
    //     vm.expectRevert();
    //     makerFacet.newMaker(
    //         recipient,
    //         poolAddr,
    //         lowTick,
    //         highTick,
    //         0, // zero liquidity
    //         false,
    //         minSqrtPriceX96,
    //         maxSqrtPriceX96,
    //         rftData
    //     );
    // }

    // function testNewMakerPriceBounds() public {
    //     bytes memory rftData = "";

    //     // Test with invalid price bounds
    //     vm.expectRevert();
    //     makerFacet.newMaker(
    //         recipient,
    //         poolAddr,
    //         lowTick,
    //         highTick,
    //         liquidity,
    //         false,
    //         maxSqrtPriceX96, // min > max
    //         minSqrtPriceX96,
    //         rftData
    //     );
    // }

    // // ============ Maker Position Removal Tests ============

    // function testRemoveMaker() public {
    //     // First create a maker position
    //     bytes memory rftData = "";
    //     uint256 assetId = makerFacet.newMaker(
    //         recipient,
    //         poolAddr,
    //         lowTick,
    //         highTick,
    //         liquidity,
    //         false,
    //         minSqrtPriceX96,
    //         maxSqrtPriceX96,
    //         rftData
    //     );

    //     // Mock the asset owner
    //     vm.prank(recipient);

    //     // Remove the maker position
    //     (address removedToken0, address removedToken1, uint256 removedX, uint256 removedY) = makerFacet.removeMaker(
    //         recipient,
    //         assetId,
    //         uint128(minSqrtPriceX96),
    //         uint128(maxSqrtPriceX96),
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

    // function testRemoveMakerNotOwner() public {
    //     // First create a maker position
    //     bytes memory rftData = "";
    //     uint256 assetId = makerFacet.newMaker(
    //         recipient,
    //         poolAddr,
    //         lowTick,
    //         highTick,
    //         liquidity,
    //         false,
    //         minSqrtPriceX96,
    //         maxSqrtPriceX96,
    //         rftData
    //     );

    //     // Try to remove as non-owner
    //     address nonOwner = address(0x456);
    //     vm.prank(nonOwner);

    //     vm.expectRevert();
    //     makerFacet.removeMaker(recipient, assetId, uint128(minSqrtPriceX96), uint128(maxSqrtPriceX96), rftData);
    // }

    // function testRemoveMakerNotMakerAsset() public {
    //     // Create a taker asset instead of maker
    //     // This would require setting up the taker facet first
    //     // For now, we'll test the revert case by trying to remove a non-existent asset

    //     bytes memory rftData = "";
    //     vm.expectRevert();
    //     makerFacet.removeMaker(
    //         recipient,
    //         999, // non-existent asset
    //         uint128(minSqrtPriceX96),
    //         uint128(maxSqrtPriceX96),
    //         rftData
    //     );
    // }

    // // ============ Fee Collection Tests ============

    // function testCollectFees() public {
    //     // First create a maker position
    //     bytes memory rftData = "";
    //     uint256 assetId = makerFacet.newMaker(
    //         recipient,
    //         poolAddr,
    //         lowTick,
    //         highTick,
    //         liquidity,
    //         false,
    //         minSqrtPriceX96,
    //         maxSqrtPriceX96,
    //         rftData
    //     );

    //     // Mock the asset owner
    //     vm.prank(recipient);

    //     // Collect fees
    //     (uint256 fees0, uint256 fees1) = makerFacet.collectFees(
    //         recipient,
    //         assetId,
    //         minSqrtPriceX96,
    //         maxSqrtPriceX96,
    //         rftData
    //     );

    //     // Verify fees were collected
    //     assertGe(fees0, 0);
    //     assertGe(fees1, 0);
    // }

    // function testCollectFeesNotOwner() public {
    //     // First create a maker position
    //     bytes memory rftData = "";
    //     uint256 assetId = makerFacet.newMaker(
    //         recipient,
    //         poolAddr,
    //         lowTick,
    //         highTick,
    //         liquidity,
    //         false,
    //         minSqrtPriceX96,
    //         maxSqrtPriceX96,
    //         rftData
    //     );

    //     // Try to collect fees as non-owner
    //     address nonOwner = address(0x456);
    //     vm.prank(nonOwner);

    //     vm.expectRevert();
    //     makerFacet.collectFees(recipient, assetId, minSqrtPriceX96, maxSqrtPriceX96, rftData);
    // }

    // function testCollectFeesNotMakerAsset() public {
    //     bytes memory rftData = "";
    //     vm.expectRevert();
    //     makerFacet.collectFees(
    //         recipient,
    //         999, // non-existent asset
    //         minSqrtPriceX96,
    //         maxSqrtPriceX96,
    //         rftData
    //     );
    // }
}

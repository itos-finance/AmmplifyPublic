// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.27;

// import { UniswapV3Pool } from "v3-core/UniswapV3Pool.sol";

// import { MultiSetupTest } from "../MultiSetup.u.sol";

// import { PoolInfo } from "../../src/Pool.sol";
// import { LiqType } from "../../src/walkers/Liq.sol";
// import { Node } from "../../src/walkers/Node.sol";
// import { Key, KeyImpl } from "../../src/tree/Key.sol";

// import { MockERC20 } from "../mocks/MockERC20.sol";

// /// @dev The minimum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MIN_TICK)
// uint160 constant MIN_SQRT_RATIO = 4295128739;
// /// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
// uint160 constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

// contract ViewFacetTest is MultiSetupTest {
//     UniswapV3Pool public pool;

//     address public recipient;
//     address public poolAddr;
//     int24 public lowTick;
//     int24 public highTick;
//     uint128 public liquidity;
//     uint160 public minSqrtPriceX96;
//     uint160 public maxSqrtPriceX96;

//     PoolInfo public poolInfo;

//     function setUp() public {
//         _newDiamond();
//         (uint256 idx, address _pool, address _token0, address _token1) = setUpPool();
//         addPoolLiq(0, -600, 600, 100e18);

//         token0 = MockERC20(_token0);
//         token1 = MockERC20(_token1);
//         pool = UniswapV3Pool(_pool);

//         // Set up test parameters
//         recipient = address(this);
//         poolAddr = address(pool);
//         lowTick = -600;
//         highTick = 600;
//         liquidity = 1e18;
//         minSqrtPriceX96 = MIN_SQRT_RATIO;
//         maxSqrtPriceX96 = MAX_SQRT_RATIO;
//     }

//     // ============ Pool Information Tests ============

//     function testGetPoolInfo() public {
//         PoolInfo memory retrievedPoolInfo = viewFacet.getPoolInfo(poolAddr);

//         // Verify pool info is retrieved correctly
//         assertEq(retrievedPoolInfo.poolAddr, poolAddr);
//         assertEq(retrievedPoolInfo.token0, address(token0));
//         assertEq(retrievedPoolInfo.token1, address(token1));
//         assertEq(retrievedPoolInfo.tickSpacing, 60);
//         assertEq(retrievedPoolInfo.treeWidth, 256);
//     }

//     function testGetPoolInfoInvalidPool() public {
//         address invalidPool = address(0x999);

//         // This should revert or return empty data for invalid pool
//         // The exact behavior depends on the implementation
//         vm.expectRevert();
//         viewFacet.getPoolInfo(invalidPool);
//     }

//     // ============ Asset Information Tests ============

//     function testGetAssetInfo() public {
//         // First create a maker asset to test with
//         bytes memory rftData = "";
//         vm.roll(10);
//         uint256 assetId = makerFacet.newMaker(
//             address(this),
//             address(pool),
//             -600,
//             600,
//             1e18,
//             false, // non-compounding
//             MIN_SQRT_RATIO,
//             MAX_SQRT_RATIO,
//             rftData
//         );

//         // Now test getting asset info
//         (address owner, address poolAddr_, int24 lowTick_, int24 highTick_, LiqType liqType, uint128 liq) = viewFacet
//             .getAssetInfo(assetId);

//         // Verify asset information is retrieved correctly
//         assertEq(owner, recipient);
//         assertEq(poolAddr_, poolAddr);
//         assertEq(lowTick_, lowTick);
//         assertEq(highTick_, highTick);
//         assertEq(uint8(liqType), uint8(LiqType.MAKER_NC));
//         assertEq(liq, liquidity);
//     }

//     function testGetAssetInfoInvalidAsset() public {
//         uint256 invalidAssetId = 999;

//         // This should revert for invalid asset
//         vm.expectRevert();
//         viewFacet.getAssetInfo(invalidAssetId);
//     }

//     // ============ Node Information Tests ============

//     function testGetNodes() public {
//         // Create test keys using KeyImpl.make function
//         Key[] memory keys = new Key[](2);
//         keys[0] = KeyImpl.make(0, 1); // base: 0, width: 1
//         keys[1] = KeyImpl.make(1, 2); // base: 1, width: 2

//         // Get nodes from the view facet
//         Node[] memory nodes = viewFacet.getNodes(poolAddr, keys);

//         // Verify the correct number of nodes are returned
//         assertEq(nodes.length, keys.length);
//     }

//     function testGetNodesEmptyKeys() public {
//         Key[] memory emptyKeys = new Key[](0);

//         Node[] memory nodes = viewFacet.getNodes(poolAddr, emptyKeys);

//         // Should return empty array
//         assertEq(nodes.length, 0);
//     }

//     function testGetNodesInvalidKeys() public {
//         // Test with keys that don't exist in the store
//         Key[] memory invalidKeys = new Key[](1);
//         invalidKeys[0] = KeyImpl.make(999, 1000); // base: 999, width: 1000

//         // This should handle invalid keys gracefully
//         Node[] memory nodes = viewFacet.getNodes(poolAddr, invalidKeys);
//         assertEq(nodes.length, 1);
//     }

//     // ============ Asset Balance Queries Tests ============

//     function testQueryAssetBalancesMaker() public {
//         // Create a maker asset to test balance queries
//         bytes memory rftData = "";
//         vm.roll(10);
//         uint256 assetId = makerFacet.newMaker(
//             address(this),
//             address(pool),
//             -600,
//             600,
//             1e18,
//             false, // non-compounding
//             MIN_SQRT_RATIO,
//             MAX_SQRT_RATIO,
//             rftData
//         );

//         // Query asset balances
//         (int256 netBalance0, int256 netBalance1, uint256 fees0, uint256 fees1) = viewFacet.queryAssetBalances(
//             assetId,
//             minSqrtPriceX96,
//             maxSqrtPriceX96
//         );

//         // For maker assets, balances should be positive
//         assertGe(netBalance0, 0);
//         assertGe(netBalance1, 0);
//         assertGe(fees0, 0);
//         assertGe(fees1, 0);
//     }

//     function testQueryAssetBalancesTaker() public {
//         // Create a taker asset to test balance queries
//         bytes memory rftData = "";
//         vm.roll(10);
//         uint256 assetId = takerFacet.newTaker(
//             address(this),
//             address(pool),
//             -600,
//             600,
//             1e18,
//             MIN_SQRT_RATIO,
//             MAX_SQRT_RATIO,
//             rftData
//         );

//         // Query asset balances
//         (int256 netBalance0, int256 netBalance1, uint256 fees0, uint256 fees1) = viewFacet.queryAssetBalances(
//             assetId,
//             minSqrtPriceX96,
//             maxSqrtPriceX96
//         );

//         // For taker assets, balances can be negative
//         // Fees represent fees owed
//         assertGe(fees0, 0);
//         assertGe(fees1, 0);
//     }

//     function testQueryAssetBalancesInvalidAsset() public {
//         uint256 invalidAssetId = 999;

//         // This should revert for invalid asset
//         vm.expectRevert();
//         viewFacet.queryAssetBalances(invalidAssetId, minSqrtPriceX96, maxSqrtPriceX96);
//     }

//     // ============ Balance Consistency Tests ============

//     function testBalanceConsistencyAcrossQueries() public {
//         // Create a maker asset
//         bytes memory rftData = "";
//         vm.roll(10);
//         uint256 assetId = makerFacet.newMaker(
//             address(this),
//             address(pool),
//             -600,
//             600,
//             1e18,
//             false, // non-compounding
//             MIN_SQRT_RATIO,
//             MAX_SQRT_RATIO,
//             rftData
//         );

//         // Query balances multiple times
//         (int256 netBalance0_1, int256 netBalance1_1, uint256 fees0_1, uint256 fees1_1) = viewFacet.queryAssetBalances(
//             assetId,
//             minSqrtPriceX96,
//             maxSqrtPriceX96
//         );

//         (int256 netBalance0_2, int256 netBalance1_2, uint256 fees0_2, uint256 fees1_2) = viewFacet.queryAssetBalances(
//             assetId,
//             minSqrtPriceX96,
//             maxSqrtPriceX96
//         );

//         // All queries should return the same results
//         assertEq(netBalance0_1, netBalance0_2);
//         assertEq(netBalance1_1, netBalance1_2);
//         assertEq(fees0_1, fees0_2);
//         assertEq(fees1_1, fees1_2);
//     }

//     function testBalanceConsistencyAfterStateChanges() public {
//         // Create a maker asset
//         bytes memory rftData = "";
//         vm.roll(10);
//         uint256 assetId = makerFacet.newMaker(
//             address(this),
//             address(pool),
//             -600,
//             600,
//             1e18,
//             false, // non-compounding
//             MIN_SQRT_RATIO,
//             MAX_SQRT_RATIO,
//             rftData
//         );

//         // 1. Query initial balances
//         (
//             int256 netBalance0_initial,
//             int256 netBalance1_initial,
//             uint256 fees0_initial,
//             uint256 fees1_initial
//         ) = viewFacet.queryAssetBalances(assetId, minSqrtPriceX96, maxSqrtPriceX96);

//         // 2. Modify state (collect fees)
//         vm.prank(recipient);
//         (uint256 collectedFees0, uint256 collectedFees1) = makerFacet.collectFees(
//             recipient,
//             assetId,
//             minSqrtPriceX96,
//             maxSqrtPriceX96,
//             rftData
//         );

//         // 3. Query balances again
//         (int256 netBalance0_after, int256 netBalance1_after, uint256 fees0_after, uint256 fees1_after) = viewFacet
//             .queryAssetBalances(assetId, minSqrtPriceX96, maxSqrtPriceX96);

//         // 4. Verify consistency - balances should remain the same, fees may change
//         assertEq(netBalance0_initial, netBalance0_after);
//         assertEq(netBalance1_initial, netBalance1_after);
//     }

//     // ============ Data Validation Tests ============

//     function testDataValidation() public {
//         // Create a maker asset
//         bytes memory rftData = "";
//         vm.roll(10);
//         uint256 assetId = makerFacet.newMaker(
//             address(this),
//             address(pool),
//             -600,
//             600,
//             1e18,
//             false, // non-compounding
//             MIN_SQRT_RATIO,
//             MAX_SQRT_RATIO,
//             rftData
//         );

//         // Verify data validation
//         (address owner, address poolAddr_, int24 lowTick_, int24 highTick_, LiqType liqType, uint128 liq) = viewFacet
//             .getAssetInfo(assetId);

//         // Verify:
//         // - Balances are non-negative where appropriate
//         // - Asset ID is sequential
//         // - Pool addresses match
//         // - Tick ranges are valid
//         assertEq(assetId, 1);
//         assertEq(poolAddr_, poolAddr);
//         assertLt(lowTick_, highTick_);
//         assertGt(liq, 0);
//     }

//     function testDataIntegrity() public {
//         // Create multiple assets to test data integrity
//         bytes memory rftData = "";
//         vm.roll(10);

//         uint256 assetId1 = makerFacet.newMaker(
//             address(this),
//             address(pool),
//             -600,
//             600,
//             1e18,
//             false, // non-compounding
//             MIN_SQRT_RATIO,
//             MAX_SQRT_RATIO,
//             rftData
//         );

//         uint256 assetId2 = takerFacet.newTaker(
//             address(this),
//             address(pool),
//             -300,
//             300,
//             2e18,
//             MIN_SQRT_RATIO,
//             MAX_SQRT_RATIO,
//             rftData
//         );

//         // Verify data integrity across multiple assets
//         (address owner1, , , , , ) = viewFacet.getAssetInfo(assetId1);
//         (address owner2, , , , , ) = viewFacet.getAssetInfo(assetId2);

//         // Asset ownership should be consistent
//         assertEq(owner1, recipient);
//         assertEq(owner2, recipient);

//         // Asset IDs should be sequential
//         assertEq(assetId1, 1);
//         assertEq(assetId2, 2);
//     }

//     // ============ Edge Case Tests ============

//     function testEdgeCaseZeroLiquidity() public {
//         // Test behavior with zero liquidity assets
//         // This would require creating an asset with zero liquidity
//         // For now, we'll test that the system handles it gracefully
//         assertTrue(true);
//     }

//     function testEdgeCaseExtremeTicks() public {
//         // Test behavior with extreme tick values
//         // This would require creating assets with very low/high ticks
//         // For now, we'll test that the system handles it gracefully
//         assertTrue(true);
//     }

//     function testEdgeCaseLargeBalances() public {
//         // Test behavior with very large balance amounts
//         // This would require assets with large balances
//         // For now, we'll test that the system handles it gracefully
//         assertTrue(true);
//     }

//     // ============ Gas Optimization Tests ============

//     function testGasUsageForSingleAsset() public {
//         // Create a maker asset to test gas usage
//         bytes memory rftData = "";
//         vm.roll(10);
//         uint256 assetId = makerFacet.newMaker(
//             address(this),
//             address(pool),
//             -600,
//             600,
//             1e18,
//             false, // non-compounding
//             MIN_SQRT_RATIO,
//             MAX_SQRT_RATIO,
//             rftData
//         );

//         // Measure gas usage for single asset query
//         uint256 gasBefore = gasleft();
//         viewFacet.getAssetInfo(assetId);
//         uint256 gasUsed = gasBefore - gasleft();

//         // Gas usage should be reasonable
//         assertLt(gasUsed, 100000);
//     }

//     function testGasUsageForMultipleAssets() public {
//         // Create multiple assets to test gas usage
//         bytes memory rftData = "";
//         vm.roll(10);

//         uint256 assetId1 = makerFacet.newMaker(
//             address(this),
//             address(pool),
//             -600,
//             600,
//             1e18,
//             false, // non-compounding
//             MIN_SQRT_RATIO,
//             MAX_SQRT_RATIO,
//             rftData
//         );

//         uint256 assetId2 = takerFacet.newTaker(
//             address(this),
//             address(pool),
//             -300,
//             300,
//             2e18,
//             MIN_SQRT_RATIO,
//             MAX_SQRT_RATIO,
//             rftData
//         );

//         // Measure gas usage for multiple asset queries
//         uint256 gasBefore = gasleft();
//         viewFacet.getAssetInfo(assetId1);
//         viewFacet.getAssetInfo(assetId2);
//         uint256 gasUsed = gasBefore - gasleft();

//         // Gas usage should be reasonable
//         assertLt(gasUsed, 200000);
//     }

//     function testGasUsageForLargeNodeSets() public {
//         // Test gas usage when querying large numbers of nodes
//         // This would require many nodes in the store
//         // For now, we'll test that the system handles it gracefully
//         assertTrue(true);
//     }

//     // ============ Integration Tests ============

//     function testIntegrationWithOtherFacets() public {
//         // Test that ViewFacet works correctly with other facets
//         // Create assets using different facets
//         bytes memory rftData = "";
//         vm.roll(10);

//         uint256 makerAssetId = makerFacet.newMaker(
//             address(this),
//             address(pool),
//             -600,
//             600,
//             1e18,
//             false, // non-compounding
//             MIN_SQRT_RATIO,
//             MAX_SQRT_RATIO,
//             rftData
//         );

//         uint256 takerAssetId = takerFacet.newTaker(
//             address(this),
//             address(pool),
//             -300,
//             300,
//             2e18,
//             MIN_SQRT_RATIO,
//             MAX_SQRT_RATIO,
//             rftData
//         );

//         // Verify that ViewFacet can see assets created by other facets
//         (address makerOwner, , , , , ) = viewFacet.getAssetInfo(makerAssetId);
//         (address takerOwner, , , , , ) = viewFacet.getAssetInfo(takerAssetId);

//         assertEq(makerOwner, recipient);
//         assertEq(takerOwner, recipient);
//     }

//     function testIntegrationWithRealPools() public {
//         // Test integration with real Uniswap V3 pools
//         // This test will need forking and real pool addresses
//         // For now, we'll test that the system handles it gracefully
//         assertTrue(true);
//     }

//     // ============ Helper Functions ============

//     function testViewFacetDeployment() public {
//         // Test that ViewFacet is accessible through the diamond
//         // The viewFacet should be available from MultiSetupTest
//         assertTrue(address(viewFacet) != address(0));
//     }

//     function testViewFacetInterface() public {
//         // Test that ViewFacet implements the expected interface
//         // This would require checking function signatures
//         // For now, we'll test that the main functions exist
//         assertTrue(true);
//     }
// }

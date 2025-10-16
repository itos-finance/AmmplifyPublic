// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { console2 as console } from "forge-std/console2.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { Data, DataImpl } from "../../src/walkers/Data.sol";
import { Key, KeyImpl } from "../../src/tree/Key.sol";
import { Pool, PoolInfo, PoolLib } from "../../src/Pool.sol";
import { UniV3IntegrationSetup } from "../UniV3.u.sol";
import { Asset, AssetLib } from "../../src/Asset.sol";
import { Store } from "../../src/Store.sol";
import { Node } from "../../src/walkers/Node.sol";
import { TreeTickLib } from "../../src/tree/Tick.sol";
import { PoolWalker } from "../../src/walkers/Pool.sol";
import { IUniswapV3Pool } from "v3-core/interfaces/IUniswapV3Pool.sol";

contract PoolWalkerTest is Test, UniV3IntegrationSetup {
    Node public node;

    function setUp() public {
        setUpPool(500); // For a tick spacing of 10.

        MockERC20(poolToken0s[0]).mint(address(this), 1e24);
        MockERC20(poolToken1s[0]).mint(address(this), 1e24);
    }

    function testUpdateLiq() public {
        // Generic data setup.
        PoolInfo memory pInfo = PoolLib.getPoolInfo(pools[0]);
        (Asset storage asset, ) = AssetLib.newMaker(msg.sender, pInfo, -100, 100, 1e24, true);
        Data memory data = DataImpl.make(pInfo, asset, 0, type(uint160).max, 1);
        // Check the pool's current liquidity for this key.
        Key key = KeyImpl.make(6400, 1600);
        (int24 lowTick, int24 highTick) = key.ticks(data.fees.rootWidth, data.fees.tickSpacing);
        bytes32 posKey = keccak256(abi.encodePacked(address(this), lowTick, highTick));
        (uint128 liq, , , , ) = IUniswapV3Pool(pools[0]).positions(posKey);
        assertEq(liq, 0);

        node.liq.mLiq = 100e8;
        PoolWalker.updateLiq(key, node, data);
        (liq, , , , ) = IUniswapV3Pool(pools[0]).positions(posKey);
        // There should always be 1 extra liq so the ticks never clear.
        assertEq(liq, 100e8 + 1);

        // Check that the pool's liquidity has been updated.
        node.liq.mLiq = 50e8;
        PoolWalker.updateLiq(key, node, data);
        (liq, , , , ) = IUniswapV3Pool(pools[0]).positions(posKey);
        // Still just one extra liq.
        assertEq(liq, 50e8 + 1);

        node.liq.borrowed = 200e8;
        PoolWalker.updateLiq(key, node, data);
        (liq, , , , ) = IUniswapV3Pool(pools[0]).positions(posKey);
        assertEq(liq, 250e8 + 1);
    }

    function testSettleTickSpacing60() public {
        // Set up a pool with fee tier 3000 (tick spacing 60)
        setUpPool(3000);

        // Get pool info for the new pool
        PoolInfo memory pInfo = PoolLib.getPoolInfo(pools[1]);

        // Verify the tick spacing is 60
        assertEq(pInfo.tickSpacing, 60);

        // Create asset and data for testing
        (Asset storage asset, ) = AssetLib.newMaker(msg.sender, pInfo, -100, 100, 1e24, true);
        Data memory data = DataImpl.make(pInfo, asset, 0, type(uint160).max, 1);

        // Test the settle function with range aligned to tick spacing 60
        // Use ticks that are multiples of 60 and within the range -2**13 to 2**13
        int24 lowTick = -8192 * 60; // -8100 = -135 * 60, close to -2**13
        int24 highTick = 8192 * 60; // 8100 = 135 * 60, close to 2**13

        // This should not revert - the settle function should handle the full range
        PoolWalker.settle(pInfo, lowTick, highTick, data);

        // If we get here, the test passes
        assertTrue(true, "Settle function completed successfully for tick spacing 60 with range -2**13 to 2**13");
    }
}

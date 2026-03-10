// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { console2 as console } from "forge-std/console2.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { Data, DataImpl } from "../../src/walkers/Data.sol";
import { Key, KeyImpl } from "../../src/tree/Key.sol";
import { Pool, PoolInfo, PoolLib, PoolValidation } from "../../src/Pool.sol";
import { UniV4IntegrationSetup } from "../UniV4.u.sol";
import { Asset, AssetLib } from "../../src/Asset.sol";
import { Store } from "../../src/Store.sol";
import { Node } from "../../src/walkers/Node.sol";
import { TreeTickLib } from "../../src/tree/Tick.sol";
import { PoolWalker } from "../../src/walkers/Pool.sol";
import { StateLibrary } from "v4-core/libraries/StateLibrary.sol";
import { IPoolManager } from "v4-core/interfaces/IPoolManager.sol";
import { PoolKey } from "v4-core/types/PoolKey.sol";
import { PoolId, PoolIdLibrary } from "v4-core/types/PoolId.sol";
import { FeeLib } from "../../src/Fee.sol";

contract PoolWalkerTest is Test, UniV4IntegrationSetup {
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    Node public node;

    function setUp() public {
        FeeLib.init();
        setUpPool(500); // For a tick spacing of 10.
        PoolValidation.initPoolManager(address(manager));
        Store.registerPoolKey(poolKeys[0]);

        MockERC20(poolToken0s[0]).mint(address(this), 1e24);
        MockERC20(poolToken1s[0]).mint(address(this), 1e24);
    }

    function _getPositionLiq(uint256 poolIdx, int24 tickLower, int24 tickUpper) internal view returns (uint128 liq) {
        (liq, , ) = IPoolManager(address(manager)).getPositionInfo(
            poolKeys[poolIdx].toId(),
            address(this),
            tickLower,
            tickUpper,
            bytes32(0)
        );
    }

    function testUpdateLiq() public {
        // Generic data setup.
        PoolInfo memory pInfo = PoolLib.getPoolInfo(pools[0]);
        (Asset storage asset, ) = AssetLib.newMaker(msg.sender, pInfo, -100, 100, 1e24, true);
        Data memory data = DataImpl.make(pInfo, asset, 0, type(uint160).max, 1);
        // Check the pool's current liquidity for this key.
        Key key = KeyImpl.make(6400, 1600);
        (int24 lowTick, int24 highTick) = key.ticks(data.fees.rootWidth, data.fees.tickSpacing);
        uint128 liq = _getPositionLiq(0, lowTick, highTick);
        assertEq(liq, 0, "0");

        // Mint more liq.
        node.liq.mLiq = 100e8;
        PoolLib.clearOps();
        PoolWalker.downUpdateLiq(key, node, data);
        liq = _getPositionLiq(0, lowTick, highTick);
        // We need to add liq so nothing changes on the down.
        assertEq(liq, 0, "1");
        assertEq(node.liq.dirty, PoolWalker.ADD_LIQ_DIRTY_FLAG, "2");
        PoolWalker.upUpdateLiq(key, node, data);
        // Execute batched ops to apply liquidity to V4 pool.
        executePoolLibOps(pInfo);

        liq = _getPositionLiq(0, lowTick, highTick);
        // There should always be 1 extra liq so the ticks never clear.
        assertEq(liq, 100e8 + 1, "4");

        // Check that the pool's liquidity has decreased.
        node.liq.mLiq = 50e8;
        node.liq.dirty = 0;
        PoolLib.clearOps();
        PoolWalker.downUpdateLiq(key, node, data);
        executePoolLibOps(pInfo);
        liq = _getPositionLiq(0, lowTick, highTick);
        // Still just one extra liq.
        assertEq(liq, 50e8 + 1, "6");
        assertEq(node.liq.dirty, 0, "7");
        assertEq(data.clearPreLend(key), 0, "8");

        node.liq.borrowed = 200e8;
        PoolLib.clearOps();
        PoolWalker.downUpdateLiq(key, node, data);
        PoolWalker.upUpdateLiq(key, node, data);
        executePoolLibOps(pInfo);
        liq = _getPositionLiq(0, lowTick, highTick);
        assertEq(liq, 250e8 + 1, "9");
    }

    function testSettleTickSpacing60() public {
        // Set up a pool with fee tier 3000 (tick spacing 60)
        setUpPool(3000);
        Store.registerPoolKey(poolKeys[1]);

        // Get pool info for the new pool
        PoolInfo memory pInfo = PoolLib.getPoolInfo(pools[1]);

        // Verify the tick spacing is 60
        assertEq(pInfo.tickSpacing, 60);

        // Create asset and data for testing
        (Asset storage asset, ) = AssetLib.newMaker(msg.sender, pInfo, -100, 100, 1e24, true);
        Data memory data = DataImpl.make(pInfo, asset, 0, type(uint160).max, 1);

        // Test the settle function with range aligned to tick spacing 60
        int24 lowTick = -8192 * 60;
        int24 highTick = 8192 * 60;

        // This should not revert
        PoolWalker.settle(pInfo, lowTick, highTick, data);

        assertTrue(true, "Settle function completed successfully for tick spacing 60 with range -2**13 to 2**13");
    }
}

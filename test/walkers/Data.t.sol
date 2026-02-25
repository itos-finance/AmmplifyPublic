// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { console2 as console } from "forge-std/console2.sol";
import { Data, DataImpl } from "../../src/walkers/Data.sol";
import { Key, KeyImpl } from "../../src/tree/Key.sol";
import { Pool, PoolInfo, PoolLib } from "../../src/Pool.sol";
import { UniV3IntegrationSetup } from "../UniV3.u.sol";
import { Asset, AssetLib } from "../../src/Asset.sol";
import { Store } from "../../src/Store.sol";
import { TreeTickLib } from "../../src/tree/Tick.sol";
import { FeeLib } from "../../src/Fee.sol";

import { console } from "forge-std/console.sol";

contract DataTest is Test, UniV3IntegrationSetup {
    function setUp() public {
        FeeLib.init();
        setUpPool(500); // For a tick spacing of 10.
    }

    function testMake() public {
        Pool storage p = Store.pool(pools[0]);
        p.timestamp = uint128(block.timestamp);
        PoolInfo memory pInfo = PoolLib.getPoolInfo(pools[0]);
        (Asset storage asset, ) = AssetLib.newMaker(msg.sender, pInfo, -100, 100, 1e24);
        // Setup done.
        Data memory data = DataImpl.make(pInfo, asset, 0, 2 << 96, 1);
        // We can't really test this here because of how foundry works with expecting reverts.
        // So we'll have to test it in the higher level integration tests.
        // vm.expectRevert(abi.encodeWithSelector(DataImpl.PriceSlippageExceeded.selector, 1 << 96, 2 << 96, 3 << 96));
        // DataImpl.make(pInfo, asset, 2 << 96, 3 << 96, 1);
        // Is pool info correct?
        assertEq(data.poolAddr, pInfo.poolAddr);
        bytes32 poolStore = data.poolStore;
        assembly {
            p.slot := poolStore
        }
        assertEq(p.timestamp, block.timestamp);
        assertEq(data.sqrtPriceX96, 1 << 96);
        assertEq(data.timestamp, block.timestamp);
    }

    function testComputeBorrows() public {
        PoolInfo memory pInfo = PoolLib.getPoolInfo(pools[0]);
        (Asset storage asset, ) = AssetLib.newMaker(msg.sender, pInfo, -100, 100, 1e24);
        Data memory data = DataImpl.make(pInfo, asset, 0, 2 << 96, 1);
        uint24 base = TreeTickLib.tickToTreeIndex(100, data.fees.rootWidth, data.fees.tickSpacing);
        Key key = KeyImpl.make(base, 16);
        // First test it with taking as X.
        data.takeAsX = true;
        (uint256 x, uint256 y) = data.computeBorrow(key, 100e18, false);
        assertGt(x, 0);
        assertEq(y, 0);
        // Pool price changes don't affect borrow amount.
        swapTo(0, 4 << 96);
        (uint256 x2, uint256 y2) = data.computeBorrow(key, 100e18, false);
        assertEq(x, x2, "x2");
        assertEq(y, y2, "y2");
        (x2, y2) = data.computeBorrow(key, 200e18, false);
        // Roughly doubles the amount.
        assertApproxEqAbs(x * 2, x2, 1, "x22");
        assertApproxEqAbs(y * 2, y2, 1, "y22");
        // Doubling the width should also double the amounts (roughly).
        base = TreeTickLib.tickToTreeIndex(20, data.fees.rootWidth, data.fees.tickSpacing);
        key = KeyImpl.make(base, 32);
        (x2, y2) = data.computeBorrow(key, 100e18, false);
        assertApproxEqRel(x * 2, x2, 1e16, "x222");
        assertApproxEqRel(y * 2, y2, 1e16, "y222");
        // However if we switch to taking as y, we have no x now.
        data.takeAsX = false;
        (x, y) = data.computeBorrow(key, 100e18, false);
        assertEq(x, 0);
        assertGt(y, 0);
    }

    function testComputeBalances() public {
        PoolInfo memory pInfo = PoolLib.getPoolInfo(pools[0]);
        console.log("pool info");
        (Asset storage asset, ) = AssetLib.newMaker(msg.sender, pInfo, -100, 100, 1e24);
        console.log("asset created");
        Data memory data = DataImpl.make(pInfo, asset, 0, 2 << 96, 1);
        console.log("data created");
        uint24 base = TreeTickLib.tickToTreeIndex(-640, data.fees.rootWidth, data.fees.tickSpacing);
        console.log("base", base);
        console.log("rootWidth", data.fees.rootWidth);
        console.log("tickSpacing", data.fees.tickSpacing);
        Key key = KeyImpl.make(base, 128);
        // This is centered around 0, so we'll have balances in both.
        (uint256 x, uint256 y) = data.computeBalances(key, 100e18, false);
        assertNotEq(x, 0, "x0");
        assertNotEq(y, 0, "y0");
        // But if the price moves out of range, we'll just have one token, and in fact it matches
        // the borrow balances.
        data.sqrtPriceX96 = 4 << 96;
        // Taking as y to match the price going above.
        (uint256 bx, uint256 by) = data.computeBorrow(key, 100e18, false);
        (uint256 x2, uint256 y2) = data.computeBalances(key, 100e18, false);
        assertNotEq(x, x2, "x8");
        assertNotEq(y, y2, "y8");
        assertEq(x2, bx, "xb");
        assertEq(y2, by, "yb");
    }
}

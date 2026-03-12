// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { console2 as console } from "forge-std/console2.sol";
import { Data, DataImpl } from "../../src/walkers/Data.sol";
import { Key, KeyImpl } from "../../src/tree/Key.sol";
import { Pool, PoolInfo, PoolLib, PoolValidation } from "../../src/Pool.sol";
import { UniV4IntegrationSetup } from "../UniV4.u.sol";
import { Asset, AssetLib, AssetNode } from "../../src/Asset.sol";
import { Store } from "../../src/Store.sol";
import { Node } from "../../src/walkers/Node.sol";
import { TreeTickLib } from "../../src/tree/Tick.sol";
import { LiqType, LiqNode, LiqData, LiqDataLib, LiqWalker } from "../../src/walkers/Liq.sol";
import { FeeLib } from "../../src/Fee.sol";

contract LiqWalkerTest is Test, UniV4IntegrationSetup {
    Node public node;
    Node public left;
    Node public right;

    function setUp() public {
        FeeLib.init();
        setUpPool(500); // For a tick spacing of 10.
        PoolValidation.initPoolManager(address(manager));
        Store.registerPoolKey(poolKeys[0]);
    }

    function testUp() public {}

    function testUpdateFeeCheckpoints() public {
        // Generic data setup.
        PoolInfo memory pInfo = PoolLib.getPoolInfo(pools[0]);
        (Asset storage asset, ) = AssetLib.newMaker(msg.sender, pInfo, -100, 100, 1e24);
        Data memory data = DataImpl.make(pInfo, asset, 0, type(uint160).max, 1);
        // Test specific
        Key key = KeyImpl.make(16000, 1);
        LiqWalker.LiqIter memory iter = LiqWalker.LiqIter({ key: key, width: 1, lowTick: 160000, highTick: 160010 });

        Node storage n = data.node(key);
        n.liq.mLiq = 5e8;
        addPoolLiq(0, 160000, 160010, 5e8);
        LiqWalker.updateFeeCheckpoints(iter, n, data);

        // mLiq should not change from updateFeeCheckpoints.
        assertEq(n.liq.mLiq, 5e8, "mLiq");
    }

    function testModifyMakerAdd() public {
        // Generic data setup.
        PoolInfo memory pInfo = PoolLib.getPoolInfo(pools[0]);
        (Asset storage asset, ) = AssetLib.newMaker(msg.sender, pInfo, -100, 100, 1e24);
        Data memory data = DataImpl.make(pInfo, asset, 0, type(uint160).max, 1);
        // Test specific
        Key key = KeyImpl.make(data.fees.rootWidth / 2, 1);
        (int24 low, int24 high) = key.ticks(data.fees.rootWidth, data.fees.tickSpacing);
        console.log("ticks", uint24(low), uint24(high));
        LiqWalker.LiqIter memory iter = LiqWalker.LiqIter({ key: key, width: 1, lowTick: low, highTick: high });

        // Empty node.
        Node storage n = data.node(key);
        AssetNode storage aNode = data.assetNode(key);
        LiqWalker.modify(iter, n, data, 200e8);
        assertEq(n.liq.dirty, 1, "1d");
        assertEq(aNode.sliq, 200e8, "sliq");
        assertEq(n.liq.mLiq, 200e8, "mLiq");
        assertGt(data.xBalance, 0, "1x");
        assertEq(data.yBalance, 0, "1y");
    }

    function testModifyAddRemove() public {
        // Generic data setup.
        PoolInfo memory pInfo = PoolLib.getPoolInfo(pools[0]);
        (Asset storage asset, ) = AssetLib.newMaker(msg.sender, pInfo, -100, 100, 1e24);
        Data memory data = DataImpl.make(pInfo, asset, 0, type(uint160).max, 1);

        Key key = KeyImpl.make(data.fees.rootWidth / 2, 1);
        (int24 low, int24 high) = key.ticks(data.fees.rootWidth, data.fees.tickSpacing);
        LiqWalker.LiqIter memory iter = LiqWalker.LiqIter({ key: key, width: 1, lowTick: low, highTick: high });
        // We start with nothing.
        Node storage n = data.node(key);
        n.liq.mLiq = 0;
        AssetNode storage aNode = data.assetNode(key);
        aNode.sliq = 0;
        // Add to 100e8.
        LiqWalker.modify(iter, n, data, 100e8);
        console.log("added");
        // Remove it all
        LiqWalker.modify(iter, n, data, 0);
    }

    function testModifyMakerSubtract() public {
        // Generic data setup.
        PoolInfo memory pInfo = PoolLib.getPoolInfo(pools[0]);
        (Asset storage asset, ) = AssetLib.newMaker(msg.sender, pInfo, -100, 100, 1e24);
        Data memory data = DataImpl.make(pInfo, asset, 0, type(uint160).max, 1);
        // Test specific
        Key key = KeyImpl.make(data.fees.rootWidth / 2, 1);
        (int24 low, int24 high) = key.ticks(data.fees.rootWidth, data.fees.tickSpacing);
        console.log("ticks", uint24(low), uint24(high));
        LiqWalker.LiqIter memory iter = LiqWalker.LiqIter({ key: key, width: 1, lowTick: low, highTick: high });

        Node storage n = data.node(key);
        AssetNode storage aNode = data.assetNode(key);
        n.liq.mLiq = 200e8;
        n.liq.subtreeMLiq = 1000e8;
        aNode.sliq = 100e8;
        LiqWalker.modify(iter, n, data, 40e8);
        assertEq(n.liq.dirty, 1);
        assertEq(aNode.sliq, 40e8, "0");
        assertEq(n.liq.mLiq, 140e8, "2");
        assertLt(data.xBalance, 0, "3");
        assertEq(data.yBalance, 0, "4"); // Since we're above the range.
        assertEq(n.liq.subtreeMLiq, 1000e8, "6"); // Unchanged since we update in up, not modify.
    }

    function testModifyMakerAddExisting() public {
        // Generic data setup.
        PoolInfo memory pInfo = PoolLib.getPoolInfo(pools[0]);
        (Asset storage asset, ) = AssetLib.newMaker(msg.sender, pInfo, -100, 100, 1e24);
        Data memory data = DataImpl.make(pInfo, asset, 0, type(uint160).max, 1);
        // Test specific
        Key key = KeyImpl.make(data.fees.rootWidth / 2, 1);
        (int24 low, int24 high) = key.ticks(data.fees.rootWidth, data.fees.tickSpacing);
        console.log("ticks", uint24(low), uint24(high));
        LiqWalker.LiqIter memory iter = LiqWalker.LiqIter({ key: key, width: 1, lowTick: low, highTick: high });

        Node storage n = data.node(key);
        AssetNode storage aNode = data.assetNode(key);
        n.liq.mLiq = 200e8;
        n.liq.subtreeMLiq = 1000e8;
        aNode.sliq = 50e8;
        LiqWalker.modify(iter, n, data, 80e8);
        assertEq(n.liq.dirty, 1);
        assertEq(aNode.sliq, 80e8, "0");
        assertEq(n.liq.mLiq, 230e8, "3");
        assertEq(n.liq.subtreeMLiq, 1000e8, "4"); // Unchanged since we update in up, not modify.
        assertGt(data.xBalance, 0, "5");
        assertEq(data.yBalance, 0, "6");
    }

    function testModifyMakerSubtractExisting() public {
        // Generic data setup.
        PoolInfo memory pInfo = PoolLib.getPoolInfo(pools[0]);
        (Asset storage asset, ) = AssetLib.newMaker(msg.sender, pInfo, -100, 100, 1e24);
        Data memory data = DataImpl.make(pInfo, asset, 0, type(uint160).max, 1);
        // Test specific
        Key key = KeyImpl.make(data.fees.rootWidth / 2, 1);
        (int24 low, int24 high) = key.ticks(data.fees.rootWidth, data.fees.tickSpacing);
        console.log("ticks", uint24(low), uint24(high));
        LiqWalker.LiqIter memory iter = LiqWalker.LiqIter({ key: key, width: 1, lowTick: low, highTick: high });

        Node storage n = data.node(key);
        AssetNode storage aNode = data.assetNode(key);
        n.liq.mLiq = 200e8;
        n.liq.subtreeMLiq = 1000e8;
        aNode.sliq = 50e8;
        LiqWalker.modify(iter, n, data, 25e8);
        assertEq(n.liq.dirty, 1);
        assertEq(aNode.sliq, 25e8, "0");
        assertEq(n.liq.mLiq, 175e8, "3");
        assertEq(n.liq.subtreeMLiq, 1000e8, "4"); // Unchanged since we update in up, not modify.
        assertLt(data.xBalance, 0, "5");
        assertEq(data.yBalance, 0, "6");
    }

    function testModifyTakerAdd() public {
        // Generic data setup.
        PoolInfo memory pInfo = PoolLib.getPoolInfo(pools[0]);
        (Asset storage asset, ) = AssetLib.newTaker(msg.sender, pInfo, -100, 100, 1e24, 0, 0);
        Data memory data = DataImpl.make(pInfo, asset, 0, type(uint160).max, 1);
        // Test specific
        Key key = KeyImpl.make(data.fees.rootWidth / 2, 1);
        (int24 low, int24 high) = key.ticks(data.fees.rootWidth, data.fees.tickSpacing);
        console.log("ticks", uint24(low), uint24(high));
        LiqWalker.LiqIter memory iter = LiqWalker.LiqIter({ key: key, width: 1, lowTick: low, highTick: high });

        Node storage n = data.node(key);
        AssetNode storage aNode = data.assetNode(key);
        n.liq.tLiq = 200e8;
        aNode.sliq = 50e8;
        LiqWalker.modify(iter, n, data, 90e8);
        assertEq(n.liq.dirty, 1);
        assertEq(aNode.sliq, 90e8, "0");
        assertEq(n.liq.tLiq, 240e8, "1");
        // Subtree values aren't modified by modify.
        assertEq(n.liq.subtreeBorrowedX, 0, "3");
        assertEq(n.liq.subtreeBorrowedY, 0, "4");
        assertLt(data.xBalance, 0, "5");
        assertEq(data.yBalance, 0, "6");
    }

    function testModifyTakerSubtract() public {
        // Generic data setup.
        PoolInfo memory pInfo = PoolLib.getPoolInfo(pools[0]);
        (Asset storage asset, ) = AssetLib.newTaker(msg.sender, pInfo, -100, 100, 1e24, 0, 0);
        Data memory data = DataImpl.make(pInfo, asset, 0, type(uint160).max, 1);
        // Test specific
        Key key = KeyImpl.make(data.fees.rootWidth / 2, 1);
        (int24 low, int24 high) = key.ticks(data.fees.rootWidth, data.fees.tickSpacing);
        console.log("ticks", uint24(low), uint24(high));
        LiqWalker.LiqIter memory iter = LiqWalker.LiqIter({ key: key, width: 1, lowTick: low, highTick: high });

        Node storage n = data.node(key);
        AssetNode storage aNode = data.assetNode(key);
        n.liq.tLiq = 200e8;
        aNode.sliq = 50e8;
        n.liq.borrowedX = 500e24;
        n.liq.borrowedY = 500e24;
        n.liq.subtreeTLiq = 1000e8;
        n.liq.subtreeBorrowedX = 500e24;
        n.liq.subtreeBorrowedY = 500e24;
        console.log("modifying to zero");
        LiqWalker.modify(iter, n, data, 0);
        assertEq(n.liq.dirty, 1);
        assertEq(aNode.sliq, 0, "0");
        assertEq(n.liq.tLiq, 150e8, "1");
        assertEq(n.liq.subtreeTLiq, 1000e8, "2"); // Unchanged since we update in up, not modify.
        assertFalse(data.takeAsX, "takeAsX");
        assertEq(n.liq.borrowedX, 500e24, "3");
        assertLt(n.liq.borrowedY, 500e24, "4");
        assertEq(n.liq.subtreeBorrowedX, 500e24, "3s"); // Subtree is unchanged in modify.
        assertEq(n.liq.subtreeBorrowedY, 500e24, "4s");
        assertGt(data.xBalance, 0, "5");
        assertEq(data.yBalance, 0, "6");
    }

    function testSolveLiqRepay() public {
        // Generic data setup.
        PoolInfo memory pInfo = PoolLib.getPoolInfo(pools[0]);
        (Asset storage asset, ) = AssetLib.newTaker(msg.sender, pInfo, -100, 100, 1e24, 0, 0);
        Data memory data = DataImpl.make(pInfo, asset, 0, type(uint160).max, 1);
        // Test specific
        Key key = KeyImpl.make(data.fees.rootWidth / 2, 1);
        (int24 low, int24 high) = key.ticks(data.fees.rootWidth, data.fees.tickSpacing);
        LiqWalker.LiqIter memory iter = LiqWalker.LiqIter({ key: key, width: 1, lowTick: low, highTick: high });

        Node storage n = data.node(key);
        // Nothing changes if there is no borrow
        n.liq.mLiq = 100e8;
        n.liq.tLiq = 90e8;
        n.liq.lent = 10e8;
        LiqWalker.solveLiq(iter.key, n, data);
        assertEq(n.liq.dirty, 0, "0");
        // Nothing changes if the sibling can't repay
        n.liq.borrowed = 20e8;
        n.liq.tLiq = 100e8;
        Node storage sib = data.node(key.sibling());
        sib.liq.mLiq = 50;
        sib.liq.tLiq = 70;
        sib.liq.borrowed = 20;
        LiqWalker.solveLiq(iter.key, n, data);
        assertEq(n.liq.dirty, 0, "1");
        assertEq(sib.liq.dirty, 0, "2");
        // Repays to the parent what it can.
        Node storage parent = data.node(key.parent());
        parent.liq.lent = 100e8;
        sib.liq.tLiq = 0;
        LiqWalker.solveLiq(iter.key, n, data);
        // But below the borrow threshold.
        assertEq(n.liq.dirty, 0, "3");
        // With MIN_BORROW_THRESHOLD = 1e12, the repayable (20) is below the threshold
        // so it still won't repay. We need to make the amounts large enough.
        n.liq.mLiq = 100e12;
        n.liq.tLiq = 100e8;
        n.liq.lent = 10e12;
        n.liq.borrowed = 20e12;
        sib.liq.mLiq = 50e12;
        sib.liq.tLiq = 0;
        sib.liq.borrowed = 20e12;
        parent.liq.lent = 100e12;
        LiqWalker.solveLiq(iter.key, n, data);
        assertEq(n.liq.dirty, 3, "4");
        assertEq(sib.liq.dirty, 1, "5");
        assertEq(parent.liq.dirty, 1, "6");
        assertEq(sib.liq.net(), 70e12, "8"); // Won't change until solved.
        assertEq(n.liq.net(), 90e12 - 100e8, "9"); // mLiq(100e12) - tLiq(100e8) - lent(10e12), borrowed now 0
        LiqWalker.solveLiq(iter.key.sibling(), sib, data);
        assertEq(sib.liq.net(), 50e12, "10"); // borrowed cleared via preBorrow
        LiqWalker.solveLiq(iter.key.parent(), parent, data); // Finalizes the repayment
        assertEq(parent.liq.lent, 80e12, "11"); // 100e12 - 20e12 repaid
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testSolveLiqBorrow() public {
        // Generic data setup.
        PoolInfo memory pInfo = PoolLib.getPoolInfo(pools[0]);
        (Asset storage asset, ) = AssetLib.newTaker(msg.sender, pInfo, -100, 100, 1e24, 0, 0);
        Data memory data = DataImpl.make(pInfo, asset, 0, type(uint160).max, 1);
        // Test specific
        Key key = KeyImpl.make(0, data.fees.rootWidth / 2);
        (int24 low, int24 high) = key.ticks(data.fees.rootWidth, data.fees.tickSpacing);
        LiqWalker.LiqIter memory iter = LiqWalker.LiqIter({
            key: key,
            width: data.fees.rootWidth / 2,
            lowTick: low,
            highTick: high
        });

        Node storage n = data.node(key);
        // We'll want to test that it borrows from the parent even when there is none.
        // And that the sibling gets liquidity even when it doesn't need it.
        n.liq.lent = 10e12;
        LiqWalker.solveLiq(iter.key, n, data);
        Key sibKey = key.sibling();
        Node storage sib = data.node(sibKey);
        assertEq(n.liq.borrowed, 10e12, "0");
        assertEq(sib.liq.net(), 0, "2"); // Stays 0 until solved.
        assertEq(n.liq.dirty, 3, "3");
        assertEq(sib.liq.dirty, 1, "4");
        LiqWalker.solveLiq(sibKey, sib, data);
        assertEq(sib.liq.borrowed, 10e12, "5");
        assertEq(sib.liq.net(), 10e12, "6"); // Stays 0 until solved.
        // However if the root nets negatively then it errors.
        Key parentKey = key.parent();
        (low, high) = parentKey.ticks(data.fees.rootWidth, data.fees.tickSpacing);
        iter = LiqWalker.LiqIter({ key: parentKey, width: data.fees.rootWidth, lowTick: low, highTick: high });
        Node storage parent = data.node(parentKey);
        assertEq(parent.liq.net(), 0, "7");
        // Should have a prelend of 10e12 now.
        assertEq(parent.liq.dirty, 1, "9");
        vm.expectRevert(abi.encodeWithSelector(LiqWalker.InsufficientBorrowLiquidity.selector, -int256(10e12)));
        console.log("parentKey", parentKey.base(), parentKey.width());
        console.log("isRoot", data.isRoot(parentKey));
        LiqWalker.solveLiq(parentKey, parent, data);
    }
}

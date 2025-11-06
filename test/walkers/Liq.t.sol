// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { console2 as console } from "forge-std/console2.sol";
import { Data, DataImpl } from "../../src/walkers/Data.sol";
import { Key, KeyImpl } from "../../src/tree/Key.sol";
import { Pool, PoolInfo, PoolLib } from "../../src/Pool.sol";
import { UniV3IntegrationSetup } from "../UniV3.u.sol";
import { Asset, AssetLib, AssetNode } from "../../src/Asset.sol";
import { Store } from "../../src/Store.sol";
import { Node } from "../../src/walkers/Node.sol";
import { TreeTickLib } from "../../src/tree/Tick.sol";
import { LiqType, LiqNode, LiqNodeImpl, LiqData, LiqDataLib, LiqWalker } from "../../src/walkers/Liq.sol";
import { FeeLib } from "../../src/Fee.sol";

contract LiqWalkerTest is Test, UniV3IntegrationSetup {
    Node public node;
    Node public left;
    Node public right;

    function setUp() public {
        FeeLib.init();
        setUpPool(500); // For a tick spacing of 10.
    }

    function testUp() public {}

    function testCompound() public {
        // Generic data setup.
        PoolInfo memory pInfo = PoolLib.getPoolInfo(pools[0]);
        (Asset storage asset, ) = AssetLib.newMaker(msg.sender, pInfo, -100, 100, 1e24, true);
        Data memory data = DataImpl.make(pInfo, asset, 0, type(uint160).max, 1);
        // Test specific
        Key key = KeyImpl.make(16000, 1);
        LiqWalker.LiqIter memory iter = LiqWalker.LiqIter({ key: key, width: 1, lowTick: 160000, highTick: 160010 });

        // Test without swap fee earnings first.
        Node storage n = data.node(key);
        n.fees.xCFees = 100e18;
        n.fees.yCFees = 200e18;
        n.liq.mLiq = 5e8;
        addPoolLiq(0, 160000, 160010, 5e8);
        LiqWalker.compound(iter, n, data);

        // We can't compound yet because there are no standing fees.
        assertEq(n.liq.mLiq, 5e8, "mLiq");
        // But once we add them in.
        data.liq.xFeesCollected = 100e18;
        data.liq.yFeesCollected = 200e18;

        LiqWalker.compound(iter, n, data);
        assertGt(n.liq.mLiq, 5e8, "mLiq2");
        assertLt(n.fees.xCFees, 100e18, "xFees");
        // Cuz we're above the current price, we just need x to compound.
        assertEq(n.fees.yCFees, 200e18, "yFees same");

        // But if we were to overflow, the compound doesn't happen.
        console.log("Overflow compound");
        n.fees.xCFees = 1 << 127;
        n.fees.yCFees = 1 << 127;
        n.liq.mLiq = LiqNodeImpl.MAX_MLIQ - 1e8;
        LiqWalker.compound(iter, n, data);
        assertEq(n.liq.mLiq, LiqNodeImpl.MAX_MLIQ - 1e8, "mLiq same");
        assertEq(n.fees.xCFees, 1 << 127, "xFees same");
        assertEq(n.fees.yCFees, 1 << 127, "yFees same still");
    }

    function testModifyMakerAdd() public {
        // Generic data setup.
        PoolInfo memory pInfo = PoolLib.getPoolInfo(pools[0]);
        (Asset storage asset, ) = AssetLib.newMaker(msg.sender, pInfo, -100, 100, 1e24, true);
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
        uint128 sliq = n.liq.shares;
        assertEq(n.liq.dirty, 1, "1d");
        n.liq.dirty = 0; // clear.
        assertGt(data.xBalance, 0, "1x");
        assertEq(data.yBalance, 0, "1y");
        data.xBalance = 0;
        data.yBalance = 0;

        // Now modify it to itself. There should be no change.
        aNode.sliq = sliq / 2;
        // The sliq should be worth 100e8 so no change happens.
        LiqWalker.modify(iter, n, data, 100e8);
        assertEq(n.liq.dirty, 0, "d0");
        assertEq(aNode.sliq, sliq / 2, "0");
        assertEq(n.liq.shares, sliq, "1");
        assertEq(n.liq.mLiq, 200e8, "2");
        assertEq(data.xBalance, 0, "3");
        assertEq(data.yBalance, 0, "4");

        // But now with a higher target we'll add liq. We'll double the position.
        LiqWalker.modify(iter, n, data, 200e8);
        assertEq(n.liq.dirty, 1, "d1");
        assertEq(aNode.sliq, sliq, "5");
        assertEq(n.liq.shares, (3 * sliq) / 2, "6");
        assertEq(n.liq.mLiq, 300e8, "7");
        assertGt(data.xBalance, 0, "8");
        // Because our range is entirely above the current price.
        assertEq(data.yBalance, 0, "9");
    }

    function testModifyAddRemove() public {
        // Generic data setup.
        PoolInfo memory pInfo = PoolLib.getPoolInfo(pools[0]);
        (Asset storage asset, ) = AssetLib.newMaker(msg.sender, pInfo, -100, 100, 1e24, true);
        Data memory data = DataImpl.make(pInfo, asset, 0, type(uint160).max, 1);

        Key key = KeyImpl.make(data.fees.rootWidth / 2, 1);
        (int24 low, int24 high) = key.ticks(data.fees.rootWidth, data.fees.tickSpacing);
        LiqWalker.LiqIter memory iter = LiqWalker.LiqIter({ key: key, width: 1, lowTick: low, highTick: high });
        // We start with nothing.
        Node storage n = data.node(key);
        n.liq.mLiq = 0;
        n.liq.shares = 0;
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
        (Asset storage asset, ) = AssetLib.newMaker(msg.sender, pInfo, -100, 100, 1e24, true);
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
        n.fees.xCFees = 500;
        uint128 equivLiq = PoolLib.getEquivalentLiq(low, high, 500, 0, data.sqrtPriceX96, data.sqrtPriceX96, true);
        n.liq.ncLiq = 100e8;
        n.liq.shares = 200e8; // Actual shares
        uint128 totalShares = 200e8 + LiqWalker.VIRTUAL_SHARES;
        aNode.sliq = totalShares / 2; // If we want half we need half of the virtual shares as well.
        // The asset owns half the liq here and we want 2/5th of their position left.
        LiqWalker.modify(iter, n, data, ((100e8 + equivLiq) * 2) / 10);
        assertEq(n.liq.dirty, 1);
        assertApproxEqAbs(aNode.sliq, totalShares / 5, 1, "0"); // Half of 2/5ths
        assertLt(aNode.sliq, totalShares / 5, "00");
        uint128 sharesLost = totalShares / 2 - (totalShares / 5);
        assertApproxEqAbs(n.liq.shares, 200e8 - sharesLost, 1, "1");
        assertLt(n.liq.shares, 200e8 - sharesLost, "11");
        assertEq(n.liq.mLiq, 170e8, "2");
        assertLt(data.xBalance, 0, "3");
        assertEq(data.yBalance, 0, "4"); // Since we're above the range.
        assertEq(n.fees.xCFees, 350, "5");
        assertEq(n.liq.subtreeMLiq, 1000e8, "6"); // Unchanged since we update in up, not modify.
    }

    function testModifyNCMakerAdd() public {
        // Generic data setup.
        PoolInfo memory pInfo = PoolLib.getPoolInfo(pools[0]);
        // Non-compounding
        (Asset storage asset, ) = AssetLib.newMaker(msg.sender, pInfo, -100, 100, 1e24, false);
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
        n.fees.xCFees = 500;
        n.liq.ncLiq = 100e8;
        n.liq.shares = 100e8;
        aNode.sliq = 50e8;
        LiqWalker.modify(iter, n, data, 80e8);
        assertEq(n.liq.dirty, 1);
        assertEq(aNode.sliq, 80e8, "0");
        assertEq(n.liq.shares, 100e8, "1");
        assertEq(n.liq.ncLiq, 130e8, "2");
        assertEq(n.liq.mLiq, 230e8, "3");
        assertEq(n.liq.subtreeMLiq, 1000e8, "4"); // Unchanged since we update in up, not modify.
        assertGt(data.xBalance, 0, "5");
        assertEq(data.yBalance, 0, "6");
    }

    function testModifyNCMakerSubtract() public {
        // Generic data setup.
        PoolInfo memory pInfo = PoolLib.getPoolInfo(pools[0]);
        // Non-compounding
        (Asset storage asset, ) = AssetLib.newMaker(msg.sender, pInfo, -100, 100, 1e24, false);
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
        n.fees.xCFees = 500;
        n.liq.ncLiq = 100e8;
        n.liq.shares = 100e8;
        aNode.sliq = 50e8;
        LiqWalker.modify(iter, n, data, 25e8);
        assertEq(n.liq.dirty, 1);
        assertEq(aNode.sliq, 25e8, "0");
        assertEq(n.liq.shares, 100e8, "1");
        assertEq(n.liq.ncLiq, 75e8, "2");
        assertEq(n.liq.mLiq, 175e8, "3");
        assertEq(n.liq.subtreeMLiq, 1000e8, "4"); // Unchanged since we update in up, not modify.
        assertLt(data.xBalance, 0, "5");
        assertEq(data.yBalance, 0, "6");
    }

    function testModifyTakerAdd() public {
        // Generic data setup.
        PoolInfo memory pInfo = PoolLib.getPoolInfo(pools[0]);
        // Non-compounding
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
        // Non-compounding
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
        // Non-compounding
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
        // But below the compound threshold.
        assertEq(n.liq.dirty, 0, "3");
        data.liq.compoundThreshold = 10;
        LiqWalker.solveLiq(iter.key, n, data);
        assertEq(n.liq.dirty, 3, "4");
        assertEq(sib.liq.dirty, 1, "5");
        assertEq(parent.liq.dirty, 1, "6");
        assertEq(parent.liq.preLend, -20, "7");
        assertEq(sib.liq.preBorrow, -20, "8");
        assertEq(sib.liq.net(), 70, "8"); // Won't change until solved.
        assertEq(n.liq.net(), 10e8 - 20, "9");
        LiqWalker.solveLiq(iter.key, sib, data);
        assertEq(sib.liq.net(), 50, "10");
        LiqWalker.solveLiq(iter.key, parent, data); // Finalizes the repayment
        assertEq(parent.liq.lent, 100e8 - 20, "11");
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testSolveLiqBorrow() public {
        // Generic data setup.
        PoolInfo memory pInfo = PoolLib.getPoolInfo(pools[0]);
        // Non-compounding
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
        n.liq.lent = 10e8;
        data.liq.compoundThreshold = 1e12;
        LiqWalker.solveLiq(iter.key, n, data);
        Node storage sib = data.node(key.sibling());
        assertEq(n.liq.borrowed, 1e12, "0");
        assertEq(sib.liq.preBorrow, 1e12, "1");
        assertEq(sib.liq.net(), 0, "2"); // Stays 0 until solved.
        assertEq(n.liq.dirty, 3, "3");
        assertEq(sib.liq.dirty, 1, "4");
        LiqWalker.solveLiq(iter.key, sib, data);
        assertEq(sib.liq.borrowed, 1e12, "5");
        assertEq(sib.liq.net(), 1e12, "6"); // Stays 0 until solved.
        // However if the root nets negatively then it errors.
        Key parentKey = key.parent();
        (low, high) = parentKey.ticks(data.fees.rootWidth, data.fees.tickSpacing);
        iter = LiqWalker.LiqIter({ key: parentKey, width: data.fees.rootWidth, lowTick: low, highTick: high });
        Node storage parent = data.node(parentKey);
        assertEq(parent.liq.net(), 0, "7");
        assertEq(parent.liq.preLend, 1e12, "8");
        assertEq(parent.liq.dirty, 1, "9");
        vm.expectRevert(abi.encodeWithSelector(LiqWalker.InsufficientBorrowLiquidity.selector, -1e12));
        LiqWalker.solveLiq(iter.key, parent, data);
    }
}

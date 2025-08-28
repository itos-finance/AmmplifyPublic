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
import { Node } from "../../src/walkers/Node.sol";
import { TreeTickLib } from "../../src/tree/Tick.sol";
import { FeeWalker } from "../../src/walkers/Fee.sol";
import { FeeLib } from "../../src/Fee.sol";

contract FeeWalkerTest is Test, UniV3IntegrationSetup {
    Node public node;
    Node public left;
    Node public right;

    function setUp() public {
        setUpPool(500); // For a tick spacing of 10.
        FeeLib.init();
    }

    function testDown() public {
        // Test down by walking down with unclaimed in certains nodes and see if the balance that gets
        // pushed to their children nodes make sense under different borrow distributions.
        Pool storage p = Store.pool(pools[0]);
    }

    function testUp() public {
        // Test up by walking up and seeing the fee trackers get updated correctly
        // under different borrow distributions.
        Pool storage p = Store.pool(pools[0]);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testLeftRightWeights() public {
        // Just test that left/right weights are computed without issue.
        PoolInfo memory pInfo = PoolLib.getPoolInfo(pools[0]);
        (Asset storage asset, ) = AssetLib.newMaker(msg.sender, pInfo, -100, 100, 1e24, true);
        Data memory data = DataImpl.make(pInfo, asset, 0, type(uint160).max, 1);
        // Everything is zero right now. So weights should be equal for both sides.
        (uint256 lw, uint256 rw) = FeeWalker.getLeftRightWeights(data.liq, data.fees, node.liq, left.liq, right.liq, 8);
        assertEq(lw, rw, "w0");
        // Just adding mliq won't change anything.
        node.liq.mLiq = 100e18;
        (uint256 lw0, uint256 rw0) = FeeWalker.getLeftRightWeights(
            data.liq,
            data.fees,
            node.liq,
            left.liq,
            right.liq,
            8
        );
        assertEq(lw, lw0, "w00");
        assertEq(rw, rw0, "w00");
        // Changing the child weight doesn't do anything since there are no prefixes.
        (lw, rw) = FeeWalker.getLeftRightWeights(data.liq, data.fees, node.liq, left.liq, right.liq, 128);
        assertEq(lw, rw, "w1");
        // Now with some borrow, but it's still the same.
        node.liq.tLiq = 20e18;
        (lw, rw) = FeeWalker.getLeftRightWeights(data.liq, data.fees, node.liq, left.liq, right.liq, 8);
        assertEq(lw, rw, "w2");
        // But with higher borrow the weights should go up.
        node.liq.tLiq = 80e18;
        (uint256 lw2, uint256 rw2) = FeeWalker.getLeftRightWeights(
            data.liq,
            data.fees,
            node.liq,
            left.liq,
            right.liq,
            8
        );
        assertGt(lw2, lw, "lw3");
        assertGt(rw2, rw, "rw3");
        assertEq(lw2, rw2, "w3");
        // Add some prefixes of the same ratio, weights should not change.
        data.liq.tLiqPrefix = 800e18;
        data.liq.mLiqPrefix = 1000e18;
        (lw, rw) = FeeWalker.getLeftRightWeights(data.liq, data.fees, node.liq, left.liq, right.liq, 8);
        assertEq(lw, lw2, "lw4");
        assertEq(rw, rw2, "rw4");
        // And changes in childwidth affect the prefix but proportionally so there is no change.
        (lw, rw) = FeeWalker.getLeftRightWeights(data.liq, data.fees, node.liq, left.liq, right.liq, 1024);
        assertEq(lw, lw2, "lw5");
        assertEq(rw, rw2, "rw5");
        // But if we change the prefix ratio, then a large child width will affect the weights.
        data.liq.tLiqPrefix = 20e18;
        data.liq.mLiqPrefix = 100e18;
        (lw, rw) = FeeWalker.getLeftRightWeights(data.liq, data.fees, node.liq, left.liq, right.liq, 1024 * 1024);
        assertLt(lw, lw2, "lw6");
        assertLt(rw, rw2, "rw6");
        assertEq(lw, rw, "w6");

        // With symmetric borrows both weights should stay the same.
        left.liq.subtreeTLiq = 40e18;
        right.liq.subtreeTLiq = 40e18;
        (lw, rw) = FeeWalker.getLeftRightWeights(data.liq, data.fees, node.liq, left.liq, right.liq, 1024);
        assertEq(lw, rw, "lw7");
        // Max out the ratio using subtrees.
        left.liq.subtreeTLiq = 201e18;
        right.liq.subtreeTLiq = 201e18;
        left.liq.subtreeMLiq = 1e18;
        right.liq.subtreeMLiq = 1e18;
        (lw2, rw2) = FeeWalker.getLeftRightWeights(data.liq, data.fees, node.liq, left.liq, right.liq, 2);
        assertEq(lw2, rw2, "w72");

        // Now test asymmetric borrows.
        left.liq.subtreeTLiq = 90e18;
        right.liq.subtreeTLiq = 10e18;
        (lw, rw) = FeeWalker.getLeftRightWeights(data.liq, data.fees, node.liq, left.liq, right.liq, 8);
        assertGt(lw, rw, "lw8");
        left.liq.subtreeMLiq = 200e18;
        (lw, rw) = FeeWalker.getLeftRightWeights(data.liq, data.fees, node.liq, left.liq, right.liq, 8);
        assertLt(lw, rw, "lw9");
        // Upping the child will raise the prefix which will push down the weight discrepancy.
        (lw2, rw2) = FeeWalker.getLeftRightWeights(data.liq, data.fees, node.liq, left.liq, right.liq, 1024);
        assertLt(rw2 - lw2, rw - lw, "lw10");
        // Raising the tLiq prefix will push it back up.
        data.liq.tLiqPrefix = 40e18;
        (lw, rw) = FeeWalker.getLeftRightWeights(data.liq, data.fees, node.liq, left.liq, right.liq, 1024);
        assertGt(rw - lw, rw2 - lw2, "lw11");
    }

    function testChargeTrueFeeRate() public {
        PoolInfo memory pInfo = PoolLib.getPoolInfo(pools[0]);
        (Asset storage asset, ) = AssetLib.newMaker(msg.sender, pInfo, -100, 100, 1e24, true);
        Data memory data = DataImpl.make(pInfo, asset, 0, type(uint160).max, 1);
        data.timestamp = uint128(block.timestamp) - 1;

        // First test with leaf nodes to avoid child splits.
        // Test without anything first.
        Key key = KeyImpl.make(32, 8);
        (uint256 cmx, uint256 cmy, uint256 ctx, uint256 cty) = FeeWalker.chargeTrueFeeRate(key, node, data);
        assertEq(cmx, 0, "cmx0");
        assertEq(cmy, 0, "cmy0");
        assertEq(ctx, 1, "ctx0");
        assertEq(cty, 1, "cty0");
        // Test without any takers first to see if their rates get set to 1 and makers stay at 0.
        node.liq.subtreeMLiq = 100e18;
        node.liq.mLiq = 12.5e18;
        (cmx, cmy, ctx, cty) = FeeWalker.chargeTrueFeeRate(key, node, data);
        assertEq(cmx, 0, "cmx1");
        assertEq(cmy, 0, "cmy1");
        assertEq(ctx, 1, "ctx1");
        assertEq(cty, 1, "cty1");
        // Now with some takers.
        key = KeyImpl.make(16, 1); // Leaf from here.
        node.liq.subtreeTLiq = 20e18;
        (cmx, cmy, ctx, cty) = FeeWalker.chargeTrueFeeRate(key, node, data);
        // Because borrows are still 0 the results are still 0/1.
        assertEq(cmx, 0, "cmx2");
        assertEq(cmy, 0, "cmy2");
        assertEq(ctx, 1, "ctx2");
        assertEq(cty, 1, "cty2");
        // Now with some borrows.
        node.liq.subtreeBorrowedX = 2e18;
        node.liq.subtreeBorrowedY = 1e18;
        (cmx, cmy, ctx, cty) = FeeWalker.chargeTrueFeeRate(key, node, data);
        assertGt(ctx, 1, "ctx3");
        assertGt(cty, 1, "cty3");
        assertApproxEqAbs(ctx, cty * 2, 1, "ctxcty3");
        assertEq(ctx / 5, cmx, "cmx3");
        assertEq(cty / 5, cmy, "cmy3");
        assertNotEq(node.fees.xCFees, 0, "xcfees03");
        assertNotEq(node.fees.yCFees, 0, "ycfees03");
        assertEq(node.fees.xCFees, node.liq.mLiq * cmx, "xCFees3");
        assertEq(node.fees.yCFees, node.liq.mLiq * cmy, "yCFees3");
        // If we drop some of the compounding mliq and added ncliq the rates might stay the same
        // but fewer cFees will be given.
        uint256 oldXCFees = node.fees.xCFees;
        uint256 oldYCFees = node.fees.yCFees;
        node.fees.xCFees = 0;
        node.fees.yCFees = 0;
        node.liq.ncLiq = 50e18; // Gets subtracted from the overall mliq.
        (uint256 cmx2, uint256 cmy2, uint256 ctx2, uint256 cty2) = FeeWalker.chargeTrueFeeRate(key, node, data);
        assertEq(ctx, ctx2, "ctx4");
        assertEq(cty, cty2, "cty4");
        assertEq(cmx, cmx2, "cmx4");
        assertEq(cmy, cmy2, "cmy4");
        assertEq(node.fees.xCFees, oldXCFees / 2, "xCFees4");
        assertEq(node.fees.yCFees, oldYCFees / 2, "yCFees4");

        // Even without borrows, a prefix tliq will create borrows.
        node.liq.subtreeTLiq = 0;
        node.liq.subtreeBorrowedX = 0;
        node.liq.subtreeBorrowedY = 0;
        data.liq.tLiqPrefix = 50e18;
        (cmx, cmy, ctx, cty) = FeeWalker.chargeTrueFeeRate(key, node, data);
        assertGt(ctx, 1, "ctx5");
        assertGt(cty, 1, "cty5");
        assertGt(cmx, 0, "cmx5");
        assertGt(cmy, 0, "cmy5");

        // Now test with a non-leaf node to make sure child splits are handled.
        key = KeyImpl.make(256, 128);
        node.liq.subtreeMLiq = 200e18;
        node.liq.subtreeBorrowedX = 150e18;
        node.liq.subtreeBorrowedY = 120e18;
        data.liq.mLiqPrefix = 300e18;
        data.liq.tLiqPrefix = 150e18;
        (Key leftKey, Key rightKey) = key.children();
        Node storage leftChild = data.node(leftKey);
        Node storage rightChild = data.node(rightKey);
        leftChild.liq.subtreeMLiq = 12e18;
        leftChild.liq.subtreeTLiq = 6e18;
        leftChild.liq.mLiq = 1e17;
        leftChild.liq.tLiq = 5e16;
        leftChild.liq.subtreeBorrowedX = 4e18;
        leftChild.liq.subtreeBorrowedY = 2e18;
        rightChild.liq.subtreeMLiq = 17e18;
        rightChild.liq.subtreeTLiq = 30e18;
        rightChild.liq.mLiq = 2e17;
        rightChild.liq.tLiq = 1e17;
        rightChild.liq.subtreeBorrowedX = 18e18;
        rightChild.liq.subtreeBorrowedY = 40e18;
        (cmx, cmy, ctx, cty) = FeeWalker.chargeTrueFeeRate(key, node, data);
    }

    /// Nothing too serious to test here. Just that overall the fees are moved in the right direction.
    /// Can try with different weights and borrow splits.
    function testChildSplit() public {
        PoolInfo memory pInfo = PoolLib.getPoolInfo(pools[0]);
        (Asset storage asset, ) = AssetLib.newMaker(msg.sender, pInfo, -100, 100, 1e24, true);
        Data memory data = DataImpl.make(pInfo, asset, 0, type(uint160).max, 1);
    }

    function testAdd128Fees() public {
        PoolInfo memory pInfo = PoolLib.getPoolInfo(pools[0]);
        (Asset storage asset, ) = AssetLib.newMaker(msg.sender, pInfo, -100, 100, 1e24, true);
        Data memory data = DataImpl.make(pInfo, asset, 0, type(uint160).max, 1);
        assertEq(110, FeeWalker.add128Fees(50, 60, data, true));
        assertEq(120, FeeWalker.add128Fees(50, 70, data, false));
        assertEq(type(uint128).max, FeeWalker.add128Fees(1 << 127, 1 << 127, data, true));
        assertEq(data.xBalance, -1, "dx1");
        assertEq(type(uint128).max, FeeWalker.add128Fees(1 << 127, 1 << 128, data, false));
        assertEq(data.yBalance, -(1 << 127) - 1, "dy1");
    }
}

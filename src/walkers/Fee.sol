// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { SmoothRateCurveConfig, SmoothRateCurveLib } from "Commons/Math/SmoothRateCurveLib.sol";
import { Key } from "../tree/Key.sol";
import { Phase } from "../tree/Route.sol";
import { Data } from "../visitors/Data.sol";
import { FullMath } from "../FullMath.sol";
import { FeeLib } from "../Fee.sol";

/// Data we need to persist for fee accounting.
/// @dev ONLY operations in FeeWalker are modifying this data.
/// Others can read though so they should be aware of their ordering.
struct FeeNode {
    uint256 takerXFeesPerLiqX128;
    uint256 takerYFeesPerLiqX128;
    uint256 makerXFeesPerLiqX128; // Used for non-compounding makers
    uint256 makerYFeesPerLiqX128; // Used for non-compounding makers
    uint256 xCFees; // Fees collected in x for compounding liquidity.
    uint256 yCFees; // Fees collected in y for compounding liquidity.
    uint256 unclaimedMakerXFees; // Unclaimed fees in x.
    uint256 unclaimedMakerYFees; // Unclaimed fees in y.
    uint256 unpaidTakerXFees; // Unpaid fees in x.
    uint256 unpaidTakerYFees; // Unpaid fees in y.
}

/// Transient data for calculating fees during a walk.
struct FeeData {
    uint24 rootWidth; // The width of the root node.
    int24 tickSpacing; // The tick spacing for the pool.
    // Fee curve info.
    SmoothRateCurveConfig rateConfig; // The rate curve for calculating the true taker fee rate.
    SmoothRateCurveConfig splitConfig; // For splitting fees across subtrees when approximating unclaimed fees.
    // Fee charge propogation.
    // @dev These ALREADY have the time diff multiplied in to avoid re-multiplying.
    // These report the per liq fee rate paid by each "column" of the tree,
    // for which you can just average for your own column rate.
    uint256 leftColMakerXRateX128;
    uint256 leftColTakerXRateX128;
    uint256 leftColMakerYRateX128;
    uint256 leftColTakerYRateX128;
    uint256 rightColMakerXRateX128;
    uint256 rightColTakerXRateX128;
    uint256 rightColMakerYRateX128;
    uint256 rightColTakerYRateX128;
    // Root switch entries
    uint256 lcaLeftColMakerXRateX128;
    uint256 lcaLeftColTakerXRateX128;
    uint256 lcaLeftColMakerYRateX128;
    uint256 lcaLeftColTakerYRateX128;
    // We don't need a right rate since that can be copied from the above right rates.
}

library FeeDataLib {
    function make(PoolInfo memory pInfo) internal returns (FeeData memory data) {
        return
            FeeData({
                rootWidth: pInfo.treeWidth,
                tickSpacing: pInfo.tickSpacing,
                rateConfig: FeeLib.getRateCurve(pInfo.poolAddr),
                splitConfig: FeeLib.getSplitCurve(pInfo.poolAddr),
                // Unused till propogation.
                leftColMakerXRateX128: 0,
                leftColTakerXRateX128: 0,
                leftColMakerYRateX128: 0,
                leftColTakerYRateX128: 0,
                rightColMakerXRateX128: 0,
                rightColTakerXRateX128: 0,
                rightColMakerYRateX128: 0,
                rightColTakerYRateX128: 0,
                lcaLeftColMakerXRateX128: 0,
                lcaLeftColTakerXRateX128: 0,
                lcaLeftColMakerYRateX128: 0,
                lcaLeftColTakerYRateX128: 0
            });
    }
}

library FeeWalker {
    function down(Key key, bool visit, Data memory data) internal {
        // On the way down, we accumulate the prefixes and claim fees.
        Node storage node = data.nodes[key];

        // We just claim all of our unclaimed.
        if (key.isLeaf()) {
            // If we're at a leaf, we can claim fees.
            // We round up to overpay dust.
            node.fees.takerXFeesPerLiqX128 += FullMath.mulDivRoundingUp(
                node.fees.unpaidTakerXFees,
                1 << 128,
                node.liq.subtreeTLiq
            );
            node.fees.takerYFeesPerLiqX128 += FullMath.mulDivRoundingUp(
                node.fees.unpaidTakerYFees,
                1 << 128,
                node.liq.subtreeTLiq
            );
            node.fees.unpaidTakerXFees = 0;
            node.fees.unpaidTakerYFees = 0;

            (uint128 c, uint128 nonCX128) = node.liq.splitMakerFees(node.fees.unclaimedMakerXFees);
            node.fees.makerXFeesPerLiqX128 += nonCX128;
            node.fees.xCFees += c;
            node.fees.unclaimedMakerXFees = 0;

            (c, nonCX128) = node.liq.splitMakerFees(node.fees.unclaimedMakerYFees);
            node.fees.makerYFeesPerLiqX128 += nonCX128;
            node.fees.yCFees += c;
            node.fees.unclaimedMakerYFees = 0;

            return;
        }

        // We claim our own fees first.
        {
            uint24 width = key.width();
            // Takers
            uint256 myLiq = node.liq.tLiq * width;
            uint256 perTLiqX128 = FullMath.mulDivRoundingUp(node.fees.unpaidTakerXFees, 1 << 128, node.liq.subtreeTLiq);
            node.fees.takerXFeesPerLiqX128 += perTLiqX128;
            node.fees.unpaidTakerXFees -= FullMath.mulX128(perTLiqX128, myLiq, false);
            perTLiqX128 = FullMath.mulDivRoundingUp(node.fees.unpaidTakerYFees, 1 << 128, node.liq.subtreeTLiq);
            node.fees.takerYFeesPerLiqX128 += perTLiqX128;
            node.fees.unpaidTakerYFees -= FullMath.mulX128(perTLiqX128, myLiq, false);
            // Makers
            myLiq = node.liq.mLiq * width;
            uint256 myEarnings = FullMath.mulDiv(node.fees.unclaimedMakerXFees, myLiq, node.liq.subtreeMLiq);
            node.fees.unclaimedMakerXFees -= myEarnings;
            (uint128 c, uint128 nonCX128) = node.liq.splitMakerFees(myEarnings);
            node.fees.makerXFeesPerLiqX128 += nonCX128;
            node.fees.xCFees += c;
            myEarnings = FullMath.mulDiv(node.fees.unclaimedMakerYFees, myLiq, node.liq.subtreeMLiq);
            node.fees.unclaimedMakerYFees -= myEarnings;
            (c, nonCX128) = node.liq.splitMakerFees(myEarnings);
            node.fees.makerYFeesPerLiqX128 += nonCX128;
            node.fees.yCFees += c;
        }

        // Now split fees before updating prefixes.
        (Key leftChild, Key rightChild) = key.children();
        Node storage leftNode = data.nodes[leftChild];
        Node storage rightNode = data.nodes[rightChild];
        uint24 childWidth = leftChild.width();
        childSplit(
            node,
            leftNode,
            rightNode,
            childWidth,
            node.fees.unpaidTakerXFees,
            node.fees.unpaidTakerYFees,
            node.fees.unclaimedMakerXFees,
            node.fees.unclaimedMakerYFees
        );
        node.fees.unpaidTakerXFees = 0;
        node.fees.unpaidTakerYFees = 0;
        node.fees.unclaimedMakerXFees = 0;
        node.fees.unclaimedMakerYFees = 0;

        // Now we can add to the prefix if we're not visiting.
        if (!visit) {
            data.liq.mLiqPrefix += liqNode.mLiq;
            data.liq.tLiqPrefix += liqNode.tLiq;
        }
    }

    function up(Key key, bool visit, Data memory data) internal {
        // On the way up, we charge the true fee rate as much as possible.
        if (visit) {
            // We use the real fee rate calculation since we can.
            // The prefix will be correct going into this because the prop beforehand has removed their prefix.
            if (key.isLeft()) {
                (
                    data.fees.leftColMakerXRateX128,
                    data.fees.leftColMakerYRateX128,
                    data.fees.leftColTakerXRateX128,
                    data.fees.leftColTakerYRateX128
                ) = chargeTrueFeeRate(data, node);
            } else {
                (
                    data.fees.rightColMakerXRateX128,
                    data.fees.rightColMakerYRateX128,
                    data.fees.rightColTakerXRateX128,
                    data.fees.rightColTakerYRateX128
                ) = chargeTrueFeeRate(data, node);
            }
        } else {
            // Check for any uncalculated fee rates.
            if (data.fees.leftColMakerXRateX128 == 0) {
                // The prefix is correct here since we haven't removed ourselves yet.
                (
                    data.fees.leftColMakerXRateX128,
                    data.fees.leftColMakerYRateX128,
                    data.fees.leftColTakerXRateX128,
                    data.fees.leftColTakerYRateX128
                ) = chargeTrueFeeRate(data, leftNode);
            }
            if (data.fees.rightColTakerXRateX128 == 0) {
                (
                    data.fees.rightColMakerXRateX128,
                    data.fees.rightColMakerYRateX128,
                    data.fees.rightColTakerXRateX128,
                    data.fees.rightColTakerYRateX128
                ) = chargeTrueFeeRate(data, rightNode);
            }

            // We just infer our rate from the children.
            uint256 colMakerXRateX128 = (data.fees.leftColMakerXRateX128 + data.fees.rightColMakerXRateX128) / 2;
            uint256 colMakerYRateX128 = (data.fees.leftColMakerYRateX128 + data.fees.rightColMakerYRateX128) / 2;
            // +1 to round up.
            uint256 colTakerXRateX128 = (data.leftColTakerXRateX128 + data.rightColTakerXRateX128 + 1) / 2;
            uint256 colTakerYRateX128 = (data.leftColTakerYRateX128 + data.rightColTakerYRateX128 + 1) / 2;

            // We charge/pay our own fees.
            node.fees.takerXFeesPerLiqX128 += colTakerXRateX128;
            node.fees.takerYFeesPerLiqX128 += colTakerYRateX128;
            node.fees.makerXFeesPerLiqX128 += colMakerXRateX128;
            node.fees.makerYFeesPerLiqX128 += colMakerYRateX128;
            // We round down to avoid overpaying dust.
            uint256 compoundingLiq = node.liq.mLiq - node.liq.ncLiq;
            node.fees.xCFees += FullMath.mulX128(colMakerXRateX128, compoundingLiq, false);
            node.fees.yCFees += FullMath.mulX128(colMakerYRateX128, compoundingLiq, false);

            // The children have already been charged their fees.

            // We propogate up our fees.
            if (key.isLeft()) {
                data.leftColMakerXRateX128 = colMakerXRateX128;
                data.leftColMakerYRateX128 = colMakerYRateX128;
                data.leftColTakerXRateX128 = colTakerXRateX128;
                data.leftColTakerYRateX128 = colTakerYRateX128;
                data.rightColMakerXRateX128 = 0;
                data.rightColMakerYRateX128 = 0;
                data.rightColTakerXRateX128 = 0;
                data.rightColTakerYRateX128 = 0;
            } else {
                data.rightColMakerXRateX128 = colMakerXRateX128;
                data.rightColMakerYRateX128 = colMakerYRateX128;
                data.rightColTakerXRateX128 = colTakerXRateX128;
                data.rightColTakerYRateX128 = colTakerYRateX128;
                data.leftColMakerXRateX128 = 0;
                data.leftColMakerYRateX128 = 0;
                data.leftColTakerXRateX128 = 0;
                data.leftColTakerYRateX128 = 0;
            }

            // We remove the prefix now, before we potentially visit the sibling.
            data.mLiqPrefix -= node.liq.mLiq;
            data.tLiqPrefix -= node.liq.tLiq;
        }
    }

    function phase(Phase walkPhase, Data memory data) internal {
        if (walkPhase == Phase.LEFT_UP) {
            // At the end of left, if we visited the lca right child then
            // we can just proceed to the root propogation with the same child rates.
            if (data.rightColTakerXRateX128 == 0) {
                // We're going to visit the right route, so we need to save the left.
                data.lcaLeftColMakerXRateX128 = data.leftColMakerXRateX128;
                data.lcaLeftColMakerYRateX128 = data.leftColMakerYRateX128;
                data.lcaLeftColTakerXRateX128 = data.leftColTakerXRateX128;
                data.lcaLeftColTakerYRateX128 = data.leftColTakerYRateX128;
            }
        } else if (walkPhase == Phase.RIGHT_UP) {
            // At the end of right, we'll proceed to root propogation but if we have a
            // saved lca left child rate, then we need to move that back into use.
            if (data.lcaLeftColTakerXRateX128 != 0) {
                data.leftColMakerXRateX128 = data.lcaLeftColMakerXRateX128;
                data.leftColMakerYRateX128 = data.lcaLeftColMakerYRateX128;
                data.leftColTakerXRateX128 = data.lcaLeftColTakerXRateX128;
                data.leftColTakerYRateX128 = data.lcaLeftColTakerYRateX128;
            }
        }
    }

    /* Helpers */

    /// Returns the initial split weights for the left and right children according to liquidity utilization.
    /// @dev Be sure to multiply the by weights by the quantity of the borrowed asset to get the actual
    /// split weights.
    /// @dev This assumes the prefix does not include the current node's liquidity.
    function getLeftRightWeights(
        FeeData memory data,
        LiqNode storage node,
        LiqNode storage left,
        LiqNode storage right,
        uint24 childWidth
    ) internal view returns (uint256 leftWeight, uint256 rightWeight) {
        uint256 myMLiq = node.mLiq * childWidth;
        uint256 myTLiq = node.tLiq * childWidth;
        {
            uint256 leftMLiq = left.subtreeMLiq + myMLiq;
            uint256 leftTLiq = left.subtreeTLiq + myTLiq;
            uint256 totalMLiq = leftMLiq + data.mLiqPrefix * childWidth;
            uint256 totalTLiq = leftTLiq + data.tLiqPrefix * childWidth;
            // It's okay to round down here. That's incorporated in the rate curve.
            uint64 utilX64 = uint64((totalTLiq << 64) / totalMLiq);
            leftWeight = splitConfig.calculateRateX64(utilX64);
        }
        {
            uint256 rightMLiq = right.subtreeMLiq + myMLiq;
            uint256 rightTLiq = right.subtreeTLiq + myTLiq;
            uint256 totalMLiq = rightMLiq + data.mLiqPrefix * childWidth;
            uint256 totalTLiq = rightTLiq + data.tLiqPrefix * childWidth;
            // It's okay to round down here. That's incorporated in the rate curve.
            uint64 utilX64 = uint64((totalTLiq << 64) / totalMLiq);
            // Important to incorporate tliq in the weight so the same ratio, but different tLiqs
            // pay proportionally.
            rightWeight = splitConfig.calculateRateX64(utilX64);
        }
    }

    /// @notice Called on nodes that are the deepest we'll walk for their subtree (prop children) to charge them
    /// their subtree exact fees, and report their total amounts paid.
    /// @dev This assumes the prefix does not include the current node's liquidity.
    function chargeTrueFeeRate(
        Data memory data,
        Key key,
        Node storage node,
        uint256 width // 24 but 256 for conversion convenience
    )
        internal
        view
        returns (
            uint256 colMakerXRateX128,
            uint256 colMakerYRateX128,
            uint256 colTakerXRateX128,
            uint256 colTakerYRateX128
        )
    {
        // We use the liq ratio to calculate the true fee rate the entire column should pay.
        uint256 totalMLiq = width * data.liq.mLiqPrefix + node.subtreeMLiq;
        uint256 prefixTLiq = width * data.liq.tLiqPrefix;
        uint256 totalTLiq = prefixTLiq + node.subtreeTLiq;
        uint256 timeDiff = uint128(block.timestamp) - data.fees.treeTimestamp; // Convert to 256 for next mult
        uint256 takerRateX64 = timeDiff * data.fees.rateConfig.calculateRateX64(uint64((totalTLiq << 64) / totalMLiq));
        // Then we use the total column x and y borrows to calculate the total fees paid.
        (uint256 totalXBorrows, uint256 totalYBorrows) = data.computeBorrows(key, prefixTLiq, true);
        totalXBorrows += node.subtreeBorrowedX;
        totalYBorrows += node.subtreeBorrowedY;
        uint256 colXPaid = FullMath.mulX64(totalXBorrows, takerRateX64, true);
        uint256 colYPaid = FullMath.mulX64(totalYBorrows, takerRateX64, true);

        // Determine our column rates.
        // We round down but add one to ensure that taker rates are never 0 if visited.
        // This is important for indicating no fees vs. uncalculated fees.
        colTakerXRateX128 = FullMath.mulDiv(colXPaid, 1 << 128, totalTLiq) + 1;
        colTakerYRateX128 = FullMath.mulDiv(colYPaid, 1 << 128, totalTLiq) + 1;
        // We set taker rates to at least 1 to indicate it was calulated, and the fees were just 0.
        colMakerXRateX128 = FullMath.mulDiv(colXPaid, 1 << 128, totalMLiq);
        colMakerYRateX128 = FullMath.mulDiv(colYPaid, 1 << 128, totalMLiq);
        // Now add this to our node's fee accounting.
        node.fees.takerXFeesPerLiqX128 += colTakerXRateX128;
        node.fees.takerYFeesPerLiqX128 += colTakerYRateX128;
        node.fees.makerXFeesPerLiqX128 += colMakerXRateX128;
        node.fees.makerYFeesPerLiqX128 += colMakerYRateX128;
        uint256 compoundingLiq = width * (node.liq.mLiq - node.liq.ncLiq);
        node.fees.xCFees = FullMath.mulX128(colMakerXRateX128, compoundingLiq, false);
        node.fees.yCFees = FullMath.mulX128(colMakerYRateX128, compoundingLiq, false);

        // Then we calculate the children's fees and split.
        if (!key.isLeaf()) {
            (Key leftChild, Key rightChild) = key.children();
            Node storage leftNode = data.nodes[leftChild];
            Node storage rightNode = data.nodes[rightChild];

            /// The earnings to split.
            uint256 childrenTLiq = leftNode.liq.subtreeTLiq + rightNode.liq.subtreeTLiq;
            uint256 childrenXPaid = FullMath.mulX128(colTakerXRateX128, childrenTLiq, true);
            uint256 childrenYPaid = FullMath.mulX128(colTakerYRateX128, childrenTLiq, true);
            uint256 childrenMLiq = leftNode.liq.subtreeMLiq + rightNode.liq.subtreeMLiq;
            uint256 childrenXEarned = FullMath.mulX128(colMakerXRateX128, childrenMLiq, false);
            uint256 childrenYEarned = FullMath.mulX128(colMakerYRateX128, childrenMLiq, false);

            childSplit(
                node,
                leftNode,
                rightNode,
                width / 2,
                childrenXPaid,
                childrenYPaid,
                childrenXEarned,
                childrenYEarned
            );
        }
    }

    // Split the paid amounts and earned amounts into this node's children's unclaimed/unpaid.
    function childSplit(
        Node storage node,
        Node storage leftNode,
        Node storage rightNode,
        uint24 childWidth,
        uint256 xPaid,
        uint256 yPaid,
        uint256 xEarned,
        uint256 yEarned
    ) internal {
        // We split the earnings by the left and right weights.
        (uint256 leftWeight, uint256 rightWeight) = getLeftRightWeights(
            data,
            node.liq,
            leftNode.liq,
            rightNode.liq,
            childWidth
        );

        // Calculate x weighted split.
        uint256 leftBorrowWeight = leftWeight * leftNode.liq.subtreeBorrowedX;
        uint256 rightBorrowWeight = rightWeight * rightNode.liq.subtreeBorrowedX;
        uint256 leftRatioX256 = FullMath.mulDivX256(leftBorrowWeight, leftBorrowWeight + rightBorrowWeight, false);
        uint256 leftPaid = FullMath.mulX256(xPaid, leftRatioX256, false);
        leftNode.fees.unpaidTakerXFees += leftPaid;
        rightNode.fees.unpaidTakerXFees += xPaid - leftPaid;
        uint256 leftEarned = FullMath.mulX256(xEarned, leftRatioX256, false);
        leftNode.fees.unclaimedMakerXFees += leftEarned;
        rightNode.fees.unclaimedMakerXFees += xEarned - leftEarned;

        // Repeat for Y.
        leftBorrowWeight = leftWeight * leftNode.liq.subtreeBorrowedY;
        rightBorrowWeight = rightWeight * rightNode.liq.subtreeBorrowedY;
        leftRatioX256 = FullMath.mulDivX256(leftBorrowWeight, leftBorrowWeight + rightBorrowWeight);
        leftPaid = FullMath.mulX256(yPaid, leftRatioX256, false);
        leftNode.fees.unpaidTakerYFees += leftPaid;
        rightNode.fees.unpaidTakerYFees += yPaid - leftPaid;
        leftEarned = FullMath.mulX256(yEarned, leftRatioX256, false);
        leftNode.fees.unclaimedMakerYFees += leftEarned;
        rightNode.fees.unclaimedMakerYFees += yEarned - leftEarned;
    }
}

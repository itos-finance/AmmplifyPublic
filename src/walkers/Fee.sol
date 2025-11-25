// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { SmoothRateCurveConfig, SmoothRateCurveLib } from "Commons/Math/SmoothRateCurveLib.sol";
import { UnsafeMath } from "Commons/Math/UnsafeMath.sol";
import { Key } from "../tree/Key.sol";
import { Phase } from "../tree/Route.sol";
import { Data } from "./Data.sol";
import { Node } from "./Node.sol";
import { LiqNode, LiqData } from "./Liq.sol";
import { FullMath } from "../FullMath.sol";
import { FeeLib } from "../Fee.sol";
import { PoolInfo } from "../UniV4/Pool.sol";

/// Data we need to persist for fee accounting.
/// @dev ONLY operations in FeeWalker are modifying this data.
/// Others can read though so they should be aware of their ordering.
struct FeeNode {
    // Unlike maker fees, we don't track swap fees here to avoid another storage write.
    // We store taker swap fees in the feeGrowthInside tracker in liq, and this is just the borrow fees.
    uint256 takerXFeesPerLiqX128;
    uint256 takerYFeesPerLiqX128;
    uint256 xTakerFeesPerLiqX128; // Fee rate paid by takers subtree borrowing as x.
    uint256 yTakerFeesPerLiqX128; // Fee rate paid by takers subtree borrowing as y.
    // Maker fees including swap fees and lending earnings.
    uint256 makerXFeesPerLiqX128; // Used for non-compounding makers
    uint256 makerYFeesPerLiqX128; // Used for non-compounding makers
    // Note that these are uint128. They hold a fee balance which can grow unbounded.
    // However assuming 18 decimals, and a price of one trillion, earning 1 million a day, it would take
    // a year of not compounding to cause an overflow. We do have an escape hatch for fees just in case.
    uint128 xCFees; // Fees collected in x for compounding liquidity.
    uint128 yCFees; // Fees collected in y for compounding liquidity.
    uint128 unclaimedMakerXFees; // Unclaimed fees in x.
    uint128 unclaimedMakerYFees; // Unclaimed fees in y.
    uint128 unpaidTakerXFees; // Unpaid fees in x.
    uint128 unpaidTakerYFees; // Unpaid fees in y.
}

/// Transient data for calculating fees during a walk.
struct FeeData {
    uint24 rootWidth; // The width of the root node.
    int24 tickSpacing; // The tick spacing for the pool.
    // Pool fee info.
    uint256 feeGrowthGlobal0X128;
    uint256 feeGrowthGlobal1X128;
    // Fee curve info.
    SmoothRateCurveConfig rateConfig; // The rate curve for calculating the true taker fee rate.
    SmoothRateCurveConfig splitConfig; // For splitting fees across subtrees when approximating unclaimed fees.
    // Fee charge propogation.
    // @dev These ALREADY have the time diff multiplied in to avoid re-multiplying.
    // These report the per liq fee rate paid by each "column" of the tree,
    // for which you can just average for your own column rate.
    uint256 leftColMakerXEarningsPerLiqX128;
    uint256 leftColTakerXEarningsPerLiqX128;
    uint256 leftColMakerYEarningsPerLiqX128;
    uint256 leftColTakerYEarningsPerLiqX128;
    uint256 rightColMakerXEarningsPerLiqX128;
    uint256 rightColTakerXEarningsPerLiqX128;
    uint256 rightColMakerYEarningsPerLiqX128;
    uint256 rightColTakerYEarningsPerLiqX128;
    // Indicates if right and left are already calculated
    bool leftRated;
    bool rightRated;
    // Root switch entries
    bool lcaRated;
    uint256 lcaLeftColMakerXEarningsPerLiqX128;
    uint256 lcaLeftColTakerXEarningsPerLiqX128;
    uint256 lcaLeftColMakerYEarningsPerLiqX128;
    uint256 lcaLeftColTakerYEarningsPerLiqX128;
}
// We don't need a right rate since that can be copied from the above right rates.

library FeeDataLib {
    function make(PoolInfo memory pInfo) internal view returns (FeeData memory data) {
        (uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128) = pInfo.getFeeGrowthGlobals();
        data.rootWidth = pInfo.treeWidth;
        data.tickSpacing = pInfo.tickSpacing;
        data.feeGrowthGlobal0X128 = feeGrowthGlobal0X128;
        data.feeGrowthGlobal1X128 = feeGrowthGlobal1X128;
        data.rateConfig = FeeLib.getRateCurve(pInfo.poolAddr);
        data.splitConfig = FeeLib.getSplitCurve(pInfo.poolAddr);
    }
}

library FeeWalker {
    using SmoothRateCurveLib for SmoothRateCurveConfig;

    function down(Key key, bool visit, Data memory data) internal {
        // On the way down, we accumulate the prefixes and claim fees.
        Node storage node = data.node(key);

        // We just claim all of our unclaimed.
        if (key.isLeaf()) {
            // If we're at a leaf, we can claim fees.
            // We round up to overpay dust.
            if (node.liq.subtreeTLiq > 0) {
                // If the tLiq is zero we would never propogate any fees down anyways.
                // For unclaims and unpaids, we specify if the taker is borrowing as x or y.
                if (node.fees.unpaidTakerXFees > 0) {
                    // There has to be some xTLiq if there are unpaid x fees.
                    node.fees.xTakerFeesPerLiqX128 += FullMath.mulDivRoundingUp(
                        node.fees.unpaidTakerXFees,
                        1 << 128,
                        node.liq.xTLiq
                    );
                }
                if (node.fees.unpaidTakerYFees > 0) {
                    // There has to be some yTLiq if there are unpaid y fees.
                    node.fees.yTakerFeesPerLiqX128 += FullMath.mulDivRoundingUp(
                        node.fees.unpaidTakerYFees,
                        1 << 128,
                        node.liq.tLiq - node.liq.xTLiq
                    );
                }
                node.fees.unpaidTakerXFees = 0;
                node.fees.unpaidTakerYFees = 0;
            }

            if (node.liq.mLiq > 0) {
                // If there is no mliq, fees wouldn't propogate down.
                (uint128 c, uint256 nonCX128) = node.liq.splitMakerFees(node.fees.unclaimedMakerXFees);
                node.fees.makerXFeesPerLiqX128 += nonCX128;
                node.fees.xCFees += c;
                node.fees.unclaimedMakerXFees = 0;

                (c, nonCX128) = node.liq.splitMakerFees(node.fees.unclaimedMakerYFees);
                node.fees.makerYFeesPerLiqX128 += nonCX128;
                node.fees.yCFees += c;
                node.fees.unclaimedMakerYFees = 0;
            }

            return;
        }

        // We claim our own fees first.
        {
            uint24 width = key.width();
            // Takers
            if (node.liq.tLiq > 0) {
                // Unlike makers, we divy via borrowed balances.
                if (node.liq.borrowedX > 0) {
                    uint256 myUnpaidX128 = FullMath.mulDivRoundingUp(
                        uint256(node.fees.unpaidTakerXFees) << 128,
                        node.liq.borrowedX,
                        node.liq.subtreeBorrowedX
                    );
                    node.fees.xTakerFeesPerLiqX128 += UnsafeMath.divRoundingUp(myUnpaidX128, node.liq.xTLiq);
                    if (node.liq.borrowedX == node.liq.subtreeBorrowedX) {
                        // If we're the entire subtree, we can just zero it out.
                        node.fees.unpaidTakerXFees = 0;
                    } else {
                        // We round down to avoid underpaying dust
                        node.fees.unpaidTakerXFees -= uint128(myUnpaidX128 >> 128);
                    }
                }
                if (node.liq.borrowedY > 0) {
                    uint256 myUnpaidX128 = FullMath.mulDivRoundingUp(
                        uint256(node.fees.unpaidTakerYFees) << 128,
                        node.liq.borrowedY,
                        node.liq.subtreeBorrowedY
                    );
                    node.fees.yTakerFeesPerLiqX128 += UnsafeMath.divRoundingUp(
                        myUnpaidX128,
                        node.liq.tLiq - node.liq.xTLiq
                    );
                    if (node.liq.borrowedY == node.liq.subtreeBorrowedY) {
                        node.fees.unpaidTakerYFees = 0;
                    } else {
                        node.fees.unpaidTakerYFees -= uint128(myUnpaidX128 >> 128);
                    }
                }
            }
            // Makers
            if (node.liq.mLiq > 0) {
                uint256 myLiq = node.liq.mLiq * width;
                uint256 myEarnings = FullMath.mulDiv(node.fees.unclaimedMakerXFees, myLiq, node.liq.subtreeMLiq);
                node.fees.unclaimedMakerXFees -= uint128(myEarnings);
                (uint128 c, uint256 nonCX128) = node.liq.splitMakerFees(myEarnings);
                node.fees.makerXFeesPerLiqX128 += nonCX128;
                node.fees.xCFees += c;
                myEarnings = FullMath.mulDiv(node.fees.unclaimedMakerYFees, myLiq, node.liq.subtreeMLiq);
                node.fees.unclaimedMakerYFees -= uint128(myEarnings);
                (c, nonCX128) = node.liq.splitMakerFees(myEarnings);
                node.fees.makerYFeesPerLiqX128 += nonCX128;
                node.fees.yCFees += c;
            }
        }

        // Now split fees before updating prefixes.
        (Key leftChild, Key rightChild) = key.children();
        Node storage leftNode = data.node(leftChild);
        Node storage rightNode = data.node(rightChild);
        uint24 childWidth = leftChild.width();
        childSplit(
            data,
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
            data.liq.mLiqPrefix += node.liq.mLiq;
            data.liq.tLiqPrefix += node.liq.tLiq;
        }
    }

    function up(Key key, bool visit, Data memory data) internal {
        Node storage node = data.node(key);
        // On the way up, we charge the true fee rate as much as possible.
        if (visit) {
            // We use the real fee rate calculation since we can.
            // The prefix will be correct going into this because the prop beforehand has removed their prefix.
            uint256[4] memory earnings = chargeTrueFeeRate(key, node, data);
            if (key.isLeft()) {
                data.fees.leftRated = true;
                data.fees.leftColMakerXEarningsPerLiqX128 = earnings[0];
                data.fees.leftColMakerYEarningsPerLiqX128 = earnings[1];
                data.fees.leftColTakerXEarningsPerLiqX128 = earnings[2];
                data.fees.leftColTakerYEarningsPerLiqX128 = earnings[3];
            } else {
                data.fees.rightRated = true;
                data.fees.rightColMakerXEarningsPerLiqX128 = earnings[0];
                data.fees.rightColMakerYEarningsPerLiqX128 = earnings[1];
                data.fees.rightColTakerXEarningsPerLiqX128 = earnings[2];
                data.fees.rightColTakerYEarningsPerLiqX128 = earnings[3];
            }
        } else {
            // Check for any uncalculated fee rates using the Taker rate.
            (Key leftKey, Key rightKey) = key.children();
            if (!data.fees.leftRated) {
                // The prefix is correct here since we haven't removed ourselves yet.
                uint256[4] memory earnings = chargeTrueFeeRate(leftKey, data.node(leftKey), data);
                data.fees.leftColMakerXEarningsPerLiqX128 = earnings[0];
                data.fees.leftColMakerYEarningsPerLiqX128 = earnings[1];
                data.fees.leftColTakerXEarningsPerLiqX128 = earnings[2];
                data.fees.leftColTakerYEarningsPerLiqX128 = earnings[3];
                data.fees.leftRated = true;
            }
            if (!data.fees.rightRated) {
                uint256[4] memory earnings = chargeTrueFeeRate(rightKey, data.node(rightKey), data);
                data.fees.rightColMakerXEarningsPerLiqX128 = earnings[0];
                data.fees.rightColMakerYEarningsPerLiqX128 = earnings[1];
                data.fees.rightColTakerXEarningsPerLiqX128 = earnings[2];
                data.fees.rightColTakerYEarningsPerLiqX128 = earnings[3];
                data.fees.rightRated = true;
            }

            // We just infer our rate from the children.
            // A unit of liquidity at a parent node will earn the rates of both children's ranges.
            uint256 colMakerXRateX128 = data.fees.leftColMakerXEarningsPerLiqX128 +
                data.fees.rightColMakerXEarningsPerLiqX128;
            uint256 colMakerYRateX128 = data.fees.leftColMakerYEarningsPerLiqX128 +
                data.fees.rightColMakerYEarningsPerLiqX128;
            uint256 colTakerXRateX128 = data.fees.leftColTakerXEarningsPerLiqX128 +
                data.fees.rightColTakerXEarningsPerLiqX128;
            uint256 colTakerYRateX128 = data.fees.leftColTakerYEarningsPerLiqX128 +
                data.fees.rightColTakerYEarningsPerLiqX128;

            // We charge/pay our own fees.
            node.fees.takerXFeesPerLiqX128 += colTakerXRateX128;
            node.fees.takerYFeesPerLiqX128 += colTakerYRateX128;
            node.fees.makerXFeesPerLiqX128 += colMakerXRateX128;
            node.fees.makerYFeesPerLiqX128 += colMakerYRateX128;
            // We round down to avoid overpaying dust.
            uint256 compoundingLiq = node.liq.mLiq - node.liq.ncLiq;
            node.fees.xCFees = add128Fees(
                node.fees.xCFees,
                FullMath.mulX128(colMakerXRateX128, compoundingLiq, false),
                data,
                true
            );
            node.fees.yCFees = add128Fees(
                node.fees.yCFees,
                FullMath.mulX128(colMakerYRateX128, compoundingLiq, false),
                data,
                false
            );

            // The children have already been charged their fees.

            // We propogate up our fees.
            if (key.isLeft()) {
                data.fees.leftColMakerXEarningsPerLiqX128 = colMakerXRateX128;
                data.fees.leftColMakerYEarningsPerLiqX128 = colMakerYRateX128;
                data.fees.leftColTakerXEarningsPerLiqX128 = colTakerXRateX128;
                data.fees.leftColTakerYEarningsPerLiqX128 = colTakerYRateX128;
                data.fees.leftRated = true;
                data.fees.rightColMakerXEarningsPerLiqX128 = 0;
                data.fees.rightColMakerYEarningsPerLiqX128 = 0;
                data.fees.rightColTakerXEarningsPerLiqX128 = 0;
                data.fees.rightColTakerYEarningsPerLiqX128 = 0;
                data.fees.rightRated = false;
            } else {
                data.fees.rightColMakerXEarningsPerLiqX128 = colMakerXRateX128;
                data.fees.rightColMakerYEarningsPerLiqX128 = colMakerYRateX128;
                data.fees.rightColTakerXEarningsPerLiqX128 = colTakerXRateX128;
                data.fees.rightColTakerYEarningsPerLiqX128 = colTakerYRateX128;
                data.fees.rightRated = true;
                data.fees.leftColMakerXEarningsPerLiqX128 = 0;
                data.fees.leftColMakerYEarningsPerLiqX128 = 0;
                data.fees.leftColTakerXEarningsPerLiqX128 = 0;
                data.fees.leftColTakerYEarningsPerLiqX128 = 0;
                data.fees.leftRated = false;
            }

            // We remove the prefix now, before we potentially visit the sibling.
            data.liq.mLiqPrefix -= node.liq.mLiq;
            data.liq.tLiqPrefix -= node.liq.tLiq;
        }
    }

    function phase(Phase walkPhase, Data memory data) internal pure {
        if (walkPhase == Phase.LEFT_UP) {
            // At the end of left, if we visited the lca right child then
            // we can just proceed to the root propogation with the same child rates.
            if (data.fees.rightColTakerXEarningsPerLiqX128 == 0) {
                // We're going to visit the right route, so we need to save the left.
                data.fees.lcaLeftColMakerXEarningsPerLiqX128 = data.fees.leftColMakerXEarningsPerLiqX128;
                data.fees.lcaLeftColMakerYEarningsPerLiqX128 = data.fees.leftColMakerYEarningsPerLiqX128;
                data.fees.lcaLeftColTakerXEarningsPerLiqX128 = data.fees.leftColTakerXEarningsPerLiqX128;
                data.fees.lcaLeftColTakerYEarningsPerLiqX128 = data.fees.leftColTakerYEarningsPerLiqX128;
                data.fees.lcaRated = data.fees.leftRated;
            }
        } else if (walkPhase == Phase.RIGHT_UP) {
            // At the end of right, we'll proceed to root propogation but if we have a
            // saved lca left child rate, then we need to move that back into use.
            if (data.fees.lcaLeftColTakerXEarningsPerLiqX128 != 0) {
                data.fees.leftColMakerXEarningsPerLiqX128 = data.fees.lcaLeftColMakerXEarningsPerLiqX128;
                data.fees.leftColMakerYEarningsPerLiqX128 = data.fees.lcaLeftColMakerYEarningsPerLiqX128;
                data.fees.leftColTakerXEarningsPerLiqX128 = data.fees.lcaLeftColTakerXEarningsPerLiqX128;
                data.fees.leftColTakerYEarningsPerLiqX128 = data.fees.lcaLeftColTakerYEarningsPerLiqX128;
                data.fees.leftRated = data.fees.lcaRated;
            }
        }
    }

    /* Helpers */

    /// Returns the initial split weights for the left and right children according to liquidity utilization.
    /// @dev Be sure to multiply the by weights by the quantity of the borrowed asset to get the actual
    /// split weights.
    /// @dev Think of this like how much a single borrow of a token is worth in this column versus other columns.
    /// @dev This assumes the prefix does not include the current node's liquidity.
    function getLeftRightWeights(
        LiqData memory liqData,
        FeeData memory feeData,
        LiqNode storage node,
        LiqNode storage left,
        LiqNode storage right,
        uint24 childWidth
    ) internal view returns (uint256 leftWeight, uint256 rightWeight) {
        uint256 myMLiq = node.mLiq * childWidth;
        uint256 myTLiq = node.tLiq * childWidth;
        {
            uint256 leftMLiq = left.subtreeMLiq + myMLiq;
            uint256 totalMLiq = leftMLiq + liqData.mLiqPrefix * childWidth;
            if (totalMLiq == 0) {
                // There can't be any takers in this column.
                leftWeight = feeData.splitConfig.calculateRateX64(0);
            } else {
                uint256 leftTLiq = left.subtreeTLiq + myTLiq;
                uint256 totalTLiq = leftTLiq + liqData.tLiqPrefix * childWidth;
                // It's okay to round down here. That's incorporated in the rate curve.
                uint128 utilX64 = uint128((totalTLiq << 64) / totalMLiq);
                leftWeight = feeData.splitConfig.calculateRateX64(utilX64);
            }
        }
        {
            uint256 rightMLiq = right.subtreeMLiq + myMLiq;
            uint256 totalMLiq = rightMLiq + liqData.mLiqPrefix * childWidth;
            if (totalMLiq == 0) {
                rightWeight = feeData.splitConfig.calculateRateX64(0);
            } else {
                uint256 rightTLiq = right.subtreeTLiq + myTLiq;
                uint256 totalTLiq = rightTLiq + liqData.tLiqPrefix * childWidth;
                // It's okay to round down here. That's incorporated in the rate curve.
                uint128 utilX64 = uint128((totalTLiq << 64) / totalMLiq);
                // Important to incorporate tliq in the weight so the same ratio, but different tLiqs
                // pay proportionally.
                rightWeight = feeData.splitConfig.calculateRateX64(utilX64);
            }
        }
    }

    /// @notice Called on nodes that are the deepest we'll walk for their subtree (prop children) to charge them
    /// their subtree exact fees, and report their total amounts paid.
    /// @dev This assumes the prefix does not include the current node's liquidity.
    function chargeTrueFeeRate(
        Key key,
        Node storage node,
        Data memory data
    ) internal returns (uint256[4] memory colRatesX128) {
        uint24 width = key.width();
        // We use the liq ratio to calculate the true fee rate the entire column should pay.
        uint256 totalMLiq = width * data.liq.mLiqPrefix + node.liq.subtreeMLiq;
        uint256 takerRateX64;
        {
            uint256 totalTLiq = width * data.liq.tLiqPrefix + node.liq.subtreeTLiq;
            if (totalMLiq == 0 || totalTLiq == 0) {
                // There is no maker or taker liq in this entire column, so no fees to charge, no fee rates to update,
                // no unclaimeds to propogate down.
                return colRatesX128;
            }

            uint256 timeDiff = uint128(block.timestamp) - data.timestamp; // Convert to 256 for next mult
            takerRateX64 = timeDiff * data.fees.rateConfig.calculateRateX64(uint128((totalTLiq << 64) / totalMLiq));
        }

        uint256 colXPaid;
        uint256 colYPaid;
        {
            // Then we calculate the payment made by the takers at and above the current node to set the taker rates.
            // And we calculate the payment made by the takers below the current node to set the unpaids.
            // And we use the total balances to set the maker rates and unclaimeds.
            uint128 aboveTLiq = data.liq.tLiqPrefix + node.liq.tLiq;
            (uint256 aboveXBorrows, uint256 aboveYBorrows) = data.computeTWAPBalances(key, aboveTLiq, true);
            colXPaid = FullMath.mulX64(aboveXBorrows, takerRateX64, true);
            colYPaid = FullMath.mulX64(aboveYBorrows, takerRateX64, true);
            if (aboveTLiq != 0) {
                colRatesX128[2] = FullMath.mulDiv(colXPaid, 1 << 128, aboveTLiq);
                colRatesX128[3] = FullMath.mulDiv(colYPaid, 1 << 128, aboveTLiq);
            }
        }

        // Now we compute the unpaids for subtree borrows.
        // We could store subtree borrows without the node borrow to save a subtract here,
        // but let's just use one convention.
        uint256[4] memory childrenPaidEarned;
        childrenPaidEarned[0] = FullMath.mulX64(node.liq.subtreeBorrowedX - node.liq.borrowedX, takerRateX64, true);
        childrenPaidEarned[1] = FullMath.mulX64(node.liq.subtreeBorrowedY - node.liq.borrowedY, takerRateX64, true);
        colXPaid += childrenPaidEarned[0];
        colYPaid += childrenPaidEarned[1];

        // Now divy this up among all makers above and below in the column.
        uint256 aboveMLiq = data.liq.mLiqPrefix + node.liq.mLiq;
        // Implicit is that maker liq below and maker liq above should earn the same amount which is not true
        // but is a resonable approximation that is true in the limit of a totally efficient market.
        if (aboveMLiq == 0) {
            // All of the earnings go to the children.
            colRatesX128[0] = 0;
            colRatesX128[1] = 0;
            childrenPaidEarned[2] = colXPaid;
            childrenPaidEarned[3] = colYPaid;
        } else {
            uint256 aboveMLiqTotal = aboveMLiq * width;
            if (aboveMLiqTotal == totalMLiq) {
                // If all the maker liq is above, we don't need to consider children.
                colRatesX128[0] = FullMath.mulDiv(colXPaid, 1 << 128, aboveMLiq);
                colRatesX128[1] = FullMath.mulDiv(colYPaid, 1 << 128, aboveMLiq);
                childrenPaidEarned[2] = 0;
                childrenPaidEarned[3] = 0;
            } else {
                uint256 aboveMLiqRatioX256 = FullMath.mulDivX256(aboveMLiqTotal, totalMLiq, false);
                // X first.
                uint256 aboveEarned = FullMath.mulX256(colXPaid, aboveMLiqRatioX256, false);
                colRatesX128[0] = FullMath.mulDiv(aboveEarned, 1 << 128, aboveMLiq);
                childrenPaidEarned[2] = colXPaid - aboveEarned;
                // Now Y.
                aboveEarned = FullMath.mulX256(colYPaid, aboveMLiqRatioX256, false);
                colRatesX128[1] = FullMath.mulDiv(aboveEarned, 1 << 128, aboveMLiq);
                childrenPaidEarned[3] = colYPaid - aboveEarned;
            }
        }

        // Now pay/charge these fees ourselves.
        node.fees.takerXFeesPerLiqX128 += colRatesX128[2];
        node.fees.takerYFeesPerLiqX128 += colRatesX128[3];
        node.fees.makerXFeesPerLiqX128 += colRatesX128[0];
        node.fees.makerYFeesPerLiqX128 += colRatesX128[1];

        uint256 compoundingLiq = node.liq.mLiq - node.liq.ncLiq;
        node.fees.xCFees = add128Fees(
            node.fees.xCFees,
            FullMath.mulX128(colRatesX128[0], compoundingLiq, false),
            data,
            true
        );
        node.fees.yCFees = add128Fees(
            node.fees.yCFees,
            FullMath.mulX128(colRatesX128[1], compoundingLiq, false),
            data,
            false
        );
        // Then we calculate the children's fees and split.
        if (
            childrenPaidEarned[0] > 0 ||
            childrenPaidEarned[1] > 0 ||
            childrenPaidEarned[2] > 0 ||
            childrenPaidEarned[3] > 0
        ) {
            (Key leftChild, Key rightChild) = key.children();
            Node storage leftNode = data.node(leftChild);
            Node storage rightNode = data.node(rightChild);

            childSplit(
                data,
                node,
                leftNode,
                rightNode,
                width / 2,
                childrenPaidEarned[0],
                childrenPaidEarned[1],
                childrenPaidEarned[2],
                childrenPaidEarned[3]
            );
        }
    }

    // Split the paid amounts and earned amounts into this node's children's unclaimed/unpaid.
    function childSplit(
        Data memory data,
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
            data.liq,
            data.fees,
            node.liq,
            leftNode.liq,
            rightNode.liq,
            childWidth
        );

        // Calculate x weighted split.
        uint256 leftBorrowWeight = leftWeight * leftNode.liq.subtreeBorrowedX;
        uint256 rightBorrowWeight = rightWeight * rightNode.liq.subtreeBorrowedX;
        uint256 leftPaid;
        uint256 leftEarned;
        if (leftBorrowWeight == rightBorrowWeight) {
            // We special case here to catch when both weights are zero, but check equality
            // to conveniently cheapen other cases where this applies as well.
            // If the case is zero, zero, then there will be no paids to split, so no fees are lost.
            leftPaid = xPaid / 2;
            leftEarned = xEarned / 2;
        } else if (leftBorrowWeight == 0) {
            leftPaid = 0;
            leftEarned = 0;
        } else if (rightBorrowWeight == 0) {
            leftPaid = xPaid;
            leftEarned = xEarned;
        } else {
            uint256 leftRatioX256 = FullMath.mulDivX256(leftBorrowWeight, leftBorrowWeight + rightBorrowWeight, false);
            leftPaid = FullMath.mulX256(xPaid, leftRatioX256, false);
            leftEarned = FullMath.mulX256(xEarned, leftRatioX256, false);
        }
        leftNode.fees.unpaidTakerXFees += uint128(leftPaid);
        rightNode.fees.unpaidTakerXFees += uint128(xPaid - leftPaid);
        leftNode.fees.unclaimedMakerXFees += uint128(leftEarned);
        rightNode.fees.unclaimedMakerXFees += uint128(xEarned - leftEarned);

        // Repeat for Y.
        leftBorrowWeight = leftWeight * leftNode.liq.subtreeBorrowedY;
        rightBorrowWeight = rightWeight * rightNode.liq.subtreeBorrowedY;
        if (leftBorrowWeight == rightBorrowWeight) {
            leftPaid = yPaid / 2;
            leftEarned = yEarned / 2;
        } else if (leftBorrowWeight == 0) {
            leftPaid = 0;
            leftEarned = 0;
        } else if (rightBorrowWeight == 0) {
            leftPaid = yPaid;
            leftEarned = yEarned;
        } else {
            uint256 leftRatioX256 = FullMath.mulDivX256(leftBorrowWeight, leftBorrowWeight + rightBorrowWeight, false);
            leftPaid = FullMath.mulX256(yPaid, leftRatioX256, false);
            leftEarned = FullMath.mulX256(yEarned, leftRatioX256, false);
        }
        leftNode.fees.unpaidTakerYFees += uint128(leftPaid);
        rightNode.fees.unpaidTakerYFees += uint128(yPaid - leftPaid);
        leftNode.fees.unclaimedMakerYFees += uint128(leftEarned);
        rightNode.fees.unclaimedMakerYFees += uint128(yEarned - leftEarned);
    }

    /// Increase fees by an amount but limit the output the uint128, giving the extra to the pool owner through
    /// the data balances.
    function add128Fees(uint128 a, uint256 b, Data memory data, bool isX) internal pure returns (uint128 res) {
        if (b > type(uint128).max || a + b > type(uint128).max) {
            // If the result overflows, cap it at uint128 max and add the excess to the user's received balances.
            res = type(uint128).max;
            // Any pool that has fees actually greater than int256.max must be so contrived we don't care if it
            // fails in a way that doesn't affect other pools. So we do an unsafe cast here.
            unchecked {
                uint256 excess = a + b - type(uint128).max;
                if (isX) {
                    // This will probably never be hit.
                    // If it is, the pool owner should try to do something reasonable.
                    data.escapedX += excess;
                } else {
                    data.escapedY += excess;
                }
            }
        } else {
            unchecked {
                res = uint128(a + b);
            }
        }
    }
}

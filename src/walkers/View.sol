// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { SmoothRateCurveConfig, SmoothRateCurveLib } from "Commons/Math/SmoothRateCurveLib.sol";
import { UnsafeMath } from "Commons/Math/UnsafeMath.sol";
import { Key } from "../tree/Key.sol";
import { Phase } from "../tree/Route.sol";
import { Data } from "./Data.sol";
import { Node } from "./Node.sol";
import { LiqType, LiqData, LiqDataLib, LiqWalker } from "./Liq.sol";
import { FullMath } from "../FullMath.sol";
import { FeeData, FeeDataLib, FeeWalker } from "./Fee.sol";
import { Asset, AssetNode } from "../Asset.sol";
import { PoolInfo, Pool, PoolLib, PoolViewLib } from "../Pool.sol";
import { Store } from "../Store.sol";
import { TickMath } from "v4-core/libraries/TickMath.sol";
import { SqrtPriceMath } from "v4-core/libraries/SqrtPriceMath.sol";

/// We just need to track earnings and balances
struct ViewData {
    address poolAddr;
    bytes32 poolStore;
    bytes32 assetStore;
    uint160 sqrtPriceX96;
    int24 currentTick;
    bool takeAsX; // cache it outside the asset for gas savings.
    uint128 timestamp; // The last time the pool was modified.
    FeeData fees;
    LiqData liq;
    /* Outputs */
    uint256 liqBalanceX;
    uint256 liqBalanceY;
    uint256 earningsX;
    uint256 earningsY;
    // Down helpers
    uint256 leftChildUnclaimedX;
    uint256 leftChildUnclaimedY;
    uint256 rightChildUnclaimedX;
    uint256 rightChildUnclaimedY;
    uint256 leftChildUnpaidX;
    uint256 leftChildUnpaidY;
    uint256 rightChildUnpaidX;
    uint256 rightChildUnpaidY;
    uint256 lcaRightUnclaimedX;
    uint256 lcaRightUnclaimedY;
    uint256 lcaRightUnpaidX;
    uint256 lcaRightUnpaidY;
}

using ViewDataImpl for ViewData global;

library ViewDataImpl {
    function make(PoolInfo memory pInfo, Asset storage asset) internal view returns (ViewData memory) {
        Pool storage pool = Store.pool(pInfo.poolAddr);
        bytes32 poolSlot;
        assembly {
            poolSlot := pool.slot
        }
        bytes32 assetSlot;
        assembly {
            assetSlot := asset.slot
        }
        uint160 currentSqrtPriceX96 = pInfo.sqrtPriceX96;

        return
            ViewData({
                poolAddr: pInfo.poolAddr,
                poolStore: poolSlot,
                assetStore: assetSlot,
                sqrtPriceX96: currentSqrtPriceX96,
                currentTick: pInfo.currentTick,
                takeAsX: asset.takeAsX,
                timestamp: pool.timestamp,
                liq: LiqDataLib.make(asset, pInfo, 0),
                fees: FeeDataLib.make(pInfo),
                // Outputs
                liqBalanceX: 0,
                liqBalanceY: 0,
                earningsX: 0,
                earningsY: 0,
                // Helpers
                leftChildUnclaimedX: 0,
                leftChildUnclaimedY: 0,
                rightChildUnclaimedX: 0,
                rightChildUnclaimedY: 0,
                leftChildUnpaidX: 0,
                leftChildUnpaidY: 0,
                rightChildUnpaidX: 0,
                rightChildUnpaidY: 0,
                lcaRightUnclaimedX: 0,
                lcaRightUnclaimedY: 0,
                lcaRightUnpaidX: 0,
                lcaRightUnpaidY: 0
            });
    }

    function computeBalances(
        ViewData memory self,
        Key key,
        uint128 liq,
        bool roundUp
    ) internal pure returns (uint256 xBalance, uint256 yBalance) {
        if (liq == 0) {
            return (0, 0);
        }
        (int24 lowTick, int24 highTick) = key.ticks(self.fees.rootWidth, self.fees.tickSpacing);
        (xBalance, yBalance) = PoolLib.getAmounts(self.sqrtPriceX96, lowTick, highTick, liq, roundUp);
    }

    /* Helpers */

    function node(ViewData memory self, Key key) internal view returns (Node storage) {
        Pool storage pool;
        bytes32 poolSlot = self.poolStore;
        assembly {
            pool.slot := poolSlot
        }
        return pool.nodes[key];
    }

    function assetNode(ViewData memory self, Key key) internal view returns (AssetNode storage) {
        Asset storage asset;
        bytes32 assetSlot = self.assetStore;
        assembly {
            asset.slot := assetSlot
        }
        return asset.nodes[key];
    }
}

library ViewWalker {
    using SmoothRateCurveLib for SmoothRateCurveConfig;

    // On the way down, we collect our portion of the earnings for any unclaimed/unpaids at visits.
    // But instead of waiting for the up to earn the true fee rates, we can also do tha ton the down.
    function down(Key key, bool visit, ViewData memory data) internal view {
        // On the way down, we accumulate the prefixes and claim fees.
        Node storage node = data.node(key);
        AssetNode storage aNode = data.assetNode(key);

        // Inherit the unclaimed/unpaid from the parent node since we can't assign.
        (int24 low, int24 high) = key.ticks(data.fees.rootWidth, data.fees.tickSpacing);
        uint256 unclaimedX;
        uint256 unclaimedY;
        uint256 unpaidX;
        uint256 unpaidY;
        if (key.isLeft()) {
            unclaimedX = data.leftChildUnclaimedX + node.fees.unclaimedMakerXFees;
            unclaimedY = data.leftChildUnclaimedY + node.fees.unclaimedMakerYFees;
            unpaidX = data.leftChildUnpaidX + node.fees.unpaidTakerXFees;
            unpaidY = data.leftChildUnpaidY + node.fees.unpaidTakerYFees;
        } else {
            unclaimedX = data.rightChildUnclaimedX + node.fees.unclaimedMakerXFees;
            unclaimedY = data.rightChildUnclaimedY + node.fees.unclaimedMakerYFees;
            unpaidX = data.rightChildUnpaidX + node.fees.unpaidTakerXFees;
            unpaidY = data.rightChildUnpaidY + node.fees.unpaidTakerYFees;
        }

        // If we're visiting, we just worry about our own earnings, as we'll have no children to propogate to.
        // Plus we don't want to overwrite the unclaims/unpaids inherited by our sibling.
        if (visit) {
            // First we claim the existing fee earnings.
            claimCurrentFees(node, aNode, data, low, high);

            uint128 liq = (data.liq.liqType == LiqType.MAKER)
                ? uint128(
                    FullMath.mulDiv(
                        node.liq.mLiq - node.liq.ncLiq + LiqWalker.VIRTUAL_LIQ,
                        aNode.sliq,
                        node.liq.shares + LiqWalker.VIRTUAL_SHARES
                    )
                )
                : aNode.sliq;

            // Now claim the unclaimed/unpaid fees.
            if (data.liq.liqType == LiqType.TAKER) {
                if (data.takeAsX) {
                    uint256 nodeUnpaidX128 = FullMath.mulDivRoundingUp(
                        unpaidX << 128,
                        node.liq.borrowedX,
                        node.liq.subtreeBorrowedX
                    );
                    data.earningsX += FullMath.mulX128(
                        UnsafeMath.divRoundingUp(nodeUnpaidX128, node.liq.xTLiq),
                        liq,
                        true
                    );
                } else {
                    uint256 nodeUnpaidX128 = FullMath.mulDivRoundingUp(
                        unpaidY << 128,
                        node.liq.borrowedY,
                        node.liq.subtreeBorrowedY
                    );
                    data.earningsY += FullMath.mulX128(
                        UnsafeMath.divRoundingUp(nodeUnpaidX128, node.liq.tLiq - node.liq.xTLiq),
                        liq,
                        true
                    );
                }
            } else {
                // Makers just get their liq's amount.
                data.earningsX += FullMath.mulDiv(unclaimedX, liq, node.liq.subtreeMLiq);
                data.earningsY += FullMath.mulDiv(unclaimedY, liq, node.liq.subtreeMLiq);
            }

            // Now charge the true fee rate which will always be the case with visits.
            // Note that the prefix has not been added because we visit sibling before the prop
            // sibling on the way down.
            chargeTrueFeeRate(key, node, liq, data);

            // Now claim the liquidity balances.
            bool roundUp = (data.liq.liqType == LiqType.TAKER);
            (uint256 x, uint256 y) = data.computeBalances(key, liq, roundUp);
            data.liqBalanceX += x;
            data.liqBalanceY += y;
        } else {
            // If we're not visiting, we just have to propogate down the unclaims/unpaids to the visit nodes.
            uint24 width = key.width();
            // Takers
            if (node.liq.subtreeTLiq != 0) {
                if (node.liq.borrowedX == node.liq.subtreeBorrowedX) {
                    // If we're fully borrowed, we take all the unpaid.
                    unpaidX = 0;
                } else {
                    unpaidX -= FullMath.mulDiv(unpaidX, node.liq.borrowedX, node.liq.subtreeBorrowedX);
                }
                if (node.liq.borrowedY == node.liq.subtreeBorrowedY) {
                    unpaidY = 0;
                } else {
                    unpaidY -= FullMath.mulDiv(unpaidY, node.liq.borrowedY, node.liq.subtreeBorrowedY);
                }
            }

            // Makers
            if (node.liq.subtreeMLiq != 0) {
                uint256 nodeLiq = node.liq.mLiq * width;
                unclaimedX -= FullMath.mulDivRoundingUp(unclaimedX, nodeLiq, node.liq.subtreeMLiq);
                unclaimedY -= FullMath.mulDivRoundingUp(unclaimedY, nodeLiq, node.liq.subtreeMLiq);
            }

            // Now split fees before updating prefixes.
            (Key leftChild, Key rightChild) = key.children();
            Node storage leftNode = data.node(leftChild);
            Node storage rightNode = data.node(rightChild);
            uint24 childWidth = leftChild.width();

            // We split the earnings by the left and right weights.
            (uint256 leftWeight, uint256 rightWeight) = FeeWalker.getLeftRightWeights(
                data.liq,
                data.fees,
                node.liq,
                leftNode.liq,
                rightNode.liq,
                childWidth
            );

            // X split
            (uint256 leftPaid, uint256 leftEarned) = FeeWalker.splitByWeight(
                leftWeight, rightWeight,
                leftNode.liq.subtreeBorrowedX, rightNode.liq.subtreeBorrowedX,
                unpaidX, unclaimedX
            );
            data.leftChildUnpaidX = leftPaid;
            data.rightChildUnpaidX = unpaidX - leftPaid;
            data.leftChildUnclaimedX = leftEarned;
            data.rightChildUnclaimedX = unclaimedX - leftEarned;

            // Y split
            (leftPaid, leftEarned) = FeeWalker.splitByWeight(
                leftWeight, rightWeight,
                leftNode.liq.subtreeBorrowedY, rightNode.liq.subtreeBorrowedY,
                unpaidY, unclaimedY
            );
            data.leftChildUnpaidY = leftPaid;
            data.rightChildUnpaidY = unpaidY - leftPaid;
            data.leftChildUnclaimedY = leftEarned;
            data.rightChildUnclaimedY = unclaimedY - leftEarned;

            // Now we can add to the prefix since we're not visiting.
            data.liq.mLiqPrefix += node.liq.mLiq;
            data.liq.tLiqPrefix += node.liq.tLiq;
        }
    }

    function phase(Phase walkPhase, ViewData memory data) internal pure {
        // Even
        if (walkPhase == Phase.ROOT_DOWN) {
            data.lcaRightUnclaimedX = data.rightChildUnclaimedX;
            data.lcaRightUnclaimedY = data.rightChildUnclaimedY;
            data.lcaRightUnpaidX = data.rightChildUnpaidX;
            data.lcaRightUnpaidY = data.rightChildUnpaidY;
            data.liq.rootMLiq = data.liq.mLiqPrefix;
            data.liq.rootTLiq = data.liq.tLiqPrefix;
        } else if (walkPhase == Phase.LEFT_DOWN) {
            // Note that this phase is called REGARDLESS if there was a left route to walk or not.
            data.rightChildUnclaimedX = data.lcaRightUnclaimedX;
            data.rightChildUnclaimedY = data.lcaRightUnclaimedY;
            data.rightChildUnpaidX = data.lcaRightUnpaidX;
            data.rightChildUnpaidY = data.lcaRightUnpaidY;
            data.liq.mLiqPrefix = data.liq.rootMLiq;
            data.liq.tLiqPrefix = data.liq.rootTLiq;
        }
    }

    /* Helpers */

    function claimCurrentFees(
        Node storage node,
        AssetNode storage aNode,
        ViewData memory data,
        int24 low,
        int24 high
    ) internal view {
        (uint256 newFeeGrowthInside0X128, uint256 newFeeGrowthInside1X128) = PoolViewLib.getInsideFees(
            data.poolAddr,
            data.currentTick,
            data.fees.feeGrowthGlobal0X128,
            data.fees.feeGrowthGlobal1X128,
            low,
            high
        );
        // What we haven't claimed yet.
        uint256 fee0DiffX128;
        uint256 fee1DiffX128;
        unchecked {
            fee0DiffX128 = newFeeGrowthInside0X128 - node.liq.feeGrowthInside0X128;
            fee1DiffX128 = newFeeGrowthInside1X128 - node.liq.feeGrowthInside1X128;
        }
        if (data.liq.liqType == LiqType.MAKER) {
            // We just claim our shares.
            // If the sliq and shares are zero, you should fail anyways.
            uint128 nodeShares = node.liq.shares + LiqWalker.VIRTUAL_SHARES;
            uint256 shareRatioX256 = FullMath.mulDivX256(aNode.sliq, nodeShares, false);
            {
                data.earningsX += FullMath.mulX256(node.fees.xCFees, shareRatioX256, false);
                data.earningsY += FullMath.mulX256(node.fees.yCFees, shareRatioX256, false);
            }
            {
                uint256 liq = FullMath.mulX256(node.liq.mLiq - node.liq.ncLiq, shareRatioX256, false);
                data.earningsX += FullMath.mulX128(liq, fee0DiffX128, false);
                data.earningsY += FullMath.mulX128(liq, fee1DiffX128, false);
            }
        } else if (data.liq.liqType == LiqType.MAKER_NC) {
            data.earningsX += FullMath.mulX128(
                aNode.sliq,
                fee0DiffX128 + node.fees.makerXFeesPerLiqX128 - aNode.fee0CheckX128,
                false
            );
            data.earningsY += FullMath.mulX128(
                aNode.sliq,
                fee1DiffX128 + node.fees.makerYFeesPerLiqX128 - aNode.fee1CheckX128,
                false
            );
        } else {
            newFeeGrowthInside0X128 += node.fees.takerXFeesPerLiqX128;
            newFeeGrowthInside1X128 += node.fees.takerYFeesPerLiqX128;
            if (data.takeAsX) {
                newFeeGrowthInside0X128 += node.fees.xTakerFeesPerLiqX128;
            } else {
                newFeeGrowthInside1X128 += node.fees.yTakerFeesPerLiqX128;
            }
            data.earningsX += FullMath.mulX128(aNode.sliq, newFeeGrowthInside0X128 - aNode.fee0CheckX128, true);
            data.earningsY += FullMath.mulX128(aNode.sliq, newFeeGrowthInside1X128 - aNode.fee1CheckX128, true);
        }
    }

    /// @notice Called on visited nodes to charge them their exact fees.
    /// Because this is for viewing, we don't need to worry about the subtree unclaim/unpaids and just
    /// charge the rates and add it to our data earnings.
    /// @param liq The liquidity of the position, can be taker, maker, or nc maker.
    /// @dev This assumes the prefix does not include the current node's liquidity.
    function chargeTrueFeeRate(Key key, Node storage node, uint128 liq, ViewData memory data) internal view {
        uint24 width = key.width();
        // We use the liq ratio to calculate the true fee rate the entire column should pay.
        uint256 totalMLiq = width * data.liq.mLiqPrefix + node.liq.subtreeMLiq;
        uint256 totalTLiq = width * data.liq.tLiqPrefix + node.liq.subtreeTLiq;
        if (totalMLiq == 0 || totalTLiq == 0) {
            return;
        }
        uint256 timeDiff = uint128(block.timestamp) - data.timestamp; // Convert to 256 for next mult
        uint256 takerRateX64 = timeDiff * data.fees.rateConfig.calculateRateX64(uint128((totalTLiq << 64) / totalMLiq));
        // Then we use the total column x and y borrows to calculate the total fees paid.
        uint128 aboveTLiq = data.liq.tLiqPrefix + node.liq.tLiq;
        (uint256 aboveXBorrows, uint256 aboveYBorrows) = data.computeBalances(key, aboveTLiq, true);
        uint256 colXPaid = FullMath.mulX64(aboveXBorrows, takerRateX64, true);
        uint256 colYPaid = FullMath.mulX64(aboveYBorrows, takerRateX64, true);
        if (data.liq.liqType == LiqType.TAKER) {
            if (aboveTLiq > 0) {
                data.earningsX += FullMath.mulDivRoundingUp(colXPaid, liq, aboveTLiq);
                data.earningsY += FullMath.mulDivRoundingUp(colYPaid, liq, aboveTLiq);
            }
            // If we're a taker we can stop here.
            return;
        }
        // If we're paying makers, we need the full column payment.
        uint256 childrenXPaid = FullMath.mulX64(node.liq.subtreeBorrowedX - node.liq.borrowedX, takerRateX64, true);
        uint256 childrenYPaid = FullMath.mulX64(node.liq.subtreeBorrowedY - node.liq.borrowedY, takerRateX64, true);
        colXPaid += childrenXPaid;
        colYPaid += childrenYPaid;

        data.earningsX += FullMath.mulDiv(colXPaid, liq, totalMLiq);
        data.earningsY += FullMath.mulDiv(colYPaid, liq, totalMLiq);
    }
}

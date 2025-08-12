// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Key } from "../tree/Key.sol";
import { Node } from "./Node.sol";
import { Data } from "./Data.sol";
import { Phase } from "../tree/Route.sol";
import { FullMath } from "../FullMath.sol";
import { Asset, AssetNode } from "../Asset.sol";
import { PoolInfo, PoolLib } from "../Pool.sol";
import { FeeLib } from "../Fee.sol";
import { FeeWalker } from "./Fee.sol";

enum LiqType {
    MAKER,
    MAKER_NC,
    TAKER
}

/// Data we need to persist for liquidity accounting.
struct LiqNode {
    uint128 mLiq;
    uint128 tLiq;
    uint128 ncLiq;
    uint128 shares; // Total shares of compounding maker liq.
    uint256 subtreeMLiq;
    uint256 subtreeTLiq;
    uint256 subtreeBorrowedX; // Taker required for fee calculation.
    uint256 subtreeBorrowedY;
    // Swap fee earnings checkpointing
    uint256 feeGrowthInside0X128;
    uint256 feeGrowthInside1X128;
    // Liq Redistribution
    uint128 borrowed;
    uint128 lent;
    // Dirty bit for liquidity modifications.
    bool dirty;
}

using LiqNodeImpl for LiqNode global;

library LiqNodeImpl {
    function compound(LiqNode storage self, uint128 compoundedLiq, uint24 width) internal {
        if (compoundedLiq == 0) {
            return;
        }
        self.mLiq += compoundedLiq;
        self.subtreeMLiq += width * compoundedLiq;
        self.dirty = true;
    }

    /// The net liquidity owned by the node's position.
    function net(LiqNode storage self) internal view returns (int256) {
        return int256(uint256(self.borrowed) + uint256(self.mLiq)) - int256(uint256(self.tLiq) + uint256(self.lent));
    }

    /// @notice Splits balance between compounding and non-compounding maker liquidity.
    /// @return c The nominal amount of fees collected for compounding makers.
    /// @return nonCX128 The rate earned per non-compounding liq.
    function splitMakerFees(LiqNode storage self, uint256 nominal) internal view returns (uint128 c, uint256 nonCX128) {
        // Every mliq earns the same rate here. We round down for everyone to avoid overcollection of dust.
        nonCX128 = (uint256(nominal) << 128) / self.mLiq;
        c = uint128(nominal - FullMath.mulX128(nonCX128, self.ncLiq, true)); // Round up to subtract down.
    }
}

struct LiqData {
    LiqType liqType;
    uint128 liq; // The target liquidity to set the asset node's liq to.
    uint128 compoundThreshold; // The min liquidity worth compounding.
    // Prefix info
    uint128 mLiqPrefix; // Current prefix of maker liquidity.
    uint128 tLiqPrefix; // Current prefix of taker liquidity.
    uint128 rootMLiq; // The root to LCA maker liquidity.
    uint128 rootTLiq; // The root to LCA taker liquidity.
}

library LiqDataLib {
    function make(
        Asset storage asset,
        PoolInfo memory pInfo,
        uint128 targetLiq
    ) internal view returns (LiqData memory) {
        return
            LiqData({
                liqType: asset.liqType,
                liq: targetLiq,
                compoundThreshold: FeeLib.getCompoundThreshold(pInfo.poolAddr),
                mLiqPrefix: 0,
                tLiqPrefix: 0,
                rootMLiq: 0,
                rootTLiq: 0
            });
    }
}

library LiqWalker {
    error InsufficientBorrowLiquidity(int256 netLiq);

    /// Data useful when visiting/propogating to a node.
    struct LiqIter {
        Key key;
        bool visit;
        uint24 width;
        int24 lowTick;
        int24 highTick;
    }

    function up(Key key, bool visit, Data memory data) internal {
        Node storage node = data.node(key);
        LiqIter memory iter;
        {
            (int24 lowTick, int24 highTick) = key.ticks(data.fees.rootWidth, data.fees.tickSpacing);
            iter = LiqIter({ key: key, visit: visit, width: key.width(), lowTick: lowTick, highTick: highTick });
        }

        // Compound first.
        compound(iter, node, data);

        // Do the modifications.
        if (visit) {
            modify(iter, node, data, data.liq.liq);
        } else {
            // If propogating, we can't be at a leaf.
            (Key lk, Key rk) = key.children();
            Node storage lNode = data.node(lk);
            Node storage rNode = data.node(rk);
            node.liq.subtreeMLiq = lNode.liq.subtreeMLiq + rNode.liq.subtreeMLiq + node.liq.mLiq * iter.width;
            node.liq.subtreeTLiq = lNode.liq.subtreeTLiq + rNode.liq.subtreeTLiq + node.liq.tLiq * iter.width;
        }

        // Make sure our liquidity is solvent at each node.
        solveLiq(iter, node, data);
    }

    function phase(Phase walkPhase, Data memory data) internal pure {
        if (walkPhase == Phase.ROOT_DOWN) {
            data.liq.rootMLiq = data.liq.mLiqPrefix;
            data.liq.rootTLiq = data.liq.tLiqPrefix;
        } else if (walkPhase == Phase.LEFT_DOWN) {
            data.liq.mLiqPrefix = data.liq.rootMLiq;
            data.liq.tLiqPrefix = data.liq.rootTLiq;
        } // else if (walkPhase == Phase.RIGHT_DOWN) {}
        // No action needed for right down phase.
    }

    /* Helpers */

    /// Compounding's first step is to actually collect the base pool fees (for both makers and takers).
    /// So this is a crucial step to always call when walking over any node.
    /// @dev We update the taker fees here
    function compound(LiqIter memory iter, Node storage node, Data memory data) internal {
        // Get actual liquidity to compound.
        (uint256 x, uint256 y) = PoolLib.collect(data.poolAddr, iter.lowTick, iter.highTick);
        // Now we calculate what swap fees are owed by the taker borrows.
        (uint256 newFeeGrowthInside0X128, uint256 newFeeGrowthInside1X128) = PoolLib.getInsideFees(
            data.poolAddr,
            iter.lowTick,
            iter.highTick
        );
        uint256 feeDiffInside0X128 = newFeeGrowthInside0X128 - node.liq.feeGrowthInside0X128;
        uint256 feeDiffInside1X128 = newFeeGrowthInside1X128 - node.liq.feeGrowthInside1X128;
        node.liq.feeGrowthInside0X128 = newFeeGrowthInside0X128;
        node.liq.feeGrowthInside1X128 = newFeeGrowthInside1X128;

        x += FullMath.mulX128(node.liq.tLiq, feeDiffInside0X128, true);
        y += FullMath.mulX128(node.liq.tLiq, feeDiffInside1X128, true);

        uint256 nonCX128;
        (x, nonCX128) = node.liq.splitMakerFees(x);
        node.fees.makerXFeesPerLiqX128 += nonCX128;
        node.fees.xCFees = FeeWalker.add128Fees(node.fees.xCFees, x, data, true);
        node.fees.takerXFeesPerLiqX128 += feeDiffInside0X128;
        (y, nonCX128) = node.liq.splitMakerFees(y);
        node.fees.makerYFeesPerLiqX128 += nonCX128;
        node.fees.yCFees = FeeWalker.add128Fees(node.fees.yCFees, y, data, false);
        node.fees.takerYFeesPerLiqX128 += feeDiffInside1X128;

        (uint128 assignableLiq, uint128 leftoverX, uint128 leftoverY) = PoolLib.getAssignableLiq(
            iter.lowTick,
            iter.highTick,
            node.fees.xCFees,
            node.fees.yCFees,
            data.sqrtPriceX96
        );
        if (assignableLiq < data.liq.compoundThreshold) {
            // Not worth compounding right now.
            return;
        }
        node.liq.compound(assignableLiq, iter.width);
        node.fees.xCFees = leftoverX;
        node.fees.yCFees = leftoverY;
    }

    function modify(LiqIter memory iter, Node storage node, Data memory data, uint128 targetLiq) internal {
        AssetNode storage aNode = data.assetNode(iter.key);
        // First we collect fees if there are any.
        // Fee collection happens automatically for compounding liq when modifying liq.
        collectFees(aNode, node, data);

        // Then we do the liquidity modification.
        uint128 sliq = aNode.sliq; // Our current liquidity balance.
        if (data.liq.liqType == LiqType.MAKER) {
            uint128 equivLiq = PoolLib.getEquivalentLiq(
                iter.lowTick,
                iter.highTick,
                node.fees.xCFees,
                node.fees.yCFees,
                data.sqrtPriceX96,
                true
            );
            // If this compounding liq balance overflows, the pool cannot be on reasonable tokens,
            // hence we allow the overflow error to revert. This won't affect other pools.
            uint128 compoundingLiq = node.liq.mLiq - node.liq.ncLiq + equivLiq;
            uint128 currentLiq = uint128(FullMath.mulDiv(compoundingLiq, sliq, node.liq.shares));
            uint128 targetSliq = uint128(FullMath.mulDiv(node.liq.shares, targetLiq, compoundingLiq));
            if (currentLiq < targetLiq) {
                uint128 liqDiff = targetLiq - currentLiq;
                node.liq.mLiq += liqDiff;
                node.liq.shares += targetSliq - sliq;
                node.liq.subtreeMLiq += iter.width * liqDiff;
                (uint256 xNeeded, uint256 yNeeded) = data.computeBorrows(iter.key, liqDiff, true);
                data.xBalance += int256(xNeeded);
                data.yBalance += int256(yNeeded);
            } else if (currentLiq > targetLiq) {
                uint128 sliqDiff = sliq - targetSliq;
                uint256 shareRatioX256 = FullMath.mulDivX256(sliqDiff, node.liq.shares, false);
                uint128 liq = uint128(FullMath.mulX256(compoundingLiq, shareRatioX256, false));
                node.liq.mLiq -= liq;
                node.liq.shares -= sliqDiff;
                node.liq.subtreeMLiq -= iter.width * liq;
                uint256 xClaim = FullMath.mulX256(node.fees.xCFees, shareRatioX256, false);
                node.fees.xCFees -= uint128(xClaim);
                data.xBalance -= int256(xClaim);
                uint256 yClaim = FullMath.mulX256(node.fees.yCFees, shareRatioX256, false);
                node.fees.yCFees -= uint128(yClaim);
                data.yBalance -= int256(yClaim);
                // Now we claim the balances from the liquidity itself.
                (uint256 xOwed, uint256 yOwed) = data.computeBorrows(iter.key, liq, false);
                data.xBalance -= int256(xOwed);
                data.yBalance -= int256(yOwed);
            }
        } else if (data.liq.liqType == LiqType.MAKER_NC) {
            if (sliq < targetLiq) {
                uint128 liqDiff = targetLiq - sliq;
                sliq = targetLiq;
                node.liq.mLiq += liqDiff;
                node.liq.ncLiq += liqDiff;
                node.liq.subtreeMLiq += iter.width * liqDiff;
                (uint256 xNeeded, uint256 yNeeded) = data.computeBorrows(iter.key, liqDiff, true);
                data.xBalance += int256(xNeeded);
                data.yBalance += int256(yNeeded);
            } else if (sliq > targetLiq) {
                uint128 liqDiff = sliq - targetLiq;
                node.liq.mLiq -= liqDiff;
                node.liq.ncLiq -= liqDiff;
                node.liq.subtreeMLiq -= iter.width * liqDiff;
                // Now we claim the balances from the liquidity itself.
                (uint256 xOwed, uint256 yOwed) = data.computeBorrows(iter.key, liqDiff, false);
                data.xBalance -= int256(xOwed);
                data.yBalance -= int256(yOwed);
            }
        } else if (data.liq.liqType == LiqType.TAKER) {
            if (sliq < targetLiq) {
                uint128 liqDiff = targetLiq - sliq;
                node.liq.tLiq += liqDiff;
                node.liq.subtreeTLiq += iter.width * liqDiff;
                // You'd think we want to overestimate borrows here but that can be compensated by
                // the borrow fee function. Instead we care more about the swap that takers will perform
                // with the borrowed assets, we need to ensure the swap inputs round down.
                (uint256 xBorrow, uint256 yBorrow) = data.computeBorrows(iter.key, liqDiff, false);
                node.liq.subtreeBorrowedX += xBorrow;
                node.liq.subtreeBorrowedY += yBorrow;
                data.xBalance -= int256(xBorrow);
                data.yBalance -= int256(yBorrow);
            } else if (sliq > targetLiq) {
                uint128 liqDiff = sliq - targetLiq;
                node.liq.tLiq -= liqDiff;
                node.liq.subtreeTLiq -= iter.width * liqDiff;
                // We need to match the rounding when adding tLiq, although we'd like to round up here.
                (uint256 xBorrow, uint256 yBorrow) = data.computeBorrows(iter.key, liqDiff, false);
                node.liq.subtreeBorrowedX -= xBorrow;
                node.liq.subtreeBorrowedY -= yBorrow;
                // And returns the assets.
                data.xBalance += int256(xBorrow);
                data.yBalance += int256(yBorrow);
            }
        }
        node.liq.dirty = true; // Mark the node as dirty after modification.
        aNode.sliq = sliq;
    }

    /// Ensure the liquidity at this node is solvent.
    /// @dev Call this after modifying liquidity.
    function solveLiq(LiqIter memory iter, Node storage node, Data memory data) internal {
        int256 netLiq = node.liq.net();

        if (data.isRoot(iter.key)) {
            require(netLiq > 0, InsufficientBorrowLiquidity(netLiq));
            return;
        }

        if (netLiq == 0) {
            return;
        } else if (netLiq > 0 && node.liq.borrowed > 0) {
            // Check if we can repay liquidity.
            uint128 repayable = min(uint128(uint256(netLiq)), node.liq.borrowed);
            Node storage sibling = data.node(iter.key.sibling());
            int256 sibLiq = sibling.liq.net();
            if (sibLiq <= 0 || sibling.liq.borrowed == 0) {
                // We cannot repay any borrowed liquidity.
                return;
            }
            repayable = min(repayable, uint128(uint256(sibLiq)));
            repayable = min(repayable, sibling.liq.borrowed);
            if (repayable <= data.liq.compoundThreshold) {
                // Below the compound threshold it's too small to worth repaying.
                return;
            }
            Node storage parent = data.node(iter.key.parent());
            parent.liq.lent -= repayable;
            parent.liq.dirty = true;
            node.liq.borrowed -= repayable;
            node.liq.dirty = true;
            sibling.liq.borrowed -= repayable;
            sibling.liq.dirty = true;
        } else if (netLiq < 0) {
            // We need to borrow liquidity from our parent node.
            Node storage sibling = data.node(iter.key.sibling());
            Node storage parent = data.node(iter.key.parent());
            uint128 borrow = uint128(uint256(-netLiq));
            if (borrow < data.liq.compoundThreshold) {
                // We borrow at least this amount.
                borrow = data.liq.compoundThreshold;
            }
            parent.liq.lent += borrow;
            parent.liq.dirty = true;
            node.liq.borrowed += borrow;
            node.liq.dirty = true;
            sibling.liq.borrowed += borrow;
            sibling.liq.dirty = true;
        }
    }

    /* Helpers' Helpers */

    /// Collect non-liquidating maker fees or pay taker fees.
    function collectFees(AssetNode storage aNode, Node storage node, Data memory data) internal {
        uint128 liq = aNode.sliq;
        if (data.liq.liqType == LiqType.MAKER_NC) {
            data.xBalance -= int256(FullMath.mulX128(liq, node.fees.makerXFeesPerLiqX128 - aNode.fee0CheckX128, false));
            data.yBalance -= int256(FullMath.mulX128(liq, node.fees.makerYFeesPerLiqX128 - aNode.fee1CheckX128, false));
            aNode.fee0CheckX128 = node.fees.makerXFeesPerLiqX128;
            aNode.fee1CheckX128 = node.fees.makerYFeesPerLiqX128;
        } else if (data.liq.liqType == LiqType.TAKER) {
            // Now we pay the taker fees.
            data.xBalance += int256(FullMath.mulX128(liq, node.fees.takerXFeesPerLiqX128 - aNode.fee0CheckX128, true));
            data.yBalance += int256(FullMath.mulX128(liq, node.fees.takerYFeesPerLiqX128 - aNode.fee1CheckX128, true));
            aNode.fee0CheckX128 = node.fees.takerXFeesPerLiqX128;
            aNode.fee1CheckX128 = node.fees.takerYFeesPerLiqX128;
        }
    }

    function min(uint128 a, uint128 b) internal pure returns (uint128) {
        return a < b ? a : b;
    }
}

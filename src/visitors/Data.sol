// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Key } from "../tree/Key.sol";
import { Node } from "./Node.sol";
import { Pool, PoolLib } from "../Pool.sol";
import { MAX_WIDTH_LENGTH } from "../tree/Route.sol";
import { ConfigLib } from "../Config.sol";
import { SmoothRateCurveConfig, SmoothRateCurveLib } from "Commons/Math/SmoothRateCurveLib.sol";
import { UnsafeMath } from "Commons/Math/UnsafeMath.sol";

/// The maximum number of nodes in either side of the route.
uint8 constant ROUTE_LENGTH = MAX_WIDTH_LENGTH;

enum LiqType {
    MAKER,
    MAKER_NC,
    TAKER
}

/// If any node's net liquidity changed, we must record it with one of these.
/// After a walk, we visit these keys and update their position's liquidity to to the new net value.
struct NodeDelta {
    Key key;
    uint128 sliq; // If there is any user liq change then net liq must also change.
}

/// In memory data structure used when traversing a pool's tree.
/// @dev sliq is short for shares/liquidity. It's meaning is different depending on the type of
/// maker liquidity being added.
/// When using compounding liquidity, sliq is the number of shares in the node owned by the liquidity added/removed.
/// When using non-compounding liquidity, sliq is the amount of liquidity added/removed.
/// When using taker liquidity, sliq is the amount of liquidity added/removed.
struct Data {
    // Inputs
    address poolAddr;
    LiqType liqType;
    int128 sliqDelta;
    // Derived values
    uint128 deMin;
    bytes32 poolStore;
    uint160 sqrtPriceX96;
    uint24 rootWidth;
    int24 tickSpacing;
    SmoothRateCurveConfig rateConfig;
    // Outputs
    uint8 numNodes; // Number of nodes with entries below.
    NodeDelta[ROUTE_LENGTH] changes; // The nodes that have been modified.
    uint256 xBalance;
    uint256 yBalance;
    /* Below are written to by walkers */
    // Fee tracking - Written to by data's splitFees function, and phase changes.
    uint128 mLiqPrefix;
    uint128 tLiqPrefix;
    uint128 rootMLiq;
    uint128 rootTLiq;
    // Liq Availability Verification during phase changes.
    uint128 legNet;
    uint128 net;
}

using DataImpl for Data global;

library DataImpl {
    using SmoothRateCurveLib for SmoothRateCurveConfig;

    /* Factory */
    function make(
        PoolInfo pInfo,
        int128 sliqDelta,
        LiqType liqType
    ) internal pure returns (Data memory) {
        Pool storage pool = Store.pool(pInfo.poolAddr);
        bytes32 poolStore;
        assembly {
            poolStore := pool.slot
        }

        return
            Data({
                poolAddr: poolAddr,
                liqType: liqType,
                sliqDelta: sliqDelta,
                deMin: ConfigLib.getLiqDeMin(pInfo.poolAddr),
                poolStore: poolStore,
                sqrtPriceX96: PoolLib.getSqrtPriceX96(pInfo.poolAddr),
                rootWidth: pInfo.treeWidth,
                tickSpacing: pInfo.tickSpacing,
                rateConfig: ConfigLib.getRateCurve(pInfo.poolAddr),
            });
    }

    /* Walk down methods */

    /// Charge the fees owed by takers to the makers at this node.
    /// @dev Called on the way down to catch the fee node entries up to date.
    function assignFees(Data memory self, Key key. int24 lowTick, int24 highTick) internal {
        // Get swap fees
        (uint128 x, uint128 y) = PoolLib.getFees(
            self.poolAddr,
            lowTick,
            highTick
        );
        Node storage node = self.node(key);
        // Calculate taker fees
        uint128 secDifference = uint128(block.timestamp) - node.lastTimestamp;
        if (secDifference != 0) {
            uint160 lowSqrtPriceX96 = TickMath.getSqrtRatioAtTick(lowTick);
            uint160 highSqrtPriceX96 = TickMath.getSqrtRatioAtTick(highTick);

            uint256 unitXX64 = SqrtPriceMath.getAmount0Delta(lowSqrtPriceX96, highSqrtPriceX96, 1 << 64, true);
            uint256 unitYX64 = SqrtPriceMath.getAmount1Delta(lowSqrtPriceX96, highSqrtPriceX96, 1 << 64, true);

            uint256 halfRate = uint256(node.lastTakerRateX64) * secDifference / 2;
            {
            uint128 perTakerPaidX64 = uint128(halfRate * unitXX64);
            node.takerXFeePerLiqX64 += perTakerPaidX64;
            x += FullMath.mulX64(perTakerPaidX64, node.tLiq);
            }
            {
                uint128 perTakerPaidX64 = uint128(halfRate * unitYX64);
                node.takerYFeePerLiqX64 += perTakerPaidX64;
                y += FullMath.mulX64(perTakerPaidX64, node.tLiq);
            }
        }
        node.lastTimestamp = uint128(block.timestamp);
        // Splits and assigns the fees.
        node.assignFees(x, y);
    }

    /* Walk up operations (in order of operation) */

    /// Compound the liquidity in the root node.
    /// @dev Call this first before modifying any liquidity for visiting nodes.
    function compound(Data memory self, Key key, int24 lowTick, int24 highTick) internal {
        uint256 x = node.xCFees;
        uint256 y = node.yCFees;
        (uint128 assignableLiq, uint128 leftoverX, uint128 leftoverY) = PoolLib.getAssignableLiq(
            self.poolAddr,
            lowTick,
            highTick,
            x,
            y,
            self.sqrtPriceX96
        );
        if (assignableLiq < self.deMin) {
            // Not worth compounding right now.
            return;
        }
        node.compoundLiq(assignableLiq, key.width());
        node.xCFees = leftoverX;
        node.yCFees = leftoverY;
    }

    /**
     * @notice Modify the liquidity according to our data inputs
     * @dev See sliq description in Data.
     */
    function modifyLiq(Data memory self, Key key) internal {
        Node storage node = self.node(key);
        uint24 width = key.width();
        if (self.isMaker()) {
            if (self.isNC()) {
                node.modifyNCMLiq(self.sliqDelta, width);
            } else {
                uint128 sliq = node.modifyCMLiq(self.sliqDelta, width);
                self.changes[self.numNodes++] = NodeDelta({ key: key, sliq: sliq });
            }
        } else {
            node.modifyTLiq(self.sliqDelta, width);
        }
    }

    /// Propogate subtree liquidity values from the children to the this node.
    /// @dev Call this after modifying liquidity if visiting.
    function propLiq(Data memory self, Key key) internal {
        Node storage node = self.node(key);
        if (key.isLeaf()) {
            node.subtreeMLiq = node.mLiq; // Width is 1.
            node.subtreeTLiq = node.tLiq;
            return;
        }

        (Key l, Key r) = key.children();
        Node storage lNode = self.node(l);
        Node storage rNode = self.node(r);
        node.subtreeMLiq = lNode.subtreeMLiq + rNode.subtreeMLiq + node.mLiq * key.width();
        node.subtreeTLiq = lNode.subtreeTLiq + rNode.subtreeTLiq + node.tLiq * key.width();
    }

    /// Ensure the liquidity at this node is solvent.
    /// @dev Call this after modifying liquidity.
    function solveLiq(Data memory self, Key key) internal {
        Node storage node = self.node(key);
        int128 netLiq = node.netLiq();
        if (netLiq == 0) {
            return;
        } else if (netLiq > 0 && node.borrowed > 0) {
            // Check if we can repay liquidity.
            uint128 repayable = min(uint128(netLiq), node.borrowed);
            Node storage sibling = self.node(key.sibling());
            int128 sibLiq = sibling.netLiq();
            if (sibLiq <= 0 || sibling.borrowed == 0) {
                // We cannot repay any borrowed liquidity.
                return;
            }
            repayable = min(repayable, uint128(sibLiq));
            repayable = min(repayable, sibling.borrowed);
            if (repayable <= self.deMin) {
                // Below deMinimus is not worth repaying.
                return;
            }
            Node storage parent = self.node(key.parent());
            parent.lent -= repayable;
            parent.dirty = true;
            node.borrowed -= repayable;
            node.dirty = true;
            sibling.borrowed -= repayable;
            sibling.dirty = true;
        } else if (netLiq < 0) {
            // We need to borrow liquidity from our parent node.
            Node storage sibling = self.node(key.sibling());
            Node storage parent = self.node(key.parent());
            uint128 borrow = uint128(-netLiq);
            if (borrow < self.deMin) {
                borrow = self.deMin;
            }
            parent.lent += borrow;
            parent.dirty = true;
            node.borrowed += borrow;
            node.dirty = true;
            sibling.borrowed += borrow;
            sibling.dirty = true;
        }
    }

    /// Updates the taker fee rates now that liquidity has been modified.
    /// @dev Called on the way up after liquidity has been modified.
    function updateTakerRates(Data memory self, Key key) internal {
        Node storage node = self.node(key);
        (Key left, Key right) = key.children();
        Node storage leftNode = self.node(left);
        Node storage rightNode = self.node(right);
        uint24 halfWidth = left.width();
        // Prefix doesn't include this node yet.
        uint128 mLiq = (self.mLiqPrefix + node.mLiq) * halfWidth + leftNode.subtreeMLiq;
        uint128 tLiq = (self.tLiqPrefix + node.tLiq) * halfWidth + leftNode.subtreeTLiq;
        uint128 utilX64 = UnsafeMath.divRoundingUp(uint256(tLiq) << 64, mLiq);
        uint128 rateX64 = self.rateConfig.calculateRateX64(utilX64);
        node.lastTakerRateX64 = rateX64;
    }

    /* Helpers */

    function isRoot(Data memory self, Key key) internal pure returns (bool) {
        return key.width() == self.rootWidth;
    }

    function isMaker(Data memory self) internal pure returns (bool) {
        return self.liqType == LiqType.MAKER || self.liqType == LiqType.MAKER_NC;
    }

    function isNC(Data memory self) internal pure returns (bool) {
        return self.liqType == LiqType.MAKER_NC;
    }

    function node(Data memory self, Key key) private view returns (Node storage) {
        Pool storage pool;
        assembly {
            pool.slot := self.poolStore
        }
        return pool.nodes[key];
    }

    function min(uint128 a, uint128 b) private pure returns (uint128) {
        return a < b ? a : b;
    }
}

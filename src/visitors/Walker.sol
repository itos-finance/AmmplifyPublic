// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Data } from "./Data.sol";
import { Route } from "../tree/Route.sol";




library WalkerLib {

    /// Takes the range you want to talk over and the data object you want to walk with
    /// and performs the tree walk.
    function walk(PoolInfo memory pInfo, int24 lowTick, int24 highTick, Data memory data) internal {

    }

    function down(Key key, bool visit, Data memory data) internal {
        (int24 lowTick, int24 highTick) = key.ticks(data.rootWidth, data.tickSpacing);
        data.assignFees(key, lowTick, highTick);


    }

    function up(Key key, bool visit, Data memory data) internal {
        (int24 lowTick, int24 highTick) = key.ticks(data.rootWidth, data.tickSpacing);
        data.compound(key, lowTick, highTick);
        if (visit) {
            data.modifyLiq(key);
        }
        data.propLiq(key);
        data.solveLiq(key);
        data.propFees(key);
    }


}

library ViewWalker {

}


class FeeWalker(WalkerTypeClass):
    def down(self, key, visit, data):oh
        data.claimFees(key)
        if (not visit):
            data.accumulateLiqPrefix(key)
        super().down(key, visit, data)

    def phase(self, walkPhase, data):
        if walkPhase == WalkPhase.ROOT_DOWN:
            data.rootMLiq = data.mLiqPrefix
            data.rootTLiq = data.tLiqPrefix
        elif walkPhase == WalkPhase.LEFT_DOWN:
            data.mLiqPrefix = data.rootMLiq
            data.tLiqPrefix = data.rootTLiq
        elif walkPhase == WalkPhase.RIGHT_DOWN:
            pass

class ACWalker(FeeWalker):
    THRESH = 0.01

    def up(self, key, visit, data):
        node = data.nodes[key]
        # Here we'd collect fees and split
        low = indexToPrice(key.low())
        high = indexToPrice(key.high())
        xLiq = xBalanceToLiq(node.xCFees, low, high. self.price)
        yLiq = yBalanceToLiq(node.yCFees, low, high, self.price)
        if (xLiq < yLiq):
            if (xLiq < ACWalker.THRESH):
                return
            node.xCFees = 0
            node.yCFees -= liqToYBalance(xLiq, low, high, current)
            data.modifyMLiq(key, xLiq, False)
        else:
            if (yLiq < ACWalker.THRESH):
                return
            node.yCFees = 0
            node.xCFees -= liqToXBalance(yLiq, low, high, current)
            data.modifyMLiq(key, yLiq, False)
        super().up(key, visit, data)


class LiqWalker(ACWalker):
    THRESH = 1 # How much liquidity must remain for a valid borrow.

    def up(self, key, visit, data):
        # Compound first
        super().up(key, visit, data)
        node = data.nodes[key]
        if visit:
            # Add/remove the liq.
            if data.isMaker():
                data.modifyMLiq(key, self.delta, data.isNC())
            else:
                data.modifyTLiq(key, self.delta, False)
            # Track the min liq
            data.leg_net = min(data.leg_net, node.mLiq - node.tLiq)
        else:
            # for props, we're just adding more to the liq so far.
            data.leg_net += node.mLiq - node.tLiq

    def phase(self, walkPhase, data):
        if walkPhase == WalkPhase.LEFT_UP:
            data.net = data.leg_net
            data.leg_net = math.inf
        elif walkPhase == WalkPhase.RIGHT_UP:
            data.leg_net = min(data.net, data.leg_net)
        elif walkPhase == WalkPhase.ROOT_UP:
            # we're done, check we have sufficient mliq remaining in all relevant ticks.
            assert(data.leg_net > LiqWalker.THRESH)

    # We can optimize this by only checking the bounds when net liq is decreasing.



class SplitWalker(LiqWalker):
    NODE_TYPE = SplitNode

    def up(self, key, visit, data):
        # Compound and Take first.
        super().up(key, visit, data)

        node = data.nodes[key]
        netLiq = node.netLiq()

        if (self.isRoot(key)):
            # We can't borrow, we just assert our netliq
            assert(netLiq > LiqWalker.THRESH), "Split: insufficient liquidity at root"

        if (netLiq > 0 and node.borrowed > 0):
            sibling = data.nodes[key.sibling()]
            parent = data.nodes[key.parent()]
            # Check if we can return any borrowed liq
            sibNet = sibling.netLiq()
            if sibNet > 0:
                # They must have the same borrowed amount.
                reduction = min(sibNet, netLiq, node.borrowed)
                sibling.borrowed -= reduction
                node.borrowed -= reduction
                parent.lent -= reduction
        if (netLiq < 0):
            sibling = data.nodes[key.sibling()]
            parent = data.nodes[key.parent()]
            # we need to borrow more
            node.borrowed -= netLiq
            sibling.borrowed -= netLiq
            parent.lent -= netLiq


        NODE_TYPE = SplitNode

    def up(self, key, visit, data):
        # Compound and Take first.
        super().up(key, visit, data)

        node = data.nodes[key]
        netLiq = node.netLiq()

        if (self.isRoot(key)):
            # We can't borrow, we just assert our netliq
            assert(netLiq > LiqWalker.THRESH), "Split: insufficient liquidity at root"

        if (netLiq > 0 and node.borrowed > 0):
            sibling = data.nodes[key.sibling()]
            parent = data.nodes[key.parent()]
            # Check if we can return any borrowed liq
            sibNet = sibling.netLiq()
            if sibNet > 0:
                # They must have the same borrowed amount.
                reduction = min(sibNet, netLiq, node.borrowed)
                sibling.borrowed -= reduction
                node.borrowed -= reduction
                parent.lent -= reduction
        if (netLiq < 0):
            sibling = data.nodes[key.sibling()]
            parent = data.nodes[key.parent()]
            # we need to borrow more
            node.borrowed -= netLiq
            sibling.borrowed -= netLiq
            parent.lent -= netLiq
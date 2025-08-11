// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Key } from "../tree/Key.sol";
import { Data } from "./Data.sol";
import { LiqNode } from "./Liq.sol";
import { Node } from "./Node.sol";
import { Route, RouteImpl, Phase } from "../tree/Route.sol";
import { PoolLib, PoolInfo } from "../Pool.sol";

library PoolWalker {
    error InsolventLiquidityUpdate(Key key, int256 targetLiq);

    function settle(PoolInfo memory pInfo, uint24 lowTick, uint24 highTick, Data memory data) internal {
        Route memory route = RouteImpl.make(pInfo.treeWidth, lowTick, highTick);
        route.walk(down, up, phase, data);
    }

    function down(Key, bool, Data memory) private {
        // Do nothing
    }

    /// This walker modifies the node's position to its new liquidity value.
    function up(Key key, bool visit, Data memory data) private {
        // For every node we call on, we just check if its dirty and needs an update.

        Node storage node = data.node(key);
        if (node.liq.dirty) {
            updateLiq(key, node, data);
            node.liq.dirty = false;
        }
    }

    function phase(Phase, Data memory) private {
        // Do nothing.
    }

    function updateLiq(Key key, Node storage node, Data memory data) private {
        (int24 lowTick, int24 highTick) = key.ticks(data.rootWidth, data.tickSpacing);
        // Because we lookup the liq instead of what we think we have,
        // we avoid any potential slow divergences. But it means if someone donates
        // liquidity to this node, that amount in tokens won't be deposited and will be lost.
        uint128 liq = PoolLib.getLiq(data.poolAddr, lowTick, highTick);

        int256 _targetLiq = node.liq.net();
        require(_targetLiq >= 0, InsolventLiquidityUpdate(key, _targetLiq));
        uint128 targetLiq = uint128(_targetLiq);

        if (targetLiq > liq) {
            PoolLib.mint(data.poolAddr, lowTick, highTick, targetLiq - liq);
        } else if (targetLiq < liq) {
            PoolLib.burn(data.poolAddr, lowTick, highTick, liq - targetLiq);
        }
    }
}

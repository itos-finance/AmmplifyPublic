// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Key } from "../tree/Key.sol";
import { Route } from "../tree/Route.sol";
import { FeeWalker } from "./Fee.sol";
import { LiqWalker } from "./Liq.sol";
import { Data } from "./Data.sol";
import { PoolInfo } from "../pool/PoolInfo.sol";

library WalkerLib {
    function modify(PoolInfo memory pInfo, uint24 lowTick, uint24 highTick, Data memory data) internal {
        Route memory route = RouteImpl.make(pInfo.treeWidth, lowTick, highTick);
        route.walk(down, up, phase, data);
    }

    function down(Key key, bool visit, Data memory data) internal {
        FeeWalker.down(key, visit, data);
    }

    function up(Key key, bool visit, Data memory data) internal {
        FeeWalker.up(key, visit, data);
        LiqWalker.up(key, visit, data);
    }

    function phase(Phase walkPhase, Data memory data) internal {
        FeeWalker.phase(walkPhase, data);
        LiqWalker.phase(walkPhase, data);
    }
}

library ViewWalkerLib {
    function makerWalk(
        PoolInfo memory pInfo,
        uint24 lowTick,
        uint24 highTick,
        Data memory data
    ) internal view returns (NodeDelta[ROUTE_LENGTH] memory changes) {
        // Walking logic here
    }

    function takerWalk(
        PoolInfo memory pInfo,
        uint24 lowTick,
        uint24 highTick,
        Data memory data
    ) internal view returns (NodeDelta[ROUTE_LENGTH] memory changes) {
        // Walking logic here
    }
}

library PoolWalkerLib {
    /// Resolve all of the needed liquidity changes.
    function settle(PoolInfo memory pInfo, Data memory data, NodeDelta[ROUTE_LENGTH] memory changes) internal {
        // Settle logic here
    }
}

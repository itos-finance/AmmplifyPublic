// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Key } from "../tree/Key.sol";
import { Route, Phase, RouteImpl } from "../tree/Route.sol";
import { ViewRouteImpl } from "../tree/ViewRoute.sol";
import { FeeWalker } from "./Fee.sol";
import { LiqWalker } from "./Liq.sol";
import { ViewWalker, ViewData } from "./View.sol";
import { Data } from "./Data.sol";
import { PoolInfo } from "../Pool.sol";
import { AdminLib } from "Commons/Util/Admin.sol";
import { FeeStore } from "../Fee.sol";
import { Store } from "../Store.sol";

import { console } from "forge-std/console.sol";

library WalkerLib {
    function modify(PoolInfo memory pInfo, int24 lowTick, int24 highTick, Data memory data) internal {
        uint24 low = pInfo.treeTick(lowTick);
        uint24 high = pInfo.treeTick(highTick) - 1;
        Route memory route = RouteImpl.make(pInfo.treeWidth, low, high);
        route.walk(down, up, phase, toRaw(data));

        commitFeesCollected(pInfo, data);
    }

    function down(Key key, bool visit, bytes memory raw) internal {
        Data memory data = toData(raw);
        console.log("WalkerLib down called");
        FeeWalker.down(key, visit, data);
        console.log("WalkerLib down after FeeWalker");
    }

    function up(Key key, bool visit, bytes memory raw) internal {
        Data memory data = toData(raw);
        console.log("WalkerLib up called");
        FeeWalker.up(key, visit, data);
        console.log("WalkerLib up after FeeWalker");
        LiqWalker.up(key, visit, data);
        console.log("WalkerLib up after LiqWalker");
    }

    function phase(Phase walkPhase, bytes memory raw) internal pure {
        Data memory data = toData(raw);
        FeeWalker.phase(walkPhase, data);
        LiqWalker.phase(walkPhase, data);
    }

    /* Helpers */

    function toRaw(Data memory data) internal pure returns (bytes memory raw) {
        assembly {
            raw := data
        }
    }

    function toData(bytes memory raw) internal pure returns (Data memory data) {
        assembly {
            data := raw
        }
    }

    function commitFeesCollected(PoolInfo memory pInfo, Data memory data) internal {
        // Any excess fees collected go back to the fee store.
        FeeStore storage feeStore = Store.fees();
        feeStore.standingX[data.poolAddr] = data.liq.xFeesCollected;
        feeStore.standingY[data.poolAddr] = data.liq.yFeesCollected;

        // In the crazy unlikely case the fees collected go over uint128, we give the escaped
        // fees to the contract owner.
        if (data.escapedX > 0 || data.escapedY > 0) {
            address owner = AdminLib.getOwner();
            if (data.escapedX > 0) {
                Store.fees().collateral[owner][pInfo.token0] += data.escapedX;
            }
            if (data.escapedY > 0) {
                Store.fees().collateral[owner][pInfo.token1] += data.escapedY;
            }
        }
    }
}

/// A compounding lib that effectively functions like a regular liq walk but without any modifications.
library CompoundWalkerLib {
    function compound(PoolInfo memory pInfo, int24 lowTick, int24 highTick, Data memory data) internal {
        uint24 low = pInfo.treeTick(lowTick);
        uint24 high = pInfo.treeTick(highTick) - 1;
        Route memory route = RouteImpl.make(pInfo.treeWidth, low, high);
        route.walk(WalkerLib.down, up, WalkerLib.phase, WalkerLib.toRaw(data));

        WalkerLib.commitFeesCollected(pInfo, data);
    }

    function up(Key key, bool visit, bytes memory raw) internal {
        Data memory data = WalkerLib.toData(raw);
        FeeWalker.up(key, visit, data);
        // Liq walker doesn't use visit except to determine if we should modify.
        // We never modify hence we set it to false.
        LiqWalker.up(key, false, data);
    }
}

library ViewWalkerLib {
    function viewAsset(PoolInfo memory pInfo, int24 lowTick, int24 highTick, ViewData memory data) internal view {
        uint24 low = pInfo.treeTick(lowTick);
        uint24 high = pInfo.treeTick(highTick) - 1;
        Route memory route = RouteImpl.make(pInfo.treeWidth, low, high);
        ViewRouteImpl.walkDown(route, down, phase, toRaw(data));
    }

    function down(Key key, bool visit, bytes memory raw) internal view {
        ViewWalker.down(key, visit, toData(raw));
    }

    function phase(Phase walkPhase, bytes memory raw) internal pure {
        ViewWalker.phase(walkPhase, toData(raw));
    }

    /* Helpers */

    function toRaw(ViewData memory data) internal pure returns (bytes memory raw) {
        assembly {
            raw := data
        }
    }

    function toData(bytes memory raw) internal pure returns (ViewData memory data) {
        assembly {
            data := raw
        }
    }
}

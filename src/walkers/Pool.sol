// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { Key } from "../tree/Key.sol";
import { Data } from "./Data.sol";
import { LiqNode, LiqType, LiqWalkerLite } from "./Liq.sol";
import { Node } from "./Node.sol";
import { Route, RouteImpl, Phase } from "../tree/Route.sol";
import { PoolLib, PoolInfo } from "../Pool.sol";
import { WalkerLib } from "./Lib.sol";

/// Walk down and up the pool to settle balances with the underlying AMM.
/// @dev When walking down, we settle all the liquidity decreases so we have balances to work with,
/// and then on the walk up we add liquidity with the balances as necessary.
/// In V4, burn/mint operations are recorded during the walk and executed in a batched
/// unlock callback after the walk completes.
library PoolWalker {
    error InsolventLiquidityUpdate(Key key, int256 targetLiq);
    error StalePoolPrice(address poolAddr, uint160 expectedSqrtPriceX96, uint160 actualSqrtPriceX96);
    /// We add this to the dirty bit when we discover the liquidity needs to increase on the walk up.

    uint8 public constant ADD_LIQ_DIRTY_FLAG = 1 << 7;

    /// This does all the balances changes because all liquidity is only changed here.
    /// In V4, operations are batched and executed inside a PoolManager unlock callback
    /// which handles token settlement via sync/settle/take.
    function settle(PoolInfo memory pInfo, int24 lowTick, int24 highTick, Data memory data) internal {
        // Before we settle we make sure the pool price has not changed from the time we made all our initial
        // calculations.
        uint160 sqrtPriceX96 = PoolLib.getSqrtPriceX96(pInfo.poolAddr);
        require(data.sqrtPriceX96 == sqrtPriceX96, StalePoolPrice(pInfo.poolAddr, data.sqrtPriceX96, sqrtPriceX96));

        // NOTE: We do NOT clear ops here. The modify walk may have recorded poke ops (via compound → collect)
        // that are needed to collect fees from V4. Those ops must survive into executeOps.

        uint24 low = pInfo.treeTick(lowTick);
        uint24 high = pInfo.treeTick(highTick) - 1;
        Route memory route = RouteImpl.make(pInfo.treeWidth, low, high);
        route.walk(down, up, phase, WalkerLib.toRaw(data));

        // Execute all recorded V4 operations in a single unlock callback.
        // The PoolManager's settlement verification ensures all token deltas are properly settled.
        PoolLib.executeOps(pInfo);
    }

    /// Remove liquidity on the way down.
    function down(Key key, bool, bytes memory raw) private {
        Data memory data = WalkerLib.toData(raw);
        Node storage node = data.node(key);

        // On the way down, we remove liquidity.
        (bool dirty, bool sibDirty) = node.liq.isDirty();
        if (dirty) {
            // We are the regularly walked nodes so we'll never need a solve here, we can just update.
            downUpdateLiq(key, node, data);

            if (sibDirty) {
                Key sibKey = key.sibling();
                Node storage sib = data.node(sibKey);
                LiqWalkerLite.solveSibLiq(sibKey, sib, data);
                downUpdateLiq(sibKey, sib, data);
            }
        }
    }

    /// Add liquidity on the way up.
    function up(Key key, bool, bytes memory raw) private {
        Data memory data = WalkerLib.toData(raw);
        Node storage node = data.node(key);

        (bool dirty, bool sibDirty) = node.liq.isDirty();
        if (dirty) {
            upUpdateLiq(key, node, data);
            // After the up update, we are sure the node is clean.
            node.liq.clean();

            if (sibDirty) {
                Key sibKey = key.sibling();
                Node storage sib = data.node(sibKey);
                upUpdateLiq(sibKey, sib, data);
                sib.liq.clean();
            }
        }
    }

    function phase(Phase, bytes memory) private {
        // Do nothing.
    }

    /* Helpers */

    /// On the way down, we decrease liquidity. If we see the node actually has to increase liq.
    /// We save a flag to avoid recalculating.
    /// @dev We need to allow a double visit because sib solving can change the result. So make sure
    /// operations are idempotent.
    function downUpdateLiq(Key key, Node storage node, Data memory data) internal {
        (int24 lowTick, int24 highTick) = key.ticks(data.fees.rootWidth, data.fees.tickSpacing);

        // Because we lookup the liq instead of what we think we have,
        // we avoid any potential slow divergences. But it means if someone donates
        // liquidity to this node, that amount in tokens won't be deposited and will be lost.
        uint128 liq = PoolLib.getLiq(data.poolAddr, lowTick, highTick);

        int256 _targetLiq = node.liq.net(); // This is what the liq accounting wants.
        require(_targetLiq >= 0, InsolventLiquidityUpdate(key, _targetLiq));

        // We know this cast fits.
        uint128 targetLiq = uint128(uint256(_targetLiq)) + 1;
        // We add 1 which will cause the first liq deposit into this node to pay a little dust.
        // This is because we want the node to always hold 1 unit of liquidity that only the underlying
        // pool is aware of. This way the ticks never clear their tick initializations even when
        // all liq is borrowed out according to our own accounting.

        if (targetLiq > liq) {
            // We need to add liquidity. So we save it. We know this will be cleared eventually anyways.
            node.liq.dirty |= ADD_LIQ_DIRTY_FLAG;
            // We know pre lend is zero after solving, so we store the liq diff here to avoid requerying.
            // Also LiqWalkerLite.solve doesn't touch prelend.
            data.setPreLend(key, int128(targetLiq - liq));
        } else {
            if (targetLiq < liq) {
                // In V4, burn is recorded for batched execution.
                PoolLib.burn(data.poolAddr, lowTick, highTick, liq - targetLiq);
                // In V4, collect is implicit in modifyLiquidity. Record a poke if needed.
                PoolLib.collect(data.poolAddr, lowTick, highTick, false);
            }
            // A revisit (due to sib solving) might have changed our intended mint, so we have to clear those.
            data.clearPreLend(key);
            node.liq.dirty &= ~ADD_LIQ_DIRTY_FLAG;
        }
    }

    function upUpdateLiq(Key key, Node storage node, Data memory data) internal {
        if (node.liq.dirty & ADD_LIQ_DIRTY_FLAG == 0) {
            // No need to do anything.
            return;
        }
        // The liq diff is stored by downUpdateLiq when the add liq flag is set.

        uint128 liqDiff = uint128(data.clearPreLend(key));
        (int24 lowTick, int24 highTick) = key.ticks(data.fees.rootWidth, data.fees.tickSpacing);
        // In V4, mint is recorded for batched execution.
        PoolLib.mint(data.poolAddr, lowTick, highTick, liqDiff);
    }
}

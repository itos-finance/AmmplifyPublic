// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

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
/// @dev TODO: Do we need to track the actual balances changes for comparison or does our rounding suffice?
library PoolWalker {
    error InsolventLiquidityUpdate(Key key, int256 targetLiq);

    function settle(PoolInfo memory pInfo, int24 lowTick, int24 highTick, Data memory data) internal {
        uint24 low = pInfo.treeTick(lowTick);
        uint24 high = pInfo.treeTick(highTick) - 1;
        Route memory route = RouteImpl.make(pInfo.treeWidth, low, high);
        route.walk(down, up, phase, WalkerLib.toRaw(data));
    }

    function down(Key key, bool, bytes memory raw) private {
        Data memory data = WalkerLib.toData(raw);
        Node storage node = data.node(key);

        // On the way down, we remove liquidity.
        if (data.liq.liqType == LiqType.TAKER) {
            // If we're taking, we settle liquidity on the way down because any liquidity we add due to borrowing
            // comes from reducing liquidity in the parent which leaves us with sufficient tokens for the child.
            (bool dirty, bool sibDirty) = node.liq.isDirty();
            if (dirty) {
                // We are the regularly walked nodes so we'll never need a solve here, we can just update.
                updateLiq(key, node, data);
                node.liq.clean();

                // On the way down, we walk the visit node first and then their sibling, so a dirty sib bit
                // will always indicate a dirty sibling and they're the only ones who might need a solve.
                if (sibDirty) {
                    Key sibKey = key.sibling();
                    Node storage sib = data.node(sibKey);

                    LiqWalkerLite.solveSibLiq(sib);
                    updateLiq(sibKey, sib, data);
                    sib.liq.clean();
                }
            }
        } else {
            // When we're making, we don't add any liq on the way down. We just visit dirty siblings which would
            // be repaying liq or compounding (which we already have the fees for).
            (, bool sibDirty) = node.liq.isDirty();
            if (sibDirty) {
                Key sibKey = key.sibling();
                Node storage sib = data.node(sibKey);
                // There's no way they would have been visited yet so they'll definitely be dirty and need a solve.
                LiqWalkerLite.solveSibLiq(sib);
                updateLiq(sibKey, sib, data);
                sib.liq.clean();
            }
        }
    }

    /// Add maker liquidity on the way up.
    function up(Key key, bool, bytes memory raw) private {
        // For every node we call on, we just check if its dirty and needs an update.
        // We've already updated the siblings.
        Data memory data = WalkerLib.toData(raw);
        if (data.liq.liqType != LiqType.TAKER) {
            Node storage node = data.node(key);
            (bool dirty, ) = node.liq.isDirty();
            if (dirty) {
                updateLiq(key, node, data);
                node.liq.clean();
            }
        }
    }

    function phase(Phase, bytes memory) private {
        // Do nothing.
    }

    /// @dev internal just for testing. Not used elsewhere.
    function updateLiq(Key key, Node storage node, Data memory data) internal {
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
        // uniswap pool is aware of. This way the ticks never clear their tick initializations even when
        // all liq is borrowed out according to our own accounting.

        if (targetLiq > liq) {
            PoolLib.mint(data.poolAddr, lowTick, highTick, targetLiq - liq);
        } else if (targetLiq < liq) {
            PoolLib.burn(data.poolAddr, lowTick, highTick, liq - targetLiq);
            PoolLib.collect(data.poolAddr, lowTick, highTick, false);
        }
    }
}

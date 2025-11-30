// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Key } from "../tree/Key.sol";
import { Data } from "./Data.sol";
import { LiqNode, LiqType, LiqWalkerLite } from "./Liq.sol";
import { Node } from "./Node.sol";
import { Route, RouteImpl, Phase } from "../tree/Route.sol";
import { PoolLib, PoolInfo } from "../Pool.sol";
import { WalkerLib } from "./Lib.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// Walk down and up the pool to settle balances with the underlying AMM.
/// @dev When walking down, we settle all the liquidity decreases so we have balances to work with,
/// and then on the walk up we add liquidity with the balances as necessary.
library PoolWalker {
    error InsolventLiquidityUpdate(Key key, int256 targetLiq);
    error MismatchedSettlementBalance(int256 required, int256 actual, address token);
    error StalePoolPrice(address poolAddr, uint160 expectedSqrtPriceX96, uint160 actualSqrtPriceX96);
    /// We add this to the dirty bit when we discover the liquidity needs to increase on the walk up.

    uint8 public constant ADD_LIQ_DIRTY_FLAG = 1 << 7;

    /// This does all the balances changes because all liquidity is only changed here.
    /// Thus we verify the balances changes here.
    /// TODO add test where we fudge the pool price during RFT settlement and hit the settlement mismatch.
    function settle(PoolInfo memory pInfo, int24 lowTick, int24 highTick, Data memory data) internal {
        // Before we settle we make sure the pool price has not changed from the time we made all our initial
        // calculations.
        uint160 sqrtPriceX96 = PoolLib.getSqrtPriceX96(pInfo.poolAddr);
        require(data.sqrtPriceX96 == sqrtPriceX96, StalePoolPrice(pInfo.poolAddr, data.sqrtPriceX96, sqrtPriceX96));

        uint256 startingX = IERC20(pInfo.token0).balanceOf(address(this));
        uint256 startingY = IERC20(pInfo.token1).balanceOf(address(this));

        uint24 low = pInfo.treeTick(lowTick);
        uint24 high = pInfo.treeTick(highTick) - 1;
        Route memory route = RouteImpl.make(pInfo.treeWidth, low, high);
        route.walk(down, up, phase, WalkerLib.toRaw(data));

        uint256 endingX = IERC20(pInfo.token0).balanceOf(address(this));
        uint256 endingY = IERC20(pInfo.token1).balanceOf(address(this));

        // Verify balances. Technically just checking the pool price has not changed is sufficient
        // but this adds an additional layer of safety just in case.
        int256 expectedXSpend = data.xBalance + int256(data.compoundSpendX);
        int256 actualXSpend = int256(startingX) - int256(endingX);
        verifySpend(expectedXSpend, actualXSpend, pInfo.token0);
        int256 expectedYSpend = data.yBalance + int256(data.compoundSpendY);
        int256 actualYSpend = int256(startingY) - int256(endingY);
        verifySpend(expectedYSpend, actualYSpend, pInfo.token1);
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
        // uniswap pool is aware of. This way the ticks never clear their tick initializations even when
        // all liq is borrowed out according to our own accounting.

        if (targetLiq > liq) {
            // We need to add liquidity. So we save it. We know this will be cleared eventually anyways.
            node.liq.dirty |= ADD_LIQ_DIRTY_FLAG;
            // We know pre lend is zero after solving, so we store the liq diff here to avoid requerying.
            data.modifyPreLend(key, int128(targetLiq - liq));
        } else {
            if (targetLiq < liq) {
                PoolLib.burn(data.poolAddr, lowTick, highTick, liq - targetLiq);
                PoolLib.collect(data.poolAddr, lowTick, highTick, false);
            }
            // A revisit (due to sib solving) might have changed our intended mint, so we have to clear those.
            data.clearPreLend(key);
            node.liq.dirty &= ~ADD_LIQ_DIRTY_FLAG;
        }
        // On the second walk down, we no longer need any of the fees so we can clear the growths in case
        // there is another action in this same transaction.
        PoolLib.clearTickGrowths(data.poolAddr, lowTick);
        PoolLib.clearTickGrowths(data.poolAddr, highTick);
    }

    function upUpdateLiq(Key key, Node storage node, Data memory data) internal {
        if (node.liq.dirty & ADD_LIQ_DIRTY_FLAG == 0) {
            // No need to do anything.
            return;
        }
        // The liq diff is stored by downUpdateLiq when the add liq flag is set.

        uint128 liqDiff = uint128(data.clearPreLend(key));
        (int24 lowTick, int24 highTick) = key.ticks(data.fees.rootWidth, data.fees.tickSpacing);
        PoolLib.mint(data.poolAddr, lowTick, highTick, liqDiff);
    }

    function verifySpend(int256 expectedSpend, int256 actualSpend, address token) internal pure {
        require(actualSpend <= expectedSpend, MismatchedSettlementBalance(expectedSpend, actualSpend, token));
    }
}

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

    /* Helpers */

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

    function verifySpend(int256 expectedSpend, int256 actualSpend, address token) internal pure {
        require(actualSpend <= expectedSpend, MismatchedSettlementBalance(expectedSpend, actualSpend, token));
    }
}

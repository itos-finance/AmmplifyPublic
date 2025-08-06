// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { SmoothRateCurveConfig } from "Commons/Math/SmoothRateCurveLib.sol";
import { Store } from "./Store.sol";
import { Asset } from "./Asset.sol";
import { FullMath } from "./FullMath.sol";

struct FeeStore {
    SmoothRateCurveConfig defaultFeeCurve;
    SmoothRateCurveConfig defaultSplitCurve;
    mapping(address => SmoothRateCurveConfig) feeCurves;
    mapping(address => SmoothRateCurveConfig) splitCurves;
    mapping(address => uint128) compoundThresholds;
    uint128 defaultCompoundThreshold; // Below this amount of equivalent liq, it is not worth compounding.
    /* JIT Prevention */
    // Someone can try to use JIT to manipulate fees by supplying/removing liquidity from certain nodes
    uint64 jitLifetime; // Positions with shorter lifetimes than this will pay a penalty.
    uint64 jitPenaltyX64; // Fee paid by those who's positions are held too shortly.
    /* Collateral */
    mapping(address sender => mapping(address token => uint256)) collateral;
}

/// Makers earn fees in two ways, from the swap fees of the underlying pool
/// and the borrow fees from any open takers.
/// This just handles fees earned from takers.
library FeeLib {
    function init() internal {
        FeeStore storage store = Store.fees();
        store.defaultCompoundThreshold = 1e12; // 1 of each if both tokens are 6 decimals.
        // TODO: set reasonable default values.
        store.defaultFeeCurve = SmoothRateCurveConfig({ maxUtilX64: 100, minUtilX64: 0, rateX64: 0 });
        store.defaultSplitCurve = SmoothRateCurveConfig({ maxUtilX64: 100, minUtilX64: 0, rateX64: 0 });
    }

    /* Getters */

    function getCompoundThreshold(address poolAddr) internal view returns (uint128 compoundThreshold) {
        FeeStore storage store = Store.fees();
        compoundThreshold = store.compoundThresholds[poolAddr];
        if (compoundThreshold == 0) {
            compoundThreshold = store.defaultCompoundThreshold;
        }
    }

    /// Configuration for how to split fees across children subtrees.
    function getSplitCurve(address poolAddr) internal view returns (SmoothRateCurveConfig memory splitCurve) {
        FeeStore storage store = Store.fees();
        if (store.splitCurves[poolAddr].maxUtilX64 == 0) {
            return store.defaultSplitCurve;
        } else {
            return store.splitCurves[poolAddr];
        }
    }

    /// Configuration for calculating the overall fee payment averaged across all takers.
    function getRateCurve(address poolAddr) internal view returns (SmoothRateCurveConfig memory rateCurve) {
        FeeStore storage store = Store.fees();
        if (store.rateCurves[poolAddr].maxUtilX64 == 0) {
            return store.defaultFeeCurve;
        } else {
            return store.rateCurves[poolAddr];
        }
    }

    /// Applies JIT penalities to balances if applicable for this asset.
    function applyJITPenalties(
        Asset storage asset,
        uint256 xBalance,
        uint256 yBalance
    ) internal view returns (uint256 xBalanceOut, uint256 yBalanceOut) {
        FeeStore storage store = Store.fees();
        uint128 duration = uint128(block.timestamp) - asset.timestamp;
        if (duration >= store.jitLifetime) {
            return (xBalance, yBalance);
        }
        // Apply the JIT penalty.
        uint256 penaltyX64 = store.jitPenaltyX64;
        xBalanceOut = FullMath.mulX64(xBalance, penaltyX64, true);
        yBalanceOut = FullMath.mulX64(yBalance, penaltyX64, true);
    }
}

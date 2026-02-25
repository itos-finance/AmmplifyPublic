// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {SmoothRateCurveConfig} from "Commons/Math/SmoothRateCurveLib.sol";
import {AdminLib} from "Commons/Util/Admin.sol";
import {Store} from "./Store.sol";
import {Asset} from "./Asset.sol";
import {FullMath} from "./FullMath.sol";

struct FeeStore {
    SmoothRateCurveConfig defaultFeeCurve;
    SmoothRateCurveConfig defaultSplitCurve;
    mapping(address => SmoothRateCurveConfig) feeCurves;
    mapping(address => SmoothRateCurveConfig) splitCurves;
    mapping(address => uint128) redistributionThresholds;
    mapping(address => uint32) twapIntervals;
    uint128 defaultRedistributionThreshold; // Below this amount of liq, it is not worth redistributing.
    uint32 defaultTwapInterval; // The default interval to use when calculating TWAPs.
    /* JIT Prevention */
    // Someone can try to use JIT to manipulate fees by supplying/removing liquidity from certain nodes
    uint32 jitLifetime; // Positions with shorter lifetimes than this will pay a penalty.
    uint64 jitPenaltyX64; // Fee paid by those who's positions are held too shortly.
    /* Collateral */
    mapping(address sender => mapping(address token => uint256)) collateral;
    /* Standing fees */
    // Similar to collateral but these are specifically fees collected from the underlying pool for swap fees.
    // (Taker fees paid to compensate for missed pool swap fees are counted here as well.)
    // For this to overflow the entirely of the value of all bitcoin would have to be in the AMM and
    // earn its own value in fees 26 times over. I think we're safe. For contrived tokens we don't care.
    mapping(address pool => uint128) standingX;
    mapping(address pool => uint128) standingY;
}

/// Makers earn fees in two ways, from the swap fees of the underlying pool
/// and the borrow fees from any open takers.
/// This just handles fees earned from takers.
library FeeLib {
    event JITPenalized(uint256 xPenalty, uint256 yPenalty);

    function init() internal {
        FeeStore storage store = Store.fees();
        store.defaultRedistributionThreshold = 1e12; // 1 of each if both tokens are 6 decimals.
        // Target 16% APR at 60% util. 0.2% at 0%. Stored as SPR (second percentage rate).
        store.defaultFeeCurve = SmoothRateCurveConfig({
            invAlphaX128: 1562792664755071494808317984768,
            betaX64: 18446743997862018166,
            maxUtilX64: 20291418481080508416, // 110%
            maxRateX64: 1169884834710 // 200%
        });
        // Right now, we actually use the rate curve itself to decide on the split,
        // splitting the unclaims according to the rates they would have paid.
        store.defaultSplitCurve = SmoothRateCurveConfig({
            invAlphaX128: 1562792664755071494808317984768,
            betaX64: 18446743997862018166,
            maxUtilX64: 20291418481080508416, // 110%
            maxRateX64: 1169884834710 // 200%
        });
        store.defaultTwapInterval = 300; // 5 minutes
    }

    /* Getters */

    function getRedistributionThreshold(address poolAddr) internal view returns (uint128 threshold) {
        FeeStore storage store = Store.fees();
        threshold = store.redistributionThresholds[poolAddr];
        if (threshold == 0) {
            threshold = store.defaultRedistributionThreshold;
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
        if (store.feeCurves[poolAddr].maxUtilX64 == 0) {
            return store.defaultFeeCurve;
        } else {
            return store.feeCurves[poolAddr];
        }
    }

    function getTwapInterval(address poolAddr) internal view returns (uint32 twapInterval) {
        FeeStore storage store = Store.fees();
        twapInterval = store.twapIntervals[poolAddr];
        if (twapInterval == 0) {
            twapInterval = store.defaultTwapInterval;
        }
    }

    /// Applies JIT penalities to balances if applicable for this asset.
    function applyJITPenalties(Asset storage asset, uint256 xBalance, uint256 yBalance, address tokenX, address tokenY)
        internal
        returns (uint256 xBalanceOut, uint256 yBalanceOut)
    {
        FeeStore storage store = Store.fees();
        uint128 duration = uint128(block.timestamp) - asset.timestamp;
        if (duration >= store.jitLifetime) {
            return (xBalance, yBalance);
        }
        // Apply the JIT penalty.
        uint256 penaltyX64 = (1 << 64) - store.jitPenaltyX64;
        xBalanceOut = FullMath.mulX64(xBalance, penaltyX64, true);
        yBalanceOut = FullMath.mulX64(yBalance, penaltyX64, true);
        // Give the penalties to the owner address.
        address owner = AdminLib.getOwner();
        uint256 xDiff = xBalance - xBalanceOut;
        store.collateral[owner][tokenX] += xDiff;
        uint256 yDiff = yBalance - yBalanceOut;
        store.collateral[owner][tokenY] += yDiff;
        emit JITPenalized(xDiff, yDiff);
    }

    /// Views what JIT pentalties would be applied.
    function viewJITPenalties(Asset storage asset, uint256 xBalance, uint256 yBalance)
        internal
        view
        returns (uint256 xBalanceOut, uint256 yBalanceOut)
    {
        FeeStore storage store = Store.fees();
        uint128 duration = uint128(block.timestamp) - asset.timestamp;
        if (duration >= store.jitLifetime) {
            return (xBalance, yBalance);
        }
        // Apply the JIT penalty.
        uint256 penaltyX64 = (1 << 64) - store.jitPenaltyX64;
        xBalanceOut = FullMath.mulX64(xBalance, penaltyX64, true);
        yBalanceOut = FullMath.mulX64(yBalance, penaltyX64, true);
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { SmoothRateCurveConfig } from "Commons/Math/SmoothRateCurveLib.sol";

struct FeeStore {
    SmoothRateCurveConfig defaultFeeCurve;
    mapping(address => SmoothRateCurveConfig) feeCurves;
    /* Collateral */
    mapping(address sender => mapping(address token => uint256)) collateral;
}




/// Makers earn fees in two ways, from the swap fees of the underlying pool
/// and the borrow fees from any open takers.
/// This just handles fees earned from takers.
library FeeLib {
    event FeeCurveSet(address indexed pool, SmoothRateCurveConfig feeCurve);
    event DefaultFeeCurveSet(SmoothRateCurveConfig feeCurve);

    /// Calculates the overall taker fee rate
    function calcRate()
}

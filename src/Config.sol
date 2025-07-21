// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { SmoothRateCurveConfig } from "Commons/Math/SmoothRateCurveLib.sol";
import { Store } from "./Store.sol";

struct Config {
    uint128 defLiqDeMin; // Default de minimus
    SmoothRateCurveConfig defRateCurve; // Default rate curve configuration
    mapping(address poolAddr => uint128) liqDeMins; // Per-pool de minimus
    mapping(address poolAddr => SmoothRateCurveConfig rateCurves); // Per-pool rate
}

library ConfigLib {

    function init() internal {
        Config storage config = Store.config();
        config.defLiqDeMin = 1e12; // 1 of each if both tokens are 6 decimals.
        config.defRateCurve = SmoothRateCurveConfig({
            maxUtilX64: 100,
            minUtilX64: 0,
            rateX64: 0
        });
    }

    /* Setters */

    function setDefaultLiqDeMin(uint128 liqDeMin) internal {
        Store.config().defLiqDeMin = liqDeMin;
    }

    function setDefaultRateCurve(SmoothRateCurveConfig calldata rateCurve) internal {
        Store.config().defRateCurve = rateCurve;
    }

    function setLiqDeMin(address poolAddr, uint128 liqDeMin) internal {
        Store.config().liqDeMins[poolAddr] = liqDeMin;
    }

    function setRateCurve(address poolAddr, SmoothRateCurveConfig calldata rateCurve) internal {
        Store.config().rateCurves[poolAddr] = rateCurve;
    }

    /* Getters */

    function getLiqDeMin(address poolAddr) internal view returns (uint128 deMin) {
        Config storage config = Store.config();
        deMin = config.liqDeMins[poolAddr];
        if (deMin == 0) {
            deMin = config.defLiqDeMin;
        }
    }

    function getRateCurve(address poolAddr) internal view returns (SmoothRateCurveConfig memory rateCurve) {
        Config storage config = Store.config();
        if (config.rateCurves[poolAddr].maxUtilX64 == 0) {
            return config.defRateCurve;
        } else {
            return config.rateCurves[poolAddr];
        }
    }
}

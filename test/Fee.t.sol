// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";

import { AdminLib } from "Commons/Util/Admin.sol";
import { SmoothRateCurveConfig, SmoothRateCurveLib } from "Commons/Math/SmoothRateCurveLib.sol";

import { Store } from "../src/Store.sol";
import { FeeStore, FeeLib } from "../src/Fee.sol";
import { Asset } from "../src/Asset.sol";

contract FeeTest is Test {
    function setUp() public {
        FeeLib.init();
    }

    // Init

    function testInit() public view {
        FeeStore storage store = Store.fees();
        assertEq(store.defaultCompoundThreshold, 1e12);
        _assertDefaultFeeCurve(store.defaultFeeCurve);
        _assertDefaultSplitCurve(store.defaultSplitCurve);
    }

    // Getters

    function testGetCompoundThreshold() public {
        // Default
        FeeStore storage store = Store.fees();
        assertEq(FeeLib.getCompoundThreshold(address(0)), 1e12);

        // Set
        store.compoundThresholds[address(0)] = 1e13;
        assertEq(FeeLib.getCompoundThreshold(address(0)), 1e13);
    }

    function testGetSplitCurve() public {
        // Default
        _assertDefaultSplitCurve(FeeLib.getSplitCurve(address(0)));

        // Set
        FeeStore storage store = Store.fees();
        store.splitCurves[address(0)] = SmoothRateCurveConfig({
            invAlphaX128: 1,
            betaX64: 2,
            maxUtilX64: 3,
            maxRateX64: 4
        });
        SmoothRateCurveConfig memory splitCurve = FeeLib.getSplitCurve(address(0));
        assertEq(splitCurve.invAlphaX128, 1, "setSplitCurve.invAlphaX128");
        assertEq(splitCurve.betaX64, 2, "setSplitCurve.betaX64");
        assertEq(splitCurve.maxUtilX64, 3, "setSplitCurve.maxUtilX64");
        assertEq(splitCurve.maxRateX64, 4, "setSplitCurve.maxRateX64");

        // Unset
        store.splitCurves[address(0)] = SmoothRateCurveConfig({
            invAlphaX128: 1,
            betaX64: 1,
            maxUtilX64: 0, // maxUtil64 of 0 we assume the curve is not set and use the default
            maxRateX64: 1
        });
        _assertDefaultSplitCurve(FeeLib.getSplitCurve(address(0)));
    }

    function testGetRateCurve() public {
        // Default
        _assertDefaultFeeCurve(FeeLib.getRateCurve(address(0)));

        // Set
        FeeStore storage store = Store.fees();
        store.feeCurves[address(0)] = SmoothRateCurveConfig({
            invAlphaX128: 1,
            betaX64: 2,
            maxUtilX64: 3,
            maxRateX64: 4
        });
        SmoothRateCurveConfig memory rateCurve = FeeLib.getRateCurve(address(0));
        assertEq(rateCurve.invAlphaX128, 1, "setRateCurve.invAlphaX128");
        assertEq(rateCurve.betaX64, 2, "setRateCurve.betaX64");
        assertEq(rateCurve.maxUtilX64, 3, "setRateCurve.maxUtilX64");
        assertEq(rateCurve.maxRateX64, 4, "setRateCurve.maxRateX64");

        // Unset
        store.feeCurves[address(0)] = SmoothRateCurveConfig({
            invAlphaX128: 1,
            betaX64: 1,
            maxUtilX64: 0, // maxUtil64 of 0 we assume the curve is not set and use the default
            maxRateX64: 1
        });
        _assertDefaultFeeCurve(FeeLib.getRateCurve(address(0)));
    }

    function testDefaultFeeCurve() public {
        SmoothRateCurveConfig memory rateCurve = FeeLib.getRateCurve(address(0));
        uint256 seconds_in_year = 365 days;
        uint128 rateX64 = SmoothRateCurveLib.calculateRateX64(rateCurve, 0);
        uint256 output = uint256(2 << 64) / 1000;
        assertApproxEqRel(seconds_in_year * rateX64, output, 1e12, "defaultFeeCurve.rateAt0"); // 0.2%
        rateX64 = SmoothRateCurveLib.calculateRateX64(rateCurve, uint128(60 << 64) / 100); // 60%
        assertApproxEqRel(seconds_in_year * rateX64, uint256(16 << 64) / 100, 1e12, "defaultFeeCurve.rateAt60"); // 12%
        rateX64 = SmoothRateCurveLib.calculateRateX64(rateCurve, uint128(90 << 64) / 100); // 90%
        assertApproxEqRel(seconds_in_year * rateX64, uint256(5945 << 64) / 10000, 1e12, "defaultFeeCurve.rateAt90"); // 59.45%
        rateX64 = SmoothRateCurveLib.calculateRateX64(rateCurve, uint128(1 << 64)); // 100%
        assertApproxEqRel(seconds_in_year * rateX64, uint256(131866 << 64) / 100000, 2e17, "defaultFeeCurve.rateAt100"); // ~1.31866%
    }

    // JIT

    function testApplyJITPenalties() public {
        Asset storage asset = Store.assets().assets[0];
        asset.timestamp = 200;

        FeeStore storage feeStore = Store.fees();
        feeStore.jitLifetime = 1000;
        feeStore.jitPenaltyX64 = 6148914691236516864; // 33%

        address owner = address(0xDEADBEEF);
        AdminLib.initOwner(owner);

        // No penalty
        vm.warp(1200);
        (uint256 xBalanceOut, uint256 yBalanceOut) = FeeLib.applyJITPenalties(asset, 100, 100, address(0), address(1));
        assertEq(xBalanceOut, 100, "noPenalty.xBalanceOut");
        assertEq(yBalanceOut, 100, "noPenalty.yBalanceOut");
        assertEq(feeStore.collateral[owner][address(0)], 0, "noX");
        assertEq(feeStore.collateral[owner][address(1)], 0, "noY");

        // Penalty
        vm.warp(1000);
        (xBalanceOut, yBalanceOut) = FeeLib.applyJITPenalties(asset, 100, 100, address(0), address(1));
        assertEq(xBalanceOut, 67, "penalty.xBalanceOut"); // rounds up
        assertEq(yBalanceOut, 67, "penalty.yBalanceOut"); // rounds up
        assertEq(feeStore.collateral[owner][address(0)], 33, "hasX");
        assertEq(feeStore.collateral[owner][address(1)], 33, "hasY");
    }

    // Helpers

    function _assertDefaultFeeCurve(SmoothRateCurveConfig memory rateCurve) internal pure {
        assertEq(rateCurve.invAlphaX128, 1562792664755071494808317984768, "defaultFeeCurve.invAlphaX128");
        assertEq(rateCurve.betaX64, 18446743997862018166, "defaultFeeCurve.betaX64");
        assertEq(rateCurve.maxUtilX64, 20291418481080508416, "defaultFeeCurve.maxUtilX64"); // 120%
        assertEq(rateCurve.maxRateX64, 1169884834710, "defaultFeeCurve.maxRateX64"); // 95%
    }

    function _assertDefaultSplitCurve(SmoothRateCurveConfig memory splitCurve) internal pure {
        assertEq(splitCurve.invAlphaX128, 1562792664755071494808317984768, "defaultSplitCurve.invAlphaX128"); // 1
        assertEq(splitCurve.betaX64, 18446743997862018166, "defaultSplitCurve.betaX64"); // 1 (without offset)
        assertEq(splitCurve.maxUtilX64, 20291418481080508416, "defaultSplitCurve.maxUtilX64"); // 101%
        assertEq(splitCurve.maxRateX64, 1169884834710, "defaultSplitCurve.maxRateX64"); // 100%
    }
}

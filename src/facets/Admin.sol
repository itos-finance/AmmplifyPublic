// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { TimedAdminFacet } from "Commons/Util/TimedAdmin.sol";
import { AdminLib } from "Commons/Util/Admin.sol";
import { SmoothRateCurveConfig, SmoothRateCurveLib } from "Commons/Math/SmoothRateCurveLib.sol";
import { VaultLib, VaultType } from "../vaults/Vault.sol";
import { AssetLib } from "../Asset.sol";
import { Store } from "../Store.sol";
import { FeeStore } from "../Fee.sol";
import { PoolLib, PoolInfo } from "../Pool.sol";

library AmmplifyAdminRights {
    uint256 public constant TAKER = 0x1;
}

contract AdminFacet is TimedAdminFacet {
    event DefaultFeeCurveSet(SmoothRateCurveConfig feeCurve);
    event FeeCurveSet(address indexed pool, SmoothRateCurveConfig feeCurve);
    event DefaultSplitCurveSet(SmoothRateCurveConfig splitCurve);
    event SplitCurveSet(address indexed pool, SmoothRateCurveConfig splitCurve);
    event DefaultCompoundThresholdSet(uint256 threshold);
    event CompoundThresholdSet(address indexed pool, uint256 threshold);
    event JITPenaltySet(uint32 lifetime, uint64 penaltyX64);
    event TwapIntervalSet(address indexed pool, uint32 interval);
    event DefaultTwapIntervalSet(uint32 interval);

    /* Taker related */

    uint256 private constant RIGHTS_USE_ID = uint256(keccak256("ammplify.rights.useid.20250714"));

    /* Fee related */

    function setFeeCurve(address pool, SmoothRateCurveConfig memory feeCurve) external {
        AdminLib.validateOwner();
        SmoothRateCurveLib.validate(feeCurve);
        Store.fees().feeCurves[pool] = feeCurve;
        emit FeeCurveSet(pool, feeCurve);
    }

    function setDefaultFeeCurve(SmoothRateCurveConfig memory feeCurve) external {
        AdminLib.validateOwner();
        SmoothRateCurveLib.validate(feeCurve);
        Store.fees().defaultFeeCurve = feeCurve;
        emit DefaultFeeCurveSet(feeCurve);
    }

    function setDefaultSplitCurve(SmoothRateCurveConfig memory splitCurve) external {
        AdminLib.validateOwner();
        SmoothRateCurveLib.validate(splitCurve);
        Store.fees().defaultSplitCurve = splitCurve;
        emit DefaultSplitCurveSet(splitCurve);
    }

    function setSplitCurve(address pool, SmoothRateCurveConfig memory splitCurve) external {
        AdminLib.validateOwner();
        SmoothRateCurveLib.validate(splitCurve);
        Store.fees().splitCurves[pool] = splitCurve;
        emit SplitCurveSet(pool, splitCurve);
    }

    function setDefaultCompoundThreshold(uint128 threshold) external {
        AdminLib.validateOwner();
        Store.fees().defaultCompoundThreshold = threshold;
        emit DefaultCompoundThresholdSet(threshold);
    }

    function setCompoundThreshold(address pool, uint128 threshold) external {
        AdminLib.validateOwner();
        Store.fees().compoundThresholds[pool] = threshold;
        emit CompoundThresholdSet(pool, threshold);
    }

    function setTwapInterval(address pool, uint32 interval) external {
        AdminLib.validateOwner();
        Store.fees().twapIntervals[pool] = interval;
        emit TwapIntervalSet(pool, interval);
    }

    function setDefaultTwapInterval(uint32 interval) external {
        AdminLib.validateOwner();
        Store.fees().defaultTwapInterval = interval;
        emit DefaultTwapIntervalSet(interval);
    }

    function setJITPenalties(uint32 lifetime, uint64 penaltyX64) external {
        AdminLib.validateOwner();
        Store.fees().jitLifetime = lifetime;
        Store.fees().jitPenaltyX64 = penaltyX64;
        emit JITPenaltySet(lifetime, penaltyX64);
    }

    function getFeeConfig(
        address pool
    )
        external
        view
        returns (
            SmoothRateCurveConfig memory feeCurve,
            SmoothRateCurveConfig memory splitCurve,
            uint128 compoundThreshold,
            uint32 twapInterval
        )
    {
        FeeStore storage store = Store.fees();
        feeCurve = store.feeCurves[pool];
        splitCurve = store.splitCurves[pool];
        compoundThreshold = store.compoundThresholds[pool];
        twapInterval = store.twapIntervals[pool];
    }

    function getDefaultFeeConfig()
        external
        view
        returns (
            SmoothRateCurveConfig memory feeCurve,
            SmoothRateCurveConfig memory splitCurve,
            uint128 compoundThreshold,
            uint32 twapInterval,
            uint32 jitLifetime,
            uint64 jitPenaltyX64
        )
    {
        FeeStore storage store = Store.fees();
        feeCurve = store.defaultFeeCurve;
        splitCurve = store.defaultSplitCurve;
        compoundThreshold = store.defaultCompoundThreshold;
        twapInterval = store.defaultTwapInterval;
        jitLifetime = store.jitLifetime;
        jitPenaltyX64 = store.jitPenaltyX64;
    }

    /// Send fees from the caller to a specific pool.
    /// @dev Primarily used by owner to re-add standing fees if necessary.
    /// But technically anyone can call this.
    function sendStandingFees(address poolAddr, uint128 x, uint128 y) external {
        PoolInfo memory pInfo = PoolLib.getPoolInfo(poolAddr);
        FeeStore storage feeStore = Store.fees();
        // Errors if insufficient.
        feeStore.collateral[msg.sender][pInfo.token0] -= x;
        feeStore.collateral[msg.sender][pInfo.token1] -= y;
        feeStore.standingX[poolAddr] += x;
        feeStore.standingY[poolAddr] += y;
    }

    /* Opener Permissions */

    function addPermissionedOpener(address opener) external {
        AdminLib.validateOwner();
        AssetLib.addPermissionedOpener(opener);
    }

    function removePermissionedOpener(address opener) external {
        AdminLib.validateOwner();
        AssetLib.removePermissionedOpener(opener);
    }

    /* Vault related */

    function viewVaults(address token, uint8 vaultIdx) external view returns (address vault, address backup) {
        (vault, backup) = VaultLib.getVaultAddresses(token, vaultIdx);
    }

    function addVault(address token, uint8 vaultIdx, address vault, VaultType vType) external {
        AdminLib.validateOwner();
        VaultLib.add(token, vaultIdx, vault, vType);
    }

    function removeVault(address vault) external {
        AdminLib.validateOwner();
        VaultLib.remove(vault);
    }

    function swapVault(address token, uint8 vaultId) external returns (address oldVault, address newVault) {
        AdminLib.validateOwner();
        (oldVault, newVault) = VaultLib.hotSwap(token, vaultId);
    }

    // Internal overrides

    function getRightsUseID(bool) internal pure override returns (uint256) {
        return RIGHTS_USE_ID;
    }

    function getDelay(bool add) public pure override returns (uint32) {
        return add ? 3 days : 1 days;
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { TimedAdminFacet } from "Commons/Util/TimedAdmin.sol";
import { AdminLib } from "Commons/Util/Admin.sol";
import { SmoothRateCurveConfig } from "Commons/Math/SmoothRateCurveLib.sol";
import { VaultLib } from "../vaults/Vault.sol";
import { Store } from "../Store.sol";
import { TAKER_VAULT_ID } from "./Taker.sol";

library AmmplifyAdminRights {
    uint256 public constant TAKER = 0x1;
}

contract AdminFacet is TimedAdminFacet {
    /* Taker related */

    uint256 private constant RIGHTS_USE_ID = uint256(keccak256("ammplify.rights.useid.20250714"));

    /* Fee related */

    function setFeeCurve(address pool, SmoothRateCurveConfig calldata feeCurve) external {
        AdminLib.validateOwner();
        Store.fees().feeCurves[pool] = feeCurve;
        emit FeeCurveSet(pool, feeCurve);
    }

    function setDefaultFeeCurve(SmoothRateCurveConfig calldata feeCurve) external {
        AdminLib.validateOwner();
        Store.fees().defaultFeeCurve = feeCurve;
        emit DefaultFeeCurveSet(feeCurve);
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

    function transferVaultBalance(address fromVault, address toVault, uint256 amount) external {
        AdminLib.validateOwner();
        VaultLib.transfer(fromVault, toVault, TAKER_VAULT_ID, amount);
    }

    // Internal overrides

    function getRightsUseID(bool) internal view override returns (uint256) {
        return RIGHTS_USE_ID;
    }

    function getDelay(bool add) public view override returns (uint32) {
        return add ? 3 days : 1 days;
    }
}

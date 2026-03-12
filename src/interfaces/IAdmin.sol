// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { SmoothRateCurveConfig } from "Commons/Math/SmoothRateCurveLib.sol";
import { VaultType } from "../vaults/Vault.sol";
import { PoolKey } from "v4-core/types/PoolKey.sol";

interface IAdmin {
    // Events
    event PoolRegistered(address indexed poolAddr, PoolKey poolKey);
    event DefaultFeeCurveSet(SmoothRateCurveConfig feeCurve);
    event FeeCurveSet(address indexed pool, SmoothRateCurveConfig feeCurve);
    event DefaultSplitCurveSet(SmoothRateCurveConfig splitCurve);
    event SplitCurveSet(address indexed pool, SmoothRateCurveConfig splitCurve);
    event JITPenaltySet(uint32 lifetime, uint64 penaltyX64);

    /* Vault related events */
    event VaultAdded(address indexed token, uint8 indexed vaultIdx, address indexed vault, VaultType vType);
    event VaultRemoved(address indexed vault);
    event VaultSwapped(address indexed token, uint8 indexed vaultId, address indexed oldVault, address newVault);
    event VaultBalanceTransferred(address indexed fromVault, address indexed toVault, uint256 amount);

    // Pool registration
    function registerPool(PoolKey calldata poolKey) external returns (address poolAddr);

    // Fee related functions
    function setFeeCurve(address pool, SmoothRateCurveConfig calldata feeCurve) external;
    function setDefaultFeeCurve(SmoothRateCurveConfig calldata feeCurve) external;
    function setDefaultSplitCurve(SmoothRateCurveConfig calldata splitCurve) external;
    function setSplitCurve(address pool, SmoothRateCurveConfig calldata splitCurve) external;
    function setJITPenalties(uint32 lifetime, uint64 penaltyX64) external;
    function sendStandingFees(address poolAddr, uint128 x, uint128 y) external;

    function getFeeConfig(
        address pool
    )
        external
        view
        returns (
            SmoothRateCurveConfig memory feeCurve,
            SmoothRateCurveConfig memory splitCurve
        );

    function getDefaultFeeConfig()
        external
        view
        returns (
            SmoothRateCurveConfig memory feeCurve,
            SmoothRateCurveConfig memory splitCurve,
            uint32 jitLifetime,
            uint64 jitPenaltyX64
        );

    // Opener permissions
    function addPermissionedOpener(address opener) external;
    function removePermissionedOpener(address opener) external;

    // Vault related functions
    function viewVaults(address token, uint8 vaultIdx) external view returns (address vault, address backup);
    function addVault(address token, uint8 vaultIdx, address vault, VaultType vType) external;
    function removeVault(address vault) external;
    function swapVault(address token, uint8 vaultId) external returns (address oldVault, address newVault);
    function transferVaultBalance(address fromVault, address toVault, uint256 amount) external;
}

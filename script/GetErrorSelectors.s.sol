// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/console2.sol";
import "forge-std/Script.sol";

// Import all contracts that define errors
import { SimplexDiamond } from "../src/Diamond.sol";
import { LibDiamond } from "Commons/Diamond/libraries/LibDiamond.sol";
import { AdminFacet } from "../src/facets/Admin.sol";
import { VaultLib } from "../src/vaults/Vault.sol";
import { PoolValidation } from "../src/Pool.sol";
import { AssetLib } from "../src/Asset.sol";
import { RouteImpl } from "../src/tree/Route.sol";
import { TreeTickLib } from "../src/tree/Tick.sol";
import { DataImpl } from "../src/walkers/Data.sol";
import { LiqWalker } from "../src/walkers/Liq.sol";
import { PoolWalker } from "../src/walkers/Pool.sol";
import { TakerVault } from "../src/integrations/TakerVault.sol";
import { UniV3Decomposer } from "../src/integrations/UniV3Decomposer.sol";
import { Opener } from "../src/integrations/Opener.sol";
import { VaultProxyImpl } from "../src/vaults/VaultProxy.sol";
import { VaultPointerImpl } from "../src/vaults/VaultPointer.sol";
import { VaultE4626Impl } from "../src/vaults/E4626.sol";
import { NFTManager } from "../src/integrations/NFTManager.sol";

/**
 * @title GetErrorSelectors
 * @notice Script to extract and display all error selectors from contracts
 * @dev Run with: forge script script/GetErrorSelectors.s.sol
 *
 * @dev Alternative methods to get error selectors:
 * 1. In Solidity: ErrorName.selector (as shown below)
 * 2. Using cast: cast sig "ErrorName()" or cast sig "ErrorName(uint256)"
 * 3. Programmatically: bytes4(keccak256("ErrorName()"))
 */
contract GetErrorSelectors is Script {
    // Helper function to compute error selector from signature
    function getErrorSelector(string memory errorSig) internal pure returns (bytes4) {
        return bytes4(keccak256(bytes(errorSig)));
    }

    function run() public {
        console2.log("=== Error Selectors ===");
        console2.log("");

        // Diamond errors (file-level error, compute manually)
        console2.log("Diamond Errors:");
        console2.log("FunctionNotFound:", vm.toString(getErrorSelector("FunctionNotFound(bytes4)")));
        console2.log("");

        // LibDiamond errors (file-level errors, compute manually)
        console2.log("LibDiamond Errors:");
        console2.log("NoSelectorsGivenToAdd:", vm.toString(getErrorSelector("NoSelectorsGivenToAdd()")));
        console2.log(
            "NoSelectorsProvidedForFacetForCut:",
            vm.toString(getErrorSelector("NoSelectorsProvidedForFacetForCut(address)"))
        );
        console2.log(
            "CannotAddSelectorsToZeroAddress:",
            vm.toString(getErrorSelector("CannotAddSelectorsToZeroAddress(bytes4[])"))
        );
        console2.log("NoBytecodeAtAddress:", vm.toString(getErrorSelector("NoBytecodeAtAddress(address,string)")));
        console2.log("IncorrectFacetCutAction:", vm.toString(getErrorSelector("IncorrectFacetCutAction(uint8)")));
        console2.log(
            "CannotAddFunctionToDiamondThatAlreadyExists:",
            vm.toString(getErrorSelector("CannotAddFunctionToDiamondThatAlreadyExists(bytes4)"))
        );
        console2.log(
            "CannotReplaceFunctionsFromFacetWithZeroAddress:",
            vm.toString(getErrorSelector("CannotReplaceFunctionsFromFacetWithZeroAddress(bytes4[])"))
        );
        console2.log(
            "CannotReplaceImmutableFunction:",
            vm.toString(getErrorSelector("CannotReplaceImmutableFunction(bytes4)"))
        );
        console2.log(
            "CannotReplaceFunctionWithTheSameFunctionFromTheSameFacet:",
            vm.toString(getErrorSelector("CannotReplaceFunctionWithTheSameFunctionFromTheSameFacet(bytes4)"))
        );
        console2.log(
            "CannotReplaceFunctionThatDoesNotExists:",
            vm.toString(getErrorSelector("CannotReplaceFunctionThatDoesNotExists(bytes4)"))
        );
        console2.log(
            "RemoveFacetAddressMustBeZeroAddress:",
            vm.toString(getErrorSelector("RemoveFacetAddressMustBeZeroAddress(address)"))
        );
        console2.log(
            "CannotRemoveFunctionThatDoesNotExist:",
            vm.toString(getErrorSelector("CannotRemoveFunctionThatDoesNotExist(bytes4)"))
        );
        console2.log(
            "CannotRemoveImmutableFunction:",
            vm.toString(getErrorSelector("CannotRemoveImmutableFunction(bytes4)"))
        );
        console2.log(
            "InitializationFunctionReverted:",
            vm.toString(getErrorSelector("InitializationFunctionReverted(address,bytes)"))
        );
        console2.log("");

        // AdminFacet errors
        console2.log("AdminFacet Errors:");
        console2.log("InvalidZeroInterval:", vm.toString(AdminFacet.InvalidZeroInterval.selector));
        console2.log("FullUtilizationUnhandled:", vm.toString(AdminFacet.FullUtilizationUnhandled.selector));
        console2.log("");

        // VaultLib errors
        console2.log("VaultLib Errors:");
        console2.log("VaultExists:", vm.toString(VaultLib.VaultExists.selector));
        console2.log("RemainingVaultBalance:", vm.toString(VaultLib.RemainingVaultBalance.selector));
        console2.log("VaultTypeNotRecognized:", vm.toString(VaultLib.VaultTypeNotRecognized.selector));
        console2.log("VaultNotFound:", vm.toString(VaultLib.VaultNotFound.selector));
        console2.log("VaultOccupied:", vm.toString(VaultLib.VaultOccupied.selector));
        console2.log("VaultInUse:", vm.toString(VaultLib.VaultInUse.selector));
        console2.log("NoBackup:", vm.toString(VaultLib.NoBackup.selector));
        console2.log("");

        // Pool errors
        console2.log("Pool Errors:");
        console2.log("UnrecognizedPool:", vm.toString(PoolValidation.UnrecognizedPool.selector));
        console2.log(
            "PoolInsufficientObservations:",
            vm.toString(PoolValidation.PoolInsufficientObservations.selector)
        );
        console2.log("");

        // AssetLib errors
        console2.log("AssetLib Errors:");
        console2.log("NoRecipient:", vm.toString(AssetLib.NoRecipient.selector));
        console2.log("AssetNotFound:", vm.toString(AssetLib.AssetNotFound.selector));
        console2.log("NotPermissioned:", vm.toString(AssetLib.NotPermissioned.selector));
        console2.log("");

        // RouteImpl errors
        console2.log("RouteImpl Errors:");
        console2.log("OutOfBounds:", vm.toString(RouteImpl.OutOfBounds.selector));
        console2.log("InvertedRange:", vm.toString(RouteImpl.InvertedRange.selector));
        console2.log("");

        // TreeTickLib errors
        console2.log("TreeTickLib Errors:");
        console2.log("UnalignedTick:", vm.toString(TreeTickLib.UnalignedTick.selector));
        console2.log("OutOfRange:", vm.toString(TreeTickLib.OutOfRange.selector));
        console2.log("");

        // DataImpl errors
        console2.log("DataImpl Errors:");
        console2.log("PriceSlippageExceeded:", vm.toString(DataImpl.PriceSlippageExceeded.selector));
        console2.log("");

        // LiqWalker errors
        console2.log("LiqWalker Errors:");
        console2.log("InsufficientBorrowLiquidity:", vm.toString(LiqWalker.InsufficientBorrowLiquidity.selector));
        console2.log("InsufficientStandingFees:", vm.toString(LiqWalker.InsufficientStandingFees.selector));
        console2.log("");

        // PoolWalker errors
        console2.log("PoolWalker Errors:");
        console2.log("InsolventLiquidityUpdate:", vm.toString(PoolWalker.InsolventLiquidityUpdate.selector));
        console2.log("MismatchedSettlementBalance:", vm.toString(PoolWalker.MismatchedSettlementBalance.selector));
        console2.log("StalePoolPrice:", vm.toString(PoolWalker.StalePoolPrice.selector));
        console2.log("");

        // TakerVault errors
        console2.log("TakerVault Errors:");
        console2.log("Unauthorized:", vm.toString(TakerVault.Unauthorized.selector));
        console2.log("InsufficientBalance:", vm.toString(TakerVault.InsufficientBalance.selector));
        console2.log("");

        // UniV3Decomposer errors
        console2.log("UniV3Decomposer Errors:");
        console2.log("OnlyMakerFacet:", vm.toString(UniV3Decomposer.OnlyMakerFacet.selector));
        console2.log("NotPositionOwner:", vm.toString(UniV3Decomposer.NotPositionOwner.selector));
        console2.log("PoolNotDeployed:", vm.toString(UniV3Decomposer.PoolNotDeployed.selector));
        console2.log("ReentrancyAttempt:", vm.toString(UniV3Decomposer.ReentrancyAttempt.selector));
        console2.log("");

        // Opener errors
        console2.log("Opener Errors:");
        console2.log("InvalidCallbackSender:", vm.toString(Opener.InvalidCallbackSender.selector));
        console2.log("SlippageTooHigh:", vm.toString(Opener.SlippageTooHigh.selector));
        console2.log("InvalidToken:", vm.toString(Opener.InvalidToken.selector));
        console2.log("");

        // VaultProxyImpl errors
        console2.log("VaultProxyImpl Errors:");
        console2.log("VaultTypeUnrecognized:", vm.toString(VaultProxyImpl.VaultTypeUnrecognized.selector));
        console2.log("WithdrawLimited:", vm.toString(VaultProxyImpl.WithdrawLimited.selector));
        console2.log("");

        // VaultPointerImpl errors
        console2.log("VaultPointerImpl Errors:");
        console2.log("VaultTypeUnrecognized:", vm.toString(VaultPointerImpl.VaultTypeUnrecognized.selector));
        console2.log("");

        // VaultE4626Impl errors
        console2.log("VaultE4626Impl Errors:");
        console2.log("InsufficientBalance:", vm.toString(VaultE4626Impl.InsufficientBalance.selector));
        console2.log("");

        // NFTManager errors
        console2.log("NFTManager Errors:");
        console2.log("NotAssetOwner:", vm.toString(NFTManager.NotAssetOwner.selector));
        console2.log("AssetNotMinted:", vm.toString(NFTManager.AssetNotMinted.selector));
        console2.log("OnlyMakerFacet:", vm.toString(NFTManager.OnlyMakerFacet.selector));
        console2.log("NotPositionOwner:", vm.toString(NFTManager.NotPositionOwner.selector));
        console2.log("NoActiveTokenRequest:", vm.toString(NFTManager.NoActiveTokenRequest.selector));
        console2.log("");

        console2.log("=== All Error Selectors Listed ===");
        console2.log("");
        console2.log("Note: To get error selectors using cast command:");
        console2.log('  cast sig "ErrorName()"');
        console2.log('  cast sig "ErrorName(uint256)"');
        console2.log('  cast sig "ErrorName(address,uint256)"');
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { IDiamond } from "Commons/Diamond/interfaces/IDiamond.sol";
import { LibDiamond } from "Commons/Diamond/libraries/LibDiamond.sol";
import { DiamondCutFacet } from "Commons/Diamond/facets/DiamondCutFacet.sol";
import { DiamondLoupeFacet } from "Commons/Diamond/facets/DiamondLoupeFacet.sol";
import { IDiamondCut } from "Commons/Diamond/interfaces/IDiamondCut.sol";
import { IDiamondLoupe } from "Commons/Diamond/interfaces/IDiamondLoupe.sol";
import { IERC173 } from "Commons/ERC/interfaces/IERC173.sol";
import { IERC165 } from "Commons/ERC/interfaces/IERC165.sol";

import { AdminLib } from "Commons/Util/Admin.sol";

import { AdminFacet } from "./facets/Admin.sol";
import { MakerFacet } from "./facets/Maker.sol";
import { TakerFacet } from "./facets/Taker.sol";

error FunctionNotFound(bytes4 _functionSelector);

contract SimplexDiamond is IDiamond {
    constructor() {
        AdminLib.initOwner(msg.sender);

        FacetCut[] memory cuts = new FacetCut[](5);

        {
            bytes4[] memory cutFunctionSelectors = new bytes4[](1);
            cutFunctionSelectors[0] = DiamondCutFacet.diamondCut.selector;

            cuts[0] = FacetCut({
                facetAddress: address(new DiamondCutFacet()),
                action: FacetCutAction.Add,
                functionSelectors: cutFunctionSelectors
            });
        }

        {
            bytes4[] memory loupeFacetSelectors = new bytes4[](5);
            loupeFacetSelectors[0] = DiamondLoupeFacet.facets.selector;
            loupeFacetSelectors[1] = DiamondLoupeFacet.facetFunctionSelectors.selector;
            loupeFacetSelectors[2] = DiamondLoupeFacet.facetAddresses.selector;
            loupeFacetSelectors[3] = DiamondLoupeFacet.facetAddress.selector;
            loupeFacetSelectors[4] = DiamondLoupeFacet.supportsInterface.selector;
            cuts[1] = FacetCut({
                facetAddress: address(new DiamondLoupeFacet()),
                action: FacetCutAction.Add,
                functionSelectors: loupeFacetSelectors
            });
        }

        {
            bytes4[] memory adminSelectors = new bytes4[](8);
            adminSelectors[0] = AdminFacet.transferOwnership.selector;
            adminSelectors[1] = AdminFacet.acceptOwnership.selector;
            adminSelectors[2] = AdminFacet.owner.selector;
            adminSelectors[3] = AdminFacet.adminRights.selector;
            adminSelectors[4] = AdminFacet.setFeeCurve.selector;
            adminSelectors[5] = AdminFacet.setDefaultFeeCurve.selector;
            adminSelectors[6] = AdminFacet.addVault.selector;
            adminSelectors[7] = AdminFacet.swapVault.selector;
            cuts[2] = FacetCut({
                facetAddress: address(new AdminFacet()),
                action: FacetCutAction.Add,
                functionSelectors: adminSelectors
            });
        }

        {
            bytes4[] memory selectors = new bytes4[](4);
            selectors[0] = MakerFacet.newAsset.selector;
            selectors[1] = MakerFacet.removeAsset.selector;
            selectors[2] = MakerFacet.viewAsset.selector;
            selectors[3] = MakerFacet.collectFees.selector;

            cuts[3] = IDiamond.FacetCut({
                facetAddress: address(new MakerFacet()),
                action: IDiamond.FacetCutAction.Add,
                functionSelectors: selectors
            });
        }

        {
            bytes4[] memory selectors = new bytes4[](5);
            selectors[0] = TakerFacet.collateralize.selector;
            selectors[1] = TakerFacet.withdrawCollateral.selector;
            selectors[2] = TakerFacet.newAsset.selector;
            selectors[3] = TakerFacet.removeAsset.selector;
            selectors[4] = TakerFacet.viewAsset.selector;
            cuts[4] = IDiamond.FacetCut({
                facetAddress: address(new TakerFacet()),
                action: IDiamond.FacetCutAction.Add,
                functionSelectors: selectors
            });
        }

        // Finally, install all the cuts and don't use an initialization contract.
        LibDiamond.diamondCut(cuts, address(0), "");

        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.supportedInterfaces[type(IERC165).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondCut).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondLoupe).interfaceId] = true;
        ds.supportedInterfaces[type(IERC173).interfaceId] = true;
    }

    fallback() external payable {
        LibDiamond.DiamondStorage storage ds;
        bytes32 position = LibDiamond.DIAMOND_STORAGE_POSITION;
        // get diamond storage
        assembly {
            ds.slot := position
        }
        // get facet from function selector
        address facet = ds.facetAddressAndSelectorPosition[msg.sig].facetAddress;
        if (facet == address(0)) {
            revert FunctionNotFound(msg.sig);
        }
        // Execute external function from facet using delegatecall and return any value.
        assembly {
            // copy function selector and any arguments
            calldatacopy(0, 0, calldatasize())
            // execute function call using the facet
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            // get any return value
            returndatacopy(0, 0, returndatasize())
            // return any return value or error back to the caller
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    receive() external payable {}
}

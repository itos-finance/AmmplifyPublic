// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { MakerFacet } from "../src/facets/Maker.sol";
import { IDiamondCut } from "Commons/Diamond/interfaces/IDiamondCut.sol";
import { IDiamond } from "Commons/Diamond/interfaces/IDiamond.sol";

/**
 * @title UpdateMakerFacet
 * @dev Script to deploy a new MakerFacet and perform facet cuts on both Capricorn and Uniswap Ammplify pools
 *
 * This script:
 * 1. Deploys a new MakerFacet contract
 * 2. Performs a facet cut (Replace) on the Capricorn mainnet diamond (from deployed-capricorn.json)
 * 3. Performs a facet cut (Replace) on the Uniswap Ammplify diamond (from deployed-uniswap.json)
 *
 * Usage:
 * forge script script/UpdateMakerFacet.s.sol:UpdateMakerFacet --rpc-url <RPC_URL> --private-key <PRIVATE_KEY> --broadcast
 */
contract UpdateMakerFacet is Script {
    using stdJson for string;

    function run() external {
        // Get the deployer's address and private key from environment
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        console.log("Deploying new MakerFacet with deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);

        // Read diamond addresses from JSON files
        string memory capricornJson = vm.readFile("./deployed-capricorn.json");
        string memory uniswapJson = vm.readFile("./deployed-uniswap.json");

        address capricornDiamond = capricornJson.readAddress(".ammplify.simplexDiamond");
        address uniswapDiamond = uniswapJson.readAddress(".ammplify.simplexDiamond");

        console.log("Capricorn Diamond address:", capricornDiamond);
        console.log("Uniswap Diamond address:", uniswapDiamond);

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy new MakerFacet
        console.log("\n=== Deploying New MakerFacet ===");
        MakerFacet newMakerFacet = new MakerFacet();
        console.log("New MakerFacet deployed at:", address(newMakerFacet));

        // Step 2: Prepare facet cut with all MakerFacet function selectors
        console.log("\n=== Preparing Facet Cut ===");
        IDiamond.FacetCut[] memory cuts = new IDiamond.FacetCut[](1);

        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = MakerFacet.newMaker.selector;
        selectors[1] = MakerFacet.removeMaker.selector;
        selectors[2] = MakerFacet.collectFees.selector;
        selectors[3] = MakerFacet.adjustMaker.selector;
        selectors[4] = MakerFacet.compound.selector;
        selectors[5] = MakerFacet.addPermission.selector;
        selectors[6] = MakerFacet.removePermission.selector;

        cuts[0] = IDiamond.FacetCut({
            facetAddress: address(newMakerFacet),
            action: IDiamond.FacetCutAction.Replace,
            functionSelectors: selectors
        });

        console.log("Facet cut prepared with", selectors.length, "function selectors");

        // Step 3: Perform facet cut on Capricorn diamond
        console.log("\n=== Performing Facet Cut on Capricorn Diamond ===");
        console.log("Capricorn Diamond address:", capricornDiamond);
        IDiamondCut capricornDiamondCut = IDiamondCut(capricornDiamond);
        capricornDiamondCut.diamondCut(cuts, address(0), "");
        console.log("Facet cut completed on Capricorn diamond");

        // Step 4: Perform facet cut on Uniswap diamond
        console.log("\n=== Performing Facet Cut on Uniswap Diamond ===");
        console.log("Uniswap Diamond address:", uniswapDiamond);
        IDiamondCut uniswapDiamondCut = IDiamondCut(uniswapDiamond);
        uniswapDiamondCut.diamondCut(cuts, address(0), "");
        console.log("Facet cut completed on Uniswap diamond");

        vm.stopBroadcast();

        // Summary
        console.log("\n=== Summary ===");
        console.log("New MakerFacet deployed at:", address(newMakerFacet));
        console.log("Facet cut performed on Capricorn diamond:", capricornDiamond);
        console.log("Facet cut performed on Uniswap diamond:", uniswapDiamond);
    }
}

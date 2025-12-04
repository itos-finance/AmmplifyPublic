// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/console2.sol";

import { AmmplifyPositions } from "../AmmplifyPositions.s.sol";
import { AdminFacet } from "../../src/facets/Admin.sol";

/**
 * @title SetDefaultBorrower
 * @notice Script to set the default borrower address in the Ammplify system
 * @dev Run with: forge script script/actions/SetDefaultBorrower.s.sol --broadcast --rpc-url <RPC_URL>
 * @dev Set DEFAULT_BORROWER environment variable to specify the borrower address
 */
contract SetDefaultBorrower is AmmplifyPositions {
    function run() public override {
        // Load deployer addresses from .env file
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console2.log("=== Setting Default Borrower ===");
        console2.log("Deployer address:", deployer);

        address borrower = address(0x54e3cE3f01C6934A0d74C42c08EFBCb181694FD7);
        console2.log("Borrower address:", borrower);

        // Get the AdminFacet interface to the diamond
        AdminFacet admin = AdminFacet(0x13cAE468c62Bcb8868840183d02659E9D83E10C0);
        console2.log("SimplexDiamond:", address(admin));

        // Set the default borrower
        console2.log("=== Setting Default Borrower ===");
        try admin.setDefaultBorrower(borrower) {
            console2.log("Default borrower set successfully:", borrower);
        } catch Error(string memory reason) {
            console2.log("Failed to set default borrower:", reason);
            revert(reason);
        } catch {
            console2.log("Failed to set default borrower: Unknown error");
            revert("Unknown error setting default borrower");
        }
        console2.log("=== Default Borrower Set Successfully ===");

        vm.stopBroadcast();
    }
}

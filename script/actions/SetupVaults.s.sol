// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/console2.sol";

import { AmmplifyPositions } from "../AmmplifyPositions.s.sol";
import { IAdmin } from "../../src/interfaces/IAdmin.sol";
import { VaultType } from "../../src/vaults/Vault.sol";

/**
 * @title SetupVaults
 * @notice Script to add vaults to the Ammplify diamond
 * @dev This needs to be done before creating positions
 * @dev Run with: forge script script/actions/SetupVaults.s.sol --broadcast --rpc-url <RPC_URL>
 *
 * Environment variables:
 * - VAULT_TOKEN: Token symbol for the vault (e.g. "WETH")
 * - VAULT_ADDRESS: Address of the vault contract
 * - VAULT_INDEX: Vault index (default: 0)
 */
contract SetupVaults is AmmplifyPositions {
    function run() public override {
        // Load deployer addresses from .env file
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console2.log("=== Setting up Vaults in Diamond ===");
        console2.log("Deployer address:", deployer);

        IAdmin admin = IAdmin(env.diamond);

        // Get vault configuration from environment
        string memory tokenSymbol = vm.envOr("VAULT_TOKEN", string("WETH"));
        address vaultAddress = vm.envAddress("VAULT_ADDRESS");
        uint8 vaultIndex = uint8(vm.envOr("VAULT_INDEX", uint256(0)));
        address tokenAddress = getTokenAddress(tokenSymbol);

        console2.log("Adding vault for token:", tokenSymbol);
        console2.log("Token address:", tokenAddress);
        console2.log("Vault address:", vaultAddress);
        console2.log("Vault index:", vaultIndex);

        try admin.addVault(tokenAddress, vaultIndex, vaultAddress, VaultType.E4626) {
            console2.log("Vault added successfully");
        } catch Error(string memory reason) {
            console2.log("Failed to add vault:", reason);
        } catch {
            console2.log("Failed to add vault: Unknown error");
        }

        // Query vault information to verify
        console2.log("=== Vault Verification ===");
        try admin.viewVaults(tokenAddress, vaultIndex) returns (address vault, address backup) {
            console2.log("Vault:", vault);
            console2.log("Backup Vault:", backup);
        } catch {
            console2.log("Failed to get vault info");
        }

        console2.log("=== Vault Setup Complete ===");

        vm.stopBroadcast();
    }
}

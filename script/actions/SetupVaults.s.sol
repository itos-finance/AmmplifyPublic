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
 */
contract SetupVaults is AmmplifyPositions {
    function run() public override {
        // Load deployer addresses from .env file
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console2.log("=== Setting up Vaults in Diamond ===");
        console2.log("Deployer address:", deployer);

        IAdmin admin = IAdmin(env.simplexDiamond);

        // console2.log("Adding USDC Vault:", env.usdcVault);
        // try admin.addVault(env.usdcToken, 0, env.usdcVault, VaultType.E4626) {
        //     console2.log("USDC Vault added successfully");
        // } catch Error(string memory reason) {
        //     console2.log("Failed to add USDC Vault:", reason);
        // } catch {
        //     console2.log("Failed to add USDC Vault: Unknown error");
        // }

        // admin.removeVault(env.wethVault);

        console2.log("Adding WETH Vault:", env.wethVault);
        try admin.addVault(env.wethToken, 0, env.wethVault, VaultType.E4626) {
            console2.log("WETH Vault added successfully");
        } catch Error(string memory reason) {
            console2.log("Failed to add WETH Vault:", reason);
        } catch {
            console2.log("Failed to add WETH Vault: Unknown error");
        }

        // Query vault information to verify
        console2.log("=== Vault Verification ===");
        try admin.viewVaults(env.usdcToken, 0) returns (address vault, address backup) {
            console2.log("USDC Vault (index 0):", vault);
            console2.log("USDC Backup Vault:", backup);
        } catch {
            console2.log("Failed to get USDC vault info");
        }

        try admin.viewVaults(env.wethToken, 0) returns (address vault, address backup) {
            console2.log("WETH Vault (index 0):", vault);
            console2.log("WETH Backup Vault:", backup);
        } catch {
            console2.log("Failed to get WETH vault info");
        }

        console2.log("=== Vault Setup Complete ===");

        vm.stopBroadcast();
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import { IAdmin } from "../../src/interfaces/IAdmin.sol";
import { VaultType } from "../../src/vaults/Vault.sol";
import { NoOpVault } from "../../src/integrations/NoOpVault.sol";
import { ERC20 } from "a@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title NoOpVaults
 * @notice Script to deploy a NoOpVault and add it to the Ammplify diamond
 * @dev Deploys one vault at a time for a single token
 * @dev Run with: forge script script/actions/NoOpVaults.s.sol --broadcast --rpc-url <RPC_URL>
 */
contract NoOpVaults is Script {
    // ============ CONFIGURATION - Set all variables here ============

    // Token address
    address public constant TOKEN = address(0x754704Bc059F8C67012fEd69BC8A327a5aafb603);

    // Vault address (if set, will use this; otherwise will deploy NoOpVault)
    address public constant VAULT = address(0);

    // SimplexDiamond address
    address public constant SIMPLEX_DIAMOND = address(0x5B5e9d616fAFCCC4865a6C29b6F89Ff3aAE7c892);

    // Vault index (usually 0 for first vault)
    uint8 public constant VAULT_INDEX = 0;

    function run() public {
        // Load deployer addresses from .env file
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console2.log("=== Deploying NoOpVault and Adding to Diamond ===");
        console2.log("Deployer address:", deployer);
        console2.log("Token:", TOKEN);
        console2.log("SimplexDiamond:", SIMPLEX_DIAMOND);

        // Deploy NoOpVault if vault address is not set
        address vault = VAULT;
        if (vault == address(0)) {
            console2.log("\n=== Deploying NoOpVault ===");
            ERC20 tokenERC20 = ERC20(TOKEN);
            string memory tokenName = tokenERC20.name();
            string memory tokenSymbol = tokenERC20.symbol();
            string memory vaultName = string(abi.encodePacked("NoOp ", tokenName));
            string memory vaultSymbol = string(abi.encodePacked("noop", tokenSymbol));
            NoOpVault noopVault = new NoOpVault(tokenERC20, vaultName, vaultSymbol);
            vault = address(noopVault);
            console2.log("NoOpVault deployed at:", vault);
            console2.log("Vault name:", vaultName);
            console2.log("Vault symbol:", vaultSymbol);
        }

        // Add vault to diamond
        IAdmin admin = IAdmin(SIMPLEX_DIAMOND);
        console2.log("\nAdding Vault to Diamond:");
        console2.log("  Token:", TOKEN);
        console2.log("  Vault:", vault);
        console2.log("  Index:", VAULT_INDEX);
        admin.addVault(TOKEN, VAULT_INDEX, vault, VaultType.E4626);
        console2.log("Vault added successfully");

        // Verify vault
        console2.log("\n=== Vault Verification ===");
        (address vaultResult, address backup) = admin.viewVaults(TOKEN, VAULT_INDEX);
        console2.log("Vault (index", VAULT_INDEX, "):", vaultResult);
        console2.log("Backup Vault:", backup);

        console2.log("\n=== Vault Setup Complete ===");

        vm.stopBroadcast();
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { MockERC20 } from "../test/mocks/MockERC20.sol";
import { MockERC4626 } from "../test/mocks/MockERC4626.sol";
import { ERC20 } from "a@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title DeployTokens
 * @dev Deployment script for test tokens (MockERC20 and MockERC4626)
 *
 * This script deploys:
 * - Two MockERC20 tokens (USDC and WETH equivalents)
 * - Two MockERC4626 vaults wrapping the ERC20 tokens
 * - Mints initial supply to the deployer for testing
 *
 * Usage:
 * forge script script/DeployTokens.s.sol:DeployTokens --rpc-url <RPC_URL> --broadcast
 *
 * For local testing:
 * forge script script/DeployTokens.s.sol:DeployTokens --rpc-url http://localhost:8545 --broadcast
 */
contract DeployTokens is Script {
    // Deployed contracts
    MockERC20 public usdc;
    MockERC20 public weth;
    MockERC4626 public usdcVault;
    MockERC4626 public wethVault;

    // Configuration
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000e18; // 1B tokens
    uint256 public constant DEPLOYER_MINT = 100_000_000e18; // 100M tokens for deployer

    function run() external {
        // Get the deployer's address and private key from environment
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        console.log("Deploying tokens with deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy MockERC20 tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);

        console.log("USDC deployed at:", address(usdc));
        console.log("WETH deployed at:", address(weth));

        // Mint initial supply to deployer
        usdc.mint(deployer, DEPLOYER_MINT / 1e12); // Adjust for 6 decimals
        weth.mint(deployer, DEPLOYER_MINT);

        console.log("Minted to deployer:");
        console.log("- USDC:", usdc.balanceOf(deployer));
        console.log("- WETH:", weth.balanceOf(deployer));

        // Deploy MockERC4626 vaults
        usdcVault = new MockERC4626(ERC20(address(usdc)), "USDC Vault", "vUSDC");
        wethVault = new MockERC4626(ERC20(address(weth)), "WETH Vault", "vWETH");

        console.log("USDC Vault deployed at:", address(usdcVault));
        console.log("WETH Vault deployed at:", address(wethVault));

        vm.stopBroadcast();

        // Log deployment summary
        console.log("\n=== Token Deployment Summary ===");
        console.log("USDC Token:", address(usdc));
        console.log("  - Name:", usdc.name());
        console.log("  - Symbol:", usdc.symbol());
        console.log("  - Decimals:", usdc.decimals());
        console.log("  - Deployer Balance:", usdc.balanceOf(deployer));

        console.log("WETH Token:", address(weth));
        console.log("  - Name:", weth.name());
        console.log("  - Symbol:", weth.symbol());
        console.log("  - Decimals:", weth.decimals());
        console.log("  - Deployer Balance:", weth.balanceOf(deployer));

        console.log("USDC Vault:", address(usdcVault));
        console.log("  - Name:", usdcVault.name());
        console.log("  - Symbol:", usdcVault.symbol());
        console.log("  - Asset:", address(usdcVault.asset()));

        console.log("WETH Vault:", address(wethVault));
        console.log("  - Name:", wethVault.name());
        console.log("  - Symbol:", wethVault.symbol());
        console.log("  - Asset:", address(wethVault.asset()));
    }

    /**
     * @notice Helper function to mint additional tokens for testing
     * @param recipient The address to receive tokens
     * @param usdcAmount Amount of USDC to mint (in 6 decimal format)
     * @param wethAmount Amount of WETH to mint (in 18 decimal format)
     */
    function mintTokens(address recipient, uint256 usdcAmount, uint256 wethAmount) external {
        require(address(usdc) != address(0), "Tokens not deployed");

        vm.startBroadcast();

        if (usdcAmount > 0) {
            usdc.mint(recipient, usdcAmount);
            console.log("Minted", usdcAmount, "USDC to", recipient);
        }

        if (wethAmount > 0) {
            weth.mint(recipient, wethAmount);
            console.log("Minted", wethAmount, "WETH to", recipient);
        }

        vm.stopBroadcast();
    }
}

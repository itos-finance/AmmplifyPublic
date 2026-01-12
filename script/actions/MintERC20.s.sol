// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import { MockERC20 } from "../../test/mocks/MockERC20.sol";

/**
 * @title MintERC20
 * @notice Script to deploy MockERC20 and mint tokens to a recipient
 * @dev Run with: forge script script/actions/MintERC20.s.sol --broadcast --rpc-url <RPC_URL>
 */
contract MintERC20 is Script {
    // Placeholders for hardcoded values
    // TODO: Replace these with actual hardcoded values
    address private constant TOKEN_ADDRESS_PLACEHOLDER = address(0);
    address private constant RECIPIENT_PLACEHOLDER = address(0x2a42bE604948c0cce8a1FCFC781089611E2a1ea0);
    uint256 private constant AMOUNT_PLACEHOLDER = 1e18;
    string private constant TOKEN_NAME_PLACEHOLDER = "Michigan";
    string private constant TOKEN_SYMBOL_PLACEHOLDER = "MICH";
    uint8 private constant TOKEN_DECIMALS_PLACEHOLDER = 18;

    function run() public {
        // Load deployer addresses from .env file
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console2.log("=== Deploying MockERC20 and Minting Tokens ===");
        console2.log("Deployer address:", deployer);

        // Get token address (placeholder with fallback to environment variable)
        address tokenAddress = TOKEN_ADDRESS_PLACEHOLDER;
        if (tokenAddress == address(0)) {
            try vm.envAddress("TOKEN_ADDRESS") returns (address envAddr) {
                tokenAddress = envAddr;
            } catch {
                // If no token address provided, will deploy a new one
                tokenAddress = address(0);
            }
        }

        // Get recipient (placeholder with fallback to environment variable)
        address recipient = RECIPIENT_PLACEHOLDER;
        if (recipient == address(0)) {
            recipient = vm.envAddress("RECIPIENT");
        }

        // Get amount (placeholder with fallback to environment variable)
        uint256 amount = AMOUNT_PLACEHOLDER;
        if (amount == 0) {
            amount = vm.envUint("AMOUNT");
        }

        // Get token parameters (placeholders with fallback to environment variables)
        string memory tokenName = TOKEN_NAME_PLACEHOLDER;
        if (bytes(tokenName).length == 0) {
            try vm.envString("TOKEN_NAME") returns (string memory envName) {
                tokenName = envName;
            } catch {
                tokenName = "Mock Token";
            }
        }

        string memory tokenSymbol = TOKEN_SYMBOL_PLACEHOLDER;
        if (bytes(tokenSymbol).length == 0) {
            try vm.envString("TOKEN_SYMBOL") returns (string memory envSymbol) {
                tokenSymbol = envSymbol;
            } catch {
                tokenSymbol = "MOCK";
            }
        }

        uint8 tokenDecimals = TOKEN_DECIMALS_PLACEHOLDER;
        if (tokenDecimals == 0) {
            try vm.envUint("TOKEN_DECIMALS") returns (uint256 envDecimals) {
                tokenDecimals = uint8(envDecimals);
            } catch {
                tokenDecimals = 18;
            }
        }

        MockERC20 token;

        // Deploy token if no address provided
        if (tokenAddress == address(0)) {
            console2.log("Deploying new MockERC20 token...");
            console2.log("  Name:", tokenName);
            console2.log("  Symbol:", tokenSymbol);
            console2.log("  Decimals:", tokenDecimals);
            token = new MockERC20(tokenName, tokenSymbol, tokenDecimals);
            console2.log("Token deployed at:", address(token));
        } else {
            console2.log("Using existing token at:", tokenAddress);
            token = MockERC20(tokenAddress);
        }

        // Display token info
        console2.log("=== Token Info ===");
        console2.log("Token Address:", address(token));
        console2.log("Name:", token.name());
        console2.log("Symbol:", token.symbol());
        console2.log("Decimals:", token.decimals());
        console2.log("Recipient:", recipient);
        console2.log("Amount to mint:", amount);
        console2.log("Current Balance:", token.balanceOf(recipient));

        // Mint tokens
        console2.log("=== Minting Tokens ===");
        token.mint(recipient, amount);
        console2.log("Minted", amount, "tokens to", recipient);

        // Display final balance
        uint256 newBalance = token.balanceOf(recipient);
        console2.log("New Balance:", newBalance);
        console2.log("=== Minting Complete ===");

        vm.stopBroadcast();
    }
}

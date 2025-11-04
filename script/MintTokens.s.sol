// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { MockERC20 } from "../test/mocks/MockERC20.sol";

/**
 * @title MintTokens
 * @dev Script to mint USDC and WETH tokens to a specified address
 *
 * This script reads token addresses from deployed-addresses.json and mints
 * tokens to the address specified via the RECIPIENT environment variable.
 *
 * Prerequisites:
 * - Tokens must be deployed (run DeployAll.s.sol first)
 * - Set RECIPIENT environment variable to the target address
 * - Set MINT_AMOUNT_USDC and MINT_AMOUNT_WETH environment variables (optional)
 *
 * Usage:
 * export RECIPIENT=<target_address>
 * export MINT_AMOUNT_USDC=<amount_in_units>  # Optional, defaults to 1000000 (1 USDC)
 * export MINT_AMOUNT_WETH=<amount_in_units>  # Optional, defaults to 1000000000000000000 (1 WETH)
 * forge script script/MintTokens.s.sol:MintTokens --rpc-url <RPC_URL> --broadcast
 *
 * For local testing:
 * forge script script/MintTokens.s.sol:MintTokens --rpc-url http://localhost:8545 --broadcast
 */
contract MintTokens is Script {
    // Token contracts
    MockERC20 public usdcToken;
    MockERC20 public wethToken;

    // Configuration
    address public recipient;
    uint256 public usdcAmount;
    uint256 public wethAmount;

    function run() external {
        // Get the deployer's address and private key from environment
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        // Load configuration
        _loadConfiguration();

        console.log("============================================================");
        console.log("MINTING TOKENS TO RECIPIENT");
        console.log("============================================================");
        console.log("Deployer:", deployer);
        console.log("Recipient:", recipient);
        console.log("USDC Amount:", usdcAmount);
        console.log("WETH Amount:", wethAmount);
        console.log("");

        // Load token addresses from deployed-addresses.json
        _loadTokenAddresses();

        vm.startBroadcast(deployerPrivateKey);

        // Mint USDC tokens
        console.log("Minting USDC tokens...");
        usdcToken.mint(recipient, usdcAmount);
        console.log(unicode"✅ Minted", usdcAmount, "USDC to", recipient);

        // Mint WETH tokens
        console.log("Minting WETH tokens...");
        wethToken.mint(recipient, wethAmount);
        console.log(unicode"✅ Minted", wethAmount, "WETH to", recipient);

        vm.stopBroadcast();

        // Log final summary
        _logMintingSummary();
    }

    /**
     * @notice Load configuration from environment variables
     */
    function _loadConfiguration() internal {
        // Load recipient address
        recipient = 0xbe7dC5cC7977ac378ead410869D6c96f1E6C773e;

        // Load mint amounts (with defaults)
        try vm.envUint("MINT_AMOUNT_USDC") returns (uint256 amount) {
            usdcAmount = amount;
        } catch {
            // Default to 1 USDC (6 decimals)
            usdcAmount = 1_000_000_000_000_000_000_000;
            console.log("MINT_AMOUNT_USDC not set, using default: 1 USDC");
        }

        try vm.envUint("MINT_AMOUNT_WETH") returns (uint256 amount) {
            wethAmount = amount;
        } catch {
            // Default to 1 WETH (18 decimals)
            wethAmount = 0;
            console.log("MINT_AMOUNT_WETH not set, using default: 1 WETH");
        }
    }

    /**
     * @notice Load token addresses from environment variables or deployed-addresses.json
     */
    function _loadTokenAddresses() internal {
        // Try to load from environment variables first
        try vm.envAddress("USDC_TOKEN") returns (address usdcAddr) {
            usdcToken = MockERC20(usdcAddr);
            console.log("Using USDC token from environment variable:", usdcAddr);
        } catch {
            // Fallback to reading from deployed-addresses.json
            string memory root = vm.projectRoot();
            string memory path = string.concat(root, "/deployed-addresses.json");
            string memory json = vm.readFile(path);
            usdcToken = MockERC20(vm.parseJsonAddress(json, ".tokens.USDC.address"));
            console.log("Using USDC token from deployed-addresses.json:", address(usdcToken));
        }

        try vm.envAddress("WETH_TOKEN") returns (address wethAddr) {
            wethToken = MockERC20(wethAddr);
            console.log("Using WETH token from environment variable:", wethAddr);
        } catch {
            // Fallback to reading from deployed-addresses.json
            string memory root = vm.projectRoot();
            string memory path = string.concat(root, "/deployed-addresses.json");
            string memory json = vm.readFile(path);
            wethToken = MockERC20(vm.parseJsonAddress(json, ".tokens.WETH.address"));
            console.log("Using WETH token from deployed-addresses.json:", address(wethToken));
        }

        console.log("Loaded token addresses:");
        console.log("  USDC:", address(usdcToken));
        console.log("  WETH:", address(wethToken));
        console.log("");
    }

    /**
     * @notice Log minting summary
     */
    function _logMintingSummary() internal view {
        console.log("============================================================");
        console.log("MINTING COMPLETE!");
        console.log("============================================================");

        console.log(unicode"🪙  TOKENS MINTED:");
        console.log("   Recipient:", recipient);
        console.log("   USDC Amount:", usdcAmount);
        console.log("   WETH Amount:", wethAmount);
        console.log("");

        console.log(unicode"📊  TOKEN DETAILS:");
        console.log("   USDC Token:", address(usdcToken));
        console.log("     - Name:", usdcToken.name());
        console.log("     - Symbol:", usdcToken.symbol());
        console.log("     - Decimals:", usdcToken.decimals());
        console.log("     - Recipient Balance:", usdcToken.balanceOf(recipient));
        console.log("");
        console.log("   WETH Token:", address(wethToken));
        console.log("     - Name:", wethToken.name());
        console.log("     - Symbol:", wethToken.symbol());
        console.log("     - Decimals:", wethToken.decimals());
        console.log("     - Recipient Balance:", wethToken.balanceOf(recipient));
        console.log("");

        console.log("============================================================");
        console.log(unicode"Tokens successfully minted! 🎉");
        console.log("============================================================");
    }

    /**
     * @notice Helper function to verify the minting was successful
     */
    function verifyMinting() external view returns (bool) {
        if (address(usdcToken) == address(0) || address(wethToken) == address(0)) {
            console.log("ERROR: Token contracts not loaded");
            return false;
        }

        if (recipient == address(0)) {
            console.log("ERROR: Recipient address not set");
            return false;
        }

        uint256 usdcBalance = usdcToken.balanceOf(recipient);
        uint256 wethBalance = wethToken.balanceOf(recipient);

        if (usdcBalance < usdcAmount) {
            console.log("ERROR: USDC balance insufficient");
            console.log("  Expected:", usdcAmount);
            console.log("  Actual:", usdcBalance);
            return false;
        }

        if (wethBalance < wethAmount) {
            console.log("ERROR: WETH balance insufficient");
            console.log("  Expected:", wethAmount);
            console.log("  Actual:", wethBalance);
            return false;
        }

        console.log(unicode"✅ Token minting verified successfully");
        console.log("  USDC Balance:", usdcBalance);
        console.log("  WETH Balance:", wethBalance);
        return true;
    }

    /**
     * @notice Helper function to get token information
     */
    function getTokenInfo()
        external
        view
        returns (
            address _usdcToken,
            address _wethToken,
            string memory usdcName,
            string memory usdcSymbol,
            uint8 usdcDecimals,
            string memory wethName,
            string memory wethSymbol,
            uint8 wethDecimals
        )
    {
        return (
            address(usdcToken),
            address(wethToken),
            usdcToken.name(),
            usdcToken.symbol(),
            usdcToken.decimals(),
            wethToken.name(),
            wethToken.symbol(),
            wethToken.decimals()
        );
    }
}

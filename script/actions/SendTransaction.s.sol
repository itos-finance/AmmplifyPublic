// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/**
 * @title SendTransaction
 * @notice Script to send a transaction via prank
 * @dev Run with: forge script script/actions/SendTransaction.s.sol --broadcast --rpc-url <RPC_URL>
 */
contract SendTransaction is Script {
    // ============ CONFIGURATION - Set all variables here ============

    // Address to prank (the address that will send the transaction)
    address public constant PRANK_ADDRESS = address(0x4caBBFd5Cdd7eB034Ae4A8B74F7A045EaD0dAEf5);

    // Transaction target address
    address public constant TO_ADDRESS = address(0x5B5e9d616fAFCCC4865a6C29b6F89Ff3aAE7c892);

    // Transaction data
    bytes public constant TRANSACTION_DATA =
        hex"f46dcbe70000000000000000000000004cabbfd5cdd7eb034ae4a8b74f7a045ead0daef5000000000000000000000000659bd0bc4167ba25c62e05656f78043e7ed4a9dafffffffffffffffffffffffffffffffffffffffffffffffffffffffffffb34d0fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffb4484000000000000000000000000000000000000000000000000000001942c197a1f000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000001000276a3000000000000000000000000fffd8963efd1fc6a506488495d951d5263988d2600000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000000";

    // Token addresses to deal (set to address(0) to skip)
    address public constant TOKEN0 = address(0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A);
    address public constant TOKEN1 = address(0x754704Bc059F8C67012fEd69BC8A327a5aafb603);

    // Amounts to deal (in token's native decimals)
    uint256 public constant ETH_AMOUNT = 100 ether;
    uint256 public constant TOKEN0_AMOUNT = 1_000_000e18; // Adjust decimals as needed
    uint256 public constant TOKEN1_AMOUNT = 1_000_000e6; // Adjust decimals as needed (6 for USDC)

    function run() public {
        console2.log("=== Sending Transaction via Prank ===");
        console2.log("Prank address:", PRANK_ADDRESS);
        console2.log("To address:", TO_ADDRESS);
        console2.log("Transaction data length:", TRANSACTION_DATA.length);

        // Deal ETH to prank address
        console2.log("\n=== Dealing Tokens ===");
        vm.deal(PRANK_ADDRESS, ETH_AMOUNT);
        console2.log("Dealt ETH:", ETH_AMOUNT);

        // Deal tokens to prank address
        if (TOKEN0 != address(0)) {
            deal(TOKEN0, PRANK_ADDRESS, TOKEN0_AMOUNT);
            console2.log("Dealt TOKEN0:", TOKEN0_AMOUNT);
            console2.log("  Token0 address:", TOKEN0);
            console2.log("  Token0 balance:", IERC20(TOKEN0).balanceOf(PRANK_ADDRESS));
        }

        if (TOKEN1 != address(0)) {
            deal(TOKEN1, PRANK_ADDRESS, TOKEN1_AMOUNT);
            console2.log("Dealt TOKEN1:", TOKEN1_AMOUNT);
            console2.log("  Token1 address:", TOKEN1);
            console2.log("  Token1 balance:", IERC20(TOKEN1).balanceOf(PRANK_ADDRESS));
        }

        // Prank with the specified address
        vm.prank(PRANK_ADDRESS);

        // Send the transaction
        console2.log("\n=== Sending Transaction ===");
        (bool success, bytes memory returnData) = TO_ADDRESS.call(TRANSACTION_DATA);

        if (success) {
            console2.log("Transaction successful");
            if (returnData.length > 0) {
                console2.log("Return data length:", returnData.length);
            }
        } else {
            console2.log("Transaction failed");
            if (returnData.length > 0) {
                // Try to decode as a revert reason
                console2.log("Revert reason (if available):");
                console2.logBytes(returnData);
            }
            revert("Transaction call failed");
        }

        console2.log("\n=== Transaction Complete ===");
    }
}

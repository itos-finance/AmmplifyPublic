// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/**
 * @notice WMON interface - simple wrapper contract
 */
interface IWMON {
    function deposit() external payable;
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title DepositAndSendWMON
 * @notice Simple script to deposit native MON to WMON and send it to a recipient
 */
contract DepositAndSendWMON is Script {
    // WMON contract address (Wrapped MON)
    address public constant WMON = 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A;

    function run() public {
        // Get deployer private key
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Get recipient address from environment
        address recipient = 0x590F6252Ec23e47abdDF0643d04aCE057d755363; // vm.envAddress("RECIPIENT_ADDRESS");

        // Get amount to wrap from environment (defaults to 2 MON)
        uint256 depositAmount = vm.envOr("DEPOSIT_AMOUNT", uint256(2e18));

        vm.startBroadcast(deployerPrivateKey);

        console2.log("=== Deposit and Send WMON ===");
        console2.log("Deployer:", deployer);
        console2.log("Recipient:", recipient);
        console2.log("WMON Address:", WMON);
        console2.log("Deposit Amount:", depositAmount);

        // Step 1: Check balances before
        console2.log("\n--- Balances Before ---");
        uint256 nativeBalanceBefore = deployer.balance;
        uint256 wmonBalanceBefore = IWMON(WMON).balanceOf(deployer);
        uint256 recipientBalanceBefore = IWMON(WMON).balanceOf(recipient);
        console2.log("Deployer native MON balance:", nativeBalanceBefore);
        console2.log("Deployer WMON balance:", wmonBalanceBefore);
        console2.log("Recipient WMON balance:", recipientBalanceBefore);

        // Step 2: Deposit native MON to get WMON
        console2.log("\n--- Step 1: Depositing MON to WMON ---");
        IWMON(WMON).deposit{ value: depositAmount }();

        uint256 wmonBalanceAfter = IWMON(WMON).balanceOf(deployer);
        uint256 wmonReceived = wmonBalanceAfter - wmonBalanceBefore;
        console2.log("Deployer WMON balance after deposit:", wmonBalanceAfter);
        console2.log("WMON received:", wmonReceived);

        // Step 3: Send WMON to recipient
        console2.log("\n--- Step 2: Sending WMON to Recipient ---");
        IERC20(WMON).transfer(recipient, wmonReceived);
        console2.log("Transferred", wmonReceived, "WMON to recipient");

        // Step 4: Verify final balances
        console2.log("\n--- Final Balances ---");
        uint256 deployerFinalBalance = IWMON(WMON).balanceOf(deployer);
        uint256 recipientFinalBalance = IWMON(WMON).balanceOf(recipient);
        console2.log("Deployer WMON balance:", deployerFinalBalance);
        console2.log("Recipient WMON balance:", recipientFinalBalance);
        console2.log("Recipient received:", recipientFinalBalance - recipientBalanceBefore);

        vm.stopBroadcast();
    }
}

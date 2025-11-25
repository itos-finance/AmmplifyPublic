// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/console2.sol";
import { AmmplifyPositions } from "../AmmplifyPositions.s.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/**
 * @title OpenTaker
 * @notice Example script to open a taker position
 * @dev Run with: forge script script/actions/OpenTaker.s.sol --broadcast --rpc-url <RPC_URL>
 * @dev NOTE: Taker positions require admin rights (TAKER role)
 */
contract OpenTaker is AmmplifyPositions {
    function run() public override {
        // Load deployer addresses from .env file
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console2.log("=== Opening Taker Position ===");
        console2.log("Deployer address:", deployer);
        console2.log("WARNING: This requires TAKER admin rights!");

        // Get current pool state
        printPoolState(env.usdcWethPool);

        // Fund the account with tokens (if using mock tokens)
        fundAccount(deployer, type(uint128).max, type(uint128).max);

        // Create taker parameters
        TakerParams memory params = getDefaultTakerParams(deployer);

        // Adjust parameters for a wider range
        params.ticks[0] = getValidTick(-300, 3000); // Lower tick
        params.ticks[1] = getValidTick(300, 3000); // Upper tick
        // params.ticks[0] = -491520; // getValidTick(-300, 3000); // Lower tick
        // params.ticks[1] = 491520; // getValidTick(0, 3000); // Upper tick
        params.liquidity = 3.34e15; // Well above minimum taker liquidity (1e12)

        console2.log("=== Taker Parameters ===");
        console2.log("Recipient:", params.recipient);
        console2.log("Pool:", params.poolAddr);
        console2.log("Low Tick:", params.ticks[0]);
        console2.log("High Tick:", params.ticks[1]);
        console2.log("Liquidity:", params.liquidity);
        console2.log("Vault Indices:", params.vaultIndices[0], params.vaultIndices[1]);
        console2.log("Freeze Price:", params.freezeSqrtPriceX96);

        // Collateralize the taker position before creating it
        collateralizeTaker(deployer, 10000000000e6, 2000000000000e18, params.poolAddr);

        // Set up token approvals for diamond contract
        setupApprovals(type(uint256).max);

        // Open the taker position
        uint256 assetId = openTaker(params);

        console2.log("=== Taker Position Created Successfully ===");
        console2.log("Asset ID:", assetId);

        // Check balances after
        uint256 usdcBalance = IERC20(env.usdcToken).balanceOf(deployer);
        uint256 wethBalance = IERC20(env.wethToken).balanceOf(deployer);

        console2.log("=== Final Balances ===");
        console2.log("USDC Balance:", usdcBalance);
        console2.log("WETH Balance:", wethBalance);

        vm.stopBroadcast();
    }
}

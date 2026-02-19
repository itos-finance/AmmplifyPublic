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

        address pool = getPoolAddress("USDC_WETH_3000");

        // Get current pool state
        printPoolState(pool);

        // Fund the account with tokens (if using mock tokens)
        fundAccount(deployer, type(uint128).max, type(uint128).max, pool);

        // Create taker parameters
        TakerParams memory params = TakerParams({
            recipient: deployer,
            poolAddr: pool,
            ticks: [getValidTick(-300, 3000), getValidTick(300, 3000)],
            liquidity: 3.34e15,
            vaultIndices: [0, 0],
            sqrtPriceLimitsX96: [MIN_SQRT_RATIO, MAX_SQRT_RATIO],
            freezeSqrtPriceX96: MIN_SQRT_RATIO,
            rftData: ""
        });

        console2.log("=== Taker Parameters ===");
        console2.log("Recipient:", params.recipient);
        console2.log("Pool:", params.poolAddr);
        console2.log("Low Tick:", params.ticks[0]);
        console2.log("High Tick:", params.ticks[1]);
        console2.log("Liquidity:", params.liquidity);
        console2.log("Vault Indices:", params.vaultIndices[0], params.vaultIndices[1]);
        console2.log("Freeze Price:", params.freezeSqrtPriceX96);

        // Collateralize the taker position before creating it
        collateralizeTaker(deployer, 10000000000e6, 2000000000000e18, pool);

        // Set up token approvals for diamond contract
        address[] memory tokens = new address[](2);
        tokens[0] = getToken0(pool);
        tokens[1] = getToken1(pool);
        address[] memory spenders = new address[](1);
        spenders[0] = env.diamond;
        setupApprovals(tokens, spenders, type(uint256).max);

        // Open the taker position
        uint256 assetId = openTaker(params);

        console2.log("=== Taker Position Created Successfully ===");
        console2.log("Asset ID:", assetId);

        // Check balances after
        uint256 usdcBalance = IERC20(getTokenAddress("USDC")).balanceOf(deployer);
        uint256 wethBalance = IERC20(getTokenAddress("WETH")).balanceOf(deployer);

        console2.log("=== Final Balances ===");
        console2.log("USDC Balance:", usdcBalance);
        console2.log("WETH Balance:", wethBalance);

        vm.stopBroadcast();
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { UniV4PositionOpener } from "../src/integrations/UniV4PositionOpener.sol";
import { IPoolManager } from "v4-core/interfaces/IPoolManager.sol";
import { IPositionManager } from "v4-periphery/interfaces/IPositionManager.sol";
import { IAllowanceTransfer } from "permit2/src/interfaces/IAllowanceTransfer.sol";

/**
 * @title DeployUniV4PositionOpener
 * @dev Deploys the UniV4PositionOpener contract
 *
 * Environment variables:
 *   DEPLOYER_PUBLIC_KEY  - Deployer address
 *   DEPLOYER_PRIVATE_KEY - Deployer private key
 *   POOL_MANAGER         - Uniswap V4 PoolManager address
 *   POSITION_MANAGER     - Uniswap V4 PositionManager address
 *   PERMIT2              - Permit2 address (defaults to canonical 0x000000000022D473030F116dDEE9F6B43aC78BA3)
 *
 * Usage:
 *   POOL_MANAGER=0x... POSITION_MANAGER=0x... \
 *     forge script script/DeployUniV4PositionOpener.s.sol --rpc-url <RPC_URL> --broadcast
 */
contract DeployUniV4PositionOpener is Script {
    address constant PERMIT2_CANONICAL = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    UniV4PositionOpener public opener;

    function run() external {
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        address poolManagerAddr = vm.envAddress("POOL_MANAGER");
        address posmAddr = vm.envAddress("POSITION_MANAGER");

        address permit2Addr;
        try vm.envAddress("PERMIT2") returns (address addr) {
            permit2Addr = addr;
        } catch {
            permit2Addr = PERMIT2_CANONICAL;
        }

        console.log("Deployer:", deployer);
        console.log("PoolManager:", poolManagerAddr);
        console.log("PositionManager:", posmAddr);
        console.log("Permit2:", permit2Addr);

        vm.startBroadcast(deployerPrivateKey);
        opener = new UniV4PositionOpener(
            IPoolManager(poolManagerAddr),
            IPositionManager(posmAddr),
            IAllowanceTransfer(permit2Addr)
        );
        vm.stopBroadcast();

        console.log("UniV4PositionOpener deployed at:", address(opener));
    }
}

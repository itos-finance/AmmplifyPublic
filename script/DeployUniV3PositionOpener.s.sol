// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { UniV3PositionOpener } from "../src/integrations/UniV3PositionOpener.sol";

/**
 * @title DeployUniV3PositionOpener
 * @dev Deploys the UniV3PositionOpener contract
 *
 * Environment variables:
 *   DEPLOYER_PUBLIC_KEY  - Deployer address
 *   DEPLOYER_PRIVATE_KEY - Deployer private key
 *   NFPM                 - Uniswap V3 NonfungiblePositionManager address
 *
 * The script also checks ./addresses/<protocol>.json for the NFPM address as a fallback.
 *
 * Usage:
 *   NFPM=0x... forge script script/DeployUniV3PositionOpener.s.sol --rpc-url <RPC_URL> --broadcast
 */
contract DeployUniV3PositionOpener is Script {
    UniV3PositionOpener public opener;

    function run() external {
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        address nfpmAddr = _loadNfpm();
        require(nfpmAddr != address(0), "NFPM address required");

        console.log("Deployer:", deployer);
        console.log("NFPM:", nfpmAddr);

        vm.startBroadcast(deployerPrivateKey);
        opener = new UniV3PositionOpener(nfpmAddr);
        vm.stopBroadcast();

        console.log("UniV3PositionOpener deployed at:", address(opener));
    }

    function _loadNfpm() internal view returns (address) {
        try vm.envAddress("NFPM") returns (address addr) {
            return addr;
        } catch {}

        string memory protocol = vm.envOr("AMMPLIFY_PROTOCOL", string("uniswapv3"));
        string memory addrPath = string.concat("./addresses/", protocol, ".json");
        try vm.readFile(addrPath) returns (string memory jsonData) {
            try vm.parseJsonAddress(jsonData, ".nfpm") returns (address addr) {
                return addr;
            } catch {}
        } catch {}

        return address(0);
    }
}

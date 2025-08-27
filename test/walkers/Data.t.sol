// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { Data, DataImpl } from "../../src/walkers/Data.sol";
import { Key } from "../../src/tree/Key.sol";
import { PoolInfo, PoolLib } from "../../src/Pool.sol";
import { UniV3IntegrationSetup } from "../UniV3.u.sol";
import { Asset, AssetLib } from "../../src/Asset.sol";

contract DataTest is Test, UniV3IntegrationSetup {
    function setUp() public {
        setUpPool(500); // For a tick spacing of 10.
    }

    function testMake() public {
        PoolInfo memory pInfo = PoolLib.getPoolInfo(pools[0]);
        (Asset storage asset, uint256 assetId) = AssetLib.newMaker(msg.sender, pInfo, -100, 100, 1e24, true);
    }
}

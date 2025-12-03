// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { console2 as console } from "forge-std/console2.sol";
import { ViewDataImpl, ViewData, ViewWalker } from "../../src/walkers/View.sol";
import { Data, DataImpl } from "../../src/walkers/Data.sol";
import { Key, KeyImpl } from "../../src/tree/Key.sol";
import { Pool, PoolInfo, PoolLib } from "../../src/Pool.sol";
import { FeeLib } from "../../src/Fee.sol";
import { Asset, AssetLib } from "../../src/Asset.sol";
import { UniV3IntegrationSetup } from "../UniV3.u.sol";
import { Asset, AssetLib } from "../../src/Asset.sol";

contract ViewWalkerTest is Test, UniV3IntegrationSetup {
    function setUp() public {
        setUpPool(500); // For a tick spacing of 10.
        FeeLib.init();
    }

    function testMakerSwapMatch() public {
        PoolInfo memory pInfo = PoolLib.getPoolInfo(pools[0]);
        (Asset storage asset, ) = AssetLib.newMaker(msg.sender, pInfo, -100, 100, 1e24, true);
        Data memory data = DataImpl.make(pInfo, asset, 0, type(uint160).max, 1);
    }

    function testMakerTakerMatch() public {}

    function testMakerMatch() public {}
}

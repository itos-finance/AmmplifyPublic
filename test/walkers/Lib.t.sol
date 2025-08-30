// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { console2 as console } from "forge-std/console2.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { Data, DataImpl } from "../../src/walkers/Data.sol";
import { Pool, PoolInfo, PoolLib } from "../../src/Pool.sol";
import { UniV3IntegrationSetup } from "../UniV3.u.sol";
import { Asset, AssetLib } from "../../src/Asset.sol";
import { TreeTickLib } from "../../src/tree/Tick.sol";
import { WalkerLib } from "../../src/walkers/Lib.sol";
import { FeeLib } from "../../src/Fee.sol";

contract WalkerLibTest is Test, UniV3IntegrationSetup {
    function setUp() public {
        setUpPool(500); // For a tick spacing of 10.

        MockERC20(poolToken0s[0]).mint(address(this), 1e24);
        MockERC20(poolToken0s[1]).mint(address(this), 1e24);
    }

    function testWalks() public {
        FeeLib.init();
        // Generic data setup.
        PoolInfo memory pInfo = PoolLib.getPoolInfo(pools[0]);
        // compounding
        (Asset storage asset, ) = AssetLib.newMaker(msg.sender, pInfo, -100, 100, 1e24, true);
        Data memory data = DataImpl.make(pInfo, asset, 0, type(uint160).max, 1e24);
        WalkerLib.modify(pInfo, -100, 100, data);

        // non-compounding
        (asset, ) = AssetLib.newMaker(msg.sender, pInfo, -100, 100, 1e24, false);
        data = DataImpl.make(pInfo, asset, 0, type(uint160).max, 1e24);
        WalkerLib.modify(pInfo, -100, 100, data);

        // taker
        (asset, ) = AssetLib.newTaker(msg.sender, pInfo, -50, 50, 1e24, 0, 0);
        data = DataImpl.make(pInfo, asset, 0, type(uint160).max, 1e23);
        WalkerLib.modify(pInfo, -50, 50, data);
    }
}

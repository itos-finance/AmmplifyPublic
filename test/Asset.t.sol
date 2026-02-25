// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";

import { Asset, AssetStore, AssetLib } from "../src/Asset.sol";
import { PoolInfo } from "../src/Pool.sol";
import { Store } from "../src/Store.sol";
import { LiqType } from "../src/walkers/Liq.sol";

contract AssetTest is Test {
    function testNewMaker() public {
        assertEq(Store.assets().lastAssetId, 0, "AssetStore.lastAssetId.default");

        address owner = makeAddr("cOwner");
        AssetLib.addPermission(owner, msg.sender);

        // create first maker
        PoolInfo memory pInfo1;
        pInfo1.poolAddr = makeAddr("pool1");

        vm.warp(100);

        (Asset storage asset1, uint256 assetId1) = AssetLib.newMaker(owner, pInfo1, -2000, 2000, 1e20);

        assertEq(assetId1, 1, "assetId1");

        assertEq(asset1.owner, owner, "asset1.owner");
        assertEq(asset1.poolAddr, pInfo1.poolAddr, "asset1.poolAddr");
        assertEq(asset1.lowTick, -2000, "asset1.lowTick");
        assertEq(asset1.highTick, 2000, "asset1.highTick");
        assertEq(uint8(asset1.liqType), uint8(LiqType.MAKER), "asset1.liqType");
        assertEq(asset1.liq, 1e20, "asset1.liq");
        assertEq(asset1.timestamp, 100, "asset1.timestamp");

        // confirm in store
        Asset storage storedAsset = Store.assets().assets[assetId1];
        assertEq(storedAsset.owner, asset1.owner, "storedAsset1.owner");
        assertEq(storedAsset.poolAddr, asset1.poolAddr, "storedAsset1.poolAddr");
        assertEq(storedAsset.lowTick, asset1.lowTick, "storedAsset1.lowTick");
        assertEq(storedAsset.highTick, asset1.highTick, "storedAsset1.highTick");
        assertEq(uint8(storedAsset.liqType), uint8(asset1.liqType), "storedAsset1.liqType");
        assertEq(storedAsset.liq, asset1.liq, "storedAsset1.liq");
        assertEq(storedAsset.timestamp, asset1.timestamp, "storedAsset1.timestamp");

        // create second maker
        PoolInfo memory pInfo2;
        pInfo2.poolAddr = makeAddr("pool2");

        vm.warp(200);

        (Asset storage asset2, uint256 assetId2) = AssetLib.newMaker(owner, pInfo2, -3000, 4000, 2e21);
        assertEq(assetId2, 2, "assetId2");

        assertEq(asset2.owner, owner, "asset2.owner");
        assertEq(asset2.poolAddr, pInfo2.poolAddr, "asset2.poolAddr");
        assertEq(asset2.lowTick, -3000, "asset2.lowTick");
        assertEq(asset2.highTick, 4000, "asset2.highTick");
        assertEq(uint8(asset2.liqType), uint8(LiqType.MAKER), "asset2.liqType");
        assertEq(asset2.liq, 2e21, "asset2.liq");
        assertEq(asset2.timestamp, 200, "asset2.timestamp");

        // confirm in store
        Asset storage storedAsset2 = Store.assets().assets[assetId2];
        assertEq(storedAsset2.owner, asset2.owner, "storedAsset2.owner");
        assertEq(storedAsset2.poolAddr, asset2.poolAddr, "storedAsset2.poolAddr");
        assertEq(storedAsset2.lowTick, asset2.lowTick, "storedAsset2.lowTick");
        assertEq(storedAsset2.highTick, asset2.highTick, "storedAsset2.highTick");
        assertEq(uint8(storedAsset2.liqType), uint8(asset2.liqType), "storedAsset2.liqType");
        assertEq(storedAsset2.liq, asset2.liq, "storedAsset2.liq");
        assertEq(storedAsset2.timestamp, asset2.timestamp, "storedAsset2.timestamp");

        // confirm ownership in store (addAssetToOwner)
        uint256[] storage ownerAssets = Store.assets().ownerAssets[owner];
        assertEq(ownerAssets.length, 2, "ownerAssets.length");
        assertEq(ownerAssets[0], assetId1, "ownerAssets[0]");
        assertEq(ownerAssets[1], assetId2, "ownerAssets[1]");
    }

    function testNewTaker() public {
        assertEq(Store.assets().lastAssetId, 0, "AssetStore.lastAssetId.default");

        address owner = makeAddr("owner");
        AssetLib.addPermission(owner, msg.sender);

        PoolInfo memory pInfo;
        pInfo.poolAddr = makeAddr("pool");

        // create taker
        vm.warp(100);
        (Asset storage taker, uint256 takerId) = AssetLib.newTaker(owner, pInfo, -2000, 2000, 1e20, 2, 3);

        assertEq(takerId, 1, "takerId");

        assertEq(taker.owner, owner, "taker.owner");
        assertEq(taker.poolAddr, pInfo.poolAddr, "taker.poolAddr");
        assertEq(taker.lowTick, -2000, "taker.lowTick");
        assertEq(taker.highTick, 2000, "taker.highTick");
        assertEq(uint8(taker.liqType), uint8(LiqType.TAKER), "taker.liqType");
        assertEq(taker.liq, 1e20, "taker.liq");
        assertEq(taker.xVaultIndex, 2, "taker.xVaultIndex");
        assertEq(taker.yVaultIndex, 3, "taker.yVaultIndex");
        assertEq(taker.timestamp, 100, "taker.timestamp");

        // confirm in store
        Asset storage storedTaker = Store.assets().assets[takerId];
        assertEq(storedTaker.owner, taker.owner, "storedTaker.owner");
        assertEq(storedTaker.poolAddr, taker.poolAddr, "storedTaker.poolAddr");
        assertEq(storedTaker.lowTick, taker.lowTick, "storedTaker.lowTick");
        assertEq(storedTaker.highTick, taker.highTick, "storedTaker.highTick");
        assertEq(uint8(storedTaker.liqType), uint8(taker.liqType), "storedTaker.liqType");
        assertEq(storedTaker.liq, taker.liq, "storedTaker.liq");
        assertEq(storedTaker.xVaultIndex, taker.xVaultIndex, "storedTaker.xVaultIndex");
        assertEq(storedTaker.yVaultIndex, taker.yVaultIndex, "storedTaker.yVaultIndex");
        assertEq(storedTaker.timestamp, taker.timestamp, "storedTaker.timestamp");

        // add another taker
        (, uint256 takerId2) = AssetLib.newTaker(owner, pInfo, -2000, 2000, 1e20, 2, 3);

        // confirm ownership in store (addAssetToOwner)
        uint256[] storage ownerAssets = Store.assets().ownerAssets[owner];
        assertEq(ownerAssets.length, 2, "ownerAssets.length");
        assertEq(ownerAssets[0], takerId, "ownerAssets[0].taker1");
        assertEq(ownerAssets[1], takerId2, "ownerAssets[1].taker2");
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testRevertNewTakerNoRecipient() public {
        PoolInfo memory pInfo;
        pInfo.poolAddr = makeAddr("pool");

        vm.expectRevert(abi.encodeWithSelector(AssetLib.NoRecipient.selector));
        AssetLib.newTaker(address(0x0), pInfo, -2000, -2000, 1e20, 0, 1);
    }

    function testGetAsset() public {
        address owner = makeAddr("owner");
        AssetLib.addPermission(owner, msg.sender);

        PoolInfo memory pInfo;
        pInfo.poolAddr = makeAddr("pool");

        // maker
        (Asset storage maker, uint256 makerId) = AssetLib.newMaker(owner, pInfo, -2000, 2000, 1e20);

        Asset storage gMaker = AssetLib.getAsset(makerId);
        assertEq(gMaker.owner, maker.owner, "gMaker.owner");
        assertEq(gMaker.poolAddr, maker.poolAddr, "gMaker.poolAddr");
        assertEq(gMaker.lowTick, maker.lowTick, "gMaker.lowTick");
        assertEq(gMaker.highTick, maker.highTick, "gMaker.highTick");
        assertEq(uint8(gMaker.liqType), uint8(maker.liqType), "gMaker.liqType");
        assertEq(gMaker.liq, maker.liq, "gMaker.liq");
        assertEq(gMaker.timestamp, maker.timestamp, "gMaker.timestamp");

        // taker
        (Asset storage taker, uint256 takerId) = AssetLib.newMaker(owner, pInfo, -2000, 2000, 1e20);

        Asset storage gTaker = AssetLib.getAsset(takerId);
        assertEq(gTaker.owner, taker.owner, "gTaker.owner");
        assertEq(gTaker.poolAddr, taker.poolAddr, "gTaker.poolAddr");
        assertEq(gTaker.lowTick, taker.lowTick, "gTaker.lowTick");
        assertEq(gTaker.highTick, taker.highTick, "gTaker.highTick");
        assertEq(uint8(gTaker.liqType), uint8(taker.liqType), "gTaker.liqType");
        assertEq(gTaker.liq, taker.liq, "gTaker.liq");
        assertEq(gTaker.xVaultIndex, taker.xVaultIndex, "gTaker.xVaultIndex");
        assertEq(gTaker.yVaultIndex, taker.yVaultIndex, "gTaker.yVaultIndex");
        assertEq(gTaker.timestamp, taker.timestamp, "gTaker.timestamp");
    }

    function testRemoveAsset() public {
        address owner = makeAddr("owner");
        AssetLib.addPermission(owner, msg.sender);

        PoolInfo memory pInfo;
        pInfo.poolAddr = makeAddr("pool");

        (, uint256 assetId1) = AssetLib.newMaker(owner, pInfo, -2000, 2000, 1e20);
        (, uint256 assetId2) = AssetLib.newMaker(owner, pInfo, -2000, 2000, 1e20);
        (, uint256 assetId3) = AssetLib.newMaker(owner, pInfo, -2000, 2000, 1e20);

        // Remove middle
        AssetLib.removeAsset(assetId2);

        uint256[] storage ownerAssets = Store.assets().ownerAssets[owner];
        assertEq(ownerAssets.length, 2, "ownerAssets.length");
        assertEq(ownerAssets[0], assetId1, "ownerAssets[0].assetId1");
        assertEq(ownerAssets[1], assetId3, "ownerAssets[1].assetId3");

        // Remove end
        AssetLib.removeAsset(assetId3);

        ownerAssets = Store.assets().ownerAssets[owner];
        assertEq(ownerAssets.length, 1, "ownerAssets.length");
        assertEq(ownerAssets[0], assetId1, "ownerAssets[0].assetId1");

        // Remove first
        AssetLib.removeAsset(assetId1);

        ownerAssets = Store.assets().ownerAssets[owner];
        assertEq(ownerAssets.length, 0, "ownerAssets.length");
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testRevertRemoveAssetNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(AssetLib.AssetNotFound.selector, 0));
        AssetLib.removeAsset(0);
    }

    function testUpdateTimestamp() public {
        // Fake an asset.
        Store.assets().assets[0].owner = address(this);
        // Check its default timestamp.
        Asset storage asset = AssetLib.getAsset(0);
        assertEq(asset.timestamp, 0, "asset.timestamp.default");

        vm.warp(100);
        AssetLib.updateTimestamp(asset);
        assertEq(asset.timestamp, 100, "asset.timestamp.updated1");

        vm.warp(200);
        AssetLib.updateTimestamp(asset);
        assertEq(asset.timestamp, 200, "asset.timestamp.updated2");
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testPermissions() public {
        address owner = makeAddr("owner");

        PoolInfo memory pInfo;
        pInfo.poolAddr = makeAddr("pool");

        // maker
        assertFalse(AssetLib.viewPermission(owner, msg.sender));
        vm.expectRevert(abi.encodeWithSelector(AssetLib.NotPermissioned.selector, owner, msg.sender));
        AssetLib.newMaker(owner, pInfo, -2000, 2000, 1e20);

        // Add permission.
        AssetLib.addPermission(owner, msg.sender);
        assertTrue(AssetLib.viewPermission(owner, msg.sender));
        AssetLib.newMaker(owner, pInfo, -2000, 2000, 1e20);

        // Remove permission
        AssetLib.removePermission(owner, msg.sender);
        assertFalse(AssetLib.viewPermission(owner, msg.sender));
        vm.expectRevert(abi.encodeWithSelector(AssetLib.NotPermissioned.selector, owner, msg.sender));
        AssetLib.newMaker(owner, pInfo, -2000, 2000, 1e20);

        // Add permissioned opener.
        AssetLib.addPermissionedOpener(msg.sender);
        assertTrue(AssetLib.viewPermission(owner, msg.sender));
        AssetLib.newMaker(owner, pInfo, -2000, 2000, 1e20);

        // Remove permissioned opener.
        AssetLib.removePermissionedOpener(msg.sender);
        assertFalse(AssetLib.viewPermission(owner, msg.sender));
        vm.expectRevert(abi.encodeWithSelector(AssetLib.NotPermissioned.selector, owner, msg.sender));
        AssetLib.newMaker(owner, pInfo, -2000, 2000, 1e20);

        // But we can always open for ourselves.
        AssetLib.newMaker(msg.sender, pInfo, -2000, 2000, 1e20);
    }
}

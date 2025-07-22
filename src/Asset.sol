// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { PoolInfo, PoolLib, Pool } from "./Pool.sol";
import { Key } from "./tree/Key.sol";
import { LiqType } from "./visitors/Data.sol";

struct Asset {
    address owner;
    /* Position summary */
    int24 lowTick;
    int24 highTick;
    LiqType liqType;
    int128 liq;
    /* pool info */
    address poolAddr;
    uint256 baseFeeGrowthInside0X128;
    uint256 baseFeeGrowthInside1X128;
    /* node info */
    mapping(Key => NodeAsset) nodes;
}

struct NodeAsset {
    uint128 sliq; // The share/liq of the node we own.
    // For takers, this is a checkpoint of the per liq fees owed.
    // For NC makers, this is a checkpoint of the per liq fees earned.
    // For C makers, this is not used.
    uint256 fee0CheckX128;
    uint256 fee1CheckX128;
}

struct AssetStore {
    mapping(address owner => uint256[] assetIds) ownerAssets;
    mapping(uint256 assetId => Asset) assets;
    uint256 nextAssetId;
}

library AssetLib {
    function newMaker(
        address recipient,
        PoolInfo memory pInfo,
        int24 lowTick,
        int24 highTick,
        int128 liq,
        bool isCompounding
    ) internal returns (Asset storage asset, uint256 assetId) {
        AssetStore storage store = Store.assets();
        assetId = store.nextAssetId++;
        asset = store.assets[assetId];
        asset.owner = recipient;
        asset.lowTick = lowTick;
        asset.highTick = highTick;
        asset.liqType = isCompounding ? LiqType.MAKER : LiqType.MAKER_NC;
        asset.liq = liq;
        asset.poolAddr = pInfo.poolAddr;
        (asset.baseFeeGrowthInside0X128, asset.baseFeeGrowthInside1X128) = PoolLib.getInsideFees(
            pInfo.poolAddr,
            lowTick,
            highTick
        );
        // The Nodes are to be filled in by a walker.
    }

    function newTaker(
        address recipient,
        PoolInfo memory pInfo,
        int24 lowTick,
        int24 highTick,
        int128 liq,
        uint8 xVaultIndex,
        uint8 yVaultIndex
    ) internal returns (Asset storage asset, uint256 assetId) {
        AssetStore storage store = Store.assets();
        assetId = store.nextAssetId++;
        asset = store.assets[assetId];
        asset.owner = recipient;
        asset.lowTick = lowTick;
        asset.highTick = highTick;
        asset.liqType = LiqType.TAKER;
        asset.liq = liq;
        asset.poolAddr = pInfo.poolAddr;
        (asset.baseFeeGrowthInside0X128, asset.baseFeeGrowthInside1X128) = PoolLib.getInsideFees(
            pInfo.poolAddr,
            lowTick,
            highTick
        );
        // The Nodes are to be filled in by a walker.
    }

    function getAsset(uint256 assetId) internal view returns (Asset storage asset) {
        AssetStore storage store = Store.assets();
        asset = store.assets[assetId];
    }

    function removeAsset(uint256 assetId, PoolInfo memory pInfo) internal {
        AssetStore storage store = Store.assets();
        asset = store.assets[assetId];
        // We make sure the tree ticks are inclusive.
        uint24 lowIndex = pInfo.treeTick(asset.lowTick);
        uint24 highIndex = pInfo.treeTick(asset.highTick) - 1;
        Key[] memory keys = Route.getKeys(asset.lowTick, asset.highTick);
        for (uint256 i = 0; i < keys.length; i++) {
            Key key = keys[i];
            delete asset.nodes[key];
        }
        delete store.assets[assetId];
    }
}

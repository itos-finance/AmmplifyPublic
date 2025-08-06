// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { PoolInfo, PoolLib } from "./Pool.sol";
import { Key } from "./tree/Key.sol";
import { LiqType } from "./walkers/Liq.sol";

struct Asset {
    address owner;
    /* pool info */
    address poolAddr;
    /* Position summary */
    int24 lowTick;
    int24 highTick;
    LiqType liqType;
    uint128 liq; // The original liquidity of the asset.
    /* node info */
    mapping(Key => NodeAsset) nodes;
}

struct NodeAsset {
    uint128 sliq; // The share/liq of the node we own.
    // For takers, this is a checkpoint of the per liq fees owed.
    // For NC makers, this is a checkpoint of the per liq fees earned.
    // For C makers, this is not used.
    // These checkpoints include both the swap fees and the reservation fees.
    uint256 fee0CheckX128;
    uint256 fee1CheckX128;
}

struct AssetStore {
    mapping(address owner => uint256[] assetIds) ownerAssets;
    mapping(uint256 assetId => Asset) assets;
    uint256 nextAssetId;
}

library AssetLib {
    // We limit the number of assets per owner to prevent someone from blocking removes by overloading gas
    // costs by donating positions to other users.
    uint8 public constant MAX_ASSETS_PER_OWNER = 16;

    error ExcessiveAssetsPerOwner(uint256 count);
    error AssetNotFound(uint256 assetId, address owner);

    /// Create a new maker asset.
    function newMaker(
        address recipient,
        PoolInfo memory pInfo,
        int24 lowTick,
        int24 highTick,
        uint128 liq,
        bool isCompounding
    ) internal returns (Asset storage asset, uint256 assetId) {
        AssetStore storage store = Store.assets();
        assetId = store.nextAssetId++;
        asset = store.assets[assetId];
        asset.owner = recipient;
        asset.poolAddr = pInfo.poolAddr;
        asset.lowTick = lowTick;
        asset.highTick = highTick;
        asset.liqType = isCompounding ? LiqType.MAKER : LiqType.MAKER_NC;
        asset.liq = liq;
        // The Nodes are to be filled in by a walker.
        // Add the asset to the owner's bookkeeping.
        addAssetToOwner(store, assetId, recipient);
    }

    /// Create a new taker asset.
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
        addAssetToOwner(store, assetId, recipient);
    }

    /// Fetch an asset by ID (typically for viewing).
    function getAsset(uint256 assetId) internal view returns (Asset storage asset) {
        AssetStore storage store = Store.assets();
        asset = store.assets[assetId];
    }

    /// Remove an asset.
    function removeAsset(uint256 assetId, PoolInfo memory pInfo) internal {
        AssetStore storage store = Store.assets();
        asset = store.assets[assetId];
        address owner = asset.owner;
        // The asset nodes will have been removed by the walker.
        delete store.assets[assetId];
        uint256[] storage ownerAssets = store.ownerAssets[owner];
        bool found = false;
        for (uint8 i = 0; i < ownerAssets.length; i++) {
            if (ownerAssets[i] == assetId) {
                ownerAssets[i] = ownerAssets[ownerAssets.length - 1];
                ownerAssets.pop();
                found = true;
                break;
            }
        }
        require(found, AssetNotFound(assetId, owner));
    }

    /* Helpers */

    function addAssetToOwner(AssetStore storage store, uint256 assetId, address owner) private {
        require(
            store.ownerAssets[owner].length < MAX_ASSETS_PER_OWNER,
            ExcessiveAssetsPerOwner(store.ownerAssets[owner].length)
        );
        store.ownerAssets[owner].push(assetId);
    }
}

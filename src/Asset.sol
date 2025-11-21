// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { PoolInfo, PoolLib } from "./Pool.sol";
import { Key } from "./tree/Key.sol";
import { LiqType } from "./walkers/Liq.sol";
import { Store } from "./Store.sol";

struct Asset {
    address owner;
    // This is not consistent as it may change whenever an asset for the owner is removed.
    uint96 assetIdx;
    /* pool info */
    address poolAddr;
    /* Position summary */
    int24 lowTick;
    int24 highTick;
    LiqType liqType;
    /* For Takers */
    bool takeAsX; // If the asset is a taker, are we borrowing as x or y?
    uint8 xVaultIndex;
    uint8 yVaultIndex;
    uint128 liq; // The original liquidity of the asset.
    uint128 timestamp; // The timestamp of when the asset was last modified.
    /* node info */
    mapping(Key => AssetNode) nodes;
}

struct AssetNode {
    uint128 sliq; // The share/liq of the node we own.
    // For takers, this is a checkpoint of the per liq token fees owed.
    // For NC makers, this is a checkpoint of the per liq fees earned.
    // For C makers, this is not used.
    // These checkpoints include both the swap fees and the reservation fees.
    uint256 fee0CheckX128;
    uint256 fee1CheckX128;
}

struct AssetStore {
    mapping(address owner => uint256[] assetIds) ownerAssets;
    mapping(uint256 assetId => Asset) assets;
    mapping(address owner => mapping(address opener => bool)) permissions;
    mapping(address opener => bool) permissionedOpeners;
    uint256 lastAssetId;
}

library AssetLib {
    error NoRecipient();
    error AssetNotFound(uint256 assetId);
    error NotPermissioned(address owner, address attemptedOpener);

    event PermissionAdded(address owner, address opener);
    event PermissionRemoved(address owner, address opener);
    event PermissionedOpenerAdded(address opener);
    event PermissionedOpenerRemoved(address opener);

    /// Create a new maker asset.
    function newMaker(
        address recipient,
        PoolInfo memory pInfo,
        int24 lowTick,
        int24 highTick,
        uint128 liq,
        bool isCompounding
    ) internal returns (Asset storage asset, uint256 assetId) {
        // address 0x0 is a valid recipient for maker assets.

        AssetStore storage store = Store.assets();
        assetId = ++store.lastAssetId;
        asset = store.assets[assetId];
        asset.owner = recipient;
        asset.poolAddr = pInfo.poolAddr;
        asset.lowTick = lowTick;
        asset.highTick = highTick;
        asset.liqType = isCompounding ? LiqType.MAKER : LiqType.MAKER_NC;
        asset.liq = liq;
        updateTimestamp(asset);
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
        uint128 liq,
        uint8 xVaultIndex,
        uint8 yVaultIndex
    ) internal returns (Asset storage asset, uint256 assetId) {
        require(recipient != address(0x0), NoRecipient());

        AssetStore storage store = Store.assets();
        assetId = ++store.lastAssetId;
        asset = store.assets[assetId];
        asset.owner = recipient;
        asset.poolAddr = pInfo.poolAddr;
        asset.lowTick = lowTick;
        asset.highTick = highTick;
        asset.liqType = LiqType.TAKER;
        asset.liq = liq;
        asset.xVaultIndex = xVaultIndex;
        asset.yVaultIndex = yVaultIndex;
        // Takers borrow in x if its mean price is greater than the current price.
        asset.takeAsX = lowTick + highTick > 2 * pInfo.currentTick;
        updateTimestamp(asset);
        // The Nodes are to be filled in by a walker.
        addAssetToOwner(store, assetId, recipient);
    }

    /// Fetch an asset by ID (typically for viewing).
    function getAsset(uint256 assetId) internal view returns (Asset storage asset) {
        AssetStore storage store = Store.assets();
        asset = store.assets[assetId];
        require(asset.owner != address(0x0), AssetNotFound(assetId));
    }

    /// Remove an asset.
    function removeAsset(uint256 assetId) internal {
        AssetStore storage store = Store.assets();
        Asset storage asset = store.assets[assetId];
        require(asset.poolAddr != address(0), AssetNotFound(assetId));
        address owner = asset.owner;
        uint96 idx = asset.assetIdx;
        // The asset nodes will have been removed by the walker.
        delete store.assets[assetId];
        uint256[] storage ownerAssets = store.ownerAssets[owner];
        require(ownerAssets[idx] == assetId, AssetNotFound(assetId));
        // Swap the last element with removed index.
        ownerAssets[idx] = ownerAssets[ownerAssets.length - 1];
        store.assets[ownerAssets[idx]].assetIdx = idx;
        ownerAssets.pop();
    }

    /// Update the timestamp of when the asset was last modified.
    /// @dev This is for calculating JIT penalties.
    function updateTimestamp(Asset storage asset) internal {
        asset.timestamp = uint128(block.timestamp);
    }

    /* Permissions */

    function addPermission(address owner, address opener) internal {
        AssetStore storage store = Store.assets();
        store.permissions[owner][opener] = true;
        emit PermissionAdded(owner, opener);
    }

    function removePermission(address owner, address opener) internal {
        AssetStore storage store = Store.assets();
        delete store.permissions[owner][opener];
        emit PermissionRemoved(owner, opener);
    }

    function addPermissionedOpener(address opener) internal {
        Store.assets().permissionedOpeners[opener] = true;
        emit PermissionedOpenerAdded(opener);
    }

    function removePermissionedOpener(address opener) internal {
        delete Store.assets().permissionedOpeners[opener];
        emit PermissionedOpenerRemoved(opener);
    }

    function viewPermission(address owner, address opener) internal view returns (bool) {
        AssetStore storage store = Store.assets();
        return (owner == address(0) ||
            (owner == opener) ||
            (store.permissionedOpeners[opener]) ||
            store.permissions[owner][opener]);
    }

    /* Helpers */

    /// Get a null asset (used for compounding where no asset is needed).
    function nullAsset() internal view returns (Asset storage asset) {
        // The zeroeth assetId is never used.
        return Store.assets().assets[0];
    }

    function addAssetToOwner(AssetStore storage store, uint256 assetId, address owner) private {
        address opener = msg.sender;
        require(viewPermission(owner, opener), NotPermissioned(owner, opener));
        store.assets[assetId].assetIdx = uint96(store.ownerAssets[owner].length);
        store.ownerAssets[owner].push(assetId);
    }
}

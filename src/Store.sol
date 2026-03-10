// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Pool } from "./Pool.sol";
import { AssetStore } from "./Asset.sol";
import { VaultStore } from "./vaults/Vault.sol";
import { FeeStore } from "./Fee.sol";
import { PoolKey } from "v4-core/types/PoolKey.sol";
import { PoolId, PoolIdLibrary } from "v4-core/types/PoolId.sol";

struct Storage {
    AssetStore _assets;
    address poolManager; // V4 PoolManager address
    mapping(address poolAddr => Pool) pools;
    VaultStore _vaults;
    FeeStore _fees;
    // V4 pool key storage: maps deterministic poolAddr to PoolKey
    mapping(address poolAddr => PoolKey) poolKeys;
}

library Store {
    using PoolIdLibrary for PoolKey;

    // keccak256(abi.encode(uint256(keccak256("ammplify.storage.20250715")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_SLOT = 0x56d575db4d6456485aa5ce65d80d7d37cbb42d6dfdcfcad47c900d34e619bc00;

    function load() internal pure returns (Storage storage s) {
        bytes32 position = STORAGE_SLOT;
        assembly {
            s.slot := position
        }
    }

    function pool(address poolAddr) internal view returns (Pool storage p) {
        Storage storage s = load();
        p = s.pools[poolAddr];
    }

    function vaults() internal view returns (VaultStore storage v) {
        v = load()._vaults;
    }

    function assets() internal view returns (AssetStore storage a) {
        a = load()._assets;
    }

    function fees() internal view returns (FeeStore storage f) {
        f = load()._fees;
    }

    function poolManager() internal view returns (address) {
        return load().poolManager;
    }

    /// Register a V4 PoolKey and return its deterministic poolAddr.
    function registerPoolKey(PoolKey memory poolKey) internal returns (address poolAddr) {
        poolAddr = poolIdToAddr(poolKey.toId());
        load().poolKeys[poolAddr] = poolKey;
    }

    /// Get the PoolKey for a given poolAddr.
    function getPoolKey(address poolAddr) internal view returns (PoolKey memory) {
        return load().poolKeys[poolAddr];
    }

    /// Get the PoolId for a given poolAddr.
    function getPoolId(address poolAddr) internal view returns (PoolId) {
        PoolKey memory poolKey = load().poolKeys[poolAddr];
        return poolKey.toId();
    }

    /// Derive a deterministic address from a PoolId (first 20 bytes of the hash).
    function poolIdToAddr(PoolId poolId) internal pure returns (address) {
        return address(uint160(uint256(PoolId.unwrap(poolId))));
    }
}

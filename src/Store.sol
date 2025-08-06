// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Pool } from "./Pool.sol";
import { Config } from "./Config.sol";
import { AssetStore } from "./Asset.sol";
import { VaultStore } from "./vaults/Vault.sol";
import { FeeStore } from "./Fee.sol";
import { SlotDerivation } from "openzeppelin-contracts/contracts/utils/SlotDerivation.sol";

struct Storage {
    AssetStore _assets;
    mapping(address poolAddr => Pool) pools;
    VaultStore _vaults;
    FeeStore _fees;
}

library Store {
    bytes32 public constant STORAGE_SLOT = SlotDerivation.erc7201Slot("ammplify.storage.20250715");

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

    function vaults() internal view returns (VaultStorage storage v) {
        v = load()._vaults;
    }

    function assets() internal view returns (AssetStore storage a) {
        a = load()._assets;
    }

    function fees() internal view returns (FeeStore storage f) {
        f = load()._fees;
    }
}

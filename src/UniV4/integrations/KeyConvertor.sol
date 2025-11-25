// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { PoolKey } from "v4-core/types/PoolKey.sol";
import { Currency } from "v4-core/types/Currency.sol";

interface IKeyConvertor {
    /// @notice Convert a UniswapV4 Pool Key to a unique address and create a new one if none exists.
    /// @dev We require a deposit of one MON to prevent spamming hashes for a specific key.
    /// @param key The UniswapV4 Pool Key.
    /// @return addrId The unique address representing the pool.
    function setKeyToAddressId(PoolKey calldata key) external payable returns (address addrId);

    /// Convert UniV4 Pool Key to a unique identifier the size of an address.
    function keyToAddressId(PoolKey calldata key) external view returns (address addrId);

    /// Convert the address identifier back to the UniV4 Pool Key.
    function addressIdToKey(address addrId) external view returns (PoolKey memory key);
}

/// Since everything in Ammplify uses a pool address, we convert UniV4 Pool Keys to a unique address here to avoid complication interfaces.
/// This means anyone interacting with a V4 Ammplify should use this convertor first.
contract KeyConvertor is IKeyConvertor {
    mapping((address, address, uint24, int24, address) => address) private _keyToAddressId;
    mapping(address => PoolKey) private _addressIdToKey;

    address owner;

    error OnlyOwner();
    error InsufficientRegistrationFee();

    event KeyRegistered(address indexed addrId, PoolKey key);

    constructor() {
        owner = msg.sender;
    }

    /// @inheritdoc IKeyConvertor
    function setKeyToAddressId(PoolKey calldata key) external payable returns (address addrId) {
        (address currency0, address currency1, uint24 fee, int24 tickSpacing, address hooks) = keyToFields(key);
        addrId = _keyToAddressId[(currency0, currency1, fee, tickSpacing, hooks)];
        if (addrId != address(0)) {
            return addrId;
        }

        // We have a new key.
        uint256 nonce = 0;
        addrId = address(uint160(uint256(keccak256(abi.encodePacked(nonce, key)))));
        while (_addressIdToKey[addrId].tickSpacing != 0) {
            nonce++;
            addrId = address(uint160(uint256(keccak256(abi.encodePacked(nonce, key)))));
        }

        // Store the new key and address mapping.
        require(msg.value >= 1 ether, InsufficientRegistrationFee());
        _keyToAddressId[(currency0, currency1, fee, tickSpacing, hooks)] = addrId;
        _addressIdToKey[addrId] = key;

        emit KeyRegistered(addrId, key);
    }

    /// @inheritdoc IKeyConvertor
    function keyToAddressId(PoolKey calldata key) external view returns (address addrId) {
        (address currency0, address currency1, uint24 fee, int24 tickSpacing, address hooks) = keyToFields(key);
        return _keyToAddressId[(currency0, currency1, fee, tickSpacing, hooks)]; // Will return address(0) if not found.
    }

    /// @inheritdoc IKeyConvertor
    function addressIdToKey(address addrId) external view returns (PoolKey memory key) {
        return _addressIdToKey[addrId]; // Will return empty result if not found.
    }

    /// Collect back the deposits most likely paid by the owner anyways.
    function sweep() external {
        if (msg.sender != owner) {
            revert OnlyOwner();
        }
        payable(owner).transfer(address(this).balance);
    }

    function keyToFields(PoolKey calldata key) internal pure returns (address, address, uint24, int24, address) {
        return (
            Currency.unwrap(key.currency0),
            Currency.unwrap(key.currency1),
            key.fee,
            key.tickSpacing,
            address(key.hooks)
        );
    }
}

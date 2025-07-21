// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Node } from "../visitors/Node.sol";
import { Key, KeyImpl } from "../tree/Key.sol";
import { Store } from "../Store.sol";
import { PoolInfo, PoolLib, Pool } from "../Pool.sol";

/// Query the values of internal data structures.
contract TreeFacet {
    error LengthMismatch(uint256 baseLength, uint256 widthLength);

    /// Get basic information about a pool.
    function getPoolInfo(address poolAddr) external view returns (PoolInfo memory pInfo) {
        pInfo = PoolLib.getPoolInfo(poolAddr);
    }

    /// Get information about nodes in the pool.
    function getNodeInfo(
        address poolAddr,
        uint24[] calldata base,
        uint24[] calldata width
    ) external view returns (Node[] memory node) {
        Key key = KeyImpl.make(base, width);
        Pool storage pool = Store.pool(poolAddr);
        node = new Node[](base.length);
        require(base.length == width.length, LengthMismatch(base.length, width.length));

        for (uint256 i = 0; i < base.length; i++) {
            key = KeyImpl.make(base[i], width[i]);
            node[i] = pool.nodes[key];
        }
    }
}

// SPDX-License-Identifier: BUSL-1.1-or-later
pragma solidity ^0.8.26;

import { IUnlockCallback } from "v4-core/interfaces/callback/IUnlockCallback.sol";
import { PoolLib } from "../Pool.sol";
import { IPool } from "../interfaces/IPool.sol";
import { Store } from "../Store.sol";

contract PoolFacet is IPool {
    /// @notice Called by the V4 PoolManager during unlock.
    /// @dev Executes all batched modifyLiquidity operations and settles token deltas.
    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        address manager = Store.poolManager();
        require(msg.sender == manager, UnauthorizedUnlock(manager, msg.sender));
        return PoolLib.handleUnlockCallback(data);
    }
}

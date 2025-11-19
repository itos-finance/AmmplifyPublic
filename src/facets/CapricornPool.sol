// SPDX-License-Identifier: BUSL-1.1-or-later
pragma solidity ^0.8.27;

import { TransferHelper } from "Commons/Util/TransferHelper.sol";
import { PoolInfo, PoolLib } from "../Pool.sol";
import { IPool } from "../interfaces/IPool.sol";

interface ICapricornCLMintCallback {
    function capricornCLMintCallback(uint256 amount0Delta, uint256 amount1Delta, bytes calldata data) external;
}
contract PoolFacet is ICapricornCLMintCallback {
    /// @notice Called to `msg.sender` after minting liquidity to a position from CapricornCLPool#mint.
    /// @dev In the implementation you must pay the pool tokens owed for the minted liquidity.
    /// The caller of this method must be checked to be a CapricornCLPool.
    /// @param amount0Delta The amount of token0 due to the pool for the minted liquidity
    /// @param amount1Delta The amount of token1 due to the pool for the minted liquidity
    function capricornCLMintCallback(
        uint256 amount0Delta,
        uint256 amount1Delta,
        bytes calldata /* data */
    ) external override(ICapricornCLMintCallback) {
        address activeMint = PoolLib.poolGuard();
        // require(msg.sender == activeMint, UnauthorizedMint(activeMint, msg.sender));
        PoolInfo memory pInfo = PoolLib.getPoolInfo(activeMint);
        if (amount0Delta > 0) TransferHelper.safeTransfer(pInfo.token0, activeMint, uint256(amount0Delta));
        if (amount1Delta > 0) TransferHelper.safeTransfer(pInfo.token1, activeMint, uint256(amount1Delta));
    }
}

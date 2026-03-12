// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { IPoolManager } from "v4-core/interfaces/IPoolManager.sol";
import { Currency } from "v4-core/types/Currency.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Shared helper for settling token deltas with V4 PoolManager.
library V4Settlement {
    using SafeERC20 for IERC20;

    /// @dev Settle a single currency delta after a V4 unlock callback operation.
    ///  - Negative delta: caller owes the pool manager (sync → transfer → settle).
    ///  - Positive delta: pool manager owes caller (take).
    function settleDelta(IPoolManager manager, Currency currency, address token, int256 delta) internal {
        if (delta < 0) {
            manager.sync(currency);
            IERC20(token).safeTransfer(address(manager), uint256(-delta));
            manager.settle();
        } else if (delta > 0) {
            manager.take(currency, address(this), uint256(delta));
        }
    }
}

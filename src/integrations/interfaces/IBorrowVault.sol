// SPDX-License-Identifier: BUSL-1.1
// Copyright © 2025 Itos Inc.
pragma solidity ^0.8.27;

/// A simple borrow and repay interface.
interface IBorrowVault {
    function borrow(uint256 amount) external;
    function repay(uint256 amount) external;
}

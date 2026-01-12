// SPDX-License-Identifier: BUSL-1.1
// Copyright © 2025 Itos Inc.
pragma solidity ^0.8.27;

import { ERC4626 } from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import { TransferHelper } from "Commons/util/TransferHelper.sol";
import { SafeCast } from "Commons/Math/Cast.sol";

import { IBorrowVault } from "./interfaces/IBorrowVault.sol";

/// A basic vault for holding the given token from taker positions.
/// It allows the borrower to borrow funds indefinitely, so only use this with safe borrowers.
/// @dev The ammplify owner should install this vault for new tokens upon graduation from the launchpad.
/// And set the Bettor as the borrower.
contract TakerVault is ERC4626, IBorrowVault {
    address public borrower;
    uint256 public outstanding;
    address public owner;

    using SafeERC20 for IERC20;

    error Unauthorized();
    error InsufficientBalance(uint256 balance);

    constructor(address _owner, IERC20 _asset, address _borrower) ERC4626(_asset) ERC20("TakerVault", "TKRVLT") {
        borrower = _borrower;
        owner = _owner;
    }

    /// Allow the borrower to borrow funds from the vault.
    function borrow(uint256 amount) external {
        require(msg.sender == borrower, Unauthorized());
        IERC20 token = IERC20(asset());
        uint256 balance = token.balanceOf(address(this));
        require(balance >= amount, InsufficientBalance(balance));
        outstanding += amount;

        token.safeTransfer(borrower, amount);
    }

    /// Anyone can repay.
    /// @param amount Repay up to this amount, limited by the outstanding.
    function repay(uint256 amount) external {
        if (outstanding < amount) {
            amount = outstanding;
        }

        TransferHelper.safeTransferFrom(asset(), msg.sender, address(this), amount);
        outstanding -= amount;
    }

    /// Allow the owner to forgive their debt if they're repaying in a different way.
    function forgive(uint256 amount) external {
        require(msg.sender == owner, Unauthorized());
        if (outstanding < amount) {
            outstanding = 0;
        } else {
            outstanding -= amount;
        }
    }

    function setBorrower(address _borrower) external {
        require(msg.sender == owner, Unauthorized());
        borrower = _borrower;
    }

    /* 4626 overrides */

    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) + outstanding;
    }

    function maxRedeem(address _owner) public view override returns (uint256) {
        uint256 available = IERC20(asset()).balanceOf(address(this));
        available = _convertToShares(available, Math.Rounding.Ceil);
        uint256 balance = balanceOf(_owner);
        return balance < available ? balance : available;
    }

    function _decimalsOffset() internal pure override returns (uint8) {
        return 2;
    }
}

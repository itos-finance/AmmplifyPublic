// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { ERC4626 } from "a@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { ERC20 } from "a@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract NoOpVault is ERC4626 {
    constructor(ERC20 asset, string memory name, string memory symbol) ERC20(name, symbol) ERC4626(asset) {}
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";

import { MultiSetupTest } from "../MultiSetup.u.sol";
import { UniV4IntegrationSetup } from "../UniV4.u.sol";

// TODO: UniV3Decomposer tests need V4 adaptation
contract UniV3DecomposerTest is MultiSetupTest, UniV4IntegrationSetup {
    function setUp() public {
        _newDiamond(manager);
    }
}

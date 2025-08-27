// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { Data, DataImpl } from "../../src/walkers/Data.sol";
import { Key } from "../../src/tree/Key.sol";

contract DataTest is Test {
    /*     function testMake() public {
        Data memory data = DataImpl.init(10, 20);
        assertEq(data.downLength, 10);
        assertEq(data.upLength, 20);
        assertEq(data.downVisits, 0);
        assertEq(data.upVisits, 0);
        assertEq(data.downKeys.length, 10);
        assertEq(data.upKeys.length, 20);
    } */
}

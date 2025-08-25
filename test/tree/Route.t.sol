// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Route, RouteImpl } from "../../src/tree/Route.sol";
import "forge-std/Test.sol";

contract RouteTest is Test {
    function testMakeRoute() public {
        Route memory r = RouteImpl.make(100, 10, 20);
        assertEq(r.rootWidth, 100);
        assertTrue(r.left.isEq(r.left));
        assertTrue(r.right.isEq(r.right));
    }
}

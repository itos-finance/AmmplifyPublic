// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { TreeTickLib } from "../../src/tree/Tick.sol";
import "forge-std/Test.sol";

contract TickTest is Test {
    function testTickToTreeIndex() public {
        uint24 rootWidth = 100;
        int24 tickSpacing = 5;
        int24 tick = 10;
        uint24 index = TreeTickLib.tickToTreeIndex(tick, rootWidth, tickSpacing);
        assertEq(index, uint24(tick / tickSpacing) + rootWidth / 2);
    }
    function testTreeIndexToTick() public {
        uint24 rootWidth = 100;
        int24 tickSpacing = 5;
        uint24 index = 60;
        int24 tick = TreeTickLib.treeIndexToTick(index, rootWidth, tickSpacing);
        assertEq(tick, (int24(index) - int24(rootWidth / 2)) * tickSpacing);
    }
}

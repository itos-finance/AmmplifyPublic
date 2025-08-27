// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

library TreeTickLib {
    error UnalignedTick(int24 tick, int24 tickSpacing);

    function tickToTreeIndex(int24 tick, uint24 rootWidth, int24 tickSpacing) internal pure returns (uint24) {
        unchecked {
            require(tick % tickSpacing == 0, UnalignedTick(tick, tickSpacing));
            return uint24(tick / tickSpacing) + rootWidth / 2; // Convert tick to tree index, adjusting for the root width.
        }
    }

    function treeIndexToTick(uint24 index, uint24 rootWidth, int24 tickSpacing) internal pure returns (int24) {
        unchecked {
            return (int24(index) - int24(rootWidth / 2)) * tickSpacing; // Convert tree index back to tick.
        }
    }
}

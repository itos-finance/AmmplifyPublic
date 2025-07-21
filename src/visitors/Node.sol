// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { FullMath } from "../FullMath.sol";

struct Node {
    // Liquidity
    uint128 mLiq;
    uint128 tLiq;
    uint128 ncLiq;
    uint128 shares; // Total shares of compounding maker liq.
    uint128 subtreeMLiq;
    uint128 subtreeTLiq;
    // Fees
    uint128 xCFees; // Compounding maker fees
    uint128 yCFees;
    uint256 xNCFeesPerLiqX128; // Non-compounding fees per liquidity unit
    uint256 yNCFeesPerLiqX128;
    uint128 takerXFeePerLiqX64; // Taker fee checkpoint.
    uint128 takerYFeePerLiqX64; // Taker fee checkpoint.
    // Fee checkpoint for updating.
    uint128 lastTakerRateX64; // The taker rate at the last update.
    uint128 lastTimestamp; // Last time this node was updated.
    // Liq Redistribution
    uint128 borrowed;
    uint128 lent;
    // Transient variables
    bool dirty; // Dirty bit for liquidity changes.
}

using NodeImpl for Node global;

library NodeImpl {
    /// Split the fees between the compounding and non-compounding maker liq.
    function splitFees(
        Node storage self,
        uint128 x,
        uint128 y
    ) internal view returns (uint128 xC, uint128 yC, uint128 xNC, uint128 yNC) {
        uint256 ratioX256 = FullMath.mulDivX256(self.ncLiq, self.mLiq, true);
        uint256 ncX = FullMath.mulX256(ratioX256, x, false);
        uint256 ncY = FullMath.mulX256(ratioX256, y, false);
        xC = x - uint128(ncX);
        yC = y - uint128(ncY);
        xNC = (ncX << 128) / self.ncLiq; // Rounds down.
        yNC = (ncY << 128) / self.ncLiq; // Rounds down.
    }

    /// Splits the fees and then assigns them to the node's maker liquidity.
    function assignFees(Node storage self, uint128 x, uint128 y) internal {
        (uint128 xC, uint128 yC, uint128 xNC, uint128 yNC) = splitFees(self, x, y);
        self.xCFees += xC;
        self.yCFees += yC;
        self.xNCFeesPerLiqX128 += (xNC << 128) / self.ncLiq; // Rounds down.
        self.yNCFeesPerLiqX128 += (yNC << 128) / self.ncLiq; // Rounds down.
    }

    /// The actual liq that resides in this node in the pool.
    function netLiq(Node storage self) internal view returns (int128) {
        return int128(self.borrowed) + int128(self.mLiq) - int128(self.tLiq) - int128(self.lent);
    }

    /// Modify the compounding maker liquidity.
    /// @param sliq When adding liquidity, the amount of liquidity to add. When removing, the shares to remove.
    /// @dev subtree is updated by prop, not this.
    /// @return outSliq The shares added / liquidity removed.
    function modifyCMLiq(Node storage self, int128 sliq) internal returns (uint128 outSliq) {
        // Modify according to the liq value.
        if (sliq == 0) {
            return 0;
        } else if (sliq > 0) {
            // Rounds shares down
            outSliq = uint128(FullMath.mulDiv(uint128(sliq), self.shares, self.mLiq - self.ncLiq));
            self.shares += outSliq;
            self.mLiq += uint128(sliq);
            self.dirty = true;
        } else {
            // Rounds liquidity down
            outSliq = uint128(FullMath.mulDiv(uint128(-sliq), self.mLiq - self.ncLiq, self.shares));
            self.shares -= uint128(-sliq);
            self.mLiq -= outSliq;
            self.dirty = true;
        }
    }

    /// Modify the non-compounding maker liquidity.
    function modifyNCMLiq(Node storage self, int128 liq) internal {
        // Modify according to the liq value.
        if (liq > 0) {
            uint128 addedLiq = uint128(liq);
            self.mLiq += addedLiq;
            self.ncLiq += addedLiq;
            self.dirty = true;
        } else if (liq < 0) {
            uint128 removedLiq = uint128(-liq);
            self.mLiq -= removedLiq;
            self.ncLiq -= removedLiq;
            self.dirty = true;
        }
    }

    /// Modify the taker liquidity.
    function modifyTLiq(Node storage self, int128 liq) internal {
        if (liq > 0) {
            uint128 addedLiq = uint128(liq);
            self.tLiq += addedLiq;
            self.dirty = true;
        } else if (liq < 0) {
            uint128 removedLiq = uint128(-liq);
            self.tLiq -= removedLiq;
            self.dirty = true;
        }
    }

    function compoundLiq(Node storage self, uint128 compoundedLiq) internal {
        if (compoundedLiq == 0) {
            return;
        }
        self.mLiq += compoundedLiq;
        self.dirty = true;
    }
}

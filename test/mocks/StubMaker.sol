// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../../lib/Commons/src/Util/RFT.sol";

// Stub MakerFacet capturing last call
contract StubMaker is RFTPayer {
    int24 public lastLow;
    int24 public lastHigh;
    uint256 public calls;

    function newMaker(
        address /*recipient*/,
        address /*pool*/,
        int24 low,
        int24 high,
        uint128 /*liq*/,
        bool /*comp*/,
        uint160,
        uint160,
        bytes calldata
    ) external returns (uint256) {
        lastLow = low;
        lastHigh = high;
        calls += 1;
        return calls;
    }

    function tokenRequestCB(
        address[] calldata tokens,
        int256[] calldata deltas,
        bytes calldata /* data */
    ) external override returns (bytes memory) {
        // Stub implementation - just return empty bytes
        return "";
    }
}

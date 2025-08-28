// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { IUniswapV3Factory } from "../../lib/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

// Mock Uniswap V3 Factory
contract MockFactory is IUniswapV3Factory {
    address public pool;
    address public override owner;

    constructor() {
        owner = msg.sender;
    }

    function setPool(address p) external {
        pool = p;
    }

    function getPool(address, address, uint24) external view override returns (address) {
        return pool;
    }

    // Required interface implementations
    function feeAmountTickSpacing(uint24) external pure override returns (int24) {
        return 60; // Default tick spacing
    }

    function createPool(address, address, uint24) external pure override returns (address) {
        revert("Not implemented in mock");
    }

    function setOwner(address) external pure override {
        revert("Not implemented in mock");
    }

    function enableFeeAmount(uint24, int24) external pure override {
        revert("Not implemented in mock");
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

// Mock Uniswap V3 Factory
contract MockFactory {
    address public pool;

    function setPool(address p) external {
        pool = p;
    }

    function getPool(address, address, uint24) external view returns (address) {
        return pool;
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

// Minimal ERC20 token for testing
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;

    constructor(string memory _n, string memory _s) {
        name = _n;
        symbol = _s;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        balanceOf[from] -= value;
        balanceOf[to] += value;
        return true;
    }

    function approve(address, uint256) external pure returns (bool) {
        return true;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }
}

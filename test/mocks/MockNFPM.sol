// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./MockERC20.sol";
import {
    INonfungiblePositionManager
} from "../../src/integrations/univ3-periphery/interfaces/INonfungiblePositionManager.sol";

// Mock NFPM implementing minimal interface used by Decomposer
contract MockNFPM {
    struct Pos {
        address owner;
        address token0;
        address token1;
        uint24 fee;
        int24 tickL;
        int24 tickU;
        uint128 liq;
    }

    mapping(uint256 => Pos) public positionsMap;
    uint256 public nextId = 1;
    address public factory;
    MockERC20 public t0;
    MockERC20 public t1;

    // ERC721 approval tracking
    mapping(uint256 => address) public getApproved;
    mapping(address => mapping(address => bool)) public isApprovedForAll;

    constructor(address _factory, address _t0, address _t1) {
        factory = _factory;
        t0 = MockERC20(_t0);
        t1 = MockERC20(_t1);
    }

    function mintPosition(address owner, uint24 fee, int24 tl, int24 tu, uint128 liq) external returns (uint256 id) {
        id = nextId++;
        positionsMap[id] = Pos(owner, address(t0), address(t1), fee, tl, tu, liq);
    }

    /* --- interface --- */
    function ownerOf(uint256 tokenId) external view returns (address) {
        return positionsMap[tokenId].owner;
    }

    function positions(
        uint256 tokenId
    )
        external
        view
        returns (
            uint96,
            address,
            address token0,
            address token1,
            uint24 fee,
            int24 tl,
            int24 tu,
            uint128 liq,
            uint256,
            uint256,
            uint128,
            uint128
        )
    {
        Pos memory p = positionsMap[tokenId];
        return (0, address(0), p.token0, p.token1, p.fee, p.tickL, p.tickU, p.liq, 0, 0, 0, 0);
    }

    function getFactory() external view returns (address) {
        return factory;
    }

    function decreaseLiquidity(
        INonfungiblePositionManager.DecreaseLiquidityParams calldata params
    ) external returns (uint256, uint256) {
        Pos storage p = positionsMap[params.tokenId];
        require(p.liq >= params.liquidity, "liq");
        p.liq -= params.liquidity;
        return (0, 0);
    }

    function collect(INonfungiblePositionManager.CollectParams calldata params) external returns (uint256, uint256) {
        // Mint 1 ether worth of each token to recipient for simplicity
        t0.mint(params.recipient, 1e18);
        t1.mint(params.recipient, 1e18);
        return (1e18, 1e18);
    }

    function burn(uint256 tokenId) external {
        delete positionsMap[tokenId];
    }

    function approve(address to, uint256 tokenId) external {
        address owner = positionsMap[tokenId].owner;
        require(to != owner, "ERC721: approval to current owner");
        require(
            msg.sender == owner || isApprovedForAll[owner][msg.sender],
            "ERC721: approve caller is not token owner or approved for all"
        );

        getApproved[tokenId] = to;
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        address owner = positionsMap[tokenId].owner;
        require(from == owner, "ERC721: transfer from incorrect owner");
        require(
            msg.sender == owner || msg.sender == getApproved[tokenId] || isApprovedForAll[owner][msg.sender],
            "ERC721: caller is not token owner or approved"
        );
        require(to != address(0), "ERC721: transfer to the zero address");

        // Update the position owner
        positionsMap[tokenId].owner = to;

        // Clear any existing approval for this token
        delete getApproved[tokenId];
    }
}

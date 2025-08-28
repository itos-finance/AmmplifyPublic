// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./MockERC20.sol";
import {
    INonfungiblePositionManager
} from "../../src/integrations/univ3-periphery/interfaces/INonfungiblePositionManager.sol";
import { IUniswapV3Pool } from "v3-core/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3Factory } from "v3-core/interfaces/IUniswapV3Factory.sol";

contract MockNFPM is INonfungiblePositionManager {
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
    IUniswapV3Factory public factory;

    // ERC721 approval tracking
    mapping(uint256 => address) public getApproved;
    mapping(address => mapping(address => bool)) public isApprovedForAll;

    constructor(address _factory) {
        factory = IUniswapV3Factory(_factory);
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
        return address(factory);
    }

    function mint(
        INonfungiblePositionManager.MintParams calldata params
    ) external payable returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) {
        // Get pool address from factory
        address poolAddress = factory.getPool(params.token0, params.token1, params.fee);
        require(poolAddress != address(0), "Pool not found");

        // Call the actual pool's mint function
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        (uint256 poolAmount0, uint256 poolAmount1) = pool.mint(
            params.recipient,
            params.tickLower,
            params.tickUpper,
            params.amount0Desired,
            params.data
        );

        // Create position record
        tokenId = nextId++;
        positionsMap[tokenId] = Pos(
            params.recipient,
            params.token0,
            params.token1,
            params.fee,
            params.tickLower,
            params.tickUpper,
            uint128(params.amount0Desired)
        );

        liquidity = uint128(params.amount0Desired);
        amount0 = poolAmount0;
        amount1 = poolAmount1;
        return (tokenId, liquidity, amount0, amount1);
    }

    function burn(uint256 tokenId) external payable {
        Pos memory p = positionsMap[tokenId];
        require(p.owner != address(0), "Position does not exist");

        // Get pool address from factory
        address poolAddress = factory.getPool(p.token0, p.token1, p.fee);
        require(poolAddress != address(0), "Pool not found");

        // Call the actual pool's burn function
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        (uint256 amount0, uint256 amount1) = pool.burn(p.tickL, p.tickU, p.liq);

        // Delete the position after burning
        delete positionsMap[tokenId];
    }

    function collect(
        INonfungiblePositionManager.CollectParams calldata params
    ) external payable returns (uint256, uint256) {
        Pos memory p = positionsMap[params.tokenId];
        require(p.owner != address(0), "Position does not exist");

        // Get pool address from factory
        address poolAddress = factory.getPool(p.token0, p.token1, p.fee);
        require(poolAddress != address(0), "Pool not found");

        // Call the actual pool's collect function
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        (uint128 amount0, uint128 amount1) = pool.collect(
            params.recipient,
            p.tickL,
            p.tickU,
            params.amount0Max,
            params.amount1Max
        );

        return (amount0, amount1);
    }

    function increaseLiquidity(
        INonfungiblePositionManager.IncreaseLiquidityParams calldata params
    ) external payable returns (uint128 liquidity, uint256 amount0, uint256 amount1) {}

    function decreaseLiquidity(
        INonfungiblePositionManager.DecreaseLiquidityParams calldata params
    ) external payable returns (uint256, uint256) {}

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

    // ============ ERC721 Interface Implementations ============

    function balanceOf(address owner) external view returns (uint256 balance) {
        // Mock implementation
        return 0;
    }

    function name() external view returns (string memory) {
        return "Mock NFPM";
    }

    function symbol() external view returns (string memory) {
        return "MNFT";
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        return "";
    }

    function totalSupply() external view returns (uint256) {
        return nextId - 1;
    }

    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256) {
        revert("Not implemented");
    }

    function tokenByIndex(uint256 index) external view returns (uint256) {
        require(index < nextId - 1, "Index out of bounds");
        return index + 1;
    }

    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        return true;
    }

    function transferFrom(address from, address to, uint256 tokenId) external {
        // Mock implementation
        Pos storage pos = positionsMap[tokenId];
        pos.owner = to;
    }

    function setApprovalForAll(address operator, bool approved) external {
        // Mock implementation
        isApprovedForAll[msg.sender][operator] = approved;
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external {
        // Mock implementation
        Pos storage pos = positionsMap[tokenId];
        pos.owner = to;
    }

    // ============ IPeripheryImmutableState ============

    function WETH9() external view returns (address) {
        return address(0);
    }

    // ============ IPeripheryPayments ============

    function unwrapWETH9(uint256 amountMinimum, address recipient) external payable {
        revert("Not implemented");
    }

    function sweepToken(address token, uint256 amountMinimum, address recipient) external payable {
        revert("Not implemented");
    }

    function refundETH() external payable {
        revert("Not implemented");
    }

    // ============ IPoolInitializer ============

    function createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        uint24 fee,
        uint160 sqrtPriceX96
    ) external payable returns (address pool) {
        revert("Not implemented");
    }

    // ============ IERC721Permit ============

    function PERMIT_TYPEHASH() external pure returns (bytes32) {
        return keccak256("Permit(address spender,uint256 tokenId,uint256 nonce,uint256 deadline)");
    }

    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    }

    function permit(
        address spender,
        uint256 tokenId,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable {
        revert("Not implemented");
    }

    function nonces(uint256 tokenId) external view returns (uint256) {
        return 0;
    }
}

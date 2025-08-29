// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { NonfungiblePositionManager } from "../mocks/nfpm/NonfungiblePositionManager.sol";
import { UniV3Decomposer } from "../../src/integrations/UniV3Decomposer.sol";
import { MultiSetupTest } from "../MultiSetup.u.sol";
import { MockERC20 } from "./../mocks/MockERC20.sol";
import { INonfungiblePositionManager } from "../mocks/nfpm/interfaces/INonfungiblePositionManager.sol";

contract UniV3DecomposerTest is MultiSetupTest {
    UniV3Decomposer private decomposer;

    function setUp() public {
        _newDiamond();
        _deployNFPM();

        (uint256 idx, address pool, address _token0, address _token1) = setUpPool();
        token0 = MockERC20(_token0);
        token1 = MockERC20(_token1);
        decomposer = new UniV3Decomposer(address(nfpm), address(diamond));
    }

    // Helper function to create a position using the mint function
    function createPosition(
        address owner,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) internal returns (uint256) {
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: address(token0),
            token1: address(token1),
            fee: fee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: uint256(liquidity),
            amount1Desired: uint256(liquidity),
            amount0Min: 0,
            amount1Min: 0,
            recipient: owner,
            deadline: block.timestamp + 3600
        });

        (uint256 tokenId, , , ) = nfpm.mint(params);
        return tokenId;
    }

    function testRevertNotOwner() public {
        uint256 pos = createPosition(address(0xBEEF), 3000, -600, 600, 1000);
        vm.prank(address(0xBEEF));
        nfpm.approve(address(decomposer), pos);
        vm.expectRevert();
        decomposer.decompose(pos, false, 0, 0, "");
    }

    function testDecomposeNFT() public {
        uint256 pos = createPosition(address(this), 3000, -600, 600, 1000);
        nfpm.approve(address(decomposer), pos);
        uint256 newId = decomposer.decompose(pos, false, 0, 0, "");
    }
}

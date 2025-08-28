// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { UniV3Decomposer } from "../../src/integrations/UniV3Decomposer.sol";
import { MockERC20 } from "./../mocks/MockERC20.sol";
import { MockFactory } from "./../mocks/MockFactory.sol";
import { MockNFPM } from "./../mocks/MockNFPM.sol";
import { MockPool } from "./../mocks/MockPool.sol";
import { StubMaker } from "./../mocks/StubMaker.sol";
import {
    INonfungiblePositionManager
} from "../../src/integrations/univ3-periphery/interfaces/INonfungiblePositionManager.sol";

contract UniV3DecomposerTest is Test {
    MockERC20 private t0;
    MockERC20 private t1;
    MockFactory private factory;
    MockNFPM private nfpm;
    MockPool private pool;
    StubMaker private maker;
    UniV3Decomposer private decomposer;

    function setUp() public {
        t0 = new MockERC20("T0", "T0", 18);
        t1 = new MockERC20("T1", "T1", 18);
        factory = new MockFactory();
        nfpm = new MockNFPM(address(factory));
        pool = new MockPool(address(factory), address(t0), address(t1), 3000);
        maker = new StubMaker();
        decomposer = new UniV3Decomposer(address(nfpm), address(maker));
        factory.setPool(address(pool));
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
            token0: address(t0),
            token1: address(t1),
            fee: fee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: uint256(liquidity),
            amount1Desired: uint256(liquidity),
            amount0Min: 0,
            amount1Min: 0,
            recipient: owner,
            deadline: block.timestamp + 3600,
            data: ""
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

    function testHappyPath() public {
        uint256 pos = createPosition(address(this), 3000, -600, 600, 1000);
        t0.mint(address(decomposer), 0);
        t1.mint(address(decomposer), 0); // ensure zero start
        nfpm.approve(address(decomposer), pos);
        uint256 newId = decomposer.decompose(pos, false, 0, 0, "");
        assertEq(newId, 1);
        assertEq(maker.calls(), 1);
        assertEq(maker.lastLow(), -600);
        assertEq(maker.lastHigh(), 600);
    }
}

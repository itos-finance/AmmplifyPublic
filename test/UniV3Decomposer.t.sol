// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import { UniV3Decomposer } from "../src/integrations/UniV3Decomposer.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockFactory } from "./mocks/MockFactory.sol";
import { MockNFPM } from "./mocks/MockNFPM.sol";
import { StubMaker } from "./mocks/StubMaker.sol";

contract UniV3DecomposerTest is Test {
    MockERC20 private t0;
    MockERC20 private t1;
    MockFactory private factory;
    MockNFPM private nfpm;
    StubMaker private maker;
    UniV3Decomposer private decomposer;

    function setUp() public {
        t0 = new MockERC20("T0", "T0", 18);
        t1 = new MockERC20("T1", "T1", 18);
        factory = new MockFactory();
        nfpm = new MockNFPM(address(factory), address(t0), address(t1));
        maker = new StubMaker();
        decomposer = new UniV3Decomposer(address(nfpm), address(maker));
        factory.setPool(address(0x1234));
    }

    function testRevertNotOwner() public {
        uint256 pos = nfpm.mintPosition(address(0xBEEF), 3000, -600, 600, 1000);
        vm.expectRevert();
        decomposer.decompose(pos, false, 0, 0, "");
    }

    function testHappyPath() public {
        uint256 pos = nfpm.mintPosition(address(this), 3000, -600, 600, 1000);
        factory.setPool(address(0x1234));
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

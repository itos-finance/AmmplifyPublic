// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";

import { UniV3IntegrationSetup } from "../UniV3.u.sol";
import { MultiSetupTest } from "../MultiSetup.u.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { INonfungiblePositionManager } from "../mocks/nfpm/interfaces/INonfungiblePositionManager.sol";
import { UniV3PositionOpener } from "../../src/integrations/UniV3PositionOpener.sol";
import { IERC20 } from "a@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "a@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract UniV3PositionOpenerTest is MultiSetupTest, UniV3IntegrationSetup {
    UniV3PositionOpener public opener;

    uint24 public constant POOL_FEE = 3000;
    int24 public constant LOW_TICK = -600;
    int24 public constant HIGH_TICK = 600;
    uint256 public constant AMOUNT_IN = 10e18;
    uint256 public constant AMOUNT_SWAP = 4e18;
    uint256 public constant FUND_AMOUNT = 100e18;

    address public poolAddr;

    function setUp() public {
        // Deploy NFPM
        _deployNFPM(factory);

        // Create pool with initial liquidity for swaps
        address t0;
        address t1;
        (, poolAddr, t0, t1) = setUpPool(POOL_FEE);
        token0 = MockERC20(t0);
        token1 = MockERC20(t1);

        // Add wide-range liquidity so swaps work
        int24 spacing = int24(60); // tick spacing for 3000 fee tier
        addPoolLiq(0, (-887220 / spacing) * spacing, (887220 / spacing) * spacing, 100e18);

        // Deploy opener
        opener = new UniV3PositionOpener(address(nfpm));

        // Fund alice
        token0.mint(alice, FUND_AMOUNT);
        token1.mint(alice, FUND_AMOUNT);
    }

    function test_openPosition_withToken0() public {
        vm.startPrank(alice);
        token0.approve(address(opener), AMOUNT_IN);

        uint256 tokenId = opener.openPosition(
            poolAddr,
            address(token0),
            AMOUNT_IN,
            LOW_TICK,
            HIGH_TICK,
            AMOUNT_SWAP,
            AMOUNT_SWAP - 1e17, // small slippage tolerance
            block.timestamp + 3600
        );
        vm.stopPrank();

        // Verify NFT was minted to alice
        assertEq(IERC721(address(nfpm)).ownerOf(tokenId), alice);

        // Verify position has liquidity
        (, , , , , , , uint128 liquidity, , , , ) = nfpm.positions(tokenId);
        assertGt(liquidity, 0);
    }

    function test_openPosition_withToken1() public {
        vm.startPrank(alice);
        token1.approve(address(opener), AMOUNT_IN);

        uint256 tokenId = opener.openPosition(
            poolAddr,
            address(token1),
            AMOUNT_IN,
            LOW_TICK,
            HIGH_TICK,
            AMOUNT_SWAP,
            AMOUNT_SWAP - 1e17,
            block.timestamp + 3600
        );
        vm.stopPrank();

        // Verify NFT was minted to alice
        assertEq(IERC721(address(nfpm)).ownerOf(tokenId), alice);

        // Verify position has liquidity
        (, , , , , , , uint128 liquidity, , , , ) = nfpm.positions(tokenId);
        assertGt(liquidity, 0);
    }

    function test_openPosition_refundsExcess() public {
        uint256 balanceBefore0 = token0.balanceOf(alice);
        uint256 balanceBefore1 = token1.balanceOf(alice);

        vm.startPrank(alice);
        token0.approve(address(opener), AMOUNT_IN);

        opener.openPosition(
            poolAddr,
            address(token0),
            AMOUNT_IN,
            LOW_TICK,
            HIGH_TICK,
            AMOUNT_SWAP,
            AMOUNT_SWAP - 1e17,
            block.timestamp + 3600
        );
        vm.stopPrank();

        uint256 balanceAfter0 = token0.balanceOf(alice);
        uint256 balanceAfter1 = token1.balanceOf(alice);

        // User should have received some refund (not all input was consumed)
        // token0 balance decreased but may have gotten some back
        assertLt(balanceAfter0, balanceBefore0, "token0 should have decreased");

        // token1 balance should have increased or stayed the same (refund of unused swap output)
        assertGe(balanceAfter1, balanceBefore1, "token1 should not decrease");

        // Opener contract should have no leftover tokens
        assertEq(token0.balanceOf(address(opener)), 0, "opener should have no token0");
        assertEq(token1.balanceOf(address(opener)), 0, "opener should have no token1");
    }

    function test_openPosition_revertsInvalidToken() public {
        MockERC20 badToken = new MockERC20("Bad", "BAD", 18);
        badToken.mint(alice, AMOUNT_IN);

        vm.startPrank(alice);
        badToken.approve(address(opener), AMOUNT_IN);

        vm.expectRevert(UniV3PositionOpener.InvalidToken.selector);
        opener.openPosition(
            poolAddr,
            address(badToken),
            AMOUNT_IN,
            LOW_TICK,
            HIGH_TICK,
            AMOUNT_SWAP,
            0,
            block.timestamp + 3600
        );
        vm.stopPrank();
    }

    function test_openPosition_slippageProtection() public {
        vm.startPrank(alice);
        token0.approve(address(opener), AMOUNT_IN);

        // Set amountOutMinimum higher than amountSwap to trigger slippage revert
        vm.expectRevert("Slippage too high");
        opener.openPosition(
            poolAddr,
            address(token0),
            AMOUNT_IN,
            LOW_TICK,
            HIGH_TICK,
            AMOUNT_SWAP,
            AMOUNT_SWAP + 1e18, // unreasonably high minimum
            block.timestamp + 3600
        );
        vm.stopPrank();
    }
}

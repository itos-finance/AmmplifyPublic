// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { IERC4626 } from "a@openzeppelin/contracts/interfaces/IERC4626.sol";
import { ERC20 } from "a@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Strings } from "a@openzeppelin/contracts/utils/Strings.sol";
import { IDiamond } from "Commons/Diamond/interfaces/IDiamond.sol";
import { DiamondCutFacet } from "Commons/Diamond/facets/DiamondCutFacet.sol";
import { SimplexDiamond } from "../../src/Diamond.sol";
import { AdminFacet } from "../src/facets/Admin.sol";
import { MakerFacet } from "../src/facets/Maker.sol";
import { TakerFacet } from "../src/facets/Taker.sol";
import { PoolFacet } from "../src/facets/Pool.sol";
import { ViewFacet } from "../src/facets/View.sol";

import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockERC4626 } from "./mocks/MockERC4626.sol";

contract MultiSetupTest is Test {
    // Note: removed the constant tag so we can override INITAL_VALUE in interiting tests
    uint256 public INITIAL_MINT_AMOUNT = 1e30;
    uint128 public INITIAL_VALUE = 1_000_000e18;

    /* Diamond */
    address public diamond;
    AdminFacet public adminFacet;
    MakerFacet public makerFacet;
    TakerFacet public takerFacet;
    PoolFacet public poolFacet;
    ViewFacet public viewFacet;

    /* Test Tokens */
    /// Two mock erc20s for convenience. These are guaranteed to be sorted.
    MockERC20 public token0;
    MockERC20 public token1;
    address[] public tokens;
    IERC4626[] public vaults;

    /* Some Test accounts */
    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    /// Deploy the diamond and facets
    function _newDiamond() internal {
        diamond = address(new SimplexDiamond());

        adminFacet = AdminFacet(diamond);
        makerFacet = MakerFacet(diamond);
        takerFacet = TakerFacet(diamond);
        poolFacet = PoolFacet(diamond);
        viewFacet = ViewFacet(diamond);
    }

    /// Call this last since it messes with prank.
    function _fundAccount(address account) internal {
        for (uint256 i = 0; i < tokens.length; ++i) {
            MockERC20(tokens[i]).mint(account, INITIAL_MINT_AMOUNT);
        }

        // Approve diamond for all test accounts
        vm.startPrank(account);
        for (uint256 i = 0; i < tokens.length; ++i) {
            MockERC20(tokens[i]).approve(address(diamond), type(uint256).max);
        }
        vm.stopPrank();
    }
}

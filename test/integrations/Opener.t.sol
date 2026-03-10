// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { IERC20 } from "a@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { MultiSetupTest } from "../MultiSetup.u.sol";
import { UniV4IntegrationSetup } from "../UniV4.u.sol";
import { Opener } from "../../src/integrations/Opener.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { IView } from "../../src/interfaces/IView.sol";
import { PoolKey } from "v4-core/types/PoolKey.sol";
import { TickMath } from "v4-core/libraries/TickMath.sol";
import { LiquidityAmounts } from "../../src/integrations/LiquidityAmounts.sol";

contract OpenerTest is MultiSetupTest, UniV4IntegrationSetup {
    Opener public opener;

    uint24 public constant POOL_FEE = 3000;
    int24 public constant LOW_TICK = -600;
    int24 public constant HIGH_TICK = 600;

    function setUp() public {
        // Setup a pool
        (, address poolAddr, address token0Addr, address token1Addr) = setUpPool(POOL_FEE);

        token0 = MockERC20(token0Addr);
        token1 = MockERC20(token1Addr);

        // Setup the diamond and facets
        _newDiamond(manager);

        // Register the pool with the diamond
        _registerPool(poolKeys[0]);

        // Populate tokens array for _fundAccount
        tokens.push(address(token0));
        tokens.push(address(token1));

        // Create vaults for token0 and token1
        _createPoolVaults(poolAddr);

        // Add liquidity to the pool so swaps work
        token0.mint(address(this), 1e24);
        token1.mint(address(this), 1e24);
        addPoolLiq(0, LOW_TICK * 10, HIGH_TICK * 10, 100e18);

        // Deploy Opener with V4 PoolManager
        opener = new Opener(address(diamond), address(manager));
        adminFacet.addPermissionedOpener(address(opener));
    }

    function test_openMakerWithSwap() public {
        address user = makeAddr("user");
        uint256 amountIn = 10e18;

        // Give user only token1 (they need to swap for token0)
        token1.mint(user, amountIn);

        // Calculate how much token0 to swap for
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(0); // price = 1
        uint160 sqrtPriceAX96 = TickMath.getSqrtPriceAtTick(LOW_TICK);
        uint160 sqrtPriceBX96 = TickMath.getSqrtPriceAtTick(HIGH_TICK);

        // We want a modest amount of token0 from the swap
        uint256 amountSwap = 1e18;

        vm.startPrank(user);

        // Approve Opener to spend token1
        token1.approve(address(opener), type(uint256).max);

        // Grant permission for Opener to open positions on behalf of user
        makerFacet.addPermission(address(opener));

        // Open position
        uint256 assetId = opener.openMaker(
            poolKeys[0], // poolKey
            pools[0], // poolAddr (diamond's pool address)
            address(token1), // tokenIn
            amountIn, // amountIn
            LOW_TICK,
            HIGH_TICK,
            uint160(TickMath.MIN_SQRT_PRICE + 1),
            uint160(TickMath.MAX_SQRT_PRICE - 1),
            0, // amountOutMinimum (no slippage check for test)
            amountSwap, // amountSwap
            "" // rftData
        );

        vm.stopPrank();

        // Verify position was created
        assertTrue(assetId > 0, "Asset should be created");

        // Verify user got refund of unused tokens
        uint256 userBalance0 = token0.balanceOf(user);
        uint256 userBalance1 = token1.balanceOf(user);
        // User should have some token1 refunded and potentially some token0 refunded
        assertTrue(userBalance0 > 0 || userBalance1 > 0, "User should have refund");
    }

    function test_openMakerSlippageRevert() public {
        address user = makeAddr("user");
        uint256 amountIn = 10e18;

        token1.mint(user, amountIn);

        vm.startPrank(user);
        token1.approve(address(opener), type(uint256).max);
        makerFacet.addPermission(address(opener));

        // Set amountOutMinimum very high to trigger slippage revert
        vm.expectRevert(Opener.SlippageTooHigh.selector);
        opener.openMaker(
            poolKeys[0],
            pools[0],
            address(token1),
            amountIn,
            LOW_TICK,
            HIGH_TICK,
            uint160(TickMath.MIN_SQRT_PRICE + 1),
            uint160(TickMath.MAX_SQRT_PRICE - 1),
            1000000e18, // amountOutMinimum - impossibly high
            1e18, // amountSwap
            ""
        );

        vm.stopPrank();
    }

    function test_openMakerInvalidToken() public {
        address user = makeAddr("user");
        MockERC20 fakeToken = new MockERC20("Fake", "FK", 18);
        fakeToken.mint(user, 10e18);

        vm.startPrank(user);
        fakeToken.approve(address(opener), type(uint256).max);

        vm.expectRevert(Opener.InvalidToken.selector);
        opener.openMaker(
            poolKeys[0],
            pools[0],
            address(fakeToken), // not part of the pool
            10e18,
            LOW_TICK,
            HIGH_TICK,
            uint160(TickMath.MIN_SQRT_PRICE + 1),
            uint160(TickMath.MAX_SQRT_PRICE - 1),
            0,
            1e18,
            ""
        );

        vm.stopPrank();
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IUniswapV3Pool } from "v3-core/interfaces/IUniswapV3Pool.sol";
import { TickMath } from "v3-core/libraries/TickMath.sol";

import { Opener } from "../../src/integrations/Opener.sol";
import { AdminFacet } from "../../src/facets/Admin.sol";

/// @notice Fork test for the new Opener against live Monad mainnet state.
///         Focuses on `openMakerOptimal`, which the current on-chain Opener
///         does not expose, and compares it against the legacy `openMaker`
///         path to verify the "tighter spread" claim.
contract OpenerForkTest is Test {
    // --- Monad mainnet deployments -------------------------------------------------
    // Pulled from ammplify-fe/src/lib/constant/protocol.ts + on-chain probing.
    address constant DIAMOND = 0x5B5e9d616fAFCCC4865a6C29b6F89Ff3aAE7c892; // uniswapDiamond
    address constant DIAMOND_OWNER = 0x2a42bE604948c0cce8a1FCFC781089611E2a1ea0;

    // WMON/USDC 0.3% pool.
    address constant POOL = 0x659bD0BC4167BA25c62E05656F78043E7eD4a9da;
    address constant WMON = 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A; // token0, 18 dec
    address constant USDC = 0x754704Bc059F8C67012fEd69BC8A327a5aafb603; // token1, 6 dec

    // Tick range from a real user transaction that motivated this work.
    int24 constant LOW_TICK = -310980;
    int24 constant HIGH_TICK = -309120;

    Opener internal opener;
    address internal user;

    function setUp() public {
        vm.createSelectFork(vm.envString("FORK_URL"));

        // Sanity: we're on Monad mainnet (chain id 143).
        assertEq(block.chainid, 143, "fork URL must point to Monad mainnet");

        opener = new Opener(DIAMOND);

        vm.prank(DIAMOND_OWNER);
        AdminFacet(DIAMOND).addPermissionedOpener(address(opener));

        user = makeAddr("maker-user");
    }

    // -----------------------------------------------------------------------------
    // openMakerOptimal happy paths
    // -----------------------------------------------------------------------------

    function test_OpenMakerOptimal_DepositWMON_InRange() public {
        // ~322.83 WMON, matches the calldata from the failing user tx.
        uint256 amountIn = 322_827500000000000000;
        deal(WMON, user, amountIn);

        vm.startPrank(user);
        IERC20(WMON).approve(address(opener), amountIn);

        uint256 assetId = opener.openMakerOptimal(
            POOL,
            WMON,
            amountIn,
            LOW_TICK,
            HIGH_TICK,
            true, // isCompounding
            TickMath.MIN_SQRT_RATIO,
            TickMath.MAX_SQRT_RATIO,
            0, // amountOutMinimum: loose, we're not asserting slippage here
            ""
        );
        vm.stopPrank();

        assertGt(assetId, 0, "assetId must be non-zero");

        uint256 leftoverWmon = IERC20(WMON).balanceOf(user);
        uint256 leftoverUsdc = IERC20(USDC).balanceOf(user);
        console2.log("leftover WMON wei:", leftoverWmon);
        console2.log("leftover USDC (6dec):", leftoverUsdc);

        // At worst we refund dust; the position should have consumed the bulk of WMON.
        assertLt(leftoverWmon, amountIn / 100, "refund should be < 1% of deposit");
        // Opener should not leave tokenOut stranded on the user; it mints into the position.
        assertLt(leftoverUsdc, 1e6, "leftover USDC should be < 1 USDC");
    }

    function test_OpenMakerOptimal_DepositUSDC_InRange() public {
        uint256 amountIn = 10_000_000; // 10 USDC
        deal(USDC, user, amountIn);

        vm.startPrank(user);
        IERC20(USDC).approve(address(opener), amountIn);

        uint256 assetId = opener.openMakerOptimal(
            POOL,
            USDC,
            amountIn,
            LOW_TICK,
            HIGH_TICK,
            true,
            TickMath.MIN_SQRT_RATIO,
            TickMath.MAX_SQRT_RATIO,
            0,
            ""
        );
        vm.stopPrank();

        assertGt(assetId, 0, "assetId must be non-zero");
        assertLt(IERC20(USDC).balanceOf(user), amountIn / 100, "USDC refund should be dust");
    }

    // -----------------------------------------------------------------------------
    // Revert paths
    // -----------------------------------------------------------------------------

    function test_OpenMakerOptimal_RevertsOnInvalidToken() public {
        address notInPool = makeAddr("not-a-pool-token");
        // Fund user with the arbitrary token via vm.etch is overkill; we just need
        // the approve call to be skipped because the revert fires before any transfer.
        vm.startPrank(user);
        vm.expectRevert(Opener.InvalidToken.selector);
        opener.openMakerOptimal(
            POOL,
            notInPool,
            1 ether,
            LOW_TICK,
            HIGH_TICK,
            true,
            TickMath.MIN_SQRT_RATIO,
            TickMath.MAX_SQRT_RATIO,
            0,
            ""
        );
        vm.stopPrank();
    }

    // -----------------------------------------------------------------------------
    // Legacy openMaker still works on the new contract (sanity).
    // -----------------------------------------------------------------------------

    function test_LegacyOpenMaker_WithFeComputedSwap() public {
        uint256 amountIn = 322_827500000000000000;
        uint256 amountSwap = 5_467_500; // ~5.4675 USDC, pulled from the failing user tx
        uint256 amountOutMin = 5_412_816;
        deal(WMON, user, amountIn);

        vm.startPrank(user);
        IERC20(WMON).approve(address(opener), amountIn);

        uint256 assetId = opener.openMaker(
            POOL,
            WMON,
            amountIn,
            LOW_TICK,
            HIGH_TICK,
            true,
            TickMath.MIN_SQRT_RATIO,
            TickMath.MAX_SQRT_RATIO,
            amountOutMin,
            amountSwap,
            ""
        );
        vm.stopPrank();
        assertGt(assetId, 0, "legacy path should still mint a position");
    }

    // -----------------------------------------------------------------------------
    // Side-by-side: optimal swap leaves less unused deposit than FE-computed swap.
    // Each path runs against the same fork state; we reset between them so price
    // movement from the first swap doesn't skew the comparison.
    // -----------------------------------------------------------------------------

    function test_OptimalLeavesLessRefundThanLegacy() public {
        uint256 amountIn = 322_827500000000000000;
        uint256 snap = vm.snapshot();

        // --- Legacy path ---
        deal(WMON, user, amountIn);
        vm.startPrank(user);
        IERC20(WMON).approve(address(opener), amountIn);
        opener.openMaker(
            POOL, WMON, amountIn, LOW_TICK, HIGH_TICK, true,
            TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO,
            5_412_816, 5_467_500, ""
        );
        vm.stopPrank();
        uint256 legacyRefundWmon = IERC20(WMON).balanceOf(user);
        uint256 legacyRefundUsdc = IERC20(USDC).balanceOf(user);

        vm.revertTo(snap);

        // --- Optimal path ---
        deal(WMON, user, amountIn);
        vm.startPrank(user);
        IERC20(WMON).approve(address(opener), amountIn);
        opener.openMakerOptimal(
            POOL, WMON, amountIn, LOW_TICK, HIGH_TICK, true,
            TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO,
            0, ""
        );
        vm.stopPrank();
        uint256 optimalRefundWmon = IERC20(WMON).balanceOf(user);
        uint256 optimalRefundUsdc = IERC20(USDC).balanceOf(user);

        console2.log("legacy  refund WMON:", legacyRefundWmon);
        console2.log("legacy  refund USDC:", legacyRefundUsdc);
        console2.log("optimal refund WMON:", optimalRefundWmon);
        console2.log("optimal refund USDC:", optimalRefundUsdc);

        // "Tighter spread" = less *value* left on the table after minting. The
        // legacy path swaps to a FE-estimated USDC amount and tends to overshoot
        // the balanced ratio, refunding meaningful tokenOut. The optimal path
        // targets the ratio on-chain and leaves only rounding dust.
        // Convert both refunds into a common unit (WMON) using the mainnet tick
        // price (~$0.0295 → ~33.9 WMON per USDC).
        uint256 WMON_PER_USDC = 33_900_000_000_000_000_000; // 33.9 WMON (18dec) per 1 USDC (6dec)
        uint256 legacyValueWmon = legacyRefundWmon
            + (legacyRefundUsdc * WMON_PER_USDC) / 1e6;
        uint256 optimalValueWmon = optimalRefundWmon
            + (optimalRefundUsdc * WMON_PER_USDC) / 1e6;
        console2.log("legacy  refund value (WMON):", legacyValueWmon);
        console2.log("optimal refund value (WMON):", optimalValueWmon);

        assertLt(
            optimalValueWmon,
            legacyValueWmon / 10,
            "optimal should waste >10x less value than legacy"
        );
    }
}

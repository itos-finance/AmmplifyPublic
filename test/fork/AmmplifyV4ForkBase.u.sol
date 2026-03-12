// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.26;

import { IERC20 } from "Commons/ERC/interfaces/IERC20.sol";
import { ForkableTest } from "Commons/Test/ForkableTest.sol";
import { IPoolManager } from "v4-core/interfaces/IPoolManager.sol";
import { IUnlockCallback } from "v4-core/interfaces/callback/IUnlockCallback.sol";
import { PoolKey } from "v4-core/types/PoolKey.sol";
import { PoolId, PoolIdLibrary } from "v4-core/types/PoolId.sol";
import { Currency } from "v4-core/types/Currency.sol";
import { IHooks } from "v4-core/interfaces/IHooks.sol";
import { BalanceDelta } from "v4-core/types/BalanceDelta.sol";
import { ModifyLiquidityParams, SwapParams } from "v4-core/types/PoolOperation.sol";
import { StateLibrary } from "v4-core/libraries/StateLibrary.sol";
import { TickMath } from "v4-core/libraries/TickMath.sol";

import { SimplexDiamond } from "../../src/Diamond.sol";
import { AdminFacet } from "../../src/facets/Admin.sol";
import { MakerFacet } from "../../src/facets/Maker.sol";
import { TakerFacet } from "../../src/facets/Taker.sol";
import { PoolFacet } from "../../src/facets/Pool.sol";
import { ViewFacet } from "../../src/facets/View.sol";
import { PoolLib, PoolInfo } from "../../src/Pool.sol";

/// @title AmmplifyV4ForkBase
/// @notice Base contract for fork testing Ammplify against a V4 PoolManager on Monad mainnet.
/// @dev Reads V4 addresses from monad-v4.json, deploys a fresh Ammplify diamond, and registers
///      a USDC/WMON pool. Provides helpers for V4 liquidity and swap operations.
contract AmmplifyV4ForkBase is ForkableTest, IUnlockCallback {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    // ── V4 contracts ────────────────────────────────────────────────────
    IPoolManager public poolManager;

    // ── Ammplify contracts ──────────────────────────────────────────────
    SimplexDiamond public diamond;
    AdminFacet public adminFacet;
    MakerFacet public makerFacet;
    TakerFacet public takerFacet;
    ViewFacet public viewFacet;

    // ── Pool state ──────────────────────────────────────────────────────
    PoolKey public poolKey;
    address public poolAddr; // Deterministic address used by Ammplify
    IERC20 public token0;
    IERC20 public token1;

    // ── Callback plumbing (for direct V4 interactions in tests) ────────
    enum CallbackAction { MODIFY_LIQ, SWAP }
    CallbackAction private _action;
    int24 private _tickLower;
    int24 private _tickUpper;
    int256 private _liquidityDelta;
    bool private _zeroForOne;
    int256 private _amountSpecified;
    uint160 private _sqrtPriceLimitX96;

    // ── Constants ───────────────────────────────────────────────────────
    uint24 public constant DEFAULT_FEE = 3000;
    int24 public constant DEFAULT_TICK_SPACING = 60;

    // ─────────────────────────────────────────────────────────────────────
    //  Setup
    // ─────────────────────────────────────────────────────────────────────

    function forkSetup() internal virtual override {
        // Load V4 addresses from monad-v4.json (independent of DEPLOYED_ADDRS_PATH)
        string memory jsonPath = string.concat(vm.projectRoot(), "/monad-v4.json");
        string memory json = vm.readFile(jsonPath);

        poolManager = IPoolManager(vm.parseJsonAddress(json, ".poolManager"));

        address usdc = vm.parseJsonAddress(json, ".tokens.USDC");
        address wmon = vm.parseJsonAddress(json, ".tokens.WMON");

        // Sort tokens for V4 PoolKey (currency0 < currency1)
        (address t0, address t1) = usdc < wmon ? (usdc, wmon) : (wmon, usdc);
        token0 = IERC20(t0);
        token1 = IERC20(t1);

        // Build PoolKey
        poolKey = PoolKey({
            currency0: Currency.wrap(t0),
            currency1: Currency.wrap(t1),
            fee: DEFAULT_FEE,
            tickSpacing: DEFAULT_TICK_SPACING,
            hooks: IHooks(address(0))
        });

        // Initialize pool on the forked PoolManager if it doesn't exist yet
        _initializePoolIfNeeded();

        // Deploy Ammplify diamond pointing at the forked PoolManager
        _deployDiamond();

        // Register pool so the diamond recognises it
        poolAddr = adminFacet.registerPool(poolKey);

        // Seed pool with baseline liquidity so test positions have a price context
        _seedPoolLiquidity();
    }

    function deploySetup() internal virtual override {
        // No local deploy needed — fork tests only
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Internal helpers
    // ─────────────────────────────────────────────────────────────────────

    function _initializePoolIfNeeded() internal {
        PoolId poolId = poolKey.toId();
        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(poolId);
        if (sqrtPriceX96 == 0) {
            // Initialize at tick 0 (1:1 price)
            poolManager.initialize(poolKey, TickMath.getSqrtPriceAtTick(0));
        }
    }

    function _deployDiamond() internal {
        AdminFacet adminImpl = new AdminFacet();
        MakerFacet makerImpl = new MakerFacet();
        TakerFacet takerImpl = new TakerFacet();
        PoolFacet poolImpl = new PoolFacet();
        ViewFacet viewImpl = new ViewFacet();

        SimplexDiamond.FacetAddresses memory facetAddresses = SimplexDiamond.FacetAddresses({
            adminFacet: address(adminImpl),
            makerFacet: address(makerImpl),
            takerFacet: address(takerImpl),
            poolFacet: address(poolImpl),
            viewFacet: address(viewImpl)
        });

        diamond = new SimplexDiamond(address(poolManager), facetAddresses);

        adminFacet = AdminFacet(address(diamond));
        makerFacet = MakerFacet(address(diamond));
        takerFacet = TakerFacet(address(diamond));
        viewFacet = ViewFacet(address(diamond));
    }

    function _seedPoolLiquidity() internal {
        int24 spacing = poolKey.tickSpacing;
        int24 minTick = (TickMath.MIN_TICK / spacing) * spacing;
        int24 maxTick = (TickMath.MAX_TICK / spacing) * spacing;

        // Fund this contract for seeding
        deal(address(token0), address(this), 1_000e18);
        deal(address(token1), address(this), 1_000e18);

        addLiquidity(minTick, maxTick, 1e18);

        // Advance time so the pool has observation history
        skip(1 days);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  V4 interaction helpers (public so tests can use them)
    // ─────────────────────────────────────────────────────────────────────

    function addLiquidity(int24 tickLower, int24 tickUpper, uint128 amount) public {
        if (amount == 0) return;
        _action = CallbackAction.MODIFY_LIQ;
        _tickLower = tickLower;
        _tickUpper = tickUpper;
        _liquidityDelta = int256(uint256(amount));
        poolManager.unlock("");
    }

    function removeLiquidity(int24 tickLower, int24 tickUpper, uint128 amount) public {
        _action = CallbackAction.MODIFY_LIQ;
        _tickLower = tickLower;
        _tickUpper = tickUpper;
        _liquidityDelta = -int256(uint256(amount));
        poolManager.unlock("");
    }

    function doSwap(bool zeroForOne, int256 amountSpecified) public {
        _action = CallbackAction.SWAP;
        _zeroForOne = zeroForOne;
        _amountSpecified = amountSpecified;
        _sqrtPriceLimitX96 = zeroForOne
            ? TickMath.MIN_SQRT_PRICE + 1
            : TickMath.MAX_SQRT_PRICE - 1;
        poolManager.unlock("");
    }

    // ─────────────────────────────────────────────────────────────────────
    //  V4 unlock callback
    // ─────────────────────────────────────────────────────────────────────

    function unlockCallback(bytes calldata) external override returns (bytes memory) {
        require(msg.sender == address(poolManager), "not manager");

        if (_action == CallbackAction.MODIFY_LIQ) {
            ModifyLiquidityParams memory params = ModifyLiquidityParams({
                tickLower: _tickLower,
                tickUpper: _tickUpper,
                liquidityDelta: _liquidityDelta,
                salt: bytes32(0)
            });
            (BalanceDelta delta, ) = poolManager.modifyLiquidity(poolKey, params, "");
            _settleDeltas(delta);
        } else if (_action == CallbackAction.SWAP) {
            SwapParams memory params = SwapParams({
                zeroForOne: _zeroForOne,
                amountSpecified: _amountSpecified,
                sqrtPriceLimitX96: _sqrtPriceLimitX96
            });
            BalanceDelta delta = poolManager.swap(poolKey, params, "");
            _settleDeltas(delta);
        }

        return "";
    }

    function _settleDeltas(BalanceDelta delta) internal {
        int128 d0 = delta.amount0();
        int128 d1 = delta.amount1();
        address t0 = address(token0);
        address t1 = address(token1);

        if (d0 < 0) {
            poolManager.sync(poolKey.currency0);
            IERC20(t0).transfer(address(poolManager), uint256(int256(-d0)));
            poolManager.settle();
        } else if (d0 > 0) {
            poolManager.take(poolKey.currency0, address(this), uint256(int256(d0)));
        }

        if (d1 < 0) {
            poolManager.sync(poolKey.currency1);
            IERC20(t1).transfer(address(poolManager), uint256(int256(-d1)));
            poolManager.settle();
        } else if (d1 > 0) {
            poolManager.take(poolKey.currency1, address(this), uint256(int256(d1)));
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    //  View helpers
    // ─────────────────────────────────────────────────────────────────────

    function getPoolSlot0() public view returns (uint160 sqrtPriceX96, int24 tick) {
        (sqrtPriceX96, tick, , ) = poolManager.getSlot0(poolKey.toId());
    }

    function getPoolLiquidity() public view returns (uint128) {
        return poolManager.getLiquidity(poolKey.toId());
    }

    function fundAccount(address account, uint256 amount0, uint256 amount1) public {
        deal(address(token0), account, amount0);
        deal(address(token1), account, amount1);
        vm.startPrank(account);
        token0.approve(address(diamond), type(uint256).max);
        token1.approve(address(diamond), type(uint256).max);
        vm.stopPrank();
    }
}

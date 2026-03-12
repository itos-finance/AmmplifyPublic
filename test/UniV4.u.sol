// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { PoolManager } from "v4-core/PoolManager.sol";
import { IPoolManager } from "v4-core/interfaces/IPoolManager.sol";
import { IUnlockCallback } from "v4-core/interfaces/callback/IUnlockCallback.sol";
import { PoolKey } from "v4-core/types/PoolKey.sol";
import { PoolId, PoolIdLibrary } from "v4-core/types/PoolId.sol";
import { Currency, CurrencyLibrary } from "v4-core/types/Currency.sol";
import { IHooks } from "v4-core/interfaces/IHooks.sol";
import { BalanceDelta } from "v4-core/types/BalanceDelta.sol";
import { ModifyLiquidityParams, SwapParams } from "v4-core/types/PoolOperation.sol";
import { TickMath } from "v4-core/libraries/TickMath.sol";
import { Strings } from "a@openzeppelin/contracts/utils/Strings.sol";
import { IERC20 } from "a@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { MockERC20 } from "./mocks/MockERC20.sol";
import { Test } from "forge-std/Test.sol";
import { PoolLib, PoolInfo } from "../src/Pool.sol";

/// V4 integration test setup, replacing the V3 UniV3IntegrationSetup.
contract UniV4IntegrationSetup is IUnlockCallback, Test {
    using PoolIdLibrary for PoolKey;

    uint160 public constant INIT_SQRT_PRICEX96 = 1 << 96;
    PoolManager public manager;
    ExternalUniV4Caller public extCaller;

    address[] public pools; // Deterministic pool addresses derived from PoolId
    address[] public poolToken0s;
    address[] public poolToken1s;
    int24[] public tickSpacings;
    PoolKey[] public poolKeys;

    // Transient callback state
    enum CallbackAction { MODIFY_LIQ, SWAP, POOL_LIB_OPS }
    CallbackAction private _action;
    uint256 private _idx;
    int24 private _tickLower;
    int24 private _tickUpper;
    int256 private _liquidityDelta;
    bool private _zeroForOne;
    int256 private _amountSpecified;
    uint160 private _sqrtPriceLimitX96;

    constructor() {
        manager = new PoolManager(address(this));
        extCaller = new ExternalUniV4Caller(address(manager));
    }

    function setUpPool() public returns (uint256 idx, address pool, address token0, address token1) {
        return setUpPool(3000);
    }

    function setUpPool(uint24 fee) public returns (uint256 idx, address pool, address token0, address token1) {
        return setUpPool(fee, type(uint256).max / 2, 0, INIT_SQRT_PRICEX96);
    }

    function setUpPool(
        uint24 fee,
        uint256 initialMint,
        uint128 initialLiq,
        uint160 initialPriceX96
    ) public returns (uint256 idx, address pool, address token0, address token1) {
        uint256 __idx = pools.length;
        string memory numString = Strings.toString(__idx);
        address tokenA = address(
            new MockERC20(string.concat("UniPoolToken A.", numString), string.concat("UPT.A.", numString), 18)
        );
        address tokenB = address(
            new MockERC20(string.concat("UniPoolToken B.", numString), string.concat("UPT.B.", numString), 18)
        );
        MockERC20(tokenA).mint(address(this), initialMint);
        MockERC20(tokenB).mint(address(this), initialMint);
        if (tokenA < tokenB) {
            token0 = tokenA;
            token1 = tokenB;
        } else {
            token0 = tokenB;
            token1 = tokenA;
        }

        (idx, pool) = setUpPool(token0, token1, fee, initialLiq, initialPriceX96);
    }

    function setUpPool(address token0, address token1) public returns (uint256 idx, address pool) {
        return setUpPool(token0, token1, 3000, 0, INIT_SQRT_PRICEX96);
    }

    function setUpPool(
        address token0,
        address token1,
        uint24 fee,
        uint128 initLiq,
        uint160 sqrtPriceX96
    ) public returns (uint256 idx, address pool) {
        if (token0 > token1) {
            (token0, token1) = (token1, token0);
        }
        idx = pools.length;

        // Determine tick spacing from fee (mirroring V3 convention)
        int24 spacing;
        if (fee == 500) spacing = 10;
        else if (fee == 3000) spacing = 60;
        else if (fee == 10000) spacing = 200;
        else spacing = 60; // default

        // Create V4 PoolKey
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: fee,
            tickSpacing: spacing,
            hooks: IHooks(address(0))
        });

        // Initialize pool in the PoolManager
        manager.initialize(poolKey, sqrtPriceX96);

        // Derive deterministic pool address from PoolId
        pool = address(uint160(uint256(PoolId.unwrap(poolKey.toId()))));

        pools.push(pool);
        poolToken0s.push(token0);
        poolToken1s.push(token1);
        tickSpacings.push(spacing);
        poolKeys.push(poolKey);

        // Approve tokens to the manager for liquidity provision
        IERC20(token0).approve(address(manager), type(uint256).max);
        IERC20(token1).approve(address(manager), type(uint256).max);

        addPoolLiq(idx, (TickMath.MIN_TICK / spacing) * spacing, (TickMath.MAX_TICK / spacing) * spacing, initLiq);
        skip(1 days);
    }

    function addPoolLiq(uint256 index, int24 low, int24 high, uint128 amount) public {
        if (amount == 0) return;
        _action = CallbackAction.MODIFY_LIQ;
        _idx = index;
        _tickLower = low;
        _tickUpper = high;
        _liquidityDelta = int256(uint256(amount));
        manager.unlock(abi.encode(index));
    }

    function removePoolLiq(uint256 index, int24 low, int24 high, uint128 amount) public {
        _action = CallbackAction.MODIFY_LIQ;
        _idx = index;
        _tickLower = low;
        _tickUpper = high;
        _liquidityDelta = -int256(uint256(amount));
        manager.unlock(abi.encode(index));
    }

    /// Execute batched PoolLib operations via the V4 unlock callback.
    function executePoolLibOps(PoolInfo memory pInfo) public {
        PoolLib.executeOps(pInfo);
    }

    function swap(uint256 index, int256 amount, bool zeroForOne) public {
        _action = CallbackAction.SWAP;
        _idx = index;
        _zeroForOne = zeroForOne;
        _amountSpecified = amount;
        _sqrtPriceLimitX96 = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        manager.unlock(abi.encode(index));
    }

    function swapTo(uint256 index, uint160 targetPriceX96) public {
        _action = CallbackAction.SWAP;
        _idx = index;
        _amountSpecified = type(int256).max;

        // Determine direction
        PoolKey memory poolKey = poolKeys[index];
        (uint160 currentPX96, , , ) = StateLibrary.getSlot0(manager, poolKey.toId());
        if (currentPX96 < targetPriceX96) {
            _zeroForOne = false;
            _sqrtPriceLimitX96 = targetPriceX96;
        } else {
            _zeroForOne = true;
            _sqrtPriceLimitX96 = targetPriceX96;
        }
        manager.unlock(abi.encode(index));
    }

    function extSwap(uint256 index, bool zeroForOne, int256 amountSpecified) public {
        IERC20 token0 = IERC20(poolToken0s[index]);
        IERC20 token1 = IERC20(poolToken1s[index]);
        token0.approve(address(extCaller), type(uint256).max);
        token1.approve(address(extCaller), type(uint256).max);

        extCaller.swap(
            poolKeys[index],
            address(this),
            zeroForOne,
            amountSpecified,
            zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        );

        token0.approve(address(extCaller), 0);
        token1.approve(address(extCaller), 0);
    }

    function extSwapTo(uint256 index, uint160 targetPriceX96) public {
        IERC20 token0 = IERC20(poolToken0s[index]);
        IERC20 token1 = IERC20(poolToken1s[index]);
        token0.approve(address(extCaller), type(uint256).max);
        token1.approve(address(extCaller), type(uint256).max);

        PoolKey memory poolKey = poolKeys[index];
        (uint160 currentPX96, , , ) = StateLibrary.getSlot0(manager, poolKey.toId());
        bool zeroForOne = currentPX96 >= targetPriceX96;

        extCaller.swap(poolKey, address(this), zeroForOne, type(int256).max, targetPriceX96);

        token0.approve(address(extCaller), 0);
        token1.approve(address(extCaller), 0);
    }

    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        require(msg.sender == address(manager), "not manager");

        // PoolLib.executeOps encodes (PoolKey, address, address) = 7 ABI words (224 bytes).
        // Our own callbacks encode (uint256) = 1 word (32 bytes).
        // Use data length to distinguish.
        if (data.length > 32) {
            return PoolLib.handleUnlockCallback(data);
        } else if (_action == CallbackAction.MODIFY_LIQ) {
            PoolKey memory poolKey = poolKeys[_idx];
            ModifyLiquidityParams memory params = ModifyLiquidityParams({
                tickLower: _tickLower,
                tickUpper: _tickUpper,
                liquidityDelta: _liquidityDelta,
                salt: bytes32(0)
            });

            (BalanceDelta delta, ) = manager.modifyLiquidity(poolKey, params, "");
            _settleDeltas(poolKey, delta);
        } else if (_action == CallbackAction.SWAP) {
            PoolKey memory poolKey = poolKeys[_idx];
            SwapParams memory params = SwapParams({
                zeroForOne: _zeroForOne,
                amountSpecified: _amountSpecified,
                sqrtPriceLimitX96: _sqrtPriceLimitX96
            });

            BalanceDelta delta = manager.swap(poolKey, params, "");
            _settleDeltas(poolKey, delta);
        }

        return "";
    }

    function _settleDeltas(PoolKey memory poolKey, BalanceDelta delta) internal {
        int128 d0 = delta.amount0();
        int128 d1 = delta.amount1();
        address token0 = Currency.unwrap(poolKey.currency0);
        address token1 = Currency.unwrap(poolKey.currency1);

        if (d0 < 0) {
            // We owe the pool manager (negative delta = caller must pay)
            manager.sync(poolKey.currency0);
            IERC20(token0).transfer(address(manager), uint256(int256(-d0)));
            manager.settle();
        } else if (d0 > 0) {
            // Pool owes us (positive delta = caller receives)
            manager.take(poolKey.currency0, address(this), uint256(int256(d0)));
        }

        if (d1 < 0) {
            manager.sync(poolKey.currency1);
            IERC20(token1).transfer(address(manager), uint256(int256(-d1)));
            manager.settle();
        } else if (d1 > 0) {
            manager.take(poolKey.currency1, address(this), uint256(int256(d1)));
        }
    }
}

import { StateLibrary } from "v4-core/libraries/StateLibrary.sol";

contract ExternalUniV4Caller is IUnlockCallback {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    IPoolManager public immutable manager;
    address private _caller;
    address private _recipient;
    PoolKey private _poolKey;
    bool private _zeroForOne;
    int256 private _amountSpecified;
    uint160 private _sqrtPriceLimitX96;

    constructor(address _manager) {
        manager = IPoolManager(_manager);
    }

    function swap(
        PoolKey memory poolKey,
        address to,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    ) external {
        _caller = msg.sender;
        _recipient = to;
        _poolKey = poolKey;
        _zeroForOne = zeroForOne;
        _amountSpecified = amountSpecified;
        _sqrtPriceLimitX96 = sqrtPriceLimitX96;

        // Transfer tokens from caller to us for payment
        if (zeroForOne) {
            IERC20(Currency.unwrap(poolKey.currency0)).transferFrom(msg.sender, address(this), type(uint256).max / 2);
        } else {
            IERC20(Currency.unwrap(poolKey.currency1)).transferFrom(msg.sender, address(this), type(uint256).max / 2);
        }

        manager.unlock("");
    }

    function unlockCallback(bytes calldata) external override returns (bytes memory) {
        require(msg.sender == address(manager), "not manager");

        SwapParams memory params = SwapParams({
            zeroForOne: _zeroForOne,
            amountSpecified: _amountSpecified,
            sqrtPriceLimitX96: _sqrtPriceLimitX96
        });

        BalanceDelta delta = manager.swap(_poolKey, params, "");

        // Settle
        address token0 = Currency.unwrap(_poolKey.currency0);
        address token1 = Currency.unwrap(_poolKey.currency1);
        int128 d0 = delta.amount0();
        int128 d1 = delta.amount1();

        if (d0 < 0) {
            manager.sync(_poolKey.currency0);
            IERC20(token0).transfer(address(manager), uint256(int256(-d0)));
            manager.settle();
        } else if (d0 > 0) {
            manager.take(_poolKey.currency0, _recipient, uint256(int256(d0)));
        }

        if (d1 < 0) {
            manager.sync(_poolKey.currency1);
            IERC20(token1).transfer(address(manager), uint256(int256(-d1)));
            manager.settle();
        } else if (d1 > 0) {
            manager.take(_poolKey.currency1, _recipient, uint256(int256(d1)));
        }

        // Return excess tokens to caller
        uint256 excess0 = IERC20(token0).balanceOf(address(this));
        uint256 excess1 = IERC20(token1).balanceOf(address(this));
        if (excess0 > 0) IERC20(token0).transfer(_caller, excess0);
        if (excess1 > 0) IERC20(token1).transfer(_caller, excess1);

        return "";
    }
}

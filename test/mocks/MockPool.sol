// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { IUniswapV3Pool } from "../../lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { MockERC20 } from "./MockERC20.sol";

// Mock Uniswap V3 Pool that implements the required interface
contract MockPool is IUniswapV3Pool {
    address public immutable override factory;
    address public immutable override token0;
    address public immutable override token1;
    uint24 public immutable override fee;
    int24 public immutable override tickSpacing;
    uint128 public immutable override maxLiquidityPerTick;

    MockERC20 public t0;
    MockERC20 public t1;

    constructor(address _factory, address _token0, address _token1, uint24 _fee) {
        factory = _factory;
        token0 = _token0;
        token1 = _token1;
        fee = _fee;
        tickSpacing = 60; // Default tick spacing
        maxLiquidityPerTick = type(uint128).max;

        t0 = MockERC20(_token0);
        t1 = MockERC20(_token1);
    }

    // Mock implementation of mint function
    function mint(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        bytes calldata data
    ) external override returns (uint256 amount0, uint256 amount1) {
        // Mock implementation - return some amounts based on liquidity
        amount0 = (uint256(amount) * 1e18) / 1e6; // Simple calculation
        amount1 = (uint256(amount) * 1e18) / 1e6;

        // Mint tokens to recipient if they don't have enough
        if (t0.balanceOf(recipient) < amount0) {
            t0.mint(recipient, amount0);
        }
        if (t1.balanceOf(recipient) < amount1) {
            t1.mint(recipient, amount1);
        }

        emit Mint(msg.sender, recipient, tickLower, tickUpper, amount, amount0, amount1);
        return (amount0, amount1);
    }

    // Mock implementation of burn function
    function burn(
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    ) external override returns (uint256 amount0, uint256 amount1) {
        // Mock implementation - return some amounts based on liquidity
        amount0 = (uint256(amount) * 1e18) / 1e6;
        amount1 = (uint256(amount) * 1e18) / 1e6;

        emit Burn(msg.sender, tickLower, tickUpper, amount, amount0, amount1);
        return (amount0, amount1);
    }

    // Mock implementation of collect function
    function collect(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external override returns (uint128 amount0, uint128 amount1) {
        // Mock implementation - mint some tokens to recipient
        amount0 = amount0Requested > 0 ? amount0Requested : 1e18;
        amount1 = amount1Requested > 0 ? amount1Requested : 1e18;

        t0.mint(recipient, amount0);
        t1.mint(recipient, amount1);

        emit Collect(msg.sender, recipient, tickLower, tickUpper, amount0, amount1);
        return (amount0, amount1);
    }

    // Required interface implementations with mock values
    function slot0()
        external
        pure
        override
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint32 feeProtocol,
            bool unlocked
        )
    {
        return (1 << 96, 0, 0, 0, 0, 0, true);
    }

    function feeGrowthGlobal0X128() external pure override returns (uint256) {
        return 0;
    }

    function feeGrowthGlobal1X128() external pure override returns (uint256) {
        return 0;
    }

    function protocolFees() external pure override returns (uint128, uint128) {
        return (0, 0);
    }

    function liquidity() external pure override returns (uint128) {
        return 0;
    }

    function ticks(
        int24
    )
        external
        pure
        override
        returns (
            uint128 liquidityGross,
            int128 liquidityNet,
            uint256 feeGrowthOutside0X128,
            uint256 feeGrowthOutside1X128,
            int56 tickCumulativeOutside,
            uint160 secondsPerLiquidityOutsideX128,
            uint32 secondsOutside,
            bool initialized
        )
    {
        return (0, 0, 0, 0, 0, 0, 0, false);
    }

    function tickBitmap(int16) external pure override returns (uint256) {
        return 0;
    }

    function positions(
        bytes32
    )
        external
        pure
        override
        returns (
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        return (0, 0, 0, 0, 0);
    }

    function observations(
        uint256
    ) external pure override returns (uint32 blockTimestamp, int56 tickCumulative, bool initialized) {
        return (0, 0, false);
    }

    // Derived state functions
    function observe(
        uint32[] calldata secondsAgos
    )
        external
        pure
        override
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {
        // Return empty arrays for mock
        tickCumulatives = new int56[](secondsAgos.length);
        secondsPerLiquidityCumulativeX128s = new uint160[](secondsAgos.length);
        return (tickCumulatives, secondsPerLiquidityCumulativeX128s);
    }

    function snapshotCumulativesInside(
        int24 tickLower,
        int24 tickUpper
    )
        external
        pure
        override
        returns (int56 tickCumulativeInside, uint160 secondsPerLiquidityInsideX128, uint32 secondsInside)
    {
        return (0, 0, 0);
    }

    // Other required functions with mock implementations
    function initialize(uint160 sqrtPriceX96) external override {
        emit Initialize(sqrtPriceX96, 0);
    }

    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external override returns (int256, int256) {
        emit Swap(msg.sender, recipient, 0, 0, sqrtPriceLimitX96, 0, 0);
        return (0, 0);
    }

    function flash(address recipient, uint256 amount0, uint256 amount1, bytes calldata data) external override {
        emit Flash(msg.sender, recipient, amount0, amount1, 0, 0);
    }

    function increaseObservationCardinalityNext(uint16 observationCardinalityNext) external override {
        emit IncreaseObservationCardinalityNext(0, observationCardinalityNext);
    }

    function setFeeProtocol(uint8 feeProtocol0, uint8 feeProtocol1) external override {
        emit SetFeeProtocol(0, 0, feeProtocol0, feeProtocol1);
    }

    function collectProtocol(
        address recipient,
        address recipient0,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external override returns (uint128, uint128) {
        emit CollectProtocol(msg.sender, recipient, amount0Requested, amount1Requested);
        return (amount0Requested, amount1Requested);
    }
}

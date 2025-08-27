// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { UniswapV3Factory } from "v3-core/UniswapV3Factory.sol";
import { UniswapV3Pool } from "v3-core/UniswapV3Pool.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { Strings } from "a@openzeppelin/contracts/utils/Strings.sol";

contract UniV3IntegrationSetup {
    UniswapV3Factory public factory;
    // NOTE: You don't need to store the return values of any of the setup functions besides idx
    // because you can retrieve the relevant information from here.
    address[] public pools;
    address[] public poolToken0s;
    address[] public poolToken1s;

    constructor() {
        factory = new UniswapV3Factory();
    }

    function setUpPool() public returns (uint256 idx, address pool, address token0, address token1) {
        return setUpPool(3000);
    }

    function setUpPool(uint24 fee) public returns (uint256 idx, address pool, address token0, address token1) {
        return setUpPool(fee, type(uint256).max / 2); // Give a little of a buffer, but still more than enough.
    }

    function setUpPool(
        uint24 fee,
        uint256 initialMint
    ) public returns (uint256 idx, address pool, address token0, address token1) {
        uint256 _idx = pools.length;
        string memory numString = Strings.toString(_idx);
        address tokenA = address(
            new MockERC20(string.concat("UniPoolToken A.", numString), string.concat("UPT.A.", numString))
        );
        address tokenB = address(
            new MockERC20(string.concat("UniPoolToken B.", numString), string.concat("UPT.B.", numString))
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

        (idx, pool) = setUpPool(token0, token1, fee);
    }

    function setUpPool(address token0, address token1) public returns (uint256 idx, address pool) {
        return setUpPool(token0, token1, 3000);
    }

    function setUpPool(address token0, address token1, uint24 fee) public returns (uint256 idx, address pool) {
        if (token0 > token1) {
            (token0, token1) = (token1, token0);
        }
        idx = pools.length;
        pool = factory.createPool(token0, token1, fee);
        pools.push(pool);
        poolToken0s.push(token0);
        poolToken1s.push(token1);
    }

    function addPoolLiq(uint256 index, int24 low, int24 high, uint128 amount) public {
        address pool = pools[index];
        UniswapV3Pool(pool).mint(address(this), low, high, amount, "");
    }

    function removePoolLiq(uint256 index, int24 low, int24 high, uint128 amount) public {
        address pool = pools[index];
        UniswapV3Pool(pool).burn(low, high, amount);
    }

    // Swap an amount in the pool.
    function swap(uint256 index, int256 amount, bool zeroForOne) public {
        address pool = pools[index];
        UniswapV3Pool(pool).swap(address(this), zeroForOne, amount, zeroForOne ? 0 : type(uint160).max, "");
    }

    // Swap the pool to a certain price.
    function swapTo(uint256 index, uint160 targetPriceX96) public {
        address pool = pools[index];
        (uint160 currentPX96, , , , , , ) = UniswapV3Pool(pool).slot0();
        if (currentPX96 < targetPriceX96) {
            UniswapV3Pool(pool).swap(address(this), true, type(int256).max, targetPriceX96, "");
        } else {
            UniswapV3Pool(pool).swap(address(this), false, type(int256).max, targetPriceX96, "");
        }
    }
}

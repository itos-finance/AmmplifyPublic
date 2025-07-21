// SPDX-License-Identifier: BUSL-1.1-or-later
pragma solidity ^0.8.27;

import { console2 as console } from "forge-std/console2.sol";

import { INonfungiblePositionManager } from "../../interfaces/uniswap/INonfungiblePositionManager.sol";
import { IUniswapV3Factory } from "../../interfaces/uniswap/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "../../interfaces/uniswap/IUniswapV3Pool.sol";

import { LiquidityAmounts } from "./LiquidityAmounts.sol";
import { TickMath } from "./TickMath.sol";

import { CallbackLib } from "./CallbackLib.sol";

/**
 * @notice There are two distinct ways to operate on an UniswapV3 position. We handle them both in this
 * library.
 *
 * Decomposition
 * This is process of breaking up NFT positions into the Hyperplex protocol. This action is taken
 * by users who deposit their position into Hyperplex for re-provisioning. These operations happen on the
 * nonfungiblePositionManager provided by the periphery library.
 *
 * Allocation
 * This is the process of creating and maintaining individual UniswapV3 positions for a range described by the
 * parent position's liquidity tree nodes.
 */
library V3PositionManagerLib {
    /// @notice revert when a nft position contains no liquidity
    error EmptyPosition();

    /////////////////////////////////////
    //          Decomposition          //
    /////////////////////////////////////

    /**
     * @notice queries the infomation needed to describe a user's unified position
     * @param nonfungiblePositionManager issuer and manager of nft based positions
     * @param uniswapV3Factory pool factory, used to find the pool from token0, token1, fee
     * @param tokenId to decompose
     */
    function withdraw(
        INonfungiblePositionManager nonfungiblePositionManager,
        IUniswapV3Factory uniswapV3Factory,
        uint256 tokenId
    ) internal returns (address pool, int24 tickLower, int24 tickUpper, uint256 amount0, uint256 amount1) {
        // fetch info for user's position
        uint128 liquidity;
        (pool, tickLower, tickUpper, liquidity) = V3PositionManagerLib.queryPosition(
            nonfungiblePositionManager,
            uniswapV3Factory,
            tokenId
        );

        if (liquidity == 0) {
            revert EmptyPosition();
        }

        // transfer the NFT to this contract
        nonfungiblePositionManager.safeTransferFrom(msg.sender, address(this), tokenId);

        // decrease liquidity by 100%
        V3PositionManagerLib.decreaseLiquidity(nonfungiblePositionManager, tokenId, liquidity);

        // collect all fees and tokens
        (amount0, amount1) = V3PositionManagerLib.collectOwed(nonfungiblePositionManager, tokenId);
    }

    /**
     * @notice queries the infomation needed to describe a user's unified position
     * @param nonfungiblePositionManager issuer and manager of nft based positions
     * @param uniswapV3Factory pool factory, used to find the pool from token0, token1, fee
     * @param tokenId to query
     */
    function queryPosition(
        INonfungiblePositionManager nonfungiblePositionManager,
        IUniswapV3Factory uniswapV3Factory,
        uint256 tokenId
    ) internal view returns (address, int24, int24, uint128) {
        (
            ,
            ,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            ,
            ,
            ,

        ) = nonfungiblePositionManager.positions(tokenId);

        address pool = uniswapV3Factory.getPool(token0, token1, fee);
        return (pool, tickLower, tickUpper, liquidity);
    }

    /**
     * @notice performs the decrease liquidit action on a nft position
     * note if this is being called, we're likely reducing the liquidity to zero of
     * the position, but won't burn the nft to save gas.
     * @param nonfungiblePositionManager issuer and manager of nft based positions
     * @param tokenId to action
     * @param liquidity to remove
     */
    function decreaseLiquidity(
        INonfungiblePositionManager nonfungiblePositionManager,
        uint256 tokenId,
        uint128 liquidity
    ) internal returns (uint256 amount0, uint256 amount1) {
        return
            nonfungiblePositionManager.decreaseLiquidity(
                INonfungiblePositionManager.DecreaseLiquidityParams({
                    tokenId: tokenId,
                    liquidity: liquidity,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp
                })
            );
    }

    /**
     * @notice collects the fees and removed amounts from an nft position
     * @param nonfungiblePositionManager issuer and manager of nft based positions
     * @param tokenId to action
     */
    function collectOwed(
        INonfungiblePositionManager nonfungiblePositionManager,
        uint256 tokenId
    ) internal returns (uint256 fees0, uint256 fees1) {
        return
            nonfungiblePositionManager.collect(
                INonfungiblePositionManager.CollectParams({
                    tokenId: tokenId,
                    recipient: address(this),
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                })
            );
    }

    //////////////////////////////////
    //          Allocation          //
    //////////////////////////////////
    /**
     * @notice wrapper around pool mint function to handle callback verification
     * @param pool to operate on
     * @param tickLower bound
     * @param tickUpper bound
     * @param liquidity to mint
     * @param data used to verify mint callback
     */
    function mint(
        IUniswapV3Pool pool,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        CallbackLib.CallbackData memory data
    ) internal returns (uint256 amount0, uint256 amount1) {
        (amount0, amount1) = pool.mint(address(this), tickLower, tickUpper, liquidity, abi.encode(data));
    }

    /**
     * @notice wrapper around pool burn function
     * @param pool to operate on
     * @param tickLower bound
     * @param tickUpper bound
     * @param liquidity to burn
     */
    function burn(
        IUniswapV3Pool pool,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) internal returns (uint256 amount0, uint256 amount1) {
        return pool.burn(tickLower, tickUpper, liquidity);
    }

    /**
     * @notice wrapper around pool collect function
     * @param pool to operate on
     * @param tickLower bound
     * @param tickUpper bound
     */
    function collect(
        IUniswapV3Pool pool,
        int24 tickLower,
        int24 tickUpper
    ) internal returns (uint256 amount0, uint256 amount1) {
        return pool.collect(address(this), tickLower, tickUpper, type(uint128).max, type(uint128).max);
    }

    /**
     * @notice queries the pools positions for the protocol owned position stats
     * @param pool to query
     * @param tickLower bound
     * @param tickUpper bound
     */
    function getPositionState(
        IUniswapV3Pool pool,
        int24 tickLower,
        int24 tickUpper
    )
        internal
        view
        returns (
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        return pool.positions(getPositionKey(tickLower, tickUpper));
    }

    /**
     * @notice finds the key for the protocol owned position
     * @param tickLower bound
     * @param tickUpper bound
     */
    function getPositionKey(int24 tickLower, int24 tickUpper) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), tickLower, tickUpper));
    }

    function lookupPositionState(
        IUniswapV3Pool pool,
        address holder,
        int24 tickLower,
        int24 tickUpper
    )
        internal
        view
        returns (
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        return pool.positions(keccak256(abi.encodePacked(holder, tickLower, tickUpper)));
    }

    /////////////////////////////
    //          Utils          //
    /////////////////////////////
    /**
     * @notice helper function to convert amounts of token0 / token1 to
     * a liquidity value
     * @param sqrtRatioX96 price from slot0
     * @param tickLower bound
     * @param tickUpper bound
     * @param amount0Desired max amount0 available for minting
     * @param amount1Desired max amount1 available for minting
     */
    function getLiquidityForAmounts(
        uint160 sqrtRatioX96,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) internal pure returns (uint128 liquidity) {
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            sqrtRatioAX96,
            sqrtRatioBX96,
            amount0Desired,
            amount1Desired
        );
    }

    /**
     * @notice helper function to convert the amount of liquidity to
     * amount0 and amount1
     * @param sqrtRatioX96 price from slot0
     * @param tickLower bound
     * @param tickUpper bound
     * @param liquidity to find amounts for
     * @param roundUp round amounts up
     */
    function getAmountsFromLiquidity(
        uint160 sqrtRatioX96,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        bool roundUp
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96,
            sqrtRatioAX96,
            sqrtRatioBX96,
            liquidity,
            roundUp
        );
    }

    /**
     * @notice used to determine the amount0 held by the lower passive position
     * @param liquidity to get amount for
     * @param lower tick
     * @param upper tick
     */
    function getAmount0FromLiquidity(
        uint128 liquidity,
        int24 lower,
        int24 upper
    ) internal pure returns (uint256 amount0) {
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(lower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(upper);

        return LiquidityAmounts.getAmount0ForLiquidity(sqrtRatioAX96, sqrtRatioBX96, liquidity);
    }

    /**
     * @notice used to determine the amount1 held by the upper passive position
     * @param liquidity to get amount for
     * @param lower tick
     * @param upper tick
     */
    function getAmount1FromLiquidity(
        uint128 liquidity,
        int24 lower,
        int24 upper
    ) internal pure returns (uint256 amount1) {
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(lower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(upper);

        return LiquidityAmounts.getAmount0ForLiquidity(sqrtRatioAX96, sqrtRatioBX96, liquidity);
    }

    /**
     * @notice
     * @param amount to get liquidity for
     * @param lower tick
     * @param upper tick
     */
    function getLiquidityForAmount0(
        uint256 amount,
        int24 lower,
        int24 upper
    ) internal pure returns (uint128 liquidity) {
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(lower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(upper);

        return LiquidityAmounts.getLiquidityForAmount0(sqrtRatioAX96, sqrtRatioBX96, amount);
    }

    /**
     * @notice
     * @param amount to get liquidity for
     * @param lower tick
     * @param upper tick
     */
    function getLiquidityForAmount1(
        uint256 amount,
        int24 lower,
        int24 upper
    ) internal pure returns (uint128 liquidity) {
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(lower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(upper);

        return LiquidityAmounts.getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioBX96, amount);
    }
}

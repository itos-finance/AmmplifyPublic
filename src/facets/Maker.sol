// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { PoolInfo } from "../Pool.sol";
import { Asset, AssetLib } from "../Asset.sol";
import { Data, DataImpl } from "../visitors/Data.sol";

contract MakerFacet {
    /// @notice Creates a new maker position.
    /// @param poolAddr The address of the pool.
    /// @param lowTick The lower tick of the liquidity range.
    /// @param highTick The upper tick of the liquidity range.
    /// @param liq The amount of liquidity to provide.
    /// @param minSqrtPriceX96 For any price dependent operations, the actual price of the pool must be above this.
    /// @param maxSqrtPriceX96 For any price dependent operations, the actual price of the pool must be below this.
    /// @param data Data passed during RFT to the payer.
    function newAsset(
        address recipient,
        address poolAddr,
        uint24 lowTick,
        uint24 highTick,
        uint128 liq,
        bool isCompounding,
        uint160 minSqrtPriceX96,
        uint160 maxSqrtPriceX96,
        bytes calldata rftData
    ) external returns (uint256 assetId) {
        PoolInfo memory pInfo = PoolLib.getPoolInfo(poolAddr);
        Asset storage asset;
        (asset, assetId) = AssetLib.newMaker(recipient, pInfo, lowTick, highTick, liq);
        Liqtype liqType = isCompounding ? LiqType.MAKER : LiqType.MAKER_NC;
        Data memory data = DataImpl.make(
            pInfo,
            SafeCast.toInt128(liq),
            liqType,
            asset,
            minSqrtPriceX96,
            maxSqrtPriceX96
        );
        // This fills in the nodes in the asset.
        WalkerLib.walk(pInfo, lowTick, highTick, data);
        address[] memory tokens = pInfo.tokens;
        address[] memory balances = new address[](2);
        balances[0] = data.xBalance;
        balances[1] = data.yBalance;
        RFTLib.settle(msg.sender, tokens, balances, rftData);
    }

    function removeAsset(
        address recipient,
        uint256 assetId,
        uint128 minSqrtPriceX96,
        uint128 maxSqrtPriceX96,
        bytes calldata rftData
    ) external returns (address token0, address token1, uint256 balance0, uint256 balance1) {
        Asset storage asset = AssetLib.getAsset(assetId);
        PoolInfo memory pInfo = PoolLib.getPoolInfo(asset.poolAddr);
        Data memory data = DataImpl.make(pInfo, -asset.liq, asset.liqType, asset, minSqrtPriceX96, maxSqrtPriceX96);
        WalkerLib.walk(pInfo, lowTick, highTick, data);
        AssetLib.removeAsset(assetId);
        address[] memory tokens = pInfo.tokens;
        address[] memory balances = new address[](2);
        balances[0] = data.xBalance;
        balances[1] = data.yBalance;
        RFTLib.settle(recipient, tokens, balances, rftData);
    }

    function viewAsset(
        uint256 assetId
    )
        external
        view
        returns (address poolAddr, uint128 liq, uint256 balance0, uint256 balance1, uint256 fees0, uint256 fees1)
    {
        Asset storage asset = AssetLib.getAsset(assetId);
        PoolInfo memory pInfo = PoolLib.getPoolInfo(asset.poolAddr);
        ViewData memory data = ViewDataImpl.make(pInfo, asset.liqType);
        ViewWalkerLib.walk(pInfo, asset.lowTick, asset.highTick, data);
        return (asset.poolAddr, asset.liq, data.xBalance, data.yBalance, data.fees0, data.fees1);
    }

    // Collecting fees from a position reverts back to the original liquidity profile.
    function collectFees(
        address recipient,
        uint256 assetId,
        bytes calldata rftData
    ) external returns (uint256 fees0, uint256 fees1) {
        Asset storage asset = AssetLib.getAsset(assetId);
        PoolInfo memory pInfo = PoolLib.getPoolInfo(asset.poolAddr);
        Data memory data = DataImpl.make(pInfo, -asset.liq, asset.liqType, asset, minSqrtPriceX96, maxSqrtPriceX96);
        WalkerLib.collectWalk(pInfo, lowTick, highTick, data);
        AssetLib.collectFees(assetId, data);
        address[] memory tokens = pInfo.tokens;
        address[] memory balances = new address[](2);
        balances[0] = data.xBalance;
        balances[1] = data.yBalance;
        RFTLib.settle(recipient, tokens, balances, rftData);
        fees0 = data.xBalance;
        fees1 = data.yBalance;
    }
}

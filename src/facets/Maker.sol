// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { PoolInfo } from "../Pool.sol";
import { Asset, AssetLib } from "../Asset.sol";
import { LiqType } from "../walkers/Liq.sol";
import { Data, DataImpl } from "../walkers/Data.sol";
import { ReentrancyGuardTransient } from "openzeppelin-contracts/contracts/utils/ReentrancyGuardTransient.sol";
import { WalkerLib } from "../walkers/Lib.sol";
import { PoolLib } from "../Pool.sol";
import { PoolWalker } from "../walkers/Pool.sol";
import { RFTLib } from "Commons/Util/RFT.sol";
import { FeeLib } from "../Fee.sol";

contract MakerFacet is ReentrancyGuardTransient {
    error NotMakerOwner(address owner, address sender);
    /// Thrown when the asset being view or removed is not a maker asset.
    error NotMaker(uint256 assetId);

    /// @notice Creates a new maker position.
    /// @param poolAddr The address of the pool.
    /// @param lowTick The lower tick of the liquidity range.
    /// @param highTick The upper tick of the liquidity range.
    /// @param liq The amount of liquidity to provide.
    /// @param minSqrtPriceX96 For any price dependent operations, the actual price of the pool must be above this.
    /// @param maxSqrtPriceX96 For any price dependent operations, the actual price of the pool must be below this.
    /// @param rftData Data passed during RFT to the payer.
    function newMaker(
        address recipient,
        address poolAddr,
        int24 lowTick,
        int24 highTick,
        uint128 liq,
        bool isCompounding,
        uint160 minSqrtPriceX96,
        uint160 maxSqrtPriceX96,
        bytes calldata rftData
    ) external nonReentrant returns (uint256 _assetId) {
        PoolInfo memory pInfo = PoolLib.getPoolInfo(poolAddr);
        (Asset storage asset, uint256 assetId) = AssetLib.newMaker(
            recipient,
            pInfo,
            lowTick,
            highTick,
            liq,
            isCompounding
        );
        Data memory data = DataImpl.make(pInfo, asset, minSqrtPriceX96, maxSqrtPriceX96, liq);
        // This fills in the nodes in the asset.
        WalkerLib.modify(pInfo, lowTick, highTick, data);
        // Settle balances.
        address[] memory tokens = pInfo.tokens();
        int256[] memory balances = new int256[](2);
        balances[0] = data.xBalance;
        balances[1] = data.yBalance;
        RFTLib.settle(msg.sender, tokens, balances, rftData);
        PoolWalker.settle(pInfo, lowTick, highTick, data);
        return assetId;
    }

    function removeMaker(
        address recipient,
        uint256 assetId,
        uint128 minSqrtPriceX96,
        uint128 maxSqrtPriceX96,
        bytes calldata rftData
    ) external nonReentrant returns (address token0, address token1, uint256 removedX, uint256 removedY) {
        Asset storage asset = AssetLib.getAsset(assetId);
        require(asset.owner == msg.sender, NotMakerOwner(asset.owner, msg.sender));
        require(asset.liqType == LiqType.MAKER || asset.liqType == LiqType.MAKER_NC, NotMaker(assetId));
        PoolInfo memory pInfo = PoolLib.getPoolInfo(asset.poolAddr);
        Data memory data = DataImpl.make(pInfo, asset, minSqrtPriceX96, maxSqrtPriceX96, 0);
        WalkerLib.modify(pInfo, asset.lowTick, asset.highTick, data);
        // Settle balances.
        PoolWalker.settle(pInfo, asset.lowTick, asset.highTick, data);
        removedX = uint256(-data.xBalance); // These are definitely negative.
        removedY = uint256(-data.yBalance);
        (removedX, removedY) = FeeLib.applyJITPenalties(asset, removedX, removedY);
        AssetLib.removeAsset(assetId);
        address[] memory tokens = pInfo.tokens();
        int256[] memory balances = new int256[](2);
        balances[0] = -int256(removedX); // We know they fit since they can only be less (in magnitude) than before.
        balances[1] = -int256(removedY);
        RFTLib.settle(recipient, tokens, balances, rftData);
        // Return values
        token0 = tokens[0];
        token1 = tokens[1];
    }

    // Collecting fees from a position reverts back to the original liquidity profile.
    function collectFees(
        address recipient,
        uint256 assetId,
        uint160 minSqrtPriceX96,
        uint160 maxSqrtPriceX96,
        bytes calldata rftData
    ) external nonReentrant returns (uint256 fees0, uint256 fees1) {
        Asset storage asset = AssetLib.getAsset(assetId);
        require(asset.liqType == LiqType.MAKER || asset.liqType == LiqType.MAKER_NC, NotMaker(assetId));
        PoolInfo memory pInfo = PoolLib.getPoolInfo(asset.poolAddr);
        // We collect simply by targeting the original liq balance.
        Data memory data = DataImpl.make(pInfo, asset, minSqrtPriceX96, maxSqrtPriceX96, asset.liq);
        WalkerLib.modify(pInfo, asset.lowTick, asset.highTick, data);
        // Update timestamp because for compounding liq, the liq has changed.
        // Plus if you're removing liquidity, you automatically collect on remove so no need to call this first.
        AssetLib.updateTimestamp(asset);
        // The compounds collect all the fees from the underlying positions.
        address[] memory tokens = pInfo.tokens();
        int256[] memory balances = new int256[](2);
        balances[0] = data.xBalance;
        balances[1] = data.yBalance;
        RFTLib.settle(recipient, tokens, balances, rftData);
        fees0 = uint256(-data.xBalance);
        fees1 = uint256(-data.yBalance);
    }
}

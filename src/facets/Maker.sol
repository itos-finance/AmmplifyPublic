// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { PoolInfo } from "../Pool.sol";
import { Asset, AssetLib } from "../Asset.sol";
import { LiqType } from "../walkers/Liq.sol";
import { Data, DataImpl } from "../walkers/Data.sol";
import { ReentrancyGuardTransient } from "openzeppelin-contracts/contracts/utils/ReentrancyGuardTransient.sol";
import { WalkerLib, CompoundWalkerLib } from "../walkers/Lib.sol";
import { PoolLib } from "../Pool.sol";
import { PoolWalker } from "../walkers/Pool.sol";
import { FeeLib } from "../Fee.sol";
import { IMaker } from "../interfaces/IMaker.sol";
import { RFTLib } from "Commons/Util/RFT.sol";

contract MakerFacet is ReentrancyGuardTransient, IMaker {
    uint128 public constant MIN_MAKER_LIQUIDITY = 1e6;

    /// @inheritdoc IMaker
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
        require(liq >= MIN_MAKER_LIQUIDITY, DeMinimusMaker(liq));
        PoolInfo memory pInfo = PoolLib.getPoolInfo(poolAddr); // 1 kB
        // When creating new positions, we make sure to validate the pool isn't malicious.
        pInfo.validate(); // .5 kB
        (Asset storage asset, uint256 assetId) = AssetLib.newMaker(
            recipient,
            pInfo,
            lowTick,
            highTick,
            liq,
            isCompounding
        ); // 1.2 kB
        Data memory data = DataImpl.make(pInfo, asset, minSqrtPriceX96, maxSqrtPriceX96, liq); // 4.6 kb
        // This fills in the nodes in the asset.
        WalkerLib.modify(pInfo, lowTick, highTick, data); // 21.5 kB
        // Settle balances.
        address[] memory tokens = pInfo.tokens();
        int256[] memory balances = new int256[](2);
        balances[0] = data.xBalance; // There are no fees to consider on new positions.
        balances[1] = data.yBalance;
        RFTLib.settle(msg.sender, tokens, balances, rftData); // 2.4 kB
        PoolWalker.settle(pInfo, lowTick, highTick, data); // 3.4 kB
        emit MakerCreated(
            recipient,
            poolAddr,
            assetId,
            lowTick,
            highTick,
            liq,
            isCompounding,
            balances[0],
            balances[1]
        );
        return assetId;
    }

    /// @inheritdoc IMaker
    function adjustMaker(
        address recipient,
        uint256 assetId,
        uint128 targetLiq,
        uint160 minSqrtPriceX96,
        uint160 maxSqrtPriceX96,
        bytes calldata rftData
    ) external nonReentrant returns (address token0, address token1, int256 delta0, int256 delta1) {
        Asset storage asset = AssetLib.getAsset(assetId);
        require(targetLiq >= MIN_MAKER_LIQUIDITY, DeMinimusMaker(targetLiq)); // Use remove if you want to remove.
        require(asset.owner == msg.sender, NotMakerOwner(asset.owner, msg.sender));
        require(asset.liqType == LiqType.MAKER || asset.liqType == LiqType.MAKER_NC, NotMaker(assetId));
        PoolInfo memory pInfo = PoolLib.getPoolInfo(asset.poolAddr);
        Data memory data = DataImpl.make(pInfo, asset, minSqrtPriceX96, maxSqrtPriceX96, targetLiq);
        WalkerLib.modify(pInfo, asset.lowTick, asset.highTick, data);
        address[] memory tokens = pInfo.tokens();
        int256[] memory balances = new int256[](2);
        if (data.xBalance == 0 && data.yBalance == 0) {
            revert DeMinimusMaker(targetLiq);
        } else if (targetLiq >= asset.liq) {
            // Adding more liq, may collect some fees but no need to apply JIT penalties.
            balances[0] = data.xBalance - int256(data.xFees);
            balances[1] = data.yBalance - int256(data.yFees);
            RFTLib.settle(msg.sender, tokens, balances, rftData);
            PoolWalker.settle(pInfo, asset.lowTick, asset.highTick, data);
        } else {
            // We're reducing, we may need to apply JIT penalties.
            // When reducing there should be no reason to pay anything more.
            require((data.yBalance <= 0) && (data.xBalance <= 0), "AIE");
            PoolWalker.settle(pInfo, asset.lowTick, asset.highTick, data);
            uint256 removedX = uint256(-data.xBalance);
            uint256 removedY = uint256(-data.yBalance);
            (removedX, removedY) = FeeLib.applyJITPenalties(asset, removedX, removedY, tokens[0], tokens[1]);
            balances[0] = -int256(removedX + data.xFees);
            balances[1] = -int256(removedY + data.yFees);
            RFTLib.settle(recipient, tokens, balances, rftData);
        }
        // The new "original" liq we collet to is now the targetLiq.
        asset.liq = targetLiq;
        // We have to apply jit afterwards in case someone is trying to use adjust to get around that.
        AssetLib.updateTimestamp(asset);
        emit MakerAdjusted(asset.owner, assetId, asset.poolAddr, targetLiq, balances[0], balances[1]);
        token0 = tokens[0];
        token1 = tokens[1];
        delta0 = balances[0];
        delta1 = balances[1];
    }

    /// @inheritdoc IMaker
    function removeMaker(
        address recipient,
        uint256 assetId,
        uint160 minSqrtPriceX96,
        uint160 maxSqrtPriceX96,
        bytes calldata rftData
    ) external nonReentrant returns (address token0, address token1, uint256 removedX, uint256 removedY) {
        Asset storage asset = AssetLib.getAsset(assetId);
        require(asset.owner == msg.sender, NotMakerOwner(asset.owner, msg.sender));
        require(asset.liqType == LiqType.MAKER || asset.liqType == LiqType.MAKER_NC, NotMaker(assetId));
        PoolInfo memory pInfo = PoolLib.getPoolInfo(asset.poolAddr);
        Data memory data = DataImpl.make(pInfo, asset, minSqrtPriceX96, maxSqrtPriceX96, 0);
        WalkerLib.modify(pInfo, asset.lowTick, asset.highTick, data);
        // Settle balances.
        address[] memory tokens = pInfo.tokens();
        PoolWalker.settle(pInfo, asset.lowTick, asset.highTick, data);
        removedX = uint256(-data.xBalance); // These are definitely negative.
        removedY = uint256(-data.yBalance);
        (removedX, removedY) = FeeLib.applyJITPenalties(asset, removedX, removedY, tokens[0], tokens[1]);
        // Fees are removed but don't get JIT penalized.
        removedX += data.xFees;
        removedY += data.yFees;
        emit MakerRemoved(recipient, assetId, asset.poolAddr, removedX, removedY);
        AssetLib.removeAsset(assetId);
        int256[] memory balances = new int256[](2);
        balances[0] = -int256(removedX);
        balances[1] = -int256(removedY);
        RFTLib.settle(recipient, tokens, balances, rftData);
        // Return values
        token0 = tokens[0];
        token1 = tokens[1];
    }

    // Collecting fees from a position reverts back to the original liquidity profile.
    /// @inheritdoc IMaker
    function collectFees(
        address recipient,
        uint256 assetId,
        uint160 minSqrtPriceX96,
        uint160 maxSqrtPriceX96,
        bytes calldata rftData
    ) external nonReentrant returns (uint256 fees0, uint256 fees1) {
        Asset storage asset = AssetLib.getAsset(assetId);
        require(asset.owner == msg.sender, NotMakerOwner(asset.owner, msg.sender));
        require(asset.liqType == LiqType.MAKER || asset.liqType == LiqType.MAKER_NC, NotMaker(assetId));
        PoolInfo memory pInfo = PoolLib.getPoolInfo(asset.poolAddr);
        // We collect simply by targeting the original liq balance.
        Data memory data = DataImpl.make(pInfo, asset, minSqrtPriceX96, maxSqrtPriceX96, asset.liq);
        WalkerLib.modify(pInfo, asset.lowTick, asset.highTick, data);
        PoolWalker.settle(pInfo, asset.lowTick, asset.highTick, data);
        // We don't apply the JIT penalty here because keeping the fees earned in the pool is not really a concern.
        // Even if technically someone can marginally reduce their JIT penalty be collecting and then removing.
        address[] memory tokens = pInfo.tokens();
        int256[] memory balances = new int256[](2);
        // Compounding fees are treated like liq (since they're removed in PoolWalker) so they'll show up in
        // the balance fields instead of the fee fields.
        balances[0] = data.xBalance - int256(data.xFees);
        balances[1] = data.yBalance - int256(data.yFees);
        RFTLib.settle(recipient, tokens, balances, rftData);
        // But all of this is fees.
        fees0 = uint256(-balances[0]);
        fees1 = uint256(-balances[1]);
        emit FeesCollected(recipient, assetId, asset.poolAddr, fees0, fees1);
    }

    /// Allow this address to open positions and give you ownership.
    function addPermission(address opener) external {
        AssetLib.addPermission(msg.sender, opener);
    }

    /// Remove this address from opening positions and giving you ownership.
    function removePermission(address opener) external {
        AssetLib.removePermission(msg.sender, opener);
    }

    // Collect fees from and compound a specific range of nodes.
    function compound(address poolAddr, int24 lowTick, int24 highTick) external nonReentrant {
        PoolInfo memory pInfo = PoolLib.getPoolInfo(poolAddr);
        Asset storage asset = AssetLib.nullAsset();
        // When compounding, the liq and asset parameters are unused.
        Data memory data = DataImpl.make(pInfo, asset, 0, type(uint160).max, 0);
        CompoundWalkerLib.compound(pInfo, lowTick, highTick, data);
        PoolWalker.settle(pInfo, lowTick, highTick, data);
    }
}

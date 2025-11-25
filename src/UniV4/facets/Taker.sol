// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { AdminLib } from "Commons/Util/Admin.sol";
import { AmmplifyAdminRights } from "./../../facets/Admin.sol";
import { ReentrancyGuardTransient } from "openzeppelin-contracts/contracts/utils/ReentrancyGuardTransient.sol";
import { SafeCast } from "Commons/Math/Cast.sol";
import { RFTLib } from "Commons/Util/RFT.sol";
import { Store } from "../../Store.sol";
import { PoolInfo, PoolLib } from "../Pool.sol";
import { Asset, AssetLib } from "../../Asset.sol";
import { Data, DataImpl } from "../../walkers/Data.sol";
import { WalkerLib } from "../../walkers/Lib.sol";
import { PoolWalker } from "../walkers/Pool.sol";
import { VaultLib } from "../../vaults/Vault.sol";
import { LiqType } from "../../walkers/Liq.sol";
import { ITaker } from "../../interfaces/ITaker.sol";

contract TakerFacet is ReentrancyGuardTransient, ITaker {
    // Higher requirement than makers.
    uint128 public constant MIN_TAKER_LIQUIDITY = 1e12;

    /// Our takers are permissioned, but anyone can collateralize for them.
    function collateralize(
        address recipient,
        address token,
        uint256 amount,
        bytes calldata data
    ) external nonReentrant {
        address[] memory tokens = new address[](1);
        tokens[0] = token;
        int256[] memory balances = new int256[](1);
        balances[0] = SafeCast.toInt256(amount);
        // We do a raw RFT call since this doesn't burn/mint.
        RFTLib.settle(msg.sender, tokens, balances, data);
        Store.fees().collateral[recipient][token] += amount;
        emit CollateralAdded(recipient, token, amount);
    }

    function withdrawCollateral(
        address recipient,
        address token,
        uint256 amount,
        bytes calldata data
    ) external nonReentrant {
        AdminLib.validateRights(AmmplifyAdminRights.TAKER);
        Store.fees().collateral[msg.sender][token] -= amount;
        address[] memory tokens = new address[](1);
        tokens[0] = token;
        int256[] memory balances = new int256[](1);
        balances[0] = -SafeCast.toInt256(amount);
        // We do a raw RFT call since this doesn't burn/mint.
        RFTLib.settle(recipient, tokens, balances, data);
        emit CollateralWithdrawn(recipient, token, amount);
    }

    function newTaker(
        address recipient,
        address poolAddr,
        int24[2] calldata ticks,
        uint128 liq,
        uint8[2] calldata vaultIndices,
        uint160[2] calldata sqrtPriceLimitsX96,
        uint160 freezeSqrtPriceX96,
        bytes calldata rftData
    ) external nonReentrant returns (uint256 _assetId) {
        if (liq < MIN_TAKER_LIQUIDITY) revert DeMinimusTaker(liq);
        AdminLib.validateRights(AmmplifyAdminRights.TAKER);
        PoolInfo memory pInfo = PoolLib.getPoolInfo(poolAddr);
        // When creating new positions, we make sure to validate the pool isn't malicious.
        pInfo.validate();
        (Asset storage asset, uint256 assetId) = AssetLib.newTaker(
            recipient,
            pInfo,
            ticks[0],
            ticks[1],
            liq,
            vaultIndices[0],
            vaultIndices[1]
        );
        (uint256 xFreeze, uint256 yFreeze) = PoolLib.getAmounts(freezeSqrtPriceX96, ticks[0], ticks[1], liq, true);
        settleTakerBalances(
            pInfo,
            asset,
            sqrtPriceLimitsX96,
            ticks,
            liq,
            SafeCast.toInt256(xFreeze),
            SafeCast.toInt256(yFreeze),
            rftData
        );
        VaultLib.deposit(pInfo.token0, vaultIndices[0], assetId, xFreeze);
        VaultLib.deposit(pInfo.token1, vaultIndices[1], assetId, yFreeze);
        emit TakerCreated(recipient, poolAddr, assetId, ticks[0], ticks[1], liq, vaultIndices[0], vaultIndices[1]);
        return assetId;
    }

    /// @dev There is not recipient here because RFTLib doesn't support that yet.
    function removeTaker(
        uint256 assetId,
        uint160 minSqrtPriceX96,
        uint160 maxSqrtPriceX96,
        bytes calldata rftData
    ) external nonReentrant returns (address token0, address token1, int256 balance0, int256 balance1) {
        Asset storage asset = AssetLib.getAsset(assetId);
        require(asset.owner == msg.sender, NotTakerOwner(asset.owner, msg.sender));
        require(asset.liqType == LiqType.TAKER, NotTaker(assetId));
        PoolInfo memory pInfo = PoolLib.getPoolInfo(asset.poolAddr);
        token0 = pInfo.token0;
        token1 = pInfo.token1;

        uint256 vaultX = VaultLib.withdraw(pInfo.token0, asset.xVaultIndex, assetId);
        uint256 vaultY = VaultLib.withdraw(pInfo.token1, asset.yVaultIndex, assetId);

        uint160[2] memory sqrtPriceLimitsX96 = [minSqrtPriceX96, maxSqrtPriceX96];
        int24[2] memory ticks = [asset.lowTick, asset.highTick];

        // Closing pays up the fees and leave the collateral alone. The collateral is really just there
        // to make sure while the position is open you can cover the fees. So there's really no need to keep
        // depositing and withdrawing collateral if your opened size stays roughly the same.
        (balance0, balance1) = settleTakerBalances(
            pInfo,
            asset,
            sqrtPriceLimitsX96,
            ticks,
            0,
            -SafeCast.toInt256(vaultX),
            -SafeCast.toInt256(vaultY),
            rftData
        );
        // We return balances from the perspective of the caller.
        balance0 = -balance0;
        balance1 = -balance1;

        AssetLib.removeAsset(assetId);
        emit TakerRemoved(asset.owner, assetId, asset.poolAddr, balance0, balance1);
    }

    /* Helpers */

    function settleTakerBalances(
        PoolInfo memory pInfo,
        Asset storage asset,
        uint160[2] memory sqrtPriceLimitsX96,
        int24[2] memory ticks,
        uint128 liq,
        int256 vaultDiffX,
        int256 vaultDiffY,
        bytes calldata rftData
    ) internal returns (int256 totalX, int256 totalY) {
        Data memory data = DataImpl.make(pInfo, asset, sqrtPriceLimitsX96[0], sqrtPriceLimitsX96[1], liq);
        // This fills in the nodes in the asset.
        WalkerLib.modify(pInfo, ticks[0], ticks[1], data);

        totalX = data.xBalance + vaultDiffX + int256(data.xFees);
        totalY = data.yBalance + vaultDiffY + int256(data.yFees);
        int256 settlementX = totalX > 0 ? totalX : int256(0);
        int256 settlementY = totalY > 0 ? totalY : int256(0);
        // We first take the balances we need from the user.
        settle(msg.sender, pInfo, settlementX, settlementY, rftData);
        // Now we do our mints (if borrowing) and burn.
        PoolWalker.settle(pInfo, ticks[0], ticks[1], data);
        settlementX = totalX < 0 ? totalX : int256(0);
        settlementY = totalY < 0 ? totalY : int256(0);
        // And lastly give any owed balances to the caller.
        settle(msg.sender, pInfo, settlementX, settlementY, rftData);
    }

    /// Settlement helper that wastes some memory allocation just to save on stack space.
    function settle(
        address recipient,
        PoolInfo memory pInfo,
        int256 xBalance,
        int256 yBalance,
        bytes calldata rftData
    ) internal {
        address[] memory tokens = pInfo.tokens();
        int256[] memory balances = new int256[](2);
        balances[0] = xBalance;
        balances[1] = yBalance;
        RFTLib.settle(recipient, tokens, balances, rftData);
    }
}

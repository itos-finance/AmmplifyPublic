// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { AdminLib } from "Commons/Util/Admin.sol";
import { AmmplifyAdminRights } from "./Admin.sol";
import { ReentrancyGuardTransient } from "openzeppelin-contracts/contracts/utils/ReentrancyGuardTransient.sol";

uint256 constant TAKER_VAULT_ID = 80085;

contract TakerFacet is ReentrancyGuardTransient {
    error NotTakerOwner(address owner, address sender);
    error NotTaker(uint256 assetId);

    /// Since our takers are permissioned
    function collateralize(address token, uint256 amount, bytes calldata data) external nonReentrant {
        AdminLib.validateRights(AmmplifyAdminRights.TAKER);
        address[] memory tokens = new address[](1);
        tokens[0] = token;
        address[] memory balances = new address[](1);
        balances[0] = token;
        RFTLib.settle(msg.sender, tokens, balances, data);
        Store.fees().collateral[msg.sender][token] += amount;
    }

    function withdrawCollateral(address token, uint256 amount) external nonReentrant {
        AdminLib.validateRights(AmmplifyAdminRights.TAKER);
        Store.fees().collateral[msg.sender][token] -= amount;
        address[] memory tokens = new address[](1);
        tokens[0] = token;
        address[] memory balances = new address[](1);
        balances[0] = token;
        RFTLib.settle(msg.sender, tokens, balances, data);
    }

    function newTaker(
        address recipient,
        address poolAddr,
        uint24 lowTick,
        uint24 highTick,
        uint128 liq,
        uint8 xVaultIndex,
        uint8 yVaultIndex,
        uint160 minSqrtPriceX96,
        uint160 maxSqrtPriceX96
    ) external nonReentrant returns (uint256 assetId) {
        AdminLib.validateRights(AmmplifyAdminRights.TAKER);
        PoolInfo memory pInfo = PoolLib.getPoolInfo(poolAddr);
        Asset storage asset;
        (asset, assetId) = AssetLib.newTaker(recipient, pInfo, lowTick, highTick, liq, xVaultIndex, yVaultIndex);
        Data memory data = DataImpl.make(pInfo, asset, minSqrtPriceX96, maxSqrtPriceX96);
        // This fills in the nodes in the asset.
        WalkerLib.addTakerWalk(pInfo, lowTick, highTick, data);
        PoolLib.updateLiqs(data.poolAddr, data.changes);
        VaultLib.getProxy(pInfo.token0, xVaultIndex).deposit(TAKER_VAULT_ID, data.xBalance);
        VaultLib.getProxy(pInfo.token1, yVaultIndex).deposit(TAKER_VAULT_ID, data.yBalance);
    }

    function removeTaker(
        address recipient,
        uint256 assetId,
        uint160 minSqrtPriceX96,
        uint160 maxSqrtPriceX96,
        bytes calldata rftData
    ) external nonReentrant returns (address token0, address token1, uint256 balance0, uint256 balance1) {
        AdminLib.validateRights(AmmplifyAdminRights.TAKER);
        Asset storage asset = AssetLib.getAsset(assetId);
        require(asset.owner == msg.sender, NotTakerOwner(asset.owner, msg.sender));
        require(asset.liqType == LiqType.TAKER, NotTaker(assetId));

        PoolInfo memory pInfo = PoolLib.getPoolInfo(asset.poolAddr);
        Data memory data = DataImpl.make(pInfo, asset, minSqrtPriceX96, maxSqrtPriceX96);

        WalkerLib.removeTakerWalk(pInfo, lowTick, highTick, data);
        AssetLib.removeAsset(assetId);
        address[] memory tokens = pInfo.tokens();
        address[] memory balances = new address[](2);
        balances[0] = data.xBalance;
        balances[1] = data.yBalance;
        RFTLib.settle(recipient, tokens, balances, rftData);
        PoolLib.updateLiqs(data.poolAddr, data.changes);
    }

    function viewTaker(
        uint256 assetId
    )
        external
        view
        returns (address poolAddr, uint128 liq, uint256 balance0, uint256 balance1, uint256 fees0, uint256 fees1)
    {
        Asset storage asset = AssetLib.getAsset(assetId);
        require(asset.liqType == LiqType.TAKER, NotTaker(assetId));
        PoolInfo memory pInfo = PoolLib.getPoolInfo(asset.poolAddr);
        ViewData memory data = ViewDataImpl.make(pInfo, asset);
        ViewWalkerLib.takerWalk(pInfo, asset.lowTick, asset.highTick, data);
        return (asset.poolAddr, asset.liq, data.xBalance, data.yBalance, data.fees0, data.fees1);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import { console } from "forge-std/console.sol";
import { Strings } from "a@openzeppelin/contracts/utils/Strings.sol";

import { MultiSetupTest } from "../MultiSetup.u.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";

import { Key, KeyImpl } from "../../src/tree/Key.sol";
import { TreeTickLib } from "../../src/tree/Tick.sol";
import { Node } from "../../src/walkers/Node.sol";
import { LiqNode, LiqType } from "../../src/walkers/Liq.sol";
import { FeeNode } from "../../src/walkers/Fee.sol";
import { PoolInfo } from "../../src/Pool.sol";
import { AmmplifyAdminRights } from "../../src/facets/Admin.sol";
import { SmoothRateCurveConfig } from "Commons/Math/SmoothRateCurveLib.sol";
import { TickMath } from "v3-core/libraries/TickMath.sol";

uint160 constant MIN_P = 4295128739;
uint160 constant MAX_P = 1461446703485210103287273052203988822378723970342;

enum SimOp {
    // Maker
    NEW_MAKER,
    ADJUST_MAKER,
    REMOVE_MAKER,
    COLLECT_FEES,
    COMPOUND,
    ADD_PERMISSION,
    REMOVE_PERMISSION,
    // Taker
    COLLATERALIZE,
    WITHDRAW_COLLATERAL,
    NEW_TAKER,
    REMOVE_TAKER,
    // Admin
    SET_FEE_CURVE,
    SET_DEFAULT_FEE_CURVE,
    SET_SPLIT_CURVE,
    SET_DEFAULT_SPLIT_CURVE,
    SET_COMPOUND_THRESHOLD,
    SET_DEFAULT_COMPOUND_THRESHOLD,
    SET_TWAP_INTERVAL,
    SET_DEFAULT_TWAP_INTERVAL,
    SET_JIT_PENALTIES,
    SEND_STANDING_FEES,
    ADD_PERMISSIONED_OPENER,
    REMOVE_PERMISSIONED_OPENER,
    // UniV3 pool
    SWAP,
    SWAP_TO,
    ADD_POOL_LIQ,
    REMOVE_POOL_LIQ,
    // Time
    SKIP,
    WARP
}

struct SimAction {
    SimOp op;
    uint8 actorIdx;
    bytes data;
    string label;
}

struct AssetRecord {
    uint256 assetId;
    address creator;
    SimOp createOp;
    bool alive;
}

struct Snapshot {
    uint256 stepIndex;
    uint160 sqrtPriceX96;
    int24 currentTick;
    uint256 timestamp;
    uint256[] actorBal0;
    uint256[] actorBal1;
}

contract SimBase is MultiSetupTest {
    using Strings for uint256;

    address public simPool;
    uint256 public poolIdx;
    MockERC20 public simToken0;
    MockERC20 public simToken1;

    address[] public actors;
    AssetRecord[] public assetRecords;
    Snapshot[] public snapshots;

    uint8 constant OWNER_IDX = 0;

    // ==================== Init ====================

    function _initSim(uint256 _poolIdx, address _pool) internal {
        poolIdx = _poolIdx;
        simPool = _pool;
        actors.push(address(this)); // actors[0] = owner/deployer

        PoolInfo memory pInfo = viewFacet.getPoolInfo(_pool);
        simToken0 = MockERC20(pInfo.token0);
        simToken1 = MockERC20(pInfo.token1);
        tokens.push(pInfo.token0);
        tokens.push(pInfo.token1);
    }

    // ==================== Actor Management ====================

    function _addActor(string memory name) internal returns (uint8 idx) {
        address actor = makeAddr(name);
        actors.push(actor);
        _fundAccount(actor);
        return uint8(actors.length - 1);
    }

    function _grantTakerRights(uint8 actorIdx) internal {
        adminFacet.submitRights(actors[actorIdx], AmmplifyAdminRights.TAKER, true);
        vm.warp(block.timestamp + 3 days);
        adminFacet.acceptRights();
    }

    // ==================== Maker Builders ====================

    function _newMaker(uint8 actor, address recipient, int24 low, int24 high, uint128 liq, bool compounding)
        internal
        pure
        returns (SimAction memory)
    {
        return SimAction({
            op: SimOp.NEW_MAKER,
            actorIdx: actor,
            data: abi.encode(recipient, low, high, liq, compounding),
            label: "newMaker"
        });
    }

    function _adjustMaker(uint8 actor, address recipient, uint256 assetId, uint128 targetLiq)
        internal
        pure
        returns (SimAction memory)
    {
        return SimAction({
            op: SimOp.ADJUST_MAKER,
            actorIdx: actor,
            data: abi.encode(recipient, assetId, targetLiq),
            label: "adjustMaker"
        });
    }

    function _removeMaker(uint8 actor, address recipient, uint256 assetId)
        internal
        pure
        returns (SimAction memory)
    {
        return SimAction({
            op: SimOp.REMOVE_MAKER,
            actorIdx: actor,
            data: abi.encode(recipient, assetId),
            label: "removeMaker"
        });
    }

    function _collectFees(uint8 actor, address recipient, uint256 assetId)
        internal
        pure
        returns (SimAction memory)
    {
        return SimAction({
            op: SimOp.COLLECT_FEES,
            actorIdx: actor,
            data: abi.encode(recipient, assetId),
            label: "collectFees"
        });
    }

    function _compound(uint8 actor, int24 low, int24 high) internal pure returns (SimAction memory) {
        return SimAction({op: SimOp.COMPOUND, actorIdx: actor, data: abi.encode(low, high), label: "compound"});
    }

    function _addPermission(uint8 actor, address opener) internal pure returns (SimAction memory) {
        return SimAction({op: SimOp.ADD_PERMISSION, actorIdx: actor, data: abi.encode(opener), label: "addPermission"});
    }

    function _removePermission(uint8 actor, address opener) internal pure returns (SimAction memory) {
        return SimAction({
            op: SimOp.REMOVE_PERMISSION,
            actorIdx: actor,
            data: abi.encode(opener),
            label: "removePermission"
        });
    }

    // ==================== Taker Builders ====================

    function _collateralize(uint8 actor, address recipient, uint8 tokenIdx, uint256 amount)
        internal
        pure
        returns (SimAction memory)
    {
        return SimAction({
            op: SimOp.COLLATERALIZE,
            actorIdx: actor,
            data: abi.encode(recipient, tokenIdx, amount),
            label: "collateralize"
        });
    }

    function _withdrawCollateral(uint8 actor, address recipient, uint8 tokenIdx, uint256 amount)
        internal
        pure
        returns (SimAction memory)
    {
        return SimAction({
            op: SimOp.WITHDRAW_COLLATERAL,
            actorIdx: actor,
            data: abi.encode(recipient, tokenIdx, amount),
            label: "withdrawCollateral"
        });
    }

    function _newTaker(
        uint8 actor,
        address recipient,
        int24 low,
        int24 high,
        uint128 liq,
        uint8 xVault,
        uint8 yVault,
        uint160 freezePrice
    ) internal pure returns (SimAction memory) {
        return SimAction({
            op: SimOp.NEW_TAKER,
            actorIdx: actor,
            data: abi.encode(recipient, low, high, liq, xVault, yVault, freezePrice),
            label: "newTaker"
        });
    }

    function _removeTaker(uint8 actor, uint256 assetId) internal pure returns (SimAction memory) {
        return SimAction({op: SimOp.REMOVE_TAKER, actorIdx: actor, data: abi.encode(assetId), label: "removeTaker"});
    }

    // ==================== Admin Builders ====================

    function _setFeeCurve(SmoothRateCurveConfig memory curve) internal pure returns (SimAction memory) {
        return SimAction({op: SimOp.SET_FEE_CURVE, actorIdx: OWNER_IDX, data: abi.encode(curve), label: "setFeeCurve"});
    }

    function _setDefaultFeeCurve(SmoothRateCurveConfig memory curve) internal pure returns (SimAction memory) {
        return SimAction({
            op: SimOp.SET_DEFAULT_FEE_CURVE,
            actorIdx: OWNER_IDX,
            data: abi.encode(curve),
            label: "setDefaultFeeCurve"
        });
    }

    function _setSplitCurve(SmoothRateCurveConfig memory curve) internal pure returns (SimAction memory) {
        return SimAction({
            op: SimOp.SET_SPLIT_CURVE,
            actorIdx: OWNER_IDX,
            data: abi.encode(curve),
            label: "setSplitCurve"
        });
    }

    function _setDefaultSplitCurve(SmoothRateCurveConfig memory curve) internal pure returns (SimAction memory) {
        return SimAction({
            op: SimOp.SET_DEFAULT_SPLIT_CURVE,
            actorIdx: OWNER_IDX,
            data: abi.encode(curve),
            label: "setDefaultSplitCurve"
        });
    }

    function _setCompoundThreshold(uint128 threshold) internal pure returns (SimAction memory) {
        return SimAction({
            op: SimOp.SET_COMPOUND_THRESHOLD,
            actorIdx: OWNER_IDX,
            data: abi.encode(threshold),
            label: "setCompoundThreshold"
        });
    }

    function _setDefaultCompoundThreshold(uint128 threshold) internal pure returns (SimAction memory) {
        return SimAction({
            op: SimOp.SET_DEFAULT_COMPOUND_THRESHOLD,
            actorIdx: OWNER_IDX,
            data: abi.encode(threshold),
            label: "setDefaultCompoundThreshold"
        });
    }

    function _setTwapInterval(uint32 interval) internal pure returns (SimAction memory) {
        return SimAction({
            op: SimOp.SET_TWAP_INTERVAL,
            actorIdx: OWNER_IDX,
            data: abi.encode(interval),
            label: "setTwapInterval"
        });
    }

    function _setDefaultTwapInterval(uint32 interval) internal pure returns (SimAction memory) {
        return SimAction({
            op: SimOp.SET_DEFAULT_TWAP_INTERVAL,
            actorIdx: OWNER_IDX,
            data: abi.encode(interval),
            label: "setDefaultTwapInterval"
        });
    }

    function _setJITPenalties(uint32 lifetime, uint64 penaltyX64) internal pure returns (SimAction memory) {
        return SimAction({
            op: SimOp.SET_JIT_PENALTIES,
            actorIdx: OWNER_IDX,
            data: abi.encode(lifetime, penaltyX64),
            label: "setJITPenalties"
        });
    }

    function _sendStandingFees(uint8 actor, uint128 x, uint128 y) internal pure returns (SimAction memory) {
        return SimAction({
            op: SimOp.SEND_STANDING_FEES,
            actorIdx: actor,
            data: abi.encode(x, y),
            label: "sendStandingFees"
        });
    }

    function _addPermissionedOpener(address opener) internal pure returns (SimAction memory) {
        return SimAction({
            op: SimOp.ADD_PERMISSIONED_OPENER,
            actorIdx: OWNER_IDX,
            data: abi.encode(opener),
            label: "addPermissionedOpener"
        });
    }

    function _removePermissionedOpener(address opener) internal pure returns (SimAction memory) {
        return SimAction({
            op: SimOp.REMOVE_PERMISSIONED_OPENER,
            actorIdx: OWNER_IDX,
            data: abi.encode(opener),
            label: "removePermissionedOpener"
        });
    }

    // ==================== Pool Builders ====================

    function _swap(uint8 actor, int256 amount, bool zeroForOne) internal pure returns (SimAction memory) {
        return SimAction({op: SimOp.SWAP, actorIdx: actor, data: abi.encode(amount, zeroForOne), label: "swap"});
    }

    function _swapTo(uint8 actor, uint160 targetPrice) internal pure returns (SimAction memory) {
        return SimAction({op: SimOp.SWAP_TO, actorIdx: actor, data: abi.encode(targetPrice), label: "swapTo"});
    }

    function _addPoolLiq(int24 low, int24 high, uint128 amount) internal pure returns (SimAction memory) {
        return SimAction({
            op: SimOp.ADD_POOL_LIQ,
            actorIdx: OWNER_IDX,
            data: abi.encode(low, high, amount),
            label: "addPoolLiq"
        });
    }

    function _removePoolLiq(int24 low, int24 high, uint128 amount) internal pure returns (SimAction memory) {
        return SimAction({
            op: SimOp.REMOVE_POOL_LIQ,
            actorIdx: OWNER_IDX,
            data: abi.encode(low, high, amount),
            label: "removePoolLiq"
        });
    }

    // ==================== Time Builders ====================

    function _skip(uint256 seconds_) internal pure returns (SimAction memory) {
        return SimAction({op: SimOp.SKIP, actorIdx: OWNER_IDX, data: abi.encode(seconds_), label: "skip"});
    }

    function _warp(uint256 timestamp) internal pure returns (SimAction memory) {
        return SimAction({op: SimOp.WARP, actorIdx: OWNER_IDX, data: abi.encode(timestamp), label: "warp"});
    }

    // ==================== Executor ====================

    function _run(SimAction[] memory actions) internal {
        for (uint256 i = 0; i < actions.length; i++) {
            _snapshot(i);
            _dispatch(actions[i]);
        }
    }

    function _dispatch(SimAction memory action) internal {
        SimOp op = action.op;
        address actor = actors[action.actorIdx];

        // ---- Maker ops ----
        if (op == SimOp.NEW_MAKER) {
            (address recipient, int24 low, int24 high, uint128 liq, bool compounding) =
                abi.decode(action.data, (address, int24, int24, uint128, bool));
            vm.startPrank(actor);
            uint256 assetId = makerFacet.newMaker(recipient, simPool, low, high, liq, compounding, MIN_P, MAX_P, "");
            vm.stopPrank();
            _recordAsset(assetId, actor, SimOp.NEW_MAKER);
        } else if (op == SimOp.ADJUST_MAKER) {
            (address recipient, uint256 assetId, uint128 targetLiq) =
                abi.decode(action.data, (address, uint256, uint128));
            vm.startPrank(actor);
            makerFacet.adjustMaker(recipient, assetId, targetLiq, MIN_P, MAX_P, "");
            vm.stopPrank();
        } else if (op == SimOp.REMOVE_MAKER) {
            (address recipient, uint256 assetId) = abi.decode(action.data, (address, uint256));
            vm.startPrank(actor);
            makerFacet.removeMaker(recipient, assetId, MIN_P, MAX_P, "");
            vm.stopPrank();
            _markDead(assetId);
        } else if (op == SimOp.COLLECT_FEES) {
            (address recipient, uint256 assetId) = abi.decode(action.data, (address, uint256));
            vm.startPrank(actor);
            makerFacet.collectFees(recipient, assetId, MIN_P, MAX_P, "");
            vm.stopPrank();
        } else if (op == SimOp.COMPOUND) {
            (int24 low, int24 high) = abi.decode(action.data, (int24, int24));
            vm.startPrank(actor);
            makerFacet.compound(simPool, low, high);
            vm.stopPrank();
        } else if (op == SimOp.ADD_PERMISSION) {
            address opener = abi.decode(action.data, (address));
            vm.startPrank(actor);
            makerFacet.addPermission(opener);
            vm.stopPrank();
        } else if (op == SimOp.REMOVE_PERMISSION) {
            address opener = abi.decode(action.data, (address));
            vm.startPrank(actor);
            makerFacet.removePermission(opener);
            vm.stopPrank();
        }
        // ---- Taker ops ----
        else if (op == SimOp.COLLATERALIZE) {
            (address recipient, uint8 tokenIdx, uint256 amount) =
                abi.decode(action.data, (address, uint8, uint256));
            address token = tokenIdx == 0 ? address(simToken0) : address(simToken1);
            vm.startPrank(actor);
            takerFacet.collateralize(recipient, token, amount, "");
            vm.stopPrank();
        } else if (op == SimOp.WITHDRAW_COLLATERAL) {
            (address recipient, uint8 tokenIdx, uint256 amount) =
                abi.decode(action.data, (address, uint8, uint256));
            address token = tokenIdx == 0 ? address(simToken0) : address(simToken1);
            vm.startPrank(actor);
            takerFacet.withdrawCollateral(recipient, token, amount, "");
            vm.stopPrank();
        } else if (op == SimOp.NEW_TAKER) {
            (address recipient, int24 low, int24 high, uint128 liq, uint8 xVault, uint8 yVault, uint160 freezeP) =
                abi.decode(action.data, (address, int24, int24, uint128, uint8, uint8, uint160));
            int24[2] memory ticks_;
            ticks_[0] = low;
            ticks_[1] = high;
            uint8[2] memory vaults_;
            vaults_[0] = xVault;
            vaults_[1] = yVault;
            uint160[2] memory limits_;
            limits_[0] = MIN_P;
            limits_[1] = MAX_P;
            vm.startPrank(actor);
            uint256 assetId = takerFacet.newTaker(recipient, simPool, ticks_, liq, vaults_, limits_, freezeP, "");
            vm.stopPrank();
            _recordAsset(assetId, actor, SimOp.NEW_TAKER);
        } else if (op == SimOp.REMOVE_TAKER) {
            uint256 assetId = abi.decode(action.data, (uint256));
            vm.startPrank(actor);
            takerFacet.removeTaker(assetId, MIN_P, MAX_P, "");
            vm.stopPrank();
            _markDead(assetId);
        }
        // ---- Admin ops (owner-only, called from address(this)) ----
        else if (op == SimOp.SET_FEE_CURVE) {
            SmoothRateCurveConfig memory curve = abi.decode(action.data, (SmoothRateCurveConfig));
            adminFacet.setFeeCurve(simPool, curve);
        } else if (op == SimOp.SET_DEFAULT_FEE_CURVE) {
            SmoothRateCurveConfig memory curve = abi.decode(action.data, (SmoothRateCurveConfig));
            adminFacet.setDefaultFeeCurve(curve);
        } else if (op == SimOp.SET_SPLIT_CURVE) {
            SmoothRateCurveConfig memory curve = abi.decode(action.data, (SmoothRateCurveConfig));
            adminFacet.setSplitCurve(simPool, curve);
        } else if (op == SimOp.SET_DEFAULT_SPLIT_CURVE) {
            SmoothRateCurveConfig memory curve = abi.decode(action.data, (SmoothRateCurveConfig));
            adminFacet.setDefaultSplitCurve(curve);
        } else if (op == SimOp.SET_COMPOUND_THRESHOLD) {
            uint128 threshold = abi.decode(action.data, (uint128));
            adminFacet.setCompoundThreshold(simPool, threshold);
        } else if (op == SimOp.SET_DEFAULT_COMPOUND_THRESHOLD) {
            uint128 threshold = abi.decode(action.data, (uint128));
            adminFacet.setDefaultCompoundThreshold(threshold);
        } else if (op == SimOp.SET_TWAP_INTERVAL) {
            uint32 interval = abi.decode(action.data, (uint32));
            adminFacet.setTwapInterval(simPool, interval);
        } else if (op == SimOp.SET_DEFAULT_TWAP_INTERVAL) {
            uint32 interval = abi.decode(action.data, (uint32));
            adminFacet.setDefaultTwapInterval(interval);
        } else if (op == SimOp.SET_JIT_PENALTIES) {
            (uint32 lifetime, uint64 penaltyX64) = abi.decode(action.data, (uint32, uint64));
            adminFacet.setJITPenalties(lifetime, penaltyX64);
        } else if (op == SimOp.SEND_STANDING_FEES) {
            (uint128 x, uint128 y) = abi.decode(action.data, (uint128, uint128));
            vm.startPrank(actor);
            adminFacet.sendStandingFees(simPool, x, y);
            vm.stopPrank();
        } else if (op == SimOp.ADD_PERMISSIONED_OPENER) {
            address opener = abi.decode(action.data, (address));
            adminFacet.addPermissionedOpener(opener);
        } else if (op == SimOp.REMOVE_PERMISSIONED_OPENER) {
            address opener = abi.decode(action.data, (address));
            adminFacet.removePermissionedOpener(opener);
        }
        // ---- Pool ops (called from address(this) for callbacks) ----
        else if (op == SimOp.SWAP) {
            (int256 amount, bool zeroForOne) = abi.decode(action.data, (int256, bool));
            swap(poolIdx, amount, zeroForOne);
        } else if (op == SimOp.SWAP_TO) {
            uint160 targetPrice = abi.decode(action.data, (uint160));
            swapTo(poolIdx, targetPrice);
        } else if (op == SimOp.ADD_POOL_LIQ) {
            (int24 low, int24 high, uint128 amount) = abi.decode(action.data, (int24, int24, uint128));
            addPoolLiq(poolIdx, low, high, amount);
        } else if (op == SimOp.REMOVE_POOL_LIQ) {
            (int24 low, int24 high, uint128 amount) = abi.decode(action.data, (int24, int24, uint128));
            removePoolLiq(poolIdx, low, high, amount);
        }
        // ---- Time ops ----
        else if (op == SimOp.SKIP) {
            uint256 seconds_ = abi.decode(action.data, (uint256));
            skip(seconds_);
        } else if (op == SimOp.WARP) {
            uint256 timestamp = abi.decode(action.data, (uint256));
            vm.warp(timestamp);
        }
    }

    // ==================== State Tracking ====================

    function _recordAsset(uint256 assetId, address creator, SimOp createOp) internal {
        assetRecords.push(AssetRecord({assetId: assetId, creator: creator, createOp: createOp, alive: true}));
    }

    function _markDead(uint256 assetId) internal {
        for (uint256 i = 0; i < assetRecords.length; i++) {
            if (assetRecords[i].assetId == assetId) {
                assetRecords[i].alive = false;
                return;
            }
        }
    }

    function _snapshot(uint256 stepIdx) internal {
        PoolInfo memory pInfo = viewFacet.getPoolInfo(simPool);

        uint256[] memory bal0 = new uint256[](actors.length);
        uint256[] memory bal1 = new uint256[](actors.length);
        for (uint256 i = 0; i < actors.length; i++) {
            bal0[i] = simToken0.balanceOf(actors[i]);
            bal1[i] = simToken1.balanceOf(actors[i]);
        }

        snapshots.push(Snapshot({
            stepIndex: stepIdx,
            sqrtPriceX96: pInfo.sqrtPriceX96,
            currentTick: pInfo.currentTick,
            timestamp: block.timestamp,
            actorBal0: bal0,
            actorBal1: bal1
        }));
    }

    // ==================== Tree Printing ====================

    function _printTree(int24 lowTick, int24 highTick) internal view {
        PoolInfo memory pInfo = viewFacet.getPoolInfo(simPool);
        uint24 rootWidth = pInfo.treeWidth;
        int24 tickSpacing = pInfo.tickSpacing;

        // Collect overlapping keys via recursive descent
        Key[] memory buf = new Key[](1024);
        uint256 count = _collectKeys(
            KeyImpl.make(0, uint48(rootWidth)), rootWidth, tickSpacing, lowTick, highTick, buf, 0
        );

        // Copy to correctly-sized array for the view call
        Key[] memory keys = new Key[](count);
        for (uint256 i = 0; i < count; i++) {
            keys[i] = buf[i];
        }

        // Batch-fetch node data
        Node[] memory nodes = viewFacet.getNodes(simPool, keys);

        // Header
        console.log(string.concat("Tree [", _itoa(lowTick), ", ", _itoa(highTick), "]:"));

        // Print each node
        for (uint256 i = 0; i < count; i++) {
            _printNode(keys[i], nodes[i], rootWidth, tickSpacing);
        }
    }

    function _printNode(Key key, Node memory node, uint24 rootWidth, int24 tickSpacing) internal pure {
        (uint24 b, uint24 w) = key.explode();
        (int24 nLow, int24 nHigh) = key.ticks(rootWidth, tickSpacing);
        uint256 depth = _depth(rootWidth, w);
        string memory pad = _indent(depth);

        // Liq line
        console.log(
            string.concat(
                pad,
                "[",
                uint256(b).toString(),
                ",",
                uint256(w).toString(),
                "] [",
                _itoa(nLow),
                ",",
                _itoa(nHigh),
                ") mLiq=",
                uint256(node.liq.mLiq).toString(),
                " tLiq=",
                uint256(node.liq.tLiq).toString(),
                " ncLiq=",
                uint256(node.liq.ncLiq).toString(),
                " subtreeMLiq=",
                node.liq.subtreeMLiq.toString()
            )
        );

        // Fee line (only when non-zero)
        if (
            node.fees.xCFees > 0 || node.fees.yCFees > 0 || node.fees.unclaimedMakerXFees > 0
                || node.fees.unclaimedMakerYFees > 0 || node.fees.unpaidTakerXFees > 0
                || node.fees.unpaidTakerYFees > 0
        ) {
            console.log(
                string.concat(
                    pad,
                    "  fees: xCFees=",
                    uint256(node.fees.xCFees).toString(),
                    " yCFees=",
                    uint256(node.fees.yCFees).toString(),
                    " unclaimedMkrX=",
                    uint256(node.fees.unclaimedMakerXFees).toString(),
                    " unclaimedMkrY=",
                    uint256(node.fees.unclaimedMakerYFees).toString(),
                    " unpaidTkrX=",
                    uint256(node.fees.unpaidTakerXFees).toString(),
                    " unpaidTkrY=",
                    uint256(node.fees.unpaidTakerYFees).toString()
                )
            );
        }
    }

    function _collectKeys(
        Key key,
        uint24 rootWidth,
        int24 tickSpacing,
        int24 queryLow,
        int24 queryHigh,
        Key[] memory buf,
        uint256 count
    ) internal pure returns (uint256 newCount) {
        (int24 nodeLow, int24 nodeHigh) = key.ticks(rootWidth, tickSpacing);
        // No overlap
        if (nodeLow >= queryHigh || nodeHigh <= queryLow) return count;
        // Add this key
        buf[count] = key;
        newCount = count + 1;
        // Leaf — stop
        if (key.isLeaf()) return newCount;
        // Recurse children
        (Key left, Key right) = key.children();
        newCount = _collectKeys(left, rootWidth, tickSpacing, queryLow, queryHigh, buf, newCount);
        newCount = _collectKeys(right, rootWidth, tickSpacing, queryLow, queryHigh, buf, newCount);
    }

    // ==================== Asset / Pool Printing ====================

    function _printAsset(uint256 assetId) internal view {
        (address owner_, address poolAddr_, int24 low, int24 high, LiqType liqType, uint128 liq) =
            viewFacet.getAssetInfo(assetId);
        (int256 net0, int256 net1, uint256 fees0, uint256 fees1) = viewFacet.queryAssetBalances(assetId);

        console.log(
            string.concat(
                "Asset #",
                assetId.toString(),
                " owner=",
                vm.toString(owner_),
                " pool=",
                vm.toString(poolAddr_),
                " type=",
                uint256(uint8(liqType)).toString()
            )
        );
        console.log(
            string.concat(
                "  ticks=[", _itoa(low), ",", _itoa(high), ") liq=", uint256(liq).toString()
            )
        );
        console.log(
            string.concat(
                "  net0=",
                _itoa(net0),
                " net1=",
                _itoa(net1),
                " fees0=",
                fees0.toString(),
                " fees1=",
                fees1.toString()
            )
        );
    }

    function _printAllAssets() internal view {
        for (uint256 i = 0; i < assetRecords.length; i++) {
            if (assetRecords[i].alive) {
                _printAsset(assetRecords[i].assetId);
            }
        }
    }

    function _printPoolState() internal view {
        PoolInfo memory pInfo = viewFacet.getPoolInfo(simPool);
        console.log(
            string.concat(
                "Pool: sqrtPriceX96=",
                uint256(pInfo.sqrtPriceX96).toString(),
                " tick=",
                _itoa(pInfo.currentTick),
                " treeWidth=",
                uint256(pInfo.treeWidth).toString()
            )
        );
        console.log(
            string.concat(
                "  token0Bal=",
                simToken0.balanceOf(simPool).toString(),
                " token1Bal=",
                simToken1.balanceOf(simPool).toString()
            )
        );
    }

    // ==================== Assertions ====================

    function assertPositionAlive(uint256 assetId) internal view {
        for (uint256 i = 0; i < assetRecords.length; i++) {
            if (assetRecords[i].assetId == assetId) {
                assertTrue(assetRecords[i].alive, "Position not alive");
                return;
            }
        }
        revert("Asset not found in records");
    }

    function assertPriceInRange(uint160 minSqrtP, uint160 maxSqrtP) internal view {
        PoolInfo memory pInfo = viewFacet.getPoolInfo(simPool);
        assertTrue(pInfo.sqrtPriceX96 >= minSqrtP, "Price below min");
        assertTrue(pInfo.sqrtPriceX96 <= maxSqrtP, "Price above max");
    }

    function assertFeesAccrued(uint256 assetId) internal view {
        (, , uint256 fees0, uint256 fees1) = viewFacet.queryAssetBalances(assetId);
        assertTrue(fees0 > 0 || fees1 > 0, "No fees accrued");
    }

    function assertBalancesConserved(uint256 beforeIdx, uint256 afterIdx) internal view {
        Snapshot storage before_ = snapshots[beforeIdx];
        Snapshot storage after_ = snapshots[afterIdx];
        uint256 totalBefore0;
        uint256 totalBefore1;
        uint256 totalAfter0;
        uint256 totalAfter1;
        for (uint256 i = 0; i < before_.actorBal0.length; i++) {
            totalBefore0 += before_.actorBal0[i];
            totalBefore1 += before_.actorBal1[i];
        }
        for (uint256 i = 0; i < after_.actorBal0.length; i++) {
            totalAfter0 += after_.actorBal0[i];
            totalAfter1 += after_.actorBal1[i];
        }
        assertEq(totalBefore0, totalAfter0, "Token0 not conserved");
        assertEq(totalBefore1, totalAfter1, "Token1 not conserved");
    }

    // ==================== Helpers ====================

    function _depth(uint24 rootWidth, uint24 nodeWidth) internal pure returns (uint256 d) {
        uint24 w = rootWidth;
        while (w > nodeWidth) {
            w >>= 1;
            d++;
        }
    }

    function _indent(uint256 d) internal pure returns (string memory) {
        bytes memory spaces = new bytes(d * 2);
        for (uint256 i = 0; i < spaces.length; i++) {
            spaces[i] = " ";
        }
        return string(spaces);
    }

    function _itoa(int256 x) internal pure returns (string memory) {
        if (x >= 0) return uint256(x).toString();
        return string.concat("-", uint256(-x).toString());
    }
}

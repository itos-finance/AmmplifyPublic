// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import { SimBase, SimAction, SimOp } from "./SimBase.sol";
import { TickMath } from "v3-core/libraries/TickMath.sol";

contract SimTest is SimBase {
    uint8 aliceIdx;
    uint8 bobIdx;

    function setUp() public {
        // Deploy Diamond + pool
        _newDiamond();
        (uint256 idx, address pool,,) = setUpPool();
        _initSim(idx, pool);

        // Create actors
        aliceIdx = _addActor("alice");
        bobIdx = _addActor("bob");
        _grantTakerRights(bobIdx);
        _createPoolVaults(simPool);

        // Seed base liquidity in the UniV3 pool
        addPoolLiq(0, -60000, 60000, 1e18);
    }

    function test_MakerLifecycle() public {
        SimAction[] memory actions = new SimAction[](6);
        actions[0] = _newMaker(aliceIdx, actors[aliceIdx], -600, 600, 10e18, true);
        actions[1] = _swapTo(0, TickMath.getSqrtRatioAtTick(300));
        actions[2] = _swapTo(0, TickMath.getSqrtRatioAtTick(-300));
        actions[3] = _skip(1 days);
        actions[4] = _collectFees(aliceIdx, actors[aliceIdx], 1);
        actions[5] = _removeMaker(aliceIdx, actors[aliceIdx], 1);
        _run(actions);

        // Inspect tree state
        _printTree(-600, 600);
        _printAllAssets();
        _printPoolState();

        // Assertions
        assertEq(assetRecords[0].alive, false);
        assertGt(snapshots.length, 0);
    }

    function test_MakerSwapFees() public {
        // Create a maker, generate swap fees, verify they accrue
        SimAction[] memory actions = new SimAction[](4);
        actions[0] = _newMaker(aliceIdx, actors[aliceIdx], -600, 600, 10e18, true);
        actions[1] = _swapTo(0, TickMath.getSqrtRatioAtTick(300));
        actions[2] = _swapTo(0, TickMath.getSqrtRatioAtTick(-300));
        actions[3] = _skip(1 days);
        _run(actions);

        // Fees should have accrued from the swaps
        assertFeesAccrued(1);
        assertPositionAlive(1);

        _printTree(-600, 600);
    }

    function test_MultiMakerScenario() public {
        // Two makers in different ranges, swaps through both
        SimAction[] memory actions = new SimAction[](5);
        actions[0] = _newMaker(aliceIdx, actors[aliceIdx], -1200, 0, 5e18, true);
        actions[1] = _newMaker(bobIdx, actors[bobIdx], 0, 1200, 5e18, false);
        actions[2] = _swapTo(0, TickMath.getSqrtRatioAtTick(600));
        actions[3] = _swapTo(0, TickMath.getSqrtRatioAtTick(-600));
        actions[4] = _skip(1 days);
        _run(actions);

        _printTree(-1200, 1200);
        _printAllAssets();

        assertPositionAlive(1);
        assertPositionAlive(2);
    }
}

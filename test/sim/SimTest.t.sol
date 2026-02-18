// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import { console } from "forge-std/console.sol";
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

    // ── Shared helper: phases 1-3 (makers + taker open + price oscillation) ──

    function _setupTakerScenario(bool compounding)
        internal
        returns (uint8 carolIdx, uint256 takerAssetId)
    {
        uint8 daveIdx = _addActor("dave");
        carolIdx = _addActor("carol");
        _grantTakerRights(carolIdx);

        // --- Phase 1: Open makers at overlapping ranges around tick 0 ---
        SimAction[] memory setup = new SimAction[](4);
        setup[0] = _newMaker(aliceIdx, actors[aliceIdx], -1200, 1200, 10e18, compounding);
        setup[1] = _newMaker(bobIdx, actors[bobIdx], -600, 0, 5e18, compounding);
        setup[2] = _newMaker(carolIdx, actors[carolIdx], 0, 600, 5e18, compounding);
        setup[3] = _newMaker(daveIdx, actors[daveIdx], -3000, 3000, 3e18, compounding);
        _run(setup);

        _printTree(-3000, 3000);
        _printPoolState();

        // --- Phase 2: Collateralize and open taker ---
        SimAction[] memory takerSetup = new SimAction[](3);
        takerSetup[0] = _collateralize(carolIdx, actors[carolIdx], 0, 100e18);
        takerSetup[1] = _collateralize(carolIdx, actors[carolIdx], 1, 100e18);
        takerSetup[2] = _newTaker(
            carolIdx,
            actors[carolIdx],
            -600, 600,   // taker range
            1e18,        // liq
            0, 1,        // vault indices
            TickMath.getSqrtRatioAtTick(0) // freeze at current price
        );
        _run(takerSetup);

        console.log("=== After taker opened ===");
        _printAllAssets();
        _printPoolState();

        // --- Phase 3: Swing price back and forth with day-long gaps ---
        SimAction[] memory swaps = new SimAction[](16);
        swaps[0]  = _swapTo(0, TickMath.getSqrtRatioAtTick(500));
        swaps[1]  = _skip(1 days);
        swaps[2]  = _swapTo(0, TickMath.getSqrtRatioAtTick(-500));
        swaps[3]  = _skip(1 days);
        swaps[4]  = _swapTo(0, TickMath.getSqrtRatioAtTick(800));
        swaps[5]  = _skip(1 days);
        swaps[6]  = _swapTo(0, TickMath.getSqrtRatioAtTick(-800));
        swaps[7]  = _skip(1 days);
        swaps[8]  = _swapTo(0, TickMath.getSqrtRatioAtTick(1000));
        swaps[9]  = _skip(1 days);
        swaps[10] = _swapTo(0, TickMath.getSqrtRatioAtTick(-1000));
        swaps[11] = _skip(1 days);
        swaps[12] = _swapTo(0, TickMath.getSqrtRatioAtTick(500));
        swaps[13] = _skip(1 days);
        swaps[14] = _swapTo(0, TickMath.getSqrtRatioAtTick(200));
        // Long pause before close — borrow fees accrue without any tree walk
        swaps[15] = _skip(7 days);
        _run(swaps);

        console.log("=== After price oscillation ===");
        _printTree(-3000, 3000);
        _printAllAssets();
        _printPoolState();

        takerAssetId = assetRecords[4].assetId;
        assertPositionAlive(takerAssetId);
    }

    // ── Close taker at a given tick and print cost ──

    function _closeTakerAtTick(
        uint8 carolIdx,
        uint256 takerAssetId,
        int24 closeTick,
        string memory label
    ) internal {
        // Move price to the desired close tick
        SimAction[] memory move = new SimAction[](1);
        move[0] = _swapTo(0, TickMath.getSqrtRatioAtTick(closeTick));
        _run(move);

        // Snapshot balances before close
        address carol = actors[carolIdx];
        uint256 bal0Before = simToken0.balanceOf(carol);
        uint256 bal1Before = simToken1.balanceOf(carol);

        // Close the taker
        SimAction[] memory close = new SimAction[](1);
        close[0] = _removeTaker(carolIdx, takerAssetId);
        _run(close);

        // Snapshot balances after close
        uint256 bal0After = simToken0.balanceOf(carol);
        uint256 bal1After = simToken1.balanceOf(carol);

        // Print cost to close
        console.log(string.concat("=== ", label, " ==="));
        console.log("Close tick:", uint256(uint24(closeTick)));
        if (bal0After >= bal0Before) {
            console.log("  token0 received:", bal0After - bal0Before);
        } else {
            console.log("  token0 cost:    ", bal0Before - bal0After);
        }
        if (bal1After >= bal1Before) {
            console.log("  token1 received:", bal1After - bal1Before);
        } else {
            console.log("  token1 cost:    ", bal1Before - bal1After);
        }

        _printAllAssets();
        _printPoolState();
    }

    // ── Narrow-range tests (taker [-600,600), aligned with makers) ──

    function test_TakerClose_Compounding_ITM() public {
        (uint8 carolIdx, uint256 takerAssetId) = _setupTakerScenario(true);
        _closeTakerAtTick(carolIdx, takerAssetId, 2000, "Compounding ITM close");
    }

    function test_TakerClose_Compounding_OTM() public {
        (uint8 carolIdx, uint256 takerAssetId) = _setupTakerScenario(true);
        _closeTakerAtTick(carolIdx, takerAssetId, 0, "Compounding OTM close");
    }

    function test_TakerClose_NonCompounding_ITM() public {
        (uint8 carolIdx, uint256 takerAssetId) = _setupTakerScenario(false);
        _closeTakerAtTick(carolIdx, takerAssetId, 2000, "NonCompounding ITM close");
    }

    function test_TakerClose_NonCompounding_OTM() public {
        (uint8 carolIdx, uint256 takerAssetId) = _setupTakerScenario(false);
        _closeTakerAtTick(carolIdx, takerAssetId, 0, "NonCompounding OTM close");
    }

    // ══════════════════════════════════════════════════════════════════════
    // Wide-range scenario: sparse makers + wide taker → parent-child borrows
    // ══════════════════════════════════════════════════════════════════════
    //
    // Maker layout (non-aligned with taker, forces parent-child borrows):
    //   Dave:  [-7200, 7200)  — wide base, 6e18 (covers taker everywhere)
    //   Alice: [-1200, -600)  — concentrated left island, 3e18
    //   Bob:   [600, 1200)    — concentrated right island, 3e18
    //   Carol: [-300, 300)    — thin center strip, 2e18
    //
    // Taker: [-3600, 3600) with 5e18
    //   → Dave's route places 6e18 at high-level nodes in [-7200, 7200) decomposition
    //   → Taker's route visits mid-level nodes in [-3600, 3600) decomposition
    //   → These are DIFFERENT tree nodes → child taker nodes have 0 direct mLiq
    //   → Parent (with Dave's mLiq) must lend to child during walk
    //   → Concentrated makers create uneven distribution at overlapping depths

    function _setupWideTakerScenario(bool compounding)
        internal
        returns (uint8 carolIdx, uint256 takerAssetId)
    {
        uint8 daveIdx = _addActor("dave");
        carolIdx = _addActor("carol");
        _grantTakerRights(carolIdx);

        // --- Phase 1: Non-aligned makers, wide base + concentrated islands ---
        SimAction[] memory setup = new SimAction[](4);
        // Wide base: enough total coverage (6e18 > 5e18 taker) but at different tree level
        setup[0] = _newMaker(daveIdx, actors[daveIdx], -7200, 7200, 6e18, compounding);
        // Concentrated left island: adds extra mLiq only in [-1200, -600)
        setup[1] = _newMaker(aliceIdx, actors[aliceIdx], -1200, -600, 3e18, compounding);
        // Concentrated right island: adds extra mLiq only in [600, 1200)
        setup[2] = _newMaker(bobIdx, actors[bobIdx], 600, 1200, 3e18, compounding);
        // Thin center strip: adds extra mLiq in [-300, 300)
        setup[3] = _newMaker(carolIdx, actors[carolIdx], -300, 300, 2e18, compounding);
        _run(setup);

        _printTree(-7200, 7200);
        _printPoolState();

        // --- Phase 2: Collateralize and open wide taker ---
        SimAction[] memory takerSetup = new SimAction[](3);
        takerSetup[0] = _collateralize(carolIdx, actors[carolIdx], 0, 500e18);
        takerSetup[1] = _collateralize(carolIdx, actors[carolIdx], 1, 500e18);
        takerSetup[2] = _newTaker(
            carolIdx,
            actors[carolIdx],
            -3600, 3600, // wide taker range — spans sparse zones
            5e18,        // large taker liq to exceed maker liq at sparse nodes
            0, 1,
            TickMath.getSqrtRatioAtTick(0)
        );
        _run(takerSetup);

        console.log("=== Wide: After taker opened ===");
        _printAllAssets();
        _printPoolState();

        // --- Phase 3: Wide oscillation with day-long gaps ---
        SimAction[] memory swaps = new SimAction[](16);
        swaps[0]  = _swapTo(0, TickMath.getSqrtRatioAtTick(2000));
        swaps[1]  = _skip(1 days);
        swaps[2]  = _swapTo(0, TickMath.getSqrtRatioAtTick(-2000));
        swaps[3]  = _skip(1 days);
        swaps[4]  = _swapTo(0, TickMath.getSqrtRatioAtTick(3000));
        swaps[5]  = _skip(1 days);
        swaps[6]  = _swapTo(0, TickMath.getSqrtRatioAtTick(-3000));
        swaps[7]  = _skip(1 days);
        swaps[8]  = _swapTo(0, TickMath.getSqrtRatioAtTick(3500));
        swaps[9]  = _skip(1 days);
        swaps[10] = _swapTo(0, TickMath.getSqrtRatioAtTick(-3500));
        swaps[11] = _skip(1 days);
        swaps[12] = _swapTo(0, TickMath.getSqrtRatioAtTick(1500));
        swaps[13] = _skip(1 days);
        swaps[14] = _swapTo(0, TickMath.getSqrtRatioAtTick(200));
        swaps[15] = _skip(7 days);
        _run(swaps);

        console.log("=== Wide: After price oscillation ===");
        _printTree(-7200, 7200);
        _printAllAssets();
        _printPoolState();

        takerAssetId = assetRecords[4].assetId;
        assertPositionAlive(takerAssetId);
    }

    // ── Wide-range compounding tests ──

    function test_WideTakerClose_Compounding_ITM() public {
        (uint8 carolIdx, uint256 takerAssetId) = _setupWideTakerScenario(true);
        // ITM: price far outside taker range
        _closeTakerAtTick(carolIdx, takerAssetId, 5000, "Wide Compounding ITM close");
    }

    function test_WideTakerClose_Compounding_OTM() public {
        (uint8 carolIdx, uint256 takerAssetId) = _setupWideTakerScenario(true);
        // OTM: price back at freeze
        _closeTakerAtTick(carolIdx, takerAssetId, 0, "Wide Compounding OTM close");
    }

    // ── Wide-range non-compounding tests (control) ──

    function test_WideTakerClose_NonCompounding_ITM() public {
        (uint8 carolIdx, uint256 takerAssetId) = _setupWideTakerScenario(false);
        _closeTakerAtTick(carolIdx, takerAssetId, 5000, "Wide NonCompounding ITM close");
    }

    function test_WideTakerClose_NonCompounding_OTM() public {
        (uint8 carolIdx, uint256 takerAssetId) = _setupWideTakerScenario(false);
        _closeTakerAtTick(carolIdx, takerAssetId, 0, "Wide NonCompounding OTM close");
    }
}

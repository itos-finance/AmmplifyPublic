# Foundry Gas Tracking

Reference for gas profiling and regression testing in Ammplify.

## 1. Gas Reports

Generate per-function gas reports from tests:

```bash
forge test --gas-report
```

Configure which contracts appear in reports via `foundry.toml`:

```toml
gas_reports = ["FeeWalker", "LiqWalker", "ViewWalker"]
gas_reports_ignore = ["Test*", "Mock*"]
```

- `gas_reports`: Only include these contracts (empty = all).
- `gas_reports_ignore`: Exclude these contracts from reports.

## 2. Gas Function Snapshots

Capture per-test gas usage to `.gas-snapshot`:

```bash
forge snapshot                  # Create snapshot
forge snapshot --diff           # Compare against existing snapshot
forge snapshot --check          # CI check — fails if gas changed
forge snapshot --snap <file>    # Write to a custom file
forge snapshot --asc            # Sort ascending by gas
forge snapshot --desc           # Sort descending by gas
forge snapshot --min 10000      # Only tests using >= 10000 gas
forge snapshot --max 500000     # Only tests using <= 500000 gas
```

The snapshot file is plain text, one line per test:

```
testSwap() (gas: 184523)
testAddMakerLiq() (gas: 312847)
```

## 3. Gas Section Snapshots

Measure gas for specific code sections using cheatcodes in tests:

```solidity
// Named section measurement
vm.startSnapshotGas("myOperation");
// ... code to measure ...
uint256 gasUsed = vm.stopSnapshotGas("myOperation");

// Measure only the last external call
someContract.doThing();
uint256 callGas = vm.snapshotGasLastCall("doThing");

// Snapshot an arbitrary value
vm.snapshotValue("metric", someValue);
```

Results are written to the `snapshots/` directory as JSON.

**Important:** Use `--isolate` when running section snapshots to ensure each test runs in its own EVM context for accurate measurement:

```bash
forge test --isolate --match-test testGasSection
```

## 4. Configuration

`foundry.toml` settings:

```toml
[profile.default]
gas_reports = []                # Contracts to include in gas reports
gas_reports_ignore = []         # Contracts to exclude from gas reports
gas_snapshot_check = false      # If true, `forge snapshot` fails on diff
gas_snapshot_emit = false       # If true, emit gas values as test logs
```

Environment variables:

- `FORGE_SNAPSHOT_CHECK=true` — equivalent to `gas_snapshot_check`

## 5. CI Integration

Add to CI pipeline for gas regression testing:

```yaml
- name: Gas regression check
  run: forge snapshot --check
```

This fails the build if any test's gas usage differs from the committed `.gas-snapshot`. Workflow:

1. Run `forge snapshot` locally after changes.
2. Commit `.gas-snapshot` with your PR.
3. CI runs `forge snapshot --check` to verify no unexpected regressions.

For tolerance-based checks, use `--diff` with manual review instead of `--check`.

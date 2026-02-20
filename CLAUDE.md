# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Ammplify is a liquidity management protocol built on Uniswap V3, implemented using the Diamond proxy pattern (EIP-2535). It provides a sophisticated system for managing concentrated liquidity positions with two primary participant types:

- **Makers**: Liquidity providers who deposit assets into concentrated ranges
- **Takers**: Permissioned actors who can borrow liquidity by posting collateral

The protocol uses a tree-based data structure to efficiently track and aggregate liquidity across tick ranges, enabling features like fee compounding and collateralized borrowing.

## Development Commands

### Building and Testing

```bash
# Build contracts
forge build

# Run all tests
forge test

# Run tests with gas reporting
forge test --gas-report

# Run a specific test contract
forge test --match-contract PoolTest

# Run a specific test function
forge test --match-test testNewMaker

# Run tests with detailed traces
forge test -vvvv

# Clean build artifacts
forge clean
```

### Code Quality

```bash
# Install dependencies (includes linters and formatters)
yarn install

# Lint Solidity files
yarn lint

# Lint only (Solhint + Prettier check)
yarn lint:sol
yarn prettier:check

# Format code
yarn prettier:write
```

### Deployment

```bash
# Deploy complete ecosystem (requires .env setup)
forge script script/DeployAll.s.sol --fork-url $RPC_URL --broadcast --private-key $DEPLOYER_PRIVATE_KEY

# Deploy specific components
forge script script/DeployDiamond.s.sol --fork-url $RPC_URL --broadcast
forge script script/DeployUniV3.s.sol --fork-url $RPC_URL --broadcast

# Run action scripts (examples)
forge script script/actions/OpenMaker.s.sol --fork-url $RPC_URL --broadcast
forge script script/actions/OpenTaker.s.sol --fork-url $RPC_URL --broadcast
```

## Architecture Overview

### Diamond Proxy Pattern

The core contract is `SimplexDiamond`, which implements the Diamond pattern for upgradability and modularity. All functionality is split across facets:

- **AdminFacet** (`src/facets/Admin.sol`): Fee configuration, vault management, admin rights
- **MakerFacet** (`src/facets/Maker.sol`): Creating, adjusting, and removing maker positions
- **TakerFacet** (`src/facets/Taker.sol`): Creating taker positions with collateral requirements
- **PoolFacet** (`src/facets/Pool.sol`): Uniswap V3 callback handlers
- **ViewFacet** (`src/facets/View.sol`): Read-only functions for querying state

### Storage Architecture

Global state is stored in a single storage slot location using the diamond storage pattern:

- **Store** (`src/Store.sol`): Central storage accessor with namespaced storage locations
  - `AssetStore`: Tracks all maker and taker positions (assets)
  - `VaultStore`: ERC4626 vault references for collateral
  - `FeeStore`: Fee configurations and collateral balances
  - `Pool`: Per-pool storage with node mappings

### Tree-Based Liquidity Tracking

The protocol uses a binary tree structure to efficiently aggregate liquidity:

- **Key** (`src/tree/Key.sol`): 48-bit compressed tree node identifier (24-bit base + 24-bit width)
- **Node** (`src/walkers/Node.sol`): Contains `LiqNode` (liquidity data) and `FeeNode` (fee data)
- **Walkers** (`src/walkers/`): Tree traversal logic for modifying positions
  - `WalkerLib`: Core walker that traverses tree and updates nodes
  - `PoolWalker`: Handles actual Uniswap V3 mint/burn/collect operations
  - `CompoundWalkerLib`: Specialized walker for compounding fee positions

Each node in the tree represents a tick range. Leaf nodes correspond to actual Uniswap V3 positions, while parent nodes aggregate child liquidity.

### Asset System

**Assets** (`src/Asset.sol`) represent user positions:

- Each asset has a unique ID and tracks:
  - Owner, pool address, tick bounds
  - Liquidity type: `MAKER` (compounding), `MAKER_NC` (non-compounding), or `TAKER`
  - Node-level accounting via `AssetNode` mappings
- Makers earn fees from swaps and taker reservations
- Takers pay reservation fees to makers based on borrowed liquidity and time

### Pool Integration

**PoolLib** (`src/Pool.sol`) provides Uniswap V3 integration:

- `getPoolInfo()`: Fetches immutable and current pool state
- `mint()`, `burn()`, `collect()`: Wrappers around Uniswap V3 position operations
- `getTwapSqrtPriceX96()`: TWAP price for slippage protection
- `getEquivalentLiq()`: Calculates liquidity value using both spot and TWAP prices

Pool validation ensures only Uniswap V3 pools from the configured factory are used and that pools have sufficient observations for TWAP calculations (`MIN_OBSERVATIONS = 32`).

### Vault System

**Vaults** (`src/vaults/Vault.sol`) are ERC4626-compatible wrappers:

- Takers specify vault indices when opening positions
- Vaults hold the actual borrowed tokens for takers
- Supports multiple vault types: `NOOP` (pass-through), `E4626` (standard ERC4626)

### Fee Mechanism

**FeeLib** (`src/Fee.sol`) manages protocol fees:

- Configurable fee curves per pool (default + pool-specific overrides)
- Split curves determine fee distribution between LPs and protocol
- TWAP intervals configurable per pool for slippage protection
- JIT (Just-In-Time) penalties to discourage manipulation
- Taker reservation fees calculated based on borrowed liquidity and time

## Important Concepts

### Data Struct

**Data** (`src/walkers/Data.sol`) is the central in-memory struct passed through walker operations. It accumulates:

- Token balances (`xBalance`, `yBalance`)
- Fee deltas
- Asset node checkpoints
- Pool state snapshots

The walker pattern modifies this struct as it traverses the tree, then the final state is used to settle balances and update storage.

### Reentrancy Protection

All external entry points use OpenZeppelin's `ReentrancyGuardTransient` for gas-efficient reentrancy protection using transient storage (EIP-1153).

### RFT Settlement

The protocol uses a "Reverse Fee Transfer" pattern (`Commons/Util/RFT.sol`):

- Negative balances = transfers FROM user TO protocol
- Positive balances = transfers FROM protocol TO user
- Callers provide callback data for custom settlement logic

### Pool Guard

A transient storage slot (`POOL_GUARD_SLOT` in PoolLib) validates Uniswap V3 callbacks to prevent malicious callback attacks during mint operations.

## Testing Patterns

Tests inherit from `MultiSetupTest` (`test/MultiSetup.u.sol`), which provides:

- Mock tokens (`token0`, `token1`)
- Mock ERC4626 vaults
- Deployed Diamond with all facets
- Uniswap V3 integration via `UniV3IntegrationSetup`
- Helper accounts: `owner`, `alice`, `bob`

Common test utilities in `test/utils/` and mocks in `test/mocks/`.

## Configuration Files

- **foundry.toml**: Solidity 0.8.30, via-IR enabled, 10k optimizer runs
- **remappings.txt**: Import path mappings (Commons, v3-core, v4-core)
- **.env.example**: Required environment variables for deployment
- **deployed-addresses.json**: Deployed contract addresses per network

## Deployment Artifacts

- **broadcast/**: Deployment transaction logs
- **out/**: Compiled contract artifacts and ABIs
- **cache/**: Forge compilation cache

## Key Integration Points

When adding new features:

1. **New facet functions**: Add to appropriate facet in `src/facets/`, update Diamond constructor with function selectors
2. **New storage**: Add to `Storage` struct in `src/Store.sol`, access via `Store.load()`
3. **New walkers**: Extend walker pattern in `src/walkers/`, ensure proper tree traversal
4. **Pool validation**: Ensure new pools meet `MIN_OBSERVATIONS` requirement
5. **Fee calculations**: Use `FeeLib` for consistent fee handling across the protocol

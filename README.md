# Ammplify

Ammplify is a DeFi protocol built on [Monad](https://monad.xyz) that extends Uniswap V3 concentrated liquidity with maker/taker position mechanics. This repo contains the Solidity smart contracts, deployment scripts, and a CLI for interacting with the protocol.

## Repository Structure

```
src/                  # Solidity smart contracts (diamond pattern)
├── facets/           # Diamond facets: Maker, Taker, Admin, View
├── integrations/     # UniV3 periphery, Opener, Decomposer
├── libraries/        # Shared math, storage, position logic
└── interfaces/       # Contract interfaces

script/               # Foundry deployment & action scripts
├── actions/          # Parameterized scripts (OpenMaker, CloseTaker, etc.)
├── simpleActions/    # Simplified scripts for quick testing
├── AmmplifyPositions.s.sol  # Base contract for all action scripts
└── DeployAll.s.sol   # Full protocol deployment

addresses/            # Canonical contract addresses (Monad Mainnet, Chain 143)
├── uniswapv3.json    # UniswapV3-based deployment
└── capricorn.json    # Capricorn-based deployment

cli/                  # TypeScript CLI (see cli/README.md)
test/                 # Forge test suite
```

## Deployed Addresses

All contract addresses live in `addresses/` as flat JSON files. Each file contains the full set of token addresses, protocol contract addresses, and pool addresses for a specific deployment:

```json
{
  "network": "Monad Mainnet",
  "chainId": 143,
  "tokens": {
    "USDC": { "address": "0x...", "decimals": 6 },
    "WETH": { "address": "0x...", "decimals": 18 }
  },
  "diamond": "0x...",
  "opener": "0x...",
  "decomposer": "0x...",
  "factory": "0x...",
  "nfpm": "0x...",
  "router": "0x...",
  "pools": {
    "USDC_WETH_3000": "0x..."
  }
}
```

Scripts select a deployment via the `AMMPLIFY_PROTOCOL` environment variable (defaults to `uniswapv3`):

```bash
# Use UniswapV3 deployment (default)
forge script script/actions/OpenMaker.s.sol --rpc-url $RPC_URL --broadcast

# Use Capricorn deployment
AMMPLIFY_PROTOCOL=capricorn forge script script/actions/OpenMaker.s.sol --rpc-url $RPC_URL --broadcast
```

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js 18+ (for CLI)

### Build

```bash
forge build
```

### Test

```bash
forge test
```

### CLI

```bash
cd cli
cp .env.example .env   # fill in RPC_URL, CHAIN_ID, etc.
npm install
npm run build
npm link               # makes `ammplify` available globally

ammplify pool list
ammplify view tvl --json
```

See [cli/README.md](cli/README.md) for full CLI documentation.

### Running Scripts

Action scripts inherit from `AmmplifyPositions.s.sol` and automatically load addresses from the JSON files:

```bash
export DEPLOYER_PRIVATE_KEY=0x...
export DEPLOYER_PUBLIC_KEY=0x...

# Open a maker position
forge script script/actions/OpenMaker.s.sol --rpc-url $RPC_URL --broadcast

# Setup pool positions
forge script script/actions/SetupPoolPositions.s.sol --rpc-url $RPC_URL --broadcast
```

## Architecture

Ammplify uses the **diamond pattern** (EIP-2535) where a single diamond contract delegates to specialized facets:

- **Maker Facet** - Create, adjust, and close liquidity positions
- **Taker Facet** - Open leveraged positions against maker liquidity
- **View Facet** - Read-only queries (balances, positions, pool state)
- **Admin Facet** - Protocol configuration (fee curves, vaults, permissions)

The diamond address is the single entry point for all protocol interactions. The CLI and scripts resolve it from the `diamond` field in the addresses JSON.

## License

[BUSL-1.1](./LICENSE.md)

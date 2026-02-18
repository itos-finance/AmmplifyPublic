# Ammplify CLI

Command-line interface for interacting with the Ammplify protocol on Monad.

## Installation

**From source:**

```bash
cd cli
npm install
npm run build
npm link        # makes `ammplify` available globally
```

**From NPM (when published):**

```bash
npm install -g ammplify-cli
```

## Configuration

Copy `.env.example` to `.env` and fill in the values:

```bash
cp .env.example .env
```

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `AMMPLIFY_RPC_URL` | Yes | — | JSON-RPC endpoint |
| `AMMPLIFY_CHAIN_ID` | Yes | — | Target chain ID (e.g. `10143`) |
| `AMMPLIFY_PRIVATE_KEY` | Write ops only | — | Wallet private key for transactions |
| `AMMPLIFY_MIDDLEWARE_URL` | No | `https://api.ammplify.xyz` | Middleware API for richer queries |
| `AMMPLIFY_ADDRESSES_FILE` | No | `../deployed-addresses.json` | Path to contract addresses (relative to `cli/`) |

The CLI reads contract addresses from a `deployed-addresses.json` file with this structure:

```json
{
  "network": "Chain 10143",
  "tokens": { "USDC": { "address": "0x...", "symbol": "USDC", "decimals": 6 }, ... },
  "vaults": { "USDC": { "address": "0x...", "symbol": "vUSDC", "asset": "0x..." }, ... },
  "ammplify": { "simplexDiamond": "0x...", "borrowlessDiamond": "0x...", "nftManager": "0x..." },
  "uniswap": { "factory": "0x...", "pools": { "USDC_WETH_3000": "0x..." } }
}
```

## Quick Start

```bash
# List all pools
ammplify pool list

# Check protocol TVL
ammplify view tvl

# View your maker positions
ammplify view positions 0xYourAddress

# Open a maker position (requires AMMPLIFY_PRIVATE_KEY)
ammplify maker open --pool 0x... --low-tick -100 --high-tick 100 --liquidity 1000000
```

All read commands support `--json` for machine-readable output.

## Commands Reference

### Pool

| Command | Description |
|---------|-------------|
| `pool list` | List all pools |
| `pool info <address>` | Get pool details |
| `pool liquidity <address>` | Get tick liquidity distribution |

```bash
ammplify pool list --json
ammplify pool info 0x046Afe...
ammplify pool liquidity 0x046Afe... --lower-tick -1000 --upper-tick 1000
```

### View

| Command | Description |
|---------|-------------|
| `view asset <assetId>` | View position info (owner, ticks, type, liquidity) |
| `view balances <assetId>` | View token balances and fees for a position |
| `view positions <owner>` | List all maker positions for an owner |
| `view taker-positions <owner>` | List all taker positions for an owner |
| `view collateral <owner>` | View collateral balances |
| `view tvl` | View protocol TVL |
| `view prices` | View current and historical prices |
| `view leaderboard` | View fee leaderboard |

```bash
ammplify view positions 0xYourAddress --json
ammplify view collateral 0xYourAddress --token USDC
ammplify view prices --pool 0x046Afe...
ammplify view leaderboard --window 30d
```

Options:
- `view collateral`: `--token <token>` to filter by symbol/address
- `view prices`: `--pool <address>` (required)
- `view leaderboard`: `--window <1d|30d|all-time>` (default: `all-time`)

### Maker

| Command | Description |
|---------|-------------|
| `maker open` | Open a new maker position |
| `maker close <assetId>` | Close/remove a maker position |
| `maker adjust <assetId> <targetLiq>` | Adjust liquidity to target amount |
| `maker collect-fees <assetId>` | Collect accumulated fees |
| `maker add-permission <opener>` | Allow address to open positions on your behalf |
| `maker remove-permission <opener>` | Revoke opener permission |

```bash
ammplify maker open --pool 0x... --low-tick -100 --high-tick 100 --liquidity 5000000 --compounding
ammplify maker close 42 --recipient 0xOther...
ammplify maker adjust 42 10000000
ammplify maker collect-fees 42
ammplify maker add-permission 0xOpener...
```

Options:
- `maker open`: `--pool`, `--low-tick`, `--high-tick`, `--liquidity` (all required), `--compounding`, `--recipient`
- All write commands: `--no-confirm` to skip confirmation prompt, `--recipient` to override receiver

### Taker

| Command | Description |
|---------|-------------|
| `taker open` | Open a new taker position |
| `taker close <assetId>` | Close a taker position |
| `taker collateralize` | Add collateral |
| `taker withdraw` | Withdraw collateral |

```bash
ammplify taker open --pool 0x... --low-tick -100 --high-tick 100 --liquidity 5000000 --freeze-price min
ammplify taker close 42
ammplify taker collateralize --token USDC --amount 1000
ammplify taker withdraw --token WETH --amount 0.5
```

Options:
- `taker open`: `--pool`, `--low-tick`, `--high-tick`, `--liquidity`, `--freeze-price <min|max>` (all required), `--vault-x`, `--vault-y`, `--recipient`
- `taker collateralize / withdraw`: `--token`, `--amount` (required), `--recipient`

### Admin

| Command | Description |
|---------|-------------|
| `admin fee-config <poolAddress>` | View fee curve and split curve config |
| `admin vaults <token> <index>` | View vault addresses |

```bash
ammplify admin fee-config 0x046Afe... --json
ammplify admin vaults USDC 0
```

### Token

| Command | Description |
|---------|-------------|
| `token balance <token>` | Check ERC20 token balance |
| `token approve <token> <spender> <amount>` | Set ERC20 token allowance |

```bash
ammplify token balance USDC --owner 0xYourAddress
ammplify token approve USDC 0xSpender... 1000000
```

## Development

Run in dev mode (no build step):

```bash
npx tsx src/index.ts pool list
npx tsx src/index.ts view tvl --json
```

Build:

```bash
npm run build      # runs extract-abis then tsup
```

Run tests:

```bash
npm test           # vitest run
```

## ABI Management

The `src/abi/` directory contains TypeScript ABI files extracted from Foundry build artifacts.

To regenerate after contract changes:

```bash
npm run extract-abis
```

This runs `src/abi/extract-abis.ts`, which reads from `../out/` (Foundry's output directory) and writes typed ABI constants to `src/abi/`. The extracted interfaces are:

- `IMaker` — Maker position operations
- `ITaker` — Taker position operations
- `IView` — Read-only view functions
- `IAdmin` — Admin configuration
- `IUniswapV3Pool` — Pool state reads
- `IERC20` — ERC20 token standard

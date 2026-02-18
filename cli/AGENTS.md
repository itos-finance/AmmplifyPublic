# Ammplify CLI — Agent Reference

CLI for interacting with the Ammplify DeFi protocol on Monad. Built with TypeScript, Commander.js, viem, and tsup.

## Commands

```bash
npm run dev -- <command>       # Run in dev mode (tsx)
npm run build                  # Build with tsup (runs ABI extraction first via prebuild)
npm test                       # Run tests (vitest)
npm run extract-abis           # Extract ABIs from Foundry artifacts in ../out/
```

## Architecture

```
src/
├── index.ts                   # Entry point — registers 6 command groups on Commander program
├── config.ts                  # Env loading (.env), token/vault resolution, deployed address loading
├── constants.ts               # UniswapV3 tick math constants (Q96, MIN/MAX_TICK, etc.)
├── abi/
│   ├── extract-abis.ts        # Script: reads Foundry JSON artifacts from ../out/, writes TS ABI files
│   ├── index.ts               # Re-exports all ABI constants
│   ├── IMaker.ts              # IMakerAbi — maker position operations
│   ├── ITaker.ts              # ITakerAbi — taker position operations
│   ├── IView.ts               # IViewAbi — read-only view functions
│   ├── IAdmin.ts              # IAdminAbi — admin/config queries
│   ├── IUniswapV3Pool.ts      # IUniswapV3PoolAbi — pool queries (token0, token1, slot0)
│   └── IERC20.ts              # IERC20Abi — ERC20 balance/approve/symbol/decimals
├── clients/
│   ├── chain.ts               # viem PublicClient + WalletClient (singleton, lazy-init)
│   └── middleware.ts           # HTTP client for middleware API
├── utils/
│   ├── tx.ts                  # executeTx(): simulate → confirm → submit → wait
│   ├── error.ts               # withErrorHandler() wrapper, handleError() classifier
│   ├── format.ts              # Token amounts, sqrtPrice→price, tick→price, address shortening
│   └── table.ts               # CLI table (cli-table3) and JSON output helpers
└── commands/
    ├── pool/                  # pool list, pool info, pool liquidity
    ├── view/                  # asset, balances, positions, taker-positions, collateral, tvl, prices, leaderboard
    ├── maker/                 # open, close, adjust, collect-fees, add-permission, remove-permission
    ├── taker/                 # open, close, collateralize, withdraw
    ├── admin/                 # fee-config, vaults
    └── token/                 # balance, approve
```

## Key Patterns

### Command structure

Every command handler is an async function wrapped with `withErrorHandler`:

```ts
// src/commands/<group>/<action>.ts
export const myCommand = withErrorHandler(async (arg: string, options: Options) => {
  // ... command logic
});
```

Commands are registered in `src/commands/<group>/index.ts` via a `registerXCommands(parent)` function, which is called from `src/index.ts`.

### Write operations (transactions)

All write commands follow the same flow using `executeTx()` from `src/utils/tx.ts`:

1. `simulateContract` — catch reverts before sending
2. User confirmation prompt (unless `--no-confirm`)
3. `writeContract` — submit transaction
4. `waitForTransactionReceipt` — wait for on-chain confirmation

```ts
import { executeTx } from "../../utils/tx.js";
import { getDiamondAddress } from "../../config.js";
import { IMakerAbi } from "../../abi/index.js";

await executeTx({
  address: getDiamondAddress(),  // target contract
  abi: IMakerAbi,
  functionName: "newMaker",
  args: [recipient, pool, lowTick, highTick, liquidity, compounding, minPrice, maxPrice, "0x"],
  noConfirm: !options.confirm,
  description: "Open maker position",
});
```

### Read operations (on-chain)

Read commands use `getPublicClient().readContract()` directly with the appropriate ABI. Use `Promise.all` for parallel reads:

```ts
const client = getPublicClient();
const diamond = getDiamondAddress();

const [info, balances] = await Promise.all([
  client.readContract({ address: diamond, abi: IViewAbi, functionName: "getAssetInfo", args: [id] }),
  client.readContract({ address: diamond, abi: IViewAbi, functionName: "queryAssetBalances", args: [id] }),
]);
```

### Output format

Most read commands accept `--json`. Use `printJson(data)` for JSON output, `createTable()`/`printTable()` for tabular CLI output.

## Adding a New Command

1. **Create handler**: `src/commands/<group>/<action>.ts`
   - Export a `const myAction = withErrorHandler(async (...) => { ... })`
   - For writes: use `executeTx()`. For reads: use `getPublicClient().readContract()`
2. **Register in group index**: `src/commands/<group>/index.ts`
   - Import handler, add `.command(...)...action(handler)` to the register function
3. **If a new group**: create `src/commands/<group>/index.ts` with `registerXCommands()`, add to `src/index.ts`

## Contract Interaction

### Diamond pattern

All Ammplify protocol calls go through `simplexDiamond` (retrieved via `getDiamondAddress()`). The diamond delegates to facets based on function selector, but from the CLI's perspective it's a single address. Use the facet-specific ABI (`IMakerAbi`, `ITakerAbi`, `IViewAbi`, `IAdminAbi`) — viem only needs the function signature, not the actual facet address.

### ABIs

ABIs are extracted from Foundry build artifacts (`../out/`) by `src/abi/extract-abis.ts`. This runs automatically as a `prebuild` step. Each ABI file exports a single `const XAbi = [...] as const`. After changing Solidity interfaces, run:

```bash
npm run extract-abis
```

## Token & Address Conventions

`resolveToken(input)` in `config.ts` accepts:
- Token symbols: `"USDC"`, `"WETH"` (case-insensitive)
- Vault symbols: `"vUSDC"`, `"vWETH"`
- Raw hex addresses: `"0x..."`

Returns `{ address, symbol, decimals }`. Known token decimals: USDC = 6, WETH = 18. Vaults default to 18 decimals.

`resolveVault(tokenSymbol)` maps a token symbol (e.g. `"USDC"`) to its vault address by matching the vault's `asset` field.

## Deployed Addresses

Loaded from `deployed-addresses.json` (path configurable via `AMMPLIFY_ADDRESSES_FILE` env var, defaults to `../deployed-addresses.json`). Cached as a singleton after first load in `config.ts`.

Structure:
```
{ network, deployer, tokens: {...}, vaults: {...}, ammplify: { simplexDiamond, borrowlessDiamond, nftManager }, uniswap: {...}, integrations: {...} }
```

## Environment Variables

Set in `cli/.env`:

| Variable | Required | Description |
|----------|----------|-------------|
| `AMMPLIFY_RPC_URL` | Yes | RPC endpoint URL |
| `AMMPLIFY_CHAIN_ID` | Yes | Chain ID (integer) |
| `AMMPLIFY_PRIVATE_KEY` | For writes | Hex private key (`0x...`) |
| `AMMPLIFY_MIDDLEWARE_URL` | No | Middleware API base URL (defaults to `https://api.ammplify.xyz`) |
| `AMMPLIFY_ADDRESSES_FILE` | No | Path to deployed-addresses.json (defaults to `../deployed-addresses.json`) |

## Middleware API

HTTP client in `src/clients/middleware.ts`. Available endpoints:

| Function | Method | Path | Body |
|----------|--------|------|------|
| `getPools()` | GET | `/pools` | — |
| `getTvl()` | GET | `/tvl` | — |
| `getTickLiquidity(pool, lower, upper)` | POST | `/tick-liquidity` | `{ pool, lowerTick, upperTick }` |
| `getPositions(owner)` | POST | `/positions` | `{ owner }` |
| `getTakerPositions(owner)` | POST | `/taker-positions` | `{ owner }` |
| `getPrices(pool)` | POST | `/prices` | `{ pool }` |
| `getLeaderboard(timeWindow?)` | POST | `/leaderboard` | `{ timeWindow }` |

Use middleware for aggregated/indexed data (positions list, TVL, leaderboard). Use on-chain reads for real-time state (balances, asset info, collateral).

## Constants

`src/constants.ts` — UniswapV3 tick math values:

- `MIN_SQRT_RATIO` / `MAX_SQRT_RATIO` — bounds for sqrtPriceX96 slippage params
- `MIN_TICK` / `MAX_TICK` — tick range bounds (-887272 to 887272)
- `Q96` / `Q192` — fixed-point math constants (2^96, 2^192)

Price conversion helpers in `src/utils/format.ts`:
- `sqrtPriceToPrice(sqrtPriceX96, decimals0, decimals1)` — converts sqrtPriceX96 to human price
- `tickToPrice(tick, decimals0, decimals1)` — converts tick to human price via `1.0001^tick`

## Testing

Tests use vitest with co-located test files (`*.test.ts` next to source).

```bash
npm test                       # Run all tests
npx vitest run src/config      # Run specific test file
```

Mocking patterns:
- **Middleware**: mock `globalThis.fetch` and `vi.mock("../config.js")` to stub config
- **Config**: use env vars (`AMMPLIFY_ADDRESSES_FILE`, etc.) + temp files in `beforeAll`, dynamic `import()` so env is set before module loads
- **Errors**: `vi.spyOn(process, "exit").mockImplementation(() => undefined as never)` to catch `process.exit(1)`
- **Console**: `vi.spyOn(console, "error").mockImplementation(() => {})` to suppress and assert output

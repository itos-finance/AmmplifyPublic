# Ammplify MCP Server

MCP (Model Context Protocol) server for the Ammplify DeFi protocol. Enables AI agents to read protocol data, manage liquidity positions, and earn yield on Ammplify.

## Quick Start

```bash
# Install
cd mcpserver
npm install

# Configure
cp .env.example .env
# Edit .env with your RPC URL and (optionally) private key for write operations

# Run
npm run dev
# Server starts at http://localhost:3100/mcp
```

## Tools

### Read Tools (no private key needed)
| Tool | Description |
|------|-------------|
| `get_pools` | List all Ammplify pools |
| `get_pool_info` | Pool state: price, tick, liquidity, fees |
| `get_tick_liquidity` | Liquidity distribution across ticks |
| `get_positions` | All maker positions for a wallet |
| `get_asset_info` | Position details (on-chain) |
| `get_asset_balances` | Position value + accrued fees |
| `get_tvl` | Protocol total value locked |
| `get_prices` | Token prices for a pool |
| `get_leaderboard` | Top earners by time window |
| `get_token_balance` | ERC20 balance for a wallet |
| `get_allowance` | Check token approval for Ammplify |

### Write Tools (private key required)
| Tool | Description |
|------|-------------|
| `approve_token` | Approve tokens for the Ammplify diamond |
| `open_maker` | Open a new LP position |
| `close_maker` | Close a position and withdraw |
| `adjust_maker` | Change position liquidity |
| `collect_fees` | Harvest accrued fees |
| `add_permission` | Grant position management permission |
| `remove_permission` | Revoke permission |

### Resources
- `ammplify://protocol-info` — Protocol overview and usage guide
- `ammplify://deployed-addresses` — All contract addresses

### Prompts
- `analyze-position` — Analyze a position's P&L and status
- `find-best-pool` — Compare pools and recommend the best for yield
- `open-position-guide` — Step-by-step guide to open a position

## Connect to Claude Desktop

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "ammplify": {
      "url": "http://localhost:3100/mcp"
    }
  }
}
```

Then start the server (`npm run dev`) before launching Claude Desktop.

## Connect to Claude Code

```bash
claude mcp add ammplify --transport http http://localhost:3100/mcp
```

## E2E Test Flow (Monad Testnet)

1. Start the server: `npm run dev`
2. In Claude, ask it to:
   - "List all Ammplify pools" → calls `get_pools`
   - "Show me pool info for 0x046Afe0CA5E01790c3d22fe16313d801fa0aD67D" → calls `get_pool_info`
   - "Check my USDC balance for 0x..." → calls `get_token_balance`
   - "Approve USDC for Ammplify" → calls `approve_token`
   - "Open a maker position on the USDC/WETH pool" → calls `open_maker`
   - "Show my position balances" → calls `get_asset_balances`
   - "Collect my fees" → calls `collect_fees`
   - "Close my position" → calls `close_maker`

## Architecture

```
AI Agent (Claude Desktop / Claude Code)
    ↕ MCP Protocol (Streamable HTTP)
Ammplify MCP Server (localhost:3100)
    ↕ HTTP / JSON-RPC
Middleware API (api.ammplify.xyz)  +  On-chain (Monad RPC via viem)
```

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `AMMPLIFY_RPC_URL` | Yes | RPC endpoint (e.g., `https://testnet-rpc.monad.xyz`) |
| `AMMPLIFY_CHAIN_ID` | Yes | Chain ID (e.g., `10143`) |
| `AMMPLIFY_PRIVATE_KEY` | For writes | Hex private key (`0x...`) |
| `AMMPLIFY_MIDDLEWARE_URL` | No | Middleware API URL (default: `https://api.ammplify.xyz`) |
| `AMMPLIFY_ADDRESSES_FILE` | No | Path to deployed addresses JSON |
| `PORT` | No | Server port (default: `3100`) |

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { getAddresses } from "../config.js";

const PROTOCOL_OVERVIEW = `# Ammplify Protocol

Ammplify is a liquidity provisioning protocol built on Uniswap V3 (deployed on Monad).
It turns LP positions into structured financial products:

## How It Works

**Makers (LPs)** deposit liquidity into concentrated tick ranges — functionally writing
covered calls (if price is below range) or cash-secured puts (if price is above range).
They earn:
- Swap fees from the underlying Uniswap V3 pool
- Borrow fees from Takers who borrow their liquidity

**Takers (Borrowers)** borrow maker liquidity to take leveraged directional positions.
They pay utilization-based borrow fees.

## Key Concepts

- **Tick Range**: Liquidity is deposited between a lowTick and highTick. Ticks must
  be divisible by the pool's tickSpacing (e.g., 60 for 0.3% fee tier).
- **Compounding**: Makers can auto-compound earned fees back into their position.
- **Minimum Liquidity**: 1,000,000 (1e6) for makers.
- **Binary Tree**: Ammplify manages liquidity via a tree structure that tracks positions
  at every granularity from individual ticks to the full range.

## Architecture

- Diamond proxy pattern (EIP-2535) with facets: Maker, Taker, View, Admin, Pool
- All calls go through a single diamond address
- Tokens must be approved for the diamond before depositing

## Typical LP Flow

1. Check available pools (get_pools)
2. Analyze pool state and price (get_pool_info)
3. Approve tokens for the diamond (approve_token with amount='max')
4. Open a maker position with desired tick range (open_maker)
5. Monitor position balances and fees (get_asset_balances)
6. Collect fees periodically (collect_fees)
7. Close position when ready (close_maker)
`;

export function registerResources(server: McpServer) {
  server.resource(
    "protocol-info",
    "ammplify://protocol-info",
    {
      description: "Ammplify protocol overview, architecture, and usage guide",
      mimeType: "text/markdown",
    },
    async () => ({
      contents: [{
        uri: "ammplify://protocol-info",
        mimeType: "text/markdown",
        text: PROTOCOL_OVERVIEW,
      }],
    })
  );

  server.resource(
    "deployed-addresses",
    "ammplify://deployed-addresses",
    {
      description: "Contract addresses for tokens, vaults, diamond, and pools",
      mimeType: "application/json",
    },
    async () => ({
      contents: [{
        uri: "ammplify://deployed-addresses",
        mimeType: "application/json",
        text: JSON.stringify(getAddresses(), null, 2),
      }],
    })
  );
}

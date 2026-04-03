import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

export function registerPrompts(server: McpServer) {
  server.prompt(
    "analyze-position",
    "Analyze an Ammplify maker position: fetch balances, fees, and summarize P&L",
    { asset_id: z.string().describe("Asset ID to analyze") },
    ({ asset_id }) => ({
      messages: [
        {
          role: "user" as const,
          content: {
            type: "text" as const,
            text: `Analyze Ammplify position ${asset_id}:

1. Use get_asset_info to get the position details (owner, pool, tick range, type, liquidity)
2. Use get_asset_balances to get current token balances and accrued fees
3. Use get_pool_info on the position's pool to get the current price and tick
4. Determine if the position is in-range (current tick between lowTick and highTick)
5. Summarize:
   - Position type (MAKER vs MAKER_NC) and whether it's compounding
   - Token amounts currently in the position
   - Fees earned so far
   - Whether the position is in-range or out-of-range
   - Any recommendations (e.g., collect fees, adjust range)`,
          },
        },
      ],
    })
  );

  server.prompt(
    "find-best-pool",
    "Compare available Ammplify pools and recommend the best one for earning yield",
    {},
    () => ({
      messages: [
        {
          role: "user" as const,
          content: {
            type: "text" as const,
            text: `Find the best Ammplify pool for earning yield:

1. Use get_pools to list all available pools
2. For each pool, use get_pool_info to get current price, tick, liquidity, and fee tier
3. Use get_tvl to understand protocol-wide TVL distribution
4. Use get_prices to get current token prices
5. Compare pools on:
   - Fee tier (higher = more fee income per swap)
   - Current liquidity (lower = higher fee share per LP)
   - TVL (gauge total capital deployed)
6. Recommend the best pool and suggest a tick range strategy`,
          },
        },
      ],
    })
  );

  server.prompt(
    "open-position-guide",
    "Step-by-step guide to open a new maker position on Ammplify",
    {
      pool_address: z.string().describe("Pool to LP in"),
      token_amount: z.string().optional().describe("Approximate amount to deposit (in token0 terms)"),
    },
    ({ pool_address, token_amount }) => ({
      messages: [
        {
          role: "user" as const,
          content: {
            type: "text" as const,
            text: `Help me open a new maker position on Ammplify:

Pool: ${pool_address}
${token_amount ? `Approximate deposit: ${token_amount}` : ""}

Steps:
1. Use get_pool_info to understand the pool (tokens, current price, tick spacing)
2. Suggest a tick range based on current price. For a balanced position, center around
   the current tick. The range should be divisible by the pool's tickSpacing.
3. Check my token balances with get_token_balance for both tokens
4. Check allowances with get_allowance — if not approved, use approve_token first
5. Calculate appropriate liquidity amount
6. Open the position with open_maker (compounding=true recommended)
7. Confirm with get_asset_balances

Important:
- Ticks must be divisible by tickSpacing (e.g., 60 for 0.3% fee pools)
- Minimum liquidity is 1,000,000 (1e6)
- Both tokens need to be approved for the diamond contract`,
          },
        },
      ],
    })
  );
}

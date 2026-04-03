import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { formatUnits } from "viem";
import { getPublicClient } from "../clients/chain.js";
import * as middleware from "../clients/middleware.js";
import { getDiamondAddress, getAddresses } from "../config.js";
import { IViewAbi } from "../abi/IView.js";
import { IUniswapV3PoolAbi } from "../abi/IUniswapV3Pool.js";
import { IERC20Abi } from "../abi/IERC20.js";

// JSON.stringify replacer that converts BigInt to string
function jsonStringify(obj: unknown): string {
  return JSON.stringify(obj, (_key, value) =>
    typeof value === "bigint" ? value.toString() : value,
    2
  );
}

const MIN_TICK = -887272;
const MAX_TICK = 887272;
const Q192 = 2n ** 192n;

function sqrtPriceToPrice(
  sqrtPriceX96: bigint,
  decimals0: number,
  decimals1: number
): number {
  return (
    Number(sqrtPriceX96 * sqrtPriceX96 * BigInt(10 ** decimals0)) /
    Number(Q192 * BigInt(10 ** decimals1))
  );
}

const LIQ_TYPES = ["MAKER", "MAKER_NC", "TAKER"] as const;

export function registerReadTools(server: McpServer) {
  // ─── get_pools ──────────────────────────────────────────────
  server.tool(
    "get_pools",
    "List all Ammplify pools with token pairs, fees, and addresses",
    {},
    async () => {
      const pools = await middleware.getPools();
      return { content: [{ type: "text", text: jsonStringify(pools) }] };
    }
  );

  // ─── get_pool_info ──────────────────────────────────────────
  server.tool(
    "get_pool_info",
    "Get detailed pool state: current price, tick, liquidity, fee tier, token info",
    { pool_address: z.string().describe("Uniswap V3 pool address") },
    async ({ pool_address }) => {
      const client = getPublicClient();
      const diamond = getDiamondAddress();
      const poolAddr = pool_address as `0x${string}`;

      // Fetch Uniswap pool state directly
      const [slot0, token0Addr, token1Addr, fee, tickSpacing, liquidity] =
        await Promise.all([
          client.readContract({ address: poolAddr, abi: IUniswapV3PoolAbi, functionName: "slot0" }),
          client.readContract({ address: poolAddr, abi: IUniswapV3PoolAbi, functionName: "token0" }),
          client.readContract({ address: poolAddr, abi: IUniswapV3PoolAbi, functionName: "token1" }),
          client.readContract({ address: poolAddr, abi: IUniswapV3PoolAbi, functionName: "fee" }),
          client.readContract({ address: poolAddr, abi: IUniswapV3PoolAbi, functionName: "tickSpacing" }),
          client.readContract({ address: poolAddr, abi: IUniswapV3PoolAbi, functionName: "liquidity" }),
        ]);

      // Ammplify diamond call — may fail if diamond address is wrong
      let poolInfo: unknown = null;
      try {
        poolInfo = await client.readContract({
          address: diamond, abi: IViewAbi, functionName: "getPoolInfo", args: [poolAddr],
        });
      } catch {
        // Diamond not available for this pool/chain
      }

      const [sym0, dec0, sym1, dec1] = await Promise.all([
        client.readContract({ address: token0Addr, abi: IERC20Abi, functionName: "symbol" }),
        client.readContract({ address: token0Addr, abi: IERC20Abi, functionName: "decimals" }),
        client.readContract({ address: token1Addr, abi: IERC20Abi, functionName: "symbol" }),
        client.readContract({ address: token1Addr, abi: IERC20Abi, functionName: "decimals" }),
      ]);

      const [sqrtPriceX96, currentTick] = slot0 as unknown as [bigint, number];
      const price = sqrtPriceToPrice(sqrtPriceX96, Number(dec0), Number(dec1));

      const result = {
        address: poolAddr,
        token0: { address: token0Addr, symbol: sym0, decimals: Number(dec0) },
        token1: { address: token1Addr, symbol: sym1, decimals: Number(dec1) },
        sqrtPriceX96: sqrtPriceX96.toString(),
        currentTick: Number(currentTick),
        price,
        fee: Number(fee),
        tickSpacing: Number(tickSpacing),
        liquidity: liquidity.toString(),
        poolInfo,
      };

      return { content: [{ type: "text", text: jsonStringify(result) }] };
    }
  );

  // ─── get_tick_liquidity ─────────────────────────────────────
  server.tool(
    "get_tick_liquidity",
    "Get liquidity distribution across ticks for a pool in a given range",
    {
      pool_address: z.string().describe("Pool address"),
      lower_tick: z.number().int().describe("Lower tick boundary"),
      upper_tick: z.number().int().describe("Upper tick boundary"),
    },
    async ({ pool_address, lower_tick, upper_tick }) => {
      const data = await middleware.getTickLiquidity(pool_address, lower_tick, upper_tick);
      return { content: [{ type: "text", text: jsonStringify(data) }] };
    }
  );

  // ─── get_positions ──────────────────────────────────────────
  server.tool(
    "get_positions",
    "Get all maker (LP) positions for a wallet address",
    { owner: z.string().describe("Wallet address of the position owner") },
    async ({ owner }) => {
      const data = await middleware.getPositions(owner);
      return { content: [{ type: "text", text: jsonStringify(data) }] };
    }
  );

  // ─── get_asset_info ─────────────────────────────────────────
  server.tool(
    "get_asset_info",
    "Get on-chain details for a specific position: owner, pool, tick range, type, liquidity",
    { asset_id: z.string().describe("Asset ID (uint256 as string)") },
    async ({ asset_id }) => {
      const client = getPublicClient();
      const diamond = getDiamondAddress();
      const result = await client.readContract({
        address: diamond,
        abi: IViewAbi,
        functionName: "getAssetInfo",
        args: [BigInt(asset_id)],
      });

      const [owner, poolAddr, lowTick, highTick, liqType, liq] = result as unknown as [
        string, string, number, number, number, bigint
      ];

      return {
        content: [{
          type: "text",
          text: jsonStringify({
            assetId: asset_id,
            owner,
            poolAddr,
            lowTick: Number(lowTick),
            highTick: Number(highTick),
            liqType: LIQ_TYPES[Number(liqType)] ?? `UNKNOWN(${liqType})`,
            liquidity: liq.toString(),
          }),
        }],
      };
    }
  );

  // ─── get_asset_balances ─────────────────────────────────────
  server.tool(
    "get_asset_balances",
    "Get current token balances and accrued fees for a position",
    { asset_id: z.string().describe("Asset ID (uint256 as string)") },
    async ({ asset_id }) => {
      const client = getPublicClient();
      const diamond = getDiamondAddress();

      const [assetInfo, balances] = await Promise.all([
        client.readContract({
          address: diamond,
          abi: IViewAbi,
          functionName: "getAssetInfo",
          args: [BigInt(asset_id)],
        }),
        client.readContract({
          address: diamond,
          abi: IViewAbi,
          functionName: "queryAssetBalances",
          args: [BigInt(asset_id)],
        }),
      ]);

      const [, poolAddr] = assetInfo as unknown as [string, string];
      const [netBalance0, netBalance1, fees0, fees1] = balances as unknown as [bigint, bigint, bigint, bigint];

      const [token0Addr, token1Addr] = await Promise.all([
        client.readContract({ address: poolAddr as `0x${string}`, abi: IUniswapV3PoolAbi, functionName: "token0" }),
        client.readContract({ address: poolAddr as `0x${string}`, abi: IUniswapV3PoolAbi, functionName: "token1" }),
      ]);

      const [sym0, dec0, sym1, dec1] = await Promise.all([
        client.readContract({ address: token0Addr, abi: IERC20Abi, functionName: "symbol" }),
        client.readContract({ address: token0Addr, abi: IERC20Abi, functionName: "decimals" }),
        client.readContract({ address: token1Addr, abi: IERC20Abi, functionName: "symbol" }),
        client.readContract({ address: token1Addr, abi: IERC20Abi, functionName: "decimals" }),
      ]);

      const d0 = Number(dec0);
      const d1 = Number(dec1);

      return {
        content: [{
          type: "text",
          text: jsonStringify({
            assetId: asset_id,
            pool: poolAddr,
            token0: { address: token0Addr, symbol: sym0, decimals: d0 },
            token1: { address: token1Addr, symbol: sym1, decimals: d1 },
            netBalance0: { raw: netBalance0.toString(), formatted: formatUnits(netBalance0 < 0n ? -netBalance0 : netBalance0, d0) },
            netBalance1: { raw: netBalance1.toString(), formatted: formatUnits(netBalance1 < 0n ? -netBalance1 : netBalance1, d1) },
            fees0: { raw: fees0.toString(), formatted: formatUnits(fees0, d0) },
            fees1: { raw: fees1.toString(), formatted: formatUnits(fees1, d1) },
          }),
        }],
      };
    }
  );

  // ─── get_tvl ────────────────────────────────────────────────
  server.tool(
    "get_tvl",
    "Get total value locked across the Ammplify protocol",
    {},
    async () => {
      const data = await middleware.getTvl();
      return { content: [{ type: "text", text: jsonStringify(data) }] };
    }
  );

  // ─── get_prices ─────────────────────────────────────────────
  server.tool(
    "get_prices",
    "Get current token prices for a pool",
    { pool_address: z.string().describe("Pool address") },
    async ({ pool_address }) => {
      const data = await middleware.getPrices(pool_address);
      return { content: [{ type: "text", text: jsonStringify(data) }] };
    }
  );

  // ─── get_leaderboard ───────────────────────────────────────
  server.tool(
    "get_leaderboard",
    "Get top earners on the Ammplify protocol",
    {
      time_window: z
        .enum(["1d", "30d", "all-time"])
        .default("all-time")
        .describe("Time window for leaderboard"),
    },
    async ({ time_window }) => {
      const data = await middleware.getLeaderboard(time_window);
      return { content: [{ type: "text", text: jsonStringify(data) }] };
    }
  );

  // ─── get_token_balance ──────────────────────────────────────
  server.tool(
    "get_token_balance",
    "Get ERC20 token balance for a wallet. Use token symbol (USDC, WETH) or address.",
    {
      token: z.string().describe("Token symbol (USDC, WETH) or address"),
      owner: z.string().describe("Wallet address to check balance for"),
    },
    async ({ token, owner }) => {
      const client = getPublicClient();
      const addresses = getAddresses();
      let tokenAddr: `0x${string}`;
      let symbol = token;
      let decimals = 18;

      const upper = token.toUpperCase();
      const known = Object.values(addresses.tokens).find(
        (t) => t.symbol.toUpperCase() === upper
      );
      if (known) {
        tokenAddr = known.address as `0x${string}`;
        symbol = known.symbol;
        decimals = known.decimals;
      } else {
        tokenAddr = token as `0x${string}`;
        const [sym, dec] = await Promise.all([
          client.readContract({ address: tokenAddr, abi: IERC20Abi, functionName: "symbol" }),
          client.readContract({ address: tokenAddr, abi: IERC20Abi, functionName: "decimals" }),
        ]);
        symbol = sym as string;
        decimals = Number(dec);
      }

      const balance = await client.readContract({
        address: tokenAddr,
        abi: IERC20Abi,
        functionName: "balanceOf",
        args: [owner as `0x${string}`],
      });

      return {
        content: [{
          type: "text",
          text: jsonStringify({
            token: symbol,
            address: tokenAddr,
            owner,
            balance: balance.toString(),
            formatted: formatUnits(balance as bigint, decimals),
          }),
        }],
      };
    }
  );

  // ─── get_allowance ──────────────────────────────────────────
  server.tool(
    "get_allowance",
    "Check ERC20 allowance for the Ammplify diamond contract. Useful to check if approval is needed before opening a position.",
    {
      token: z.string().describe("Token symbol (USDC, WETH) or address"),
      owner: z.string().describe("Wallet address that granted the allowance"),
    },
    async ({ token, owner }) => {
      const client = getPublicClient();
      const diamond = getDiamondAddress();
      const addresses = getAddresses();
      let tokenAddr: `0x${string}`;
      let symbol = token;

      const upper = token.toUpperCase();
      const known = Object.values(addresses.tokens).find(
        (t) => t.symbol.toUpperCase() === upper
      );
      if (known) {
        tokenAddr = known.address as `0x${string}`;
        symbol = known.symbol;
      } else {
        tokenAddr = token as `0x${string}`;
      }

      const allowance = await client.readContract({
        address: tokenAddr,
        abi: IERC20Abi,
        functionName: "allowance",
        args: [owner as `0x${string}`, diamond],
      });

      return {
        content: [{
          type: "text",
          text: jsonStringify({
            token: symbol,
            tokenAddress: tokenAddr,
            owner,
            spender: diamond,
            allowance: allowance.toString(),
            isMaxApproved: (allowance as bigint) > 2n ** 200n,
          }),
        }],
      };
    }
  );
}

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { parseUnits } from "viem";
import { getPublicClient, getWalletClient, getSignerAddress } from "../clients/chain.js";
import { getDiamondAddress, getAddresses } from "../config.js";
import { IMakerAbi } from "../abi/IMaker.js";
import { IERC20Abi } from "../abi/IERC20.js";

const MIN_SQRT_RATIO = 4295128739n;
const MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342n;

async function executeTx(params: {
  address: `0x${string}`;
  abi: readonly unknown[];
  functionName: string;
  args: unknown[];
}): Promise<{ hash: string; status: string }> {
  const publicClient = getPublicClient();
  const walletClient = getWalletClient();

  // Simulate first to catch reverts
  await publicClient.simulateContract({
    address: params.address,
    abi: params.abi,
    functionName: params.functionName,
    args: params.args,
    account: walletClient.account,
  } as any);

  // Send transaction
  const hash = await walletClient.writeContract({
    address: params.address,
    abi: params.abi,
    functionName: params.functionName,
    args: params.args,
  } as any);

  // Wait for receipt
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  return { hash, status: receipt.status };
}

export function registerWriteTools(server: McpServer) {
  // ─── approve_token ──────────────────────────────────────────
  server.tool(
    "approve_token",
    "Approve the Ammplify diamond to spend tokens. Required before opening a maker position. Use amount='max' for unlimited approval.",
    {
      token: z.string().describe("Token symbol (USDC, WETH) or address"),
      amount: z.string().describe("Amount to approve (human-readable, e.g. '1000') or 'max' for unlimited"),
    },
    async ({ token, amount }) => {
      const diamond = getDiamondAddress();
      const addresses = getAddresses();
      let tokenAddr: `0x${string}`;
      let decimals = 18;

      const upper = token.toUpperCase();
      const known = Object.values(addresses.tokens).find(
        (t) => t.symbol.toUpperCase() === upper
      );
      if (known) {
        tokenAddr = known.address as `0x${string}`;
        decimals = known.decimals;
      } else {
        tokenAddr = token as `0x${string}`;
      }

      const approveAmount =
        amount.toLowerCase() === "max"
          ? 2n ** 256n - 1n
          : parseUnits(amount, decimals);

      const result = await executeTx({
        address: tokenAddr,
        abi: IERC20Abi,
        functionName: "approve",
        args: [diamond, approveAmount],
      });

      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            action: "approve",
            token: upper,
            tokenAddress: tokenAddr,
            spender: diamond,
            amount: amount === "max" ? "unlimited" : amount,
            txHash: result.hash,
            status: result.status,
          }, null, 2),
        }],
      };
    }
  );

  // ─── open_maker ─────────────────────────────────────────────
  server.tool(
    "open_maker",
    "Open a new maker (LP) position on Ammplify. Deposits liquidity into a tick range. Requires token approval first. Minimum liquidity is 1000000 (1e6).",
    {
      pool_address: z.string().describe("Uniswap V3 pool address"),
      low_tick: z.number().int().describe("Lower tick boundary (must be divisible by pool's tickSpacing)"),
      high_tick: z.number().int().describe("Upper tick boundary (must be divisible by pool's tickSpacing)"),
      liquidity: z.string().describe("Liquidity amount as string (uint128). Minimum 1000000."),
      compounding: z.boolean().default(true).describe("Auto-compound earned fees back into the position"),
      recipient: z.string().optional().describe("Recipient address (defaults to signer)"),
    },
    async ({ pool_address, low_tick, high_tick, liquidity, compounding, recipient }) => {
      const rcpt = (recipient || getSignerAddress()) as `0x${string}`;
      const diamond = getDiamondAddress();

      const result = await executeTx({
        address: diamond,
        abi: IMakerAbi,
        functionName: "newMaker",
        args: [
          rcpt,
          pool_address as `0x${string}`,
          low_tick,
          high_tick,
          BigInt(liquidity),
          compounding,
          MIN_SQRT_RATIO,
          MAX_SQRT_RATIO,
          "0x",
        ],
      });

      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            action: "open_maker",
            pool: pool_address,
            lowTick: low_tick,
            highTick: high_tick,
            liquidity,
            compounding,
            recipient: rcpt,
            txHash: result.hash,
            status: result.status,
          }, null, 2),
        }],
      };
    }
  );

  // ─── close_maker ────────────────────────────────────────────
  server.tool(
    "close_maker",
    "Close a maker position and withdraw all tokens + accumulated fees",
    {
      asset_id: z.string().describe("Asset ID of the position to close"),
      recipient: z.string().optional().describe("Recipient address (defaults to signer)"),
    },
    async ({ asset_id, recipient }) => {
      const rcpt = (recipient || getSignerAddress()) as `0x${string}`;
      const diamond = getDiamondAddress();

      const result = await executeTx({
        address: diamond,
        abi: IMakerAbi,
        functionName: "removeMaker",
        args: [rcpt, BigInt(asset_id), MIN_SQRT_RATIO, MAX_SQRT_RATIO, "0x"],
      });

      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            action: "close_maker",
            assetId: asset_id,
            recipient: rcpt,
            txHash: result.hash,
            status: result.status,
          }, null, 2),
        }],
      };
    }
  );

  // ─── adjust_maker ──────────────────────────────────────────
  server.tool(
    "adjust_maker",
    "Adjust an existing maker position's liquidity (increase or decrease). Also collects accrued fees.",
    {
      asset_id: z.string().describe("Asset ID of the position to adjust"),
      target_liquidity: z.string().describe("New target liquidity amount (uint128 as string)"),
      recipient: z.string().optional().describe("Recipient address (defaults to signer)"),
    },
    async ({ asset_id, target_liquidity, recipient }) => {
      const rcpt = (recipient || getSignerAddress()) as `0x${string}`;
      const diamond = getDiamondAddress();

      const result = await executeTx({
        address: diamond,
        abi: IMakerAbi,
        functionName: "adjustMaker",
        args: [rcpt, BigInt(asset_id), BigInt(target_liquidity), MIN_SQRT_RATIO, MAX_SQRT_RATIO, "0x"],
      });

      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            action: "adjust_maker",
            assetId: asset_id,
            targetLiquidity: target_liquidity,
            recipient: rcpt,
            txHash: result.hash,
            status: result.status,
          }, null, 2),
        }],
      };
    }
  );

  // ─── collect_fees ──────────────────────────────────────────
  server.tool(
    "collect_fees",
    "Collect accrued fees from a maker position without changing the position size",
    {
      asset_id: z.string().describe("Asset ID of the position"),
      recipient: z.string().optional().describe("Recipient address (defaults to signer)"),
    },
    async ({ asset_id, recipient }) => {
      const rcpt = (recipient || getSignerAddress()) as `0x${string}`;
      const diamond = getDiamondAddress();

      const result = await executeTx({
        address: diamond,
        abi: IMakerAbi,
        functionName: "collectFees",
        args: [rcpt, BigInt(asset_id), MIN_SQRT_RATIO, MAX_SQRT_RATIO, "0x"],
      });

      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            action: "collect_fees",
            assetId: asset_id,
            recipient: rcpt,
            txHash: result.hash,
            status: result.status,
          }, null, 2),
        }],
      };
    }
  );

  // ─── add_permission ────────────────────────────────────────
  server.tool(
    "add_permission",
    "Grant an address permission to open positions on your behalf",
    { opener: z.string().describe("Address to grant permission to") },
    async ({ opener }) => {
      const diamond = getDiamondAddress();
      const result = await executeTx({
        address: diamond,
        abi: IMakerAbi,
        functionName: "addPermission",
        args: [opener as `0x${string}`],
      });

      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            action: "add_permission",
            opener,
            txHash: result.hash,
            status: result.status,
          }, null, 2),
        }],
      };
    }
  );

  // ─── remove_permission ─────────────────────────────────────
  server.tool(
    "remove_permission",
    "Revoke an address's permission to open positions on your behalf",
    { opener: z.string().describe("Address to revoke permission from") },
    async ({ opener }) => {
      const diamond = getDiamondAddress();
      const result = await executeTx({
        address: diamond,
        abi: IMakerAbi,
        functionName: "removePermission",
        args: [opener as `0x${string}`],
      });

      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            action: "remove_permission",
            opener,
            txHash: result.hash,
            status: result.status,
          }, null, 2),
        }],
      };
    }
  );
}

import chalk from "chalk";
import { getPublicClient } from "../../clients/chain.js";
import { getAddresses, resolveToken } from "../../config.js";
import { IERC20Abi } from "../../abi/index.js";
import { withErrorHandler } from "../../utils/error.js";
import { formatTokenAmount, shortAddr } from "../../utils/format.js";
import { createTable, printTable, printJson } from "../../utils/table.js";
import type { Address } from "viem";

export const viewCollateral = withErrorHandler(
  async (owner: string, options: { token?: string; json?: boolean }) => {
    const client = getPublicClient();
    const addresses = getAddresses();
    const ownerAddr = owner as Address;

    // If specific token, just show that one
    if (options.token) {
      const token = resolveToken(options.token);
      const balance = await client.readContract({
        address: token.address,
        abi: IERC20Abi,
        functionName: "balanceOf",
        args: [ownerAddr],
      });

      if (options.json) {
        printJson({
          owner,
          token: token.symbol,
          address: token.address,
          balance: balance.toString(),
          formatted: formatTokenAmount(balance, token.decimals),
        });
        return;
      }

      console.log(
        `${token.symbol}: ${formatTokenAmount(balance, token.decimals)}`
      );
      return;
    }

    // Show all known token balances
    const tokens = Object.values(addresses.tokens);
    const results = await Promise.all(
      tokens.map(async (t) => {
        const balance = await client.readContract({
          address: t.address as Address,
          abi: IERC20Abi,
          functionName: "balanceOf",
          args: [ownerAddr],
        });
        return { ...t, balance };
      })
    );

    if (options.json) {
      printJson(
        results.map((r) => ({
          symbol: r.symbol,
          address: r.address,
          balance: r.balance.toString(),
          formatted: formatTokenAmount(r.balance, r.decimals),
        }))
      );
      return;
    }

    console.log(chalk.bold(`\nToken Balances for ${shortAddr(owner)}\n`));
    const table = createTable(["Token", "Balance"]);
    for (const r of results) {
      table.push([r.symbol, formatTokenAmount(r.balance, r.decimals)]);
    }
    printTable(table);
  }
);

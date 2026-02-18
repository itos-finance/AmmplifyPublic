import chalk from "chalk";
import { getPublicClient } from "../../clients/chain.js";
import { resolveToken } from "../../config.js";
import { getAccount } from "../../clients/chain.js";
import { IERC20Abi } from "../../abi/index.js";
import { withErrorHandler } from "../../utils/error.js";
import { formatTokenAmount } from "../../utils/format.js";
import { printJson } from "../../utils/table.js";
import type { Address } from "viem";

export const tokenBalance = withErrorHandler(
  async (
    tokenStr: string,
    options: { owner?: string; json?: boolean }
  ) => {
    const client = getPublicClient();
    const token = resolveToken(tokenStr);

    let ownerAddr: Address;
    if (options.owner) {
      ownerAddr = options.owner as Address;
    } else {
      ownerAddr = getAccount().address;
    }

    const balance = await client.readContract({
      address: token.address,
      abi: IERC20Abi,
      functionName: "balanceOf",
      args: [ownerAddr],
    });

    const formatted = formatTokenAmount(balance, token.decimals);

    if (options.json) {
      printJson({
        token: token.symbol,
        address: token.address,
        owner: ownerAddr,
        balance: balance.toString(),
        formatted,
      });
      return;
    }

    console.log(`${token.symbol}: ${chalk.bold(formatted)}`);
  }
);

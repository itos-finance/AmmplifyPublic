import chalk from "chalk";
import { parseUnits } from "viem";
import { resolveToken } from "../../config.js";
import { IERC20Abi } from "../../abi/index.js";
import { executeTx } from "../../utils/tx.js";
import { withErrorHandler } from "../../utils/error.js";
import type { Address } from "viem";

export const tokenApprove = withErrorHandler(
  async (
    tokenStr: string,
    spender: string,
    amount: string,
    options: { confirm: boolean }
  ) => {
    const token = resolveToken(tokenStr);

    // Support "max" as a shorthand for uint256 max
    const parsedAmount =
      amount === "max"
        ? 2n ** 256n - 1n
        : parseUnits(amount, token.decimals);

    console.log(chalk.bold("\nApprove Token\n"));
    console.log(`  Token:   ${token.symbol} (${token.address})`);
    console.log(`  Spender: ${spender}`);
    console.log(`  Amount:  ${amount === "max" ? "MAX (unlimited)" : amount}`);

    await executeTx({
      address: token.address,
      abi: IERC20Abi,
      functionName: "approve",
      args: [spender as Address, parsedAmount],
      noConfirm: !options.confirm,
      description: `Approve ${amount} ${token.symbol} for ${spender}`,
    });

    console.log(chalk.green("\nApproval set successfully!"));
  }
);

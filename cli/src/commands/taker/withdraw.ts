import chalk from "chalk";
import { parseUnits } from "viem";
import { getDiamondAddress, resolveToken } from "../../config.js";
import { getAccount } from "../../clients/chain.js";
import { ITakerAbi } from "../../abi/index.js";
import { executeTx } from "../../utils/tx.js";
import { withErrorHandler } from "../../utils/error.js";
import type { Address } from "viem";

interface WithdrawOptions {
  token: string;
  amount: string;
  recipient?: string;
  confirm: boolean;
}

export const takerWithdraw = withErrorHandler(
  async (options: WithdrawOptions) => {
    const account = getAccount();
    const recipient = (options.recipient || account.address) as Address;
    const token = resolveToken(options.token);
    const amount = parseUnits(options.amount, token.decimals);

    console.log(chalk.bold("\nWithdraw Collateral\n"));
    console.log(`  Token:     ${token.symbol} (${token.address})`);
    console.log(`  Amount:    ${options.amount}`);
    console.log(`  Recipient: ${recipient}`);

    await executeTx({
      address: getDiamondAddress(),
      abi: ITakerAbi,
      functionName: "withdrawCollateral",
      args: [recipient, token.address, amount, "0x"],
      noConfirm: !options.confirm,
      description: `Withdraw ${options.amount} ${token.symbol}`,
    });

    console.log(chalk.green("\nCollateral withdrawn successfully!"));
  }
);

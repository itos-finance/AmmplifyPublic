import chalk from "chalk";
import { getDiamondAddress } from "../../config.js";
import { getAccount } from "../../clients/chain.js";
import { IMakerAbi } from "../../abi/index.js";
import { MIN_SQRT_RATIO, MAX_SQRT_RATIO } from "../../constants.js";
import { executeTx } from "../../utils/tx.js";
import { withErrorHandler } from "../../utils/error.js";
import type { Address } from "viem";

interface MakerOpenOptions {
  pool: string;
  lowTick: number;
  highTick: number;
  liquidity: string;
  compounding: boolean;
  recipient?: string;
  confirm: boolean;
}

export const makerOpen = withErrorHandler(async (options: MakerOpenOptions) => {
  const account = getAccount();
  const recipient = (options.recipient || account.address) as Address;
  const diamond = getDiamondAddress();

  console.log(chalk.bold("\nOpen Maker Position\n"));
  console.log(`  Pool:         ${options.pool}`);
  console.log(`  Ticks:        ${options.lowTick} to ${options.highTick}`);
  console.log(`  Liquidity:    ${options.liquidity}`);
  console.log(`  Compounding:  ${options.compounding}`);
  console.log(`  Recipient:    ${recipient}`);

  const receipt = await executeTx({
    address: diamond,
    abi: IMakerAbi,
    functionName: "newMaker",
    args: [
      recipient,
      options.pool as Address,
      options.lowTick,
      options.highTick,
      BigInt(options.liquidity),
      options.compounding,
      MIN_SQRT_RATIO,
      MAX_SQRT_RATIO,
      "0x",
    ],
    noConfirm: !options.confirm,
    description: `Open maker position: ticks [${options.lowTick}, ${options.highTick}], liq ${options.liquidity}`,
  });

  console.log(chalk.green("\nMaker position opened successfully!"));
});

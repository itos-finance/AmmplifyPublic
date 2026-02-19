import chalk from "chalk";
import { getDiamondAddress } from "../../config.js";
import { IMakerAbi } from "../../abi/index.js";
import { executeTx } from "../../utils/tx.js";
import { withErrorHandler } from "../../utils/error.js";
import type { Address } from "viem";

export const makerAddPermission = withErrorHandler(
  async (opener: string, options: { confirm: boolean }) => {
    console.log(chalk.bold("\nAdd Maker Permission\n"));
    console.log(`  Opener: ${opener}`);

    await executeTx({
      address: getDiamondAddress(),
      abi: IMakerAbi,
      functionName: "addPermission",
      args: [opener as Address],
      noConfirm: !options.confirm,
      description: `Allow ${opener} to open positions on your behalf`,
    });

    console.log(chalk.green("\nPermission added successfully!"));
  }
);

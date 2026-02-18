import chalk from "chalk";
import { getDiamondAddress } from "../../config.js";
import { IMakerAbi } from "../../abi/index.js";
import { executeTx } from "../../utils/tx.js";
import { withErrorHandler } from "../../utils/error.js";
import type { Address } from "viem";

export const makerRemovePermission = withErrorHandler(
  async (opener: string, options: { confirm: boolean }) => {
    console.log(chalk.bold("\nRemove Maker Permission\n"));
    console.log(`  Opener: ${opener}`);

    await executeTx({
      address: getDiamondAddress(),
      abi: IMakerAbi,
      functionName: "removePermission",
      args: [opener as Address],
      noConfirm: !options.confirm,
      description: `Revoke permission for ${opener}`,
    });

    console.log(chalk.green("\nPermission removed successfully!"));
  }
);

import chalk from "chalk";
import { getDiamondAddress } from "../../config.js";
import { getAccount } from "../../clients/chain.js";
import { IMakerAbi } from "../../abi/index.js";
import { MIN_SQRT_RATIO, MAX_SQRT_RATIO } from "../../constants.js";
import { executeTx } from "../../utils/tx.js";
import { withErrorHandler } from "../../utils/error.js";
import type { Address } from "viem";

export const makerClose = withErrorHandler(
  async (assetId: string, options: { recipient?: string; confirm: boolean }) => {
    const account = getAccount();
    const recipient = (options.recipient || account.address) as Address;

    console.log(chalk.bold("\nClose Maker Position\n"));
    console.log(`  Asset ID:  ${assetId}`);
    console.log(`  Recipient: ${recipient}`);

    await executeTx({
      address: getDiamondAddress(),
      abi: IMakerAbi,
      functionName: "removeMaker",
      args: [recipient, BigInt(assetId), MIN_SQRT_RATIO, MAX_SQRT_RATIO, "0x"],
      noConfirm: !options.confirm,
      description: `Close maker position #${assetId}`,
    });

    console.log(chalk.green("\nMaker position closed successfully!"));
  }
);

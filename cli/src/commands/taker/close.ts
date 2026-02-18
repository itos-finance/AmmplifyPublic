import chalk from "chalk";
import { getDiamondAddress } from "../../config.js";
import { ITakerAbi } from "../../abi/index.js";
import { MIN_SQRT_RATIO, MAX_SQRT_RATIO } from "../../constants.js";
import { executeTx } from "../../utils/tx.js";
import { withErrorHandler } from "../../utils/error.js";

export const takerClose = withErrorHandler(
  async (assetId: string, options: { confirm: boolean }) => {
    console.log(chalk.bold("\nClose Taker Position\n"));
    console.log(`  Asset ID: ${assetId}`);

    await executeTx({
      address: getDiamondAddress(),
      abi: ITakerAbi,
      functionName: "removeTaker",
      args: [BigInt(assetId), MIN_SQRT_RATIO, MAX_SQRT_RATIO, "0x"],
      noConfirm: !options.confirm,
      description: `Close taker position #${assetId}`,
    });

    console.log(chalk.green("\nTaker position closed successfully!"));
  }
);

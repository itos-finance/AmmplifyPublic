import chalk from "chalk";
import { getPublicClient } from "../../clients/chain.js";
import { getDiamondAddress } from "../../config.js";
import { IAdminAbi } from "../../abi/index.js";
import { withErrorHandler } from "../../utils/error.js";
import { createTable, printTable, printJson } from "../../utils/table.js";
import type { Address } from "viem";

export const adminFeeConfig = withErrorHandler(
  async (poolAddress: string, options: { json?: boolean }) => {
    const client = getPublicClient();
    const diamond = getDiamondAddress();

    const [feeCurve, splitCurve, compoundThreshold, twapInterval] =
      await client.readContract({
        address: diamond,
        abi: IAdminAbi,
        functionName: "getFeeConfig",
        args: [poolAddress as Address],
      });

    const data = {
      pool: poolAddress,
      feeCurve,
      splitCurve,
      compoundThreshold: compoundThreshold.toString(),
      twapInterval: Number(twapInterval),
    };

    if (options.json) {
      printJson(data);
      return;
    }

    console.log(chalk.bold(`\nFee Config for ${poolAddress}\n`));
    const table = createTable(["Property", "Value"]);
    table.push(
      ["Compound Threshold", data.compoundThreshold],
      ["TWAP Interval", `${data.twapInterval}s`],
      ["Fee Curve", JSON.stringify(feeCurve, null, 2)],
      ["Split Curve", JSON.stringify(splitCurve, null, 2)]
    );
    printTable(table);
  }
);

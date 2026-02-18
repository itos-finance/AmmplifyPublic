import chalk from "chalk";
import { getPublicClient } from "../../clients/chain.js";
import { getDiamondAddress, resolveToken } from "../../config.js";
import { IAdminAbi } from "../../abi/index.js";
import { withErrorHandler } from "../../utils/error.js";
import { shortAddr } from "../../utils/format.js";
import { createTable, printTable, printJson } from "../../utils/table.js";

export const adminVaults = withErrorHandler(
  async (token: string, index: string, options: { json?: boolean }) => {
    const client = getPublicClient();
    const diamond = getDiamondAddress();
    const tokenInfo = resolveToken(token);

    const [vault, backup] = await client.readContract({
      address: diamond,
      abi: IAdminAbi,
      functionName: "viewVaults",
      args: [tokenInfo.address, parseInt(index)],
    });

    if (options.json) {
      printJson({
        token: tokenInfo.symbol,
        tokenAddress: tokenInfo.address,
        vaultIndex: parseInt(index),
        vault,
        backup,
      });
      return;
    }

    console.log(chalk.bold(`\nVaults for ${tokenInfo.symbol} [index ${index}]\n`));
    const table = createTable(["Role", "Address"]);
    table.push(
      ["Primary", vault || "None"],
      ["Backup", backup || "None"]
    );
    printTable(table);
  }
);

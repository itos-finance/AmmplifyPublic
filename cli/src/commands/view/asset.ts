import chalk from "chalk";
import { getPublicClient } from "../../clients/chain.js";
import { getDiamondAddress } from "../../config.js";
import { IViewAbi } from "../../abi/index.js";
import { withErrorHandler } from "../../utils/error.js";
import { shortAddr } from "../../utils/format.js";
import { createTable, printTable, printJson } from "../../utils/table.js";

const LIQ_TYPES = ["MAKER", "TAKER"];

export const viewAsset = withErrorHandler(
  async (assetId: string, options: { json?: boolean }) => {
    const client = getPublicClient();
    const id = BigInt(assetId);

    const [owner, poolAddr, lowTick, highTick, liqType, liq] =
      await client.readContract({
        address: getDiamondAddress(),
        abi: IViewAbi,
        functionName: "getAssetInfo",
        args: [id],
      });

    const data = {
      assetId: id.toString(),
      owner,
      poolAddr,
      lowTick: Number(lowTick),
      highTick: Number(highTick),
      liqType: LIQ_TYPES[Number(liqType)] || String(liqType),
      liquidity: liq.toString(),
    };

    if (options.json) {
      printJson(data);
      return;
    }

    console.log(chalk.bold(`\nAsset #${assetId}\n`));
    const table = createTable(["Property", "Value"]);
    table.push(
      ["Owner", shortAddr(owner)],
      ["Pool", shortAddr(poolAddr)],
      ["Low Tick", data.lowTick.toString()],
      ["High Tick", data.highTick.toString()],
      ["Type", data.liqType],
      ["Liquidity", data.liquidity]
    );
    printTable(table);
  }
);

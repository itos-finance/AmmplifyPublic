import chalk from "chalk";
import { middleware } from "../../clients/index.js";
import { withErrorHandler } from "../../utils/error.js";
import { printJson } from "../../utils/table.js";

export const viewTakerPositions = withErrorHandler(
  async (owner: string, options: { json?: boolean }) => {
    const data = await middleware.getTakerPositions(owner);

    if (options.json) {
      printJson(data);
      return;
    }

    const positions = Array.isArray(data) ? data : (data as any)?.positions || [];
    if (positions.length === 0) {
      console.log(chalk.yellow(`No taker positions found for ${owner}`));
      return;
    }

    console.log(chalk.bold(`\nTaker Positions for ${owner}\n`));
    for (const pos of positions) {
      console.log(chalk.cyan(`  Asset #${pos.assetId || pos.id}`));
      console.log(`    Pool:       ${pos.pool || pos.poolAddr || "N/A"}`);
      console.log(`    Ticks:      ${pos.lowTick ?? "?"} to ${pos.highTick ?? "?"}`);
      console.log(`    Liquidity:  ${pos.liquidity || pos.liq || "N/A"}`);
      console.log();
    }
  }
);

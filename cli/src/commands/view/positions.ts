import chalk from "chalk";
import { middleware } from "../../clients/index.js";
import { withErrorHandler } from "../../utils/error.js";
import { printJson } from "../../utils/table.js";

export const viewPositions = withErrorHandler(
  async (owner: string, options: { json?: boolean }) => {
    const data = await middleware.getPositions(owner);

    if (options.json) {
      printJson(data);
      return;
    }

    // Middleware returns rich data, render it
    const positions = Array.isArray(data) ? data : (data as any)?.positions || [];
    if (positions.length === 0) {
      console.log(chalk.yellow(`No maker positions found for ${owner}`));
      return;
    }

    console.log(chalk.bold(`\nMaker Positions for ${owner}\n`));
    for (const pos of positions) {
      console.log(chalk.cyan(`  Asset #${pos.assetId || pos.id}`));
      console.log(`    Pool:       ${pos.pool || pos.poolAddr || "N/A"}`);
      console.log(`    Ticks:      ${pos.lowTick ?? "?"} to ${pos.highTick ?? "?"}`);
      console.log(`    Liquidity:  ${pos.liquidity || pos.liq || "N/A"}`);
      if (pos.fees0 !== undefined) {
        console.log(`    Fees:       ${pos.fees0} / ${pos.fees1}`);
      }
      console.log();
    }
  }
);

import chalk from "chalk";
import { middleware } from "../../clients/index.js";
import { withErrorHandler } from "../../utils/error.js";
import { printJson } from "../../utils/table.js";

export const viewPrices = withErrorHandler(
  async (options: { pool: string; json?: boolean }) => {
    const data = await middleware.getPrices(options.pool);

    if (options.json) {
      printJson(data);
      return;
    }

    console.log(chalk.bold(`\nPrices for pool ${options.pool}\n`));
    printJson(data);
  }
);

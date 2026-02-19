import chalk from "chalk";
import { middleware } from "../../clients/index.js";
import { withErrorHandler } from "../../utils/error.js";
import { printJson } from "../../utils/table.js";

export const viewLeaderboard = withErrorHandler(
  async (options: { window: string; json?: boolean }) => {
    const data = await middleware.getLeaderboard(options.window);

    if (options.json) {
      printJson(data);
      return;
    }

    console.log(chalk.bold(`\nFee Leaderboard (${options.window})\n`));
    printJson(data);
  }
);

import chalk from "chalk";
import { middleware } from "../../clients/index.js";
import { withErrorHandler } from "../../utils/error.js";
import { createTable, printTable, printJson } from "../../utils/table.js";

export const listPools = withErrorHandler(async (options: { json?: boolean }) => {
  const pools = await middleware.getPools();

  if (options.json) {
    printJson(pools);
    return;
  }

  // Handle both direct array and { pools: [...] } wrapper
  const poolList = Array.isArray(pools) ? pools : (pools as any)?.pools || [];

  if (poolList.length === 0) {
    console.log(chalk.yellow("No pools found."));
    return;
  }

  const table = createTable(["Pool", "Token0", "Token1", "Fee", "Tick Spacing"]);
  for (const pool of poolList as any[]) {
    table.push([
      pool.address || pool.pool || "N/A",
      pool.token0?.symbol || pool.token0 || "N/A",
      pool.token1?.symbol || pool.token1 || "N/A",
      pool.fee?.toString() || "N/A",
      pool.tickSpacing?.toString() || "N/A",
    ]);
  }
  printTable(table);
});

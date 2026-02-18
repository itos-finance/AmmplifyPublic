import chalk from "chalk";
import { middleware } from "../../clients/index.js";
import { withErrorHandler } from "../../utils/error.js";
import { createTable, printTable, printJson } from "../../utils/table.js";

export const viewTvl = withErrorHandler(async (options: { json?: boolean }) => {
  const data = (await middleware.getTvl()) as any;

  if (options.json) {
    printJson(data);
    return;
  }

  const pools = data?.pools || [];
  const total = data?.protocolTotal?.totalValueUSD;

  console.log(chalk.bold("\nProtocol TVL\n"));

  if (total !== undefined && total !== null) {
    console.log(chalk.green(`  Total: $${Number(total).toLocaleString("en-US", { maximumFractionDigits: 2 })}\n`));
  }

  if (pools.length > 0) {
    const table = createTable(["Pool", "Token0", "Token1", "TVL (USD)"]);
    for (const pool of pools) {
      const tvl = pool.totalValueUSD != null
        ? `$${Number(pool.totalValueUSD).toLocaleString("en-US", { maximumFractionDigits: 2 })}`
        : "N/A";
      table.push([
        pool.poolAddress?.slice(0, 10) + "..." || "N/A",
        pool.token0Symbol || "?",
        pool.token1Symbol || "?",
        tvl,
      ]);
    }
    printTable(table);
  }
});

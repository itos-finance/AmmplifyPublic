import type { Command } from "commander";
import { listPools } from "./list.js";
import { poolInfo } from "./info.js";
import { poolLiquidity } from "./liquidity.js";

export function registerPoolCommands(pool: Command) {
  pool
    .command("list")
    .description("List all pools")
    .option("--json", "Output as JSON")
    .action(listPools);

  pool
    .command("info <address>")
    .description("Get pool details")
    .option("--json", "Output as JSON")
    .action(poolInfo);

  pool
    .command("liquidity <address>")
    .description("Get tick liquidity distribution")
    .requiredOption("--lower-tick <tick>", "Lower tick", parseInt)
    .requiredOption("--upper-tick <tick>", "Upper tick", parseInt)
    .option("--json", "Output as JSON")
    .action(poolLiquidity);
}

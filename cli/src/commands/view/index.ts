import type { Command } from "commander";
import { viewAsset } from "./asset.js";
import { viewBalances } from "./balances.js";
import { viewPositions } from "./positions.js";
import { viewTakerPositions } from "./taker-positions.js";
import { viewCollateral } from "./collateral.js";
import { viewTvl } from "./tvl.js";
import { viewPrices } from "./prices.js";
import { viewLeaderboard } from "./leaderboard.js";

export function registerViewCommands(view: Command) {
  view
    .command("asset <assetId>")
    .description("View position info (owner, ticks, type, liquidity)")
    .option("--json", "Output as JSON")
    .action(viewAsset);

  view
    .command("balances <assetId>")
    .description("View token balances and fees for a position")
    .option("--json", "Output as JSON")
    .action(viewBalances);

  view
    .command("positions <owner>")
    .description("List all maker positions for an owner")
    .option("--json", "Output as JSON")
    .action(viewPositions);

  view
    .command("taker-positions <owner>")
    .description("List all taker positions for an owner")
    .option("--json", "Output as JSON")
    .action(viewTakerPositions);

  view
    .command("collateral <owner>")
    .description("View collateral balances")
    .option("--token <token>", "Filter by token symbol or address")
    .option("--json", "Output as JSON")
    .action(viewCollateral);

  view
    .command("tvl")
    .description("View protocol TVL")
    .option("--json", "Output as JSON")
    .action(viewTvl);

  view
    .command("prices")
    .description("View current and historical prices")
    .requiredOption("--pool <address>", "Pool address")
    .option("--json", "Output as JSON")
    .action(viewPrices);

  view
    .command("leaderboard")
    .description("View fee leaderboard")
    .option("--window <window>", "Time window: 1d, 30d, all-time", "all-time")
    .option("--json", "Output as JSON")
    .action(viewLeaderboard);
}

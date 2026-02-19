import type { Command } from "commander";
import { adminFeeConfig } from "./fee-config.js";
import { adminVaults } from "./vaults.js";

export function registerAdminCommands(admin: Command) {
  admin
    .command("fee-config <poolAddress>")
    .description("View fee curve and split curve config")
    .option("--json", "Output as JSON")
    .action(adminFeeConfig);

  admin
    .command("vaults <token> <index>")
    .description("View vault addresses")
    .option("--json", "Output as JSON")
    .action(adminVaults);
}

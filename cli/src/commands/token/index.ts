import type { Command } from "commander";
import { tokenBalance } from "./balance.js";
import { tokenApprove } from "./approve.js";

export function registerTokenCommands(token: Command) {
  token
    .command("balance <token>")
    .description("Check ERC20 token balance")
    .option("--owner <address>", "Owner address (defaults to signer)")
    .option("--json", "Output as JSON")
    .action(tokenBalance);

  token
    .command("approve <token> <spender> <amount>")
    .description("Set ERC20 token allowance")
    .option("--no-confirm", "Skip confirmation prompt")
    .action(tokenApprove);
}

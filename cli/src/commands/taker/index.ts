import type { Command } from "commander";
import { takerOpen } from "./open.js";
import { takerClose } from "./close.js";
import { takerCollateralize } from "./collateralize.js";
import { takerWithdraw } from "./withdraw.js";

export function registerTakerCommands(taker: Command) {
  taker
    .command("open")
    .description("Open a new taker position")
    .requiredOption("--pool <address>", "Pool address")
    .requiredOption("--low-tick <tick>", "Lower tick", parseInt)
    .requiredOption("--high-tick <tick>", "Upper tick", parseInt)
    .requiredOption("--liquidity <amount>", "Liquidity amount")
    .requiredOption(
      "--freeze-price <direction>",
      "Freeze price direction: min or max"
    )
    .option("--vault-x <index>", "X vault index", "0")
    .option("--vault-y <index>", "Y vault index", "0")
    .option("--recipient <address>", "Recipient address (defaults to signer)")
    .option("--no-confirm", "Skip confirmation prompt")
    .action(takerOpen);

  taker
    .command("close <assetId>")
    .description("Close a taker position")
    .option("--no-confirm", "Skip confirmation prompt")
    .action(takerClose);

  taker
    .command("collateralize")
    .description("Add collateral")
    .requiredOption("--token <token>", "Token symbol or address")
    .requiredOption("--amount <amount>", "Amount to deposit")
    .option("--recipient <address>", "Recipient address (defaults to signer)")
    .option("--no-confirm", "Skip confirmation prompt")
    .action(takerCollateralize);

  taker
    .command("withdraw")
    .description("Withdraw collateral")
    .requiredOption("--token <token>", "Token symbol or address")
    .requiredOption("--amount <amount>", "Amount to withdraw")
    .option("--recipient <address>", "Recipient address (defaults to signer)")
    .option("--no-confirm", "Skip confirmation prompt")
    .action(takerWithdraw);
}

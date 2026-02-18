import type { Command } from "commander";
import { makerOpen } from "./open.js";
import { makerClose } from "./close.js";
import { makerAdjust } from "./adjust.js";
import { makerCollectFees } from "./collect-fees.js";
import { makerAddPermission } from "./add-permission.js";
import { makerRemovePermission } from "./remove-permission.js";

export function registerMakerCommands(maker: Command) {
  maker
    .command("open")
    .description("Open a new maker position")
    .requiredOption("--pool <address>", "Pool address")
    .requiredOption("--low-tick <tick>", "Lower tick", parseInt)
    .requiredOption("--high-tick <tick>", "Upper tick", parseInt)
    .requiredOption("--liquidity <amount>", "Liquidity amount")
    .option("--compounding", "Enable compounding", false)
    .option("--recipient <address>", "Recipient address (defaults to signer)")
    .option("--no-confirm", "Skip confirmation prompt")
    .action(makerOpen);

  maker
    .command("close <assetId>")
    .description("Close/remove a maker position")
    .option("--recipient <address>", "Recipient address (defaults to signer)")
    .option("--no-confirm", "Skip confirmation prompt")
    .action(makerClose);

  maker
    .command("adjust <assetId> <targetLiq>")
    .description("Adjust liquidity to target amount")
    .option("--recipient <address>", "Recipient address (defaults to signer)")
    .option("--no-confirm", "Skip confirmation prompt")
    .action(makerAdjust);

  maker
    .command("collect-fees <assetId>")
    .description("Collect accumulated fees")
    .option("--recipient <address>", "Recipient address (defaults to signer)")
    .option("--no-confirm", "Skip confirmation prompt")
    .action(makerCollectFees);

  maker
    .command("add-permission <opener>")
    .description("Allow address to open positions on your behalf")
    .option("--no-confirm", "Skip confirmation prompt")
    .action(makerAddPermission);

  maker
    .command("remove-permission <opener>")
    .description("Revoke opener permission")
    .option("--no-confirm", "Skip confirmation prompt")
    .action(makerRemovePermission);
}

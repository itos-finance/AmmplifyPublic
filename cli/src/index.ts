#!/usr/bin/env node
import { Command } from "commander";
import { registerPoolCommands } from "./commands/pool/index.js";
import { registerViewCommands } from "./commands/view/index.js";
import { registerMakerCommands } from "./commands/maker/index.js";
import { registerTakerCommands } from "./commands/taker/index.js";
import { registerAdminCommands } from "./commands/admin/index.js";
import { registerTokenCommands } from "./commands/token/index.js";

const program = new Command();

program
  .name("ammplify")
  .description("CLI for interacting with the Ammplify protocol")
  .version("0.1.0");

// Register all command groups
const pool = program.command("pool").description("Pool queries");
registerPoolCommands(pool);

const view = program.command("view").description("View on-chain state");
registerViewCommands(view);

const maker = program.command("maker").description("Maker position operations");
registerMakerCommands(maker);

const taker = program.command("taker").description("Taker position operations");
registerTakerCommands(taker);

const admin = program.command("admin").description("Admin view operations");
registerAdminCommands(admin);

const token = program.command("token").description("Token utilities");
registerTokenCommands(token);

program.parse();

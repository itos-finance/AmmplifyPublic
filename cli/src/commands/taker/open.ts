import chalk from "chalk";
import { getDiamondAddress } from "../../config.js";
import { getAccount } from "../../clients/chain.js";
import { ITakerAbi } from "../../abi/index.js";
import { MIN_SQRT_RATIO, MAX_SQRT_RATIO } from "../../constants.js";
import { executeTx } from "../../utils/tx.js";
import { withErrorHandler } from "../../utils/error.js";
import type { Address } from "viem";

interface TakerOpenOptions {
  pool: string;
  lowTick: number;
  highTick: number;
  liquidity: string;
  freezePrice: string;
  vaultX: string;
  vaultY: string;
  recipient?: string;
  confirm: boolean;
}

export const takerOpen = withErrorHandler(async (options: TakerOpenOptions) => {
  const account = getAccount();
  const recipient = (options.recipient || account.address) as Address;
  const diamond = getDiamondAddress();

  // Determine freeze price direction
  const freezeSqrtPriceX96 =
    options.freezePrice === "min" ? MIN_SQRT_RATIO : MAX_SQRT_RATIO;

  console.log(chalk.bold("\nOpen Taker Position\n"));
  console.log(`  Pool:          ${options.pool}`);
  console.log(`  Ticks:         ${options.lowTick} to ${options.highTick}`);
  console.log(`  Liquidity:     ${options.liquidity}`);
  console.log(`  Freeze Price:  ${options.freezePrice}`);
  console.log(`  Vault Indices: [${options.vaultX}, ${options.vaultY}]`);
  console.log(`  Recipient:     ${recipient}`);

  const receipt = await executeTx({
    address: diamond,
    abi: ITakerAbi,
    functionName: "newTaker",
    args: [
      recipient,
      options.pool as Address,
      [options.lowTick, options.highTick], // int24[2] ticks
      BigInt(options.liquidity),
      [parseInt(options.vaultX), parseInt(options.vaultY)], // uint8[2] vaultIndices
      [MIN_SQRT_RATIO, MAX_SQRT_RATIO], // uint160[2] sqrtPriceLimitsX96
      freezeSqrtPriceX96,
      "0x",
    ],
    noConfirm: !options.confirm,
    description: `Open taker position: ticks [${options.lowTick}, ${options.highTick}], liq ${options.liquidity}`,
  });

  console.log(chalk.green("\nTaker position opened successfully!"));
});

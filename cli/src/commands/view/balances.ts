import chalk from "chalk";
import { getPublicClient } from "../../clients/chain.js";
import { getDiamondAddress } from "../../config.js";
import { IViewAbi, IUniswapV3PoolAbi, IERC20Abi } from "../../abi/index.js";
import { withErrorHandler } from "../../utils/error.js";
import {
  formatSignedAmount,
  formatTokenAmount,
  shortAddr,
} from "../../utils/format.js";
import { createTable, printTable, printJson } from "../../utils/table.js";
import type { Address } from "viem";

export const viewBalances = withErrorHandler(
  async (assetId: string, options: { json?: boolean }) => {
    const client = getPublicClient();
    const diamond = getDiamondAddress();
    const id = BigInt(assetId);

    // Get asset info and balances in parallel
    const [assetInfo, balances] = await Promise.all([
      client.readContract({
        address: diamond,
        abi: IViewAbi,
        functionName: "getAssetInfo",
        args: [id],
      }),
      client.readContract({
        address: diamond,
        abi: IViewAbi,
        functionName: "queryAssetBalances",
        args: [id],
      }),
    ]);

    const poolAddr = assetInfo[1] as Address;
    const [netBalance0, netBalance1, fees0, fees1] = balances;

    // Get token info
    const [token0Addr, token1Addr] = await Promise.all([
      client.readContract({ address: poolAddr, abi: IUniswapV3PoolAbi, functionName: "token0" }),
      client.readContract({ address: poolAddr, abi: IUniswapV3PoolAbi, functionName: "token1" }),
    ]);

    const [symbol0, decimals0, symbol1, decimals1] = await Promise.all([
      client.readContract({ address: token0Addr as Address, abi: IERC20Abi, functionName: "symbol" }),
      client.readContract({ address: token0Addr as Address, abi: IERC20Abi, functionName: "decimals" }),
      client.readContract({ address: token1Addr as Address, abi: IERC20Abi, functionName: "symbol" }),
      client.readContract({ address: token1Addr as Address, abi: IERC20Abi, functionName: "decimals" }),
    ]);

    const d0 = Number(decimals0);
    const d1 = Number(decimals1);

    if (options.json) {
      printJson({
        assetId: id.toString(),
        pool: poolAddr,
        token0: { address: token0Addr, symbol: symbol0, decimals: d0 },
        token1: { address: token1Addr, symbol: symbol1, decimals: d1 },
        netBalance0: netBalance0.toString(),
        netBalance1: netBalance1.toString(),
        fees0: fees0.toString(),
        fees1: fees1.toString(),
      });
      return;
    }

    console.log(chalk.bold(`\nBalances for Asset #${assetId}\n`));
    console.log(chalk.gray(`Pool: ${shortAddr(poolAddr)}\n`));

    const table = createTable(["", symbol0 as string, symbol1 as string]);
    table.push(
      [
        "Net Balance",
        formatSignedAmount(netBalance0, d0),
        formatSignedAmount(netBalance1, d1),
      ],
      [
        "Fees",
        formatTokenAmount(fees0, d0),
        formatTokenAmount(fees1, d1),
      ],
      [
        "Total",
        formatSignedAmount(netBalance0 + BigInt(fees0), d0),
        formatSignedAmount(netBalance1 + BigInt(fees1), d1),
      ]
    );
    printTable(table);
  }
);

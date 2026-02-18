import chalk from "chalk";
import { getPublicClient } from "../../clients/chain.js";
import { getDiamondAddress } from "../../config.js";
import { IViewAbi } from "../../abi/index.js";
import { IUniswapV3PoolAbi } from "../../abi/index.js";
import { IERC20Abi } from "../../abi/index.js";
import { withErrorHandler } from "../../utils/error.js";
import { sqrtPriceToPrice, shortAddr } from "../../utils/format.js";
import { createTable, printTable, printJson } from "../../utils/table.js";
import type { Address } from "viem";

export const poolInfo = withErrorHandler(
  async (address: string, options: { json?: boolean }) => {
    const client = getPublicClient();
    const poolAddr = address as Address;

    // Fetch pool data from UniV3 and Ammplify diamond in parallel
    const [slot0, token0Addr, token1Addr, fee, tickSpacing, liquidity, poolInfoResult] =
      await Promise.all([
        client.readContract({
          address: poolAddr,
          abi: IUniswapV3PoolAbi,
          functionName: "slot0",
        }),
        client.readContract({
          address: poolAddr,
          abi: IUniswapV3PoolAbi,
          functionName: "token0",
        }),
        client.readContract({
          address: poolAddr,
          abi: IUniswapV3PoolAbi,
          functionName: "token1",
        }),
        client.readContract({
          address: poolAddr,
          abi: IUniswapV3PoolAbi,
          functionName: "fee",
        }),
        client.readContract({
          address: poolAddr,
          abi: IUniswapV3PoolAbi,
          functionName: "tickSpacing",
        }),
        client.readContract({
          address: poolAddr,
          abi: IUniswapV3PoolAbi,
          functionName: "liquidity",
        }),
        client
          .readContract({
            address: getDiamondAddress(),
            abi: IViewAbi,
            functionName: "getPoolInfo",
            args: [poolAddr],
          })
          .catch(() => null),
      ]);

    // Get token details
    const [symbol0, decimals0, symbol1, decimals1] = await Promise.all([
      client.readContract({ address: token0Addr as Address, abi: IERC20Abi, functionName: "symbol" }),
      client.readContract({ address: token0Addr as Address, abi: IERC20Abi, functionName: "decimals" }),
      client.readContract({ address: token1Addr as Address, abi: IERC20Abi, functionName: "symbol" }),
      client.readContract({ address: token1Addr as Address, abi: IERC20Abi, functionName: "decimals" }),
    ]);

    const sqrtPriceX96 = (slot0 as any)[0] as bigint;
    const currentTick = Number((slot0 as any)[1]);
    const price = sqrtPriceToPrice(sqrtPriceX96, Number(decimals0), Number(decimals1));

    if (options.json) {
      printJson({
        address: poolAddr,
        token0: { address: token0Addr, symbol: symbol0, decimals: Number(decimals0) },
        token1: { address: token1Addr, symbol: symbol1, decimals: Number(decimals1) },
        sqrtPriceX96: sqrtPriceX96.toString(),
        currentTick,
        price,
        fee: Number(fee),
        tickSpacing: Number(tickSpacing),
        liquidity: liquidity.toString(),
        poolInfo: poolInfoResult,
      });
      return;
    }

    console.log(chalk.bold(`\nPool: ${poolAddr}\n`));
    const table = createTable(["Property", "Value"]);
    table.push(
      ["Token0", `${symbol0} (${shortAddr(token0Addr as string)})`],
      ["Token1", `${symbol1} (${shortAddr(token1Addr as string)})`],
      ["Price", `${price.toPrecision(6)} ${symbol0}/${symbol1}`],
      ["Current Tick", currentTick.toString()],
      ["sqrtPriceX96", sqrtPriceX96.toString()],
      ["Fee", `${Number(fee) / 10000}%`],
      ["Tick Spacing", tickSpacing.toString()],
      ["Liquidity", liquidity.toString()]
    );
    printTable(table);

    if (poolInfoResult) {
      console.log(chalk.gray("\nAmmplify Pool Info:"));
      console.log(poolInfoResult);
    }
  }
);

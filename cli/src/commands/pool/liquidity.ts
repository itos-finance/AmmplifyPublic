import { middleware } from "../../clients/index.js";
import { withErrorHandler } from "../../utils/error.js";
import { printJson } from "../../utils/table.js";

export const poolLiquidity = withErrorHandler(
  async (
    address: string,
    options: { lowerTick: number; upperTick: number; json?: boolean }
  ) => {
    const data = await middleware.getTickLiquidity(
      address,
      options.lowerTick,
      options.upperTick
    );

    // Always JSON for now since tick liquidity is complex data
    printJson(data);
  }
);

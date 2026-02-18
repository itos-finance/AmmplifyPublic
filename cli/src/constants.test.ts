import { describe, it, expect } from "vitest";
import {
  MIN_SQRT_RATIO,
  MAX_SQRT_RATIO,
  MIN_TICK,
  MAX_TICK,
  Q96,
  Q192,
} from "./constants.js";

describe("constants", () => {
  it("MIN_SQRT_RATIO matches UniswapV3 TickMath", () => {
    expect(MIN_SQRT_RATIO).toBe(4295128739n);
  });

  it("MAX_SQRT_RATIO matches UniswapV3 TickMath", () => {
    expect(MAX_SQRT_RATIO).toBe(
      1461446703485210103287273052203988822378723970342n
    );
  });

  it("MIN_TICK matches UniswapV3 TickMath", () => {
    expect(MIN_TICK).toBe(-887272);
  });

  it("MAX_TICK matches UniswapV3 TickMath", () => {
    expect(MAX_TICK).toBe(887272);
  });

  it("Q96 equals 2^96", () => {
    expect(Q96).toBe(2n ** 96n);
  });

  it("Q192 equals 2^192", () => {
    expect(Q192).toBe(2n ** 192n);
  });

  it("MIN_TICK and MAX_TICK are symmetric", () => {
    expect(MIN_TICK).toBe(-MAX_TICK);
  });

  it("Q192 equals Q96 squared", () => {
    expect(Q192).toBe(Q96 * Q96);
  });
});

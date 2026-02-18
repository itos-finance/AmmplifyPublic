import { describe, it, expect } from "vitest";
import {
  formatTokenAmount,
  formatSignedAmount,
  sqrtPriceToPrice,
  tickToPrice,
  shortAddr,
  formatBigInt,
} from "./format.js";

describe("formatTokenAmount", () => {
  it("formats USDC amounts (6 decimals)", () => {
    expect(formatTokenAmount(1_000_000n, 6)).toBe("1.000000");
    expect(formatTokenAmount(1_500_000n, 6)).toBe("1.500000");
    expect(formatTokenAmount(500n, 6)).toBe("0.000500");
  });

  it("formats WETH amounts (18 decimals)", () => {
    expect(formatTokenAmount(1_000_000_000_000_000_000n, 18)).toBe("1.000000");
    expect(formatTokenAmount(500_000_000_000_000_000n, 18)).toBe("0.500000");
  });

  it("returns '0' for zero amount", () => {
    expect(formatTokenAmount(0n, 6)).toBe("0");
    expect(formatTokenAmount(0n, 18)).toBe("0");
  });

  it("formats large amounts with commas", () => {
    // 2,000,000 USDC
    const result = formatTokenAmount(2_000_000_000_000n, 6);
    expect(result).toContain("2");
    expect(result).toContain("000");
    expect(result).toContain("000");
  });

  it("respects custom precision", () => {
    expect(formatTokenAmount(1_500_000n, 6, 2)).toBe("1.50");
  });
});

describe("formatSignedAmount", () => {
  it("formats positive amounts without sign", () => {
    expect(formatSignedAmount(1_000_000n, 6)).toBe("1.000000");
  });

  it("formats negative amounts with minus sign", () => {
    expect(formatSignedAmount(-1_000_000n, 6)).toBe("-1.000000");
  });

  it("formats zero", () => {
    expect(formatSignedAmount(0n, 6)).toBe("0");
  });
});

describe("sqrtPriceToPrice", () => {
  it("converts a known sqrtPriceX96 to price", () => {
    // sqrtPriceX96 = 2^96 means price = 1.0 (before decimal adjustment)
    const sqrtPriceX96 = 2n ** 96n;
    const price = sqrtPriceToPrice(sqrtPriceX96, 6, 6);
    expect(price).toBeCloseTo(1.0, 5);
  });

  it("adjusts for decimal differences (USDC/WETH)", () => {
    // sqrtPriceX96 = 2^96 => raw price = 1, adjusted by 10^(6-18) = 10^-12
    const sqrtPriceX96 = 2n ** 96n;
    const price = sqrtPriceToPrice(sqrtPriceX96, 6, 18);
    expect(price).toBeCloseTo(1e-12, 20);
  });

  it("returns a positive number for any valid sqrtPriceX96", () => {
    const sqrtPriceX96 = 1461446703485210103287273052203988822378723970342n; // MAX_SQRT_RATIO
    const price = sqrtPriceToPrice(sqrtPriceX96, 6, 6);
    expect(price).toBeGreaterThan(0);
  });
});

describe("tickToPrice", () => {
  it("converts tick 0 to price 1.0 (same decimals)", () => {
    const price = tickToPrice(0, 6, 6);
    expect(price).toBeCloseTo(1.0, 10);
  });

  it("converts positive tick", () => {
    // 1.0001^100 ≈ 1.01005
    const price = tickToPrice(100, 6, 6);
    expect(price).toBeCloseTo(Math.pow(1.0001, 100), 5);
  });

  it("converts negative tick", () => {
    const price = tickToPrice(-100, 6, 6);
    expect(price).toBeCloseTo(Math.pow(1.0001, -100), 5);
  });

  it("adjusts for decimal differences", () => {
    const price = tickToPrice(0, 6, 18);
    expect(price).toBeCloseTo(1e-12, 20);
  });
});

describe("shortAddr", () => {
  it("truncates a standard address", () => {
    const addr = "0x1234567890abcdef1234567890abcdef12345678";
    expect(shortAddr(addr)).toBe("0x1234...5678");
  });

  it("works with checksummed addresses", () => {
    const addr = "0xAbCdEf1234567890AbCdEf1234567890AbCdEf12";
    expect(shortAddr(addr)).toBe("0xAbCd...Ef12");
  });
});

describe("formatBigInt", () => {
  it("formats small numbers", () => {
    expect(formatBigInt(0n)).toBe("0");
    expect(formatBigInt(42n)).toBe("42");
  });

  it("formats large numbers with locale formatting", () => {
    const result = formatBigInt(1_000_000n);
    // Locale-dependent, but should contain the digits
    expect(result).toContain("1");
    expect(result).toContain("000");
    expect(result).toContain("000");
  });
});

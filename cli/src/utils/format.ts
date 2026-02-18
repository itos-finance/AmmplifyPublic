import { formatUnits } from "viem";
import { Q96, Q192 } from "../constants.js";

/**
 * Format a token amount with the correct number of decimals.
 */
export function formatTokenAmount(
  amount: bigint,
  decimals: number,
  precision: number = 6
): string {
  const formatted = formatUnits(amount, decimals);
  const num = parseFloat(formatted);
  if (Math.abs(num) < 1e-10) return "0";
  if (Math.abs(num) >= 1_000_000) {
    return num.toLocaleString("en-US", { maximumFractionDigits: 2 });
  }
  return num.toFixed(precision);
}

/**
 * Format a signed token amount (int256).
 */
export function formatSignedAmount(
  amount: bigint,
  decimals: number,
  precision: number = 6
): string {
  const isNeg = amount < 0n;
  const abs = isNeg ? -amount : amount;
  const formatted = formatTokenAmount(abs, decimals, precision);
  return isNeg ? `-${formatted}` : formatted;
}

/**
 * Convert sqrtPriceX96 to human-readable price.
 * price = (sqrtPriceX96 / 2^96)^2
 */
export function sqrtPriceToPrice(
  sqrtPriceX96: bigint,
  decimals0: number = 6,
  decimals1: number = 18
): number {
  // price = (sqrtPrice / 2^96)^2 * 10^(decimals0 - decimals1)
  const price = Number(sqrtPriceX96 * sqrtPriceX96 * BigInt(10 ** decimals0)) / Number(Q192 * BigInt(10 ** decimals1));
  return price;
}

/**
 * Convert tick to price.
 * price = 1.0001^tick
 */
export function tickToPrice(
  tick: number,
  decimals0: number = 6,
  decimals1: number = 18
): number {
  const price = Math.pow(1.0001, tick);
  return price * Math.pow(10, decimals0 - decimals1);
}

/**
 * Shorten an address for display.
 */
export function shortAddr(addr: string): string {
  return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
}

/**
 * Format a bigint as a string with commas.
 */
export function formatBigInt(value: bigint): string {
  return value.toLocaleString();
}

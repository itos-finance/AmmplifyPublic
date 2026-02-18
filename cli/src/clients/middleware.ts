import { getConfig } from "../config.js";

function getBaseUrl(): string {
  const { middlewareUrl } = getConfig();
  return middlewareUrl;
}

async function fetchJson<T>(
  path: string,
  options?: { method?: string; body?: unknown }
): Promise<T> {
  const url = `${getBaseUrl()}${path}`;
  const res = await fetch(url, {
    method: options?.method || "GET",
    headers: options?.body ? { "Content-Type": "application/json" } : {},
    body: options?.body ? JSON.stringify(options.body) : undefined,
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Middleware ${res.status}: ${text}`);
  }
  return res.json() as Promise<T>;
}

export async function getPools(): Promise<unknown[]> {
  return fetchJson("/pools");
}

export async function getTickLiquidity(
  pool: string,
  lowerTick: number,
  upperTick: number
): Promise<unknown> {
  return fetchJson("/tick-liquidity", {
    method: "POST",
    body: { pool, lowerTick, upperTick },
  });
}

export async function getPositions(owner: string): Promise<unknown> {
  return fetchJson("/positions", {
    method: "POST",
    body: { owner },
  });
}

export async function getTakerPositions(owner: string): Promise<unknown> {
  return fetchJson("/taker-positions", {
    method: "POST",
    body: { owner },
  });
}

export async function getTvl(): Promise<unknown> {
  return fetchJson("/tvl");
}

export async function getPrices(pool: string): Promise<unknown> {
  return fetchJson("/prices", {
    method: "POST",
    body: { pool },
  });
}

export async function getLeaderboard(
  timeWindow: string = "all-time"
): Promise<unknown> {
  return fetchJson("/leaderboard", {
    method: "POST",
    body: { timeWindow },
  });
}

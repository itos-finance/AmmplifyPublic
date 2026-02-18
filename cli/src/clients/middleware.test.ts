import { describe, it, expect, vi, beforeEach } from "vitest";

// Mock config module before importing middleware
vi.mock("../config.js", () => ({
  getConfig: () => ({
    rpcUrl: "https://test-rpc.example.com",
    chainId: 99999,
    middlewareUrl: "https://test-api.example.com",
  }),
}));

import {
  getPools,
  getTvl,
  getLeaderboard,
  getPositions,
  getTakerPositions,
  getPrices,
} from "./middleware.js";

const mockFetch = vi.fn();
globalThis.fetch = mockFetch;

beforeEach(() => {
  mockFetch.mockReset();
});

function mockOk(data: unknown) {
  mockFetch.mockResolvedValueOnce({
    ok: true,
    json: () => Promise.resolve(data),
    text: () => Promise.resolve(JSON.stringify(data)),
  });
}

function mockError(status: number, body: string) {
  mockFetch.mockResolvedValueOnce({
    ok: false,
    status,
    text: () => Promise.resolve(body),
  });
}

describe("getPools", () => {
  it("fetches and returns pool list", async () => {
    const pools = [{ id: "pool1" }, { id: "pool2" }];
    mockOk(pools);

    const result = await getPools();
    expect(result).toEqual(pools);
    expect(mockFetch).toHaveBeenCalledWith(
      "https://test-api.example.com/pools",
      expect.objectContaining({ method: "GET" })
    );
  });
});

describe("getTvl", () => {
  it("fetches and returns TVL data", async () => {
    const tvl = { total: "1000000" };
    mockOk(tvl);

    const result = await getTvl();
    expect(result).toEqual(tvl);
    expect(mockFetch).toHaveBeenCalledWith(
      "https://test-api.example.com/tvl",
      expect.objectContaining({ method: "GET" })
    );
  });
});

describe("getLeaderboard", () => {
  it("sends correct body with timeWindow", async () => {
    mockOk([{ user: "0x1", fees: "100" }]);

    await getLeaderboard("all-time");
    expect(mockFetch).toHaveBeenCalledWith(
      "https://test-api.example.com/leaderboard",
      expect.objectContaining({
        method: "POST",
        body: JSON.stringify({ timeWindow: "all-time" }),
      })
    );
  });

  it("defaults to all-time window", async () => {
    mockOk([]);

    await getLeaderboard();
    expect(mockFetch).toHaveBeenCalledWith(
      "https://test-api.example.com/leaderboard",
      expect.objectContaining({
        body: JSON.stringify({ timeWindow: "all-time" }),
      })
    );
  });
});

describe("getPositions", () => {
  it("sends owner in body", async () => {
    mockOk([]);

    await getPositions("0xOwnerAddress");
    expect(mockFetch).toHaveBeenCalledWith(
      "https://test-api.example.com/positions",
      expect.objectContaining({
        method: "POST",
        body: JSON.stringify({ owner: "0xOwnerAddress" }),
      })
    );
  });
});

describe("getTakerPositions", () => {
  it("sends owner in body", async () => {
    mockOk([]);

    await getTakerPositions("0xOwnerAddress");
    expect(mockFetch).toHaveBeenCalledWith(
      "https://test-api.example.com/taker-positions",
      expect.objectContaining({
        method: "POST",
        body: JSON.stringify({ owner: "0xOwnerAddress" }),
      })
    );
  });
});

describe("getPrices", () => {
  it("sends pool in body", async () => {
    mockOk({ price: "2000" });

    await getPrices("0xPoolAddress");
    expect(mockFetch).toHaveBeenCalledWith(
      "https://test-api.example.com/prices",
      expect.objectContaining({
        method: "POST",
        body: JSON.stringify({ pool: "0xPoolAddress" }),
      })
    );
  });
});

describe("error handling", () => {
  it("throws on non-200 response", async () => {
    mockError(500, "Internal Server Error");

    await expect(getPools()).rejects.toThrow("Middleware 500: Internal Server Error");
  });

  it("throws on 404", async () => {
    mockError(404, "Not Found");

    await expect(getTvl()).rejects.toThrow("Middleware 404: Not Found");
  });
});

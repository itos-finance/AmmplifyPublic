import { describe, it, expect, beforeAll, vi } from "vitest";
import { writeFileSync, mkdtempSync, rmSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";

// Create a temporary addresses file for testing
let tmpDir: string;
let addressesFile: string;

const testAddresses = {
  network: "testnet",
  chainId: 99999,
  tokens: {
    USDC: {
      address: "0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      decimals: 6,
    },
    WETH: {
      address: "0xBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB",
      decimals: 18,
    },
  },
  diamond: "0xEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE",
  decomposer: "0x6666666666666666666666666666666666666666",
  factory: "0x2222222222222222222222222222222222222222",
  nfpm: "0x3333333333333333333333333333333333333333",
  router: "0x4444444444444444444444444444444444444444",
  pools: { USDC_WETH_3000: "0x5555555555555555555555555555555555555555" },
};

beforeAll(() => {
  tmpDir = mkdtempSync(join(tmpdir(), "ammplify-test-"));
  addressesFile = join(tmpDir, "addresses.json");
  writeFileSync(addressesFile, JSON.stringify(testAddresses));

  // Set env vars before importing config (config reads env at module load)
  process.env.AMMPLIFY_ADDRESSES_FILE = addressesFile;
  process.env.AMMPLIFY_RPC_URL = "https://test-rpc.example.com";
  process.env.AMMPLIFY_CHAIN_ID = "99999";
});

// Dynamic import so env vars are set before module loads
let resolveToken: typeof import("./config.js")["resolveToken"];
let getDiamondAddress: typeof import("./config.js")["getDiamondAddress"];
let getAddresses: typeof import("./config.js")["getAddresses"];

beforeAll(async () => {
  const config = await import("./config.js");
  resolveToken = config.resolveToken;
  getDiamondAddress = config.getDiamondAddress;
  getAddresses = config.getAddresses;
});

describe("resolveToken", () => {
  it("resolves USDC by symbol", () => {
    const result = resolveToken("USDC");
    expect(result.address).toBe(
      "0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    );
    expect(result.symbol).toBe("USDC");
    expect(result.decimals).toBe(6);
  });

  it("resolves WETH by symbol", () => {
    const result = resolveToken("WETH");
    expect(result.address).toBe(
      "0xBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"
    );
    expect(result.symbol).toBe("WETH");
    expect(result.decimals).toBe(18);
  });

  it("is case-insensitive", () => {
    const result = resolveToken("usdc");
    expect(result.symbol).toBe("USDC");
  });

  it("passes through raw 0x address", () => {
    const addr = "0x1234567890abcdef1234567890abcdef12345678";
    const result = resolveToken(addr);
    expect(result.address).toBe(addr);
    expect(result.decimals).toBe(18); // default
  });

  it("throws for unknown token symbol", () => {
    expect(() => resolveToken("UNKNOWN")).toThrow("Unknown token: UNKNOWN");
  });
});

describe("getDiamondAddress", () => {
  it("returns diamond address", () => {
    expect(getDiamondAddress()).toBe(
      "0xEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE"
    );
  });
});

describe("getAddresses", () => {
  it("loads the addresses file", () => {
    const addresses = getAddresses();
    expect(addresses.network).toBe("testnet");
    expect(addresses.tokens.USDC.decimals).toBe(6);
  });

  it("has flat structure with protocol fields", () => {
    const addresses = getAddresses();
    expect(addresses.diamond).toBe(
      "0xEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE"
    );
    expect(addresses.factory).toBe(
      "0x2222222222222222222222222222222222222222"
    );
    expect(addresses.nfpm).toBe(
      "0x3333333333333333333333333333333333333333"
    );
    expect(addresses.pools.USDC_WETH_3000).toBe(
      "0x5555555555555555555555555555555555555555"
    );
  });
});

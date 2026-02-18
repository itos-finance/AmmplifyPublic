import { describe, it, expect, beforeAll, vi } from "vitest";
import { writeFileSync, mkdtempSync, rmSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";

// Create a temporary deployed-addresses.json for testing
let tmpDir: string;
let addressesFile: string;

const testAddresses = {
  network: "testnet",
  deployer: "0x0000000000000000000000000000000000000001",
  tokens: {
    USDC: {
      address: "0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      name: "USD Coin",
      symbol: "USDC",
      decimals: 6,
    },
    WETH: {
      address: "0xBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB",
      name: "Wrapped Ether",
      symbol: "WETH",
      decimals: 18,
    },
  },
  vaults: {
    USDC: {
      address: "0xCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC",
      name: "USDC Vault",
      symbol: "vUSDC",
      asset: "0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    },
    WETH: {
      address: "0xDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD",
      name: "WETH Vault",
      symbol: "vWETH",
      asset: "0xBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB",
    },
  },
  ammplify: {
    simplexDiamond: "0xEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE",
    borrowlessDiamond: "0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF",
    nftManager: "0x1111111111111111111111111111111111111111",
  },
  uniswap: {
    factory: "0x2222222222222222222222222222222222222222",
    nfpm: "0x3333333333333333333333333333333333333333",
    simpleSwapRouter: "0x4444444444444444444444444444444444444444",
    pools: { USDC_WETH_3000: "0x5555555555555555555555555555555555555555" },
  },
  integrations: {
    decomposer: "0x6666666666666666666666666666666666666666",
  },
};

beforeAll(() => {
  tmpDir = mkdtempSync(join(tmpdir(), "ammplify-test-"));
  addressesFile = join(tmpDir, "deployed-addresses.json");
  writeFileSync(addressesFile, JSON.stringify(testAddresses));

  // Set env vars before importing config (config reads env at module load)
  process.env.AMMPLIFY_ADDRESSES_FILE = addressesFile;
  process.env.AMMPLIFY_RPC_URL = "https://test-rpc.example.com";
  process.env.AMMPLIFY_CHAIN_ID = "99999";
});

// Dynamic import so env vars are set before module loads
let resolveToken: typeof import("./config.js")["resolveToken"];
let resolveVault: typeof import("./config.js")["resolveVault"];
let getDiamondAddress: typeof import("./config.js")["getDiamondAddress"];
let getAddresses: typeof import("./config.js")["getAddresses"];

beforeAll(async () => {
  const config = await import("./config.js");
  resolveToken = config.resolveToken;
  resolveVault = config.resolveVault;
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

describe("resolveVault", () => {
  it("resolves USDC vault", () => {
    const addr = resolveVault("USDC");
    expect(addr).toBe("0xCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC");
  });

  it("resolves WETH vault", () => {
    const addr = resolveVault("WETH");
    expect(addr).toBe("0xDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD");
  });

  it("throws for unknown vault", () => {
    expect(() => resolveVault("UNKNOWN")).toThrow("No vault found");
  });
});

describe("getDiamondAddress", () => {
  it("returns simplexDiamond address", () => {
    expect(getDiamondAddress()).toBe(
      "0xEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE"
    );
  });
});

describe("getAddresses", () => {
  it("loads the addresses file", () => {
    const addresses = getAddresses();
    expect(addresses.network).toBe("testnet");
    expect(addresses.tokens.USDC.symbol).toBe("USDC");
  });
});

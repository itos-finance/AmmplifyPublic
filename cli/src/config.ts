import { config as dotenvConfig } from "dotenv";
import { readFileSync } from "fs";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";
import { type Address } from "viem";

const __dirname = dirname(fileURLToPath(import.meta.url));
const cliRoot = resolve(__dirname, "..");

dotenvConfig({ path: resolve(cliRoot, ".env") });

export interface DeployedAddresses {
  network: string;
  chainId: number;
  tokens: Record<string, { address: string; decimals: number }>;
  diamond: string;
  opener?: string;
  decomposer: string;
  factory: string;
  nfpm: string;
  router: string;
  pools: Record<string, string>;
}

function loadAddresses(): DeployedAddresses {
  const addressesPath = resolve(
    cliRoot,
    process.env.AMMPLIFY_ADDRESSES_FILE || "../deployed-addresses.json"
  );
  return JSON.parse(readFileSync(addressesPath, "utf-8"));
}

let _addresses: DeployedAddresses | null = null;

export function getAddresses(): DeployedAddresses {
  if (!_addresses) {
    _addresses = loadAddresses();
  }
  return _addresses;
}

export function getConfig() {
  const rpcUrl = process.env.AMMPLIFY_RPC_URL;
  if (!rpcUrl) throw new Error("AMMPLIFY_RPC_URL is required");

  const chainId = process.env.AMMPLIFY_CHAIN_ID;
  if (!chainId) throw new Error("AMMPLIFY_CHAIN_ID is required");

  return {
    rpcUrl,
    chainId: parseInt(chainId),
    privateKey: process.env.AMMPLIFY_PRIVATE_KEY as `0x${string}` | undefined,
    middlewareUrl:
      process.env.AMMPLIFY_MIDDLEWARE_URL || "https://api.ammplify.xyz",
  };
}

export function getDiamondAddress(): Address {
  return getAddresses().diamond as Address;
}

/**
 * Resolve a token symbol or address to an address.
 * Accepts "USDC", "WETH", or a raw 0x address.
 */
export function resolveToken(tokenOrSymbol: string): {
  address: Address;
  symbol: string;
  decimals: number;
} {
  const addresses = getAddresses();

  // Check if it's a known symbol (keys are symbols in the new schema)
  const upper = tokenOrSymbol.toUpperCase();
  for (const [key, token] of Object.entries(addresses.tokens)) {
    if (key.toUpperCase() === upper) {
      return {
        address: token.address as Address,
        symbol: key,
        decimals: token.decimals,
      };
    }
  }

  // Treat as raw address
  if (tokenOrSymbol.startsWith("0x")) {
    return {
      address: tokenOrSymbol as Address,
      symbol: tokenOrSymbol.slice(0, 10) + "...",
      decimals: 18, // will be fetched on-chain if needed
    };
  }

  throw new Error(`Unknown token: ${tokenOrSymbol}`);
}

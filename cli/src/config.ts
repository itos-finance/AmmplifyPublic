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
  deployer: string;
  tokens: Record<
    string,
    { address: string; name: string; symbol: string; decimals: number }
  >;
  vaults: Record<
    string,
    { address: string; name: string; symbol: string; asset: string }
  >;
  ammplify: {
    simplexDiamond: string;
    borrowlessDiamond: string;
    nftManager: string;
  };
  uniswap: {
    factory: string;
    nfpm: string;
    simpleSwapRouter: string;
    pools: Record<string, string>;
  };
  integrations: {
    decomposer: string;
  };
}

function loadAddresses(): DeployedAddresses {
  const addressesPath = resolve(
    cliRoot,
    process.env.AMMPLIFY_ADDRESSES_FILE || "./addresses/uniswapv3.json"
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
  return getAddresses().ammplify.simplexDiamond as Address;
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

  // Check if it's a known symbol
  const upper = tokenOrSymbol.toUpperCase();
  for (const [, token] of Object.entries(addresses.tokens)) {
    if (token.symbol.toUpperCase() === upper) {
      return {
        address: token.address as Address,
        symbol: token.symbol,
        decimals: token.decimals,
      };
    }
  }

  // Check vault symbols
  for (const [, vault] of Object.entries(addresses.vaults)) {
    if (vault.symbol.toUpperCase() === upper) {
      return {
        address: vault.address as Address,
        symbol: vault.symbol,
        decimals: 18, // vaults typically 18 decimals
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

/**
 * Resolve a vault for a given token symbol.
 */
export function resolveVault(tokenSymbol: string): Address {
  const addresses = getAddresses();
  const upper = tokenSymbol.toUpperCase();
  for (const [, vault] of Object.entries(addresses.vaults)) {
    if (vault.symbol.toUpperCase() === `V${upper}` || vault.asset) {
      const token = Object.values(addresses.tokens).find(
        (t) => t.symbol.toUpperCase() === upper
      );
      if (token && vault.asset.toLowerCase() === token.address.toLowerCase()) {
        return vault.address as Address;
      }
    }
  }
  throw new Error(`No vault found for token: ${tokenSymbol}`);
}

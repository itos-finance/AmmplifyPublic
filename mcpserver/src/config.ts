import { config as dotenvConfig } from "dotenv";
import { readFileSync, existsSync } from "fs";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";
import { type Address } from "viem";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, "..");

dotenvConfig({ path: resolve(root, ".env") });

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

let _addresses: DeployedAddresses | null = null;

export function getAddresses(): DeployedAddresses {
  if (!_addresses) {
    const addressesPath = resolve(
      root,
      process.env.AMMPLIFY_ADDRESSES_FILE || "./addresses/monad-mainnet.json"
    );
    if (!existsSync(addressesPath)) {
      throw new Error(`Addresses file not found: ${addressesPath}`);
    }
    _addresses = JSON.parse(readFileSync(addressesPath, "utf-8"));
  }
  return _addresses!;
}

export function getConfig() {
  return {
    rpcUrl: process.env.AMMPLIFY_RPC_URL || "https://rpc.monad.xyz",
    chainId: process.env.AMMPLIFY_CHAIN_ID
      ? parseInt(process.env.AMMPLIFY_CHAIN_ID)
      : 143,
    privateKey: process.env.AMMPLIFY_PRIVATE_KEY as `0x${string}` | undefined,
    middlewareUrl:
      process.env.AMMPLIFY_MIDDLEWARE_URL || "https://api.ammplify.xyz",
    port: parseInt(process.env.PORT || "3100"),
  };
}

export function getDiamondAddress(): Address {
  return getAddresses().ammplify.simplexDiamond as Address;
}

export function resolveToken(tokenOrSymbol: string): {
  address: Address;
  symbol: string;
  decimals: number;
} {
  const addresses = getAddresses();
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

  if (tokenOrSymbol.startsWith("0x")) {
    return {
      address: tokenOrSymbol as Address,
      symbol: tokenOrSymbol.slice(0, 10) + "...",
      decimals: 18,
    };
  }

  throw new Error(`Unknown token: ${tokenOrSymbol}`);
}

import { config as dotenvConfig } from "dotenv";
import { readFileSync, existsSync } from "fs";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";
import { type Address } from "viem";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, "..");

dotenvConfig({ path: resolve(root, ".env") });

export type NetworkName = "mainnet" | "testnet";

interface NetworkDefaults {
  rpcUrl: string;
  chainId: number;
  addressesFile: string;
}

const NETWORKS: Record<NetworkName, NetworkDefaults> = {
  mainnet: {
    rpcUrl: "https://rpc.monad.xyz",
    chainId: 143,
    addressesFile: "./addresses/monad-mainnet.json",
  },
  testnet: {
    rpcUrl: "https://testnet-rpc.monad.xyz",
    chainId: 10143,
    addressesFile: "./addresses/uniswapv3.json",
  },
};

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

function getNetwork(): NetworkName {
  const env = process.env.AMMPLIFY_NETWORK?.toLowerCase();
  if (env === "testnet") return "testnet";
  return "mainnet";
}

let _addresses: DeployedAddresses | null = null;

export function getAddresses(): DeployedAddresses {
  if (!_addresses) {
    const network = getNetwork();
    const defaults = NETWORKS[network];
    const addressesPath = resolve(
      root,
      process.env.AMMPLIFY_ADDRESSES_FILE || defaults.addressesFile
    );
    if (!existsSync(addressesPath)) {
      throw new Error(
        `Addresses file not found: ${addressesPath}\n` +
        `Set AMMPLIFY_NETWORK=mainnet|testnet or AMMPLIFY_ADDRESSES_FILE to a valid path.`
      );
    }
    _addresses = JSON.parse(readFileSync(addressesPath, "utf-8"));
  }
  return _addresses!;
}

export function getConfig() {
  const network = getNetwork();
  const defaults = NETWORKS[network];

  const rpcUrl = process.env.AMMPLIFY_RPC_URL || defaults.rpcUrl;
  const chainId = process.env.AMMPLIFY_CHAIN_ID
    ? parseInt(process.env.AMMPLIFY_CHAIN_ID)
    : defaults.chainId;

  return {
    network,
    rpcUrl,
    chainId,
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

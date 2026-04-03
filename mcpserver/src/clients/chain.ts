import {
  createPublicClient,
  createWalletClient,
  http,
  type PublicClient,
  type WalletClient,
  type Chain,
  type Transport,
  type Account,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { getConfig } from "../config.js";

let _rpcOverride: string | null = null;
let _publicClient: PublicClient | null = null;
let _walletClient: WalletClient<Transport, Chain, Account> | null = null;

function getRpcUrl(): string {
  return _rpcOverride || getConfig().rpcUrl;
}

function getChain(): Chain {
  const { chainId } = getConfig();
  return {
    id: chainId,
    name: `Chain ${chainId}`,
    nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
    rpcUrls: {
      default: { http: [getRpcUrl()] },
    },
  };
}

export function setRpcUrl(url: string) {
  _rpcOverride = url;
  _publicClient = null;
  _walletClient = null;
}

export function getCurrentRpcUrl(): string {
  return getRpcUrl();
}

export function getPublicClient(): PublicClient {
  if (!_publicClient) {
    _publicClient = createPublicClient({
      chain: getChain(),
      transport: http(getRpcUrl()),
    });
  }
  return _publicClient;
}

export function getWalletClient(): WalletClient<Transport, Chain, Account> {
  if (!_walletClient) {
    const config = getConfig();
    if (!config.privateKey) {
      throw new Error(
        "AMMPLIFY_PRIVATE_KEY is required for write operations."
      );
    }
    const account = privateKeyToAccount(config.privateKey);
    _walletClient = createWalletClient({
      account,
      chain: getChain(),
      transport: http(getRpcUrl()),
    });
  }
  return _walletClient;
}

export function getSignerAddress(): `0x${string}` {
  const config = getConfig();
  if (!config.privateKey) {
    throw new Error("AMMPLIFY_PRIVATE_KEY is required for write operations.");
  }
  return privateKeyToAccount(config.privateKey).address;
}

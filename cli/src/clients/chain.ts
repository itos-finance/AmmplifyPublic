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

function getChain(): Chain {
  const { chainId, rpcUrl } = getConfig();
  return {
    id: chainId,
    name: `Chain ${chainId}`,
    nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
    rpcUrls: {
      default: { http: [rpcUrl] },
    },
  };
}

let _publicClient: PublicClient | null = null;

export function getPublicClient(): PublicClient {
  if (!_publicClient) {
    const { rpcUrl } = getConfig();
    _publicClient = createPublicClient({
      chain: getChain(),
      transport: http(rpcUrl),
    });
  }
  return _publicClient;
}

let _walletClient: WalletClient<Transport, Chain, Account> | null = null;

export function getWalletClient(): WalletClient<Transport, Chain, Account> {
  if (!_walletClient) {
    const config = getConfig();
    if (!config.privateKey) {
      throw new Error(
        "AMMPLIFY_PRIVATE_KEY is required for write operations. Set it in your .env file."
      );
    }
    const account = privateKeyToAccount(config.privateKey);
    _walletClient = createWalletClient({
      account,
      chain: getChain(),
      transport: http(config.rpcUrl),
    });
  }
  return _walletClient;
}

export function getAccount() {
  const config = getConfig();
  if (!config.privateKey) {
    throw new Error("AMMPLIFY_PRIVATE_KEY is required for write operations.");
  }
  return privateKeyToAccount(config.privateKey);
}

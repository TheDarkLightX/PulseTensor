import { type Chain } from "viem";

export type RuntimeConfig = {
  chainId: number;
  chainName: string;
  rpcUrl: string;
  explorerUrl: string;
  coreAddress: string;
  settlementAddress: string;
};

type ChainPreset = RuntimeConfig & { presetId: string };

const defaultCoreAddress = import.meta.env.VITE_DEFAULT_CORE_ADDRESS ?? "";
const defaultSettlementAddress = import.meta.env.VITE_DEFAULT_SETTLEMENT_ADDRESS ?? "";

export const chainPresets: readonly ChainPreset[] = [
  {
    presetId: "pulse-mainnet",
    chainId: 369,
    chainName: "PulseChain",
    rpcUrl: "https://rpc.pulsechain.com",
    explorerUrl: "https://scan.pulsechain.com",
    coreAddress: defaultCoreAddress,
    settlementAddress: defaultSettlementAddress
  },
  {
    presetId: "pulse-testnet",
    chainId: 943,
    chainName: "PulseChain Testnet v4",
    rpcUrl: "https://rpc.v4.testnet.pulsechain.com",
    explorerUrl: "https://scan.v4.testnet.pulsechain.com",
    coreAddress: defaultCoreAddress,
    settlementAddress: defaultSettlementAddress
  },
  {
    presetId: "local-anvil",
    chainId: 31337,
    chainName: "Local Anvil",
    rpcUrl: "http://127.0.0.1:8545",
    explorerUrl: "",
    coreAddress: defaultCoreAddress,
    settlementAddress: defaultSettlementAddress
  }
];

const STORAGE_KEY = "pulsetensor_ui_config_v1";

export function defaultChainConfig(): RuntimeConfig {
  return { ...chainPresets[0] };
}

function parsePositiveInt(raw: string | null): number | null {
  if (!raw || !/^\d+$/.test(raw)) return null;
  const value = Number(raw);
  if (!Number.isSafeInteger(value) || value <= 0) return null;
  return value;
}

function parseString(raw: string | null): string | undefined {
  if (!raw) return undefined;
  const trimmed = raw.trim();
  return trimmed.length === 0 ? undefined : trimmed;
}

export function loadSavedConfig(): Partial<RuntimeConfig> {
  const raw = localStorage.getItem(STORAGE_KEY);
  if (!raw) return {};
  try {
    const parsed = JSON.parse(raw) as Partial<RuntimeConfig>;
    return {
      chainId: typeof parsed.chainId === "number" ? parsed.chainId : undefined,
      chainName: typeof parsed.chainName === "string" ? parsed.chainName : undefined,
      rpcUrl: typeof parsed.rpcUrl === "string" ? parsed.rpcUrl : undefined,
      explorerUrl: typeof parsed.explorerUrl === "string" ? parsed.explorerUrl : undefined,
      coreAddress: typeof parsed.coreAddress === "string" ? parsed.coreAddress : undefined,
      settlementAddress: typeof parsed.settlementAddress === "string" ? parsed.settlementAddress : undefined
    };
  } catch {
    return {};
  }
}

export function saveConfig(config: RuntimeConfig): void {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(config));
}

export function loadRuntimeConfigFromUrl(): Partial<RuntimeConfig> {
  const params = new URLSearchParams(window.location.search);
  const chainId = parsePositiveInt(params.get("chainId"));
  const chainName = parseString(params.get("chainName"));
  const rpcUrl = parseString(params.get("rpc"));
  const explorerUrl = parseString(params.get("explorer"));
  const coreAddress = parseString(params.get("core"));
  const settlementAddress = parseString(params.get("settlement"));
  return {
    chainId: chainId ?? undefined,
    chainName,
    rpcUrl,
    explorerUrl,
    coreAddress,
    settlementAddress
  };
}

export function toViemChain(config: RuntimeConfig): Chain {
  return {
    id: config.chainId,
    name: config.chainName,
    nativeCurrency: {
      name: "Pulse",
      symbol: "PLS",
      decimals: 18
    },
    rpcUrls: {
      default: { http: [config.rpcUrl] },
      public: { http: [config.rpcUrl] }
    },
    blockExplorers: config.explorerUrl
      ? {
          default: {
            name: "Explorer",
            url: config.explorerUrl
          }
        }
      : undefined
  };
}

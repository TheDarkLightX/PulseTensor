import { type Chain } from "viem";
import { isSharedIpfsPathGateway } from "./hosting.ts";

export type RuntimeConfig = {
  chainId: number;
  chainName: string;
  rpcUrl: string;
  explorerUrl: string;
  coreAddress: string;
  settlementAddress: string;
};

type ChainPreset = RuntimeConfig & { presetId: string };

type StoredConfig = {
  presetId?: string;
  coreAddress?: string;
  settlementAddress?: string;
};

const defaultCoreAddress = import.meta.env?.VITE_DEFAULT_CORE_ADDRESS ?? "";
const defaultSettlementAddress = import.meta.env?.VITE_DEFAULT_SETTLEMENT_ADDRESS ?? "";

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

// V3 stores only a built-in preset identifier and public contract addresses. Earlier
// versions could contain arbitrary, credential-bearing routing values and are migrated
// without ever restoring those values directly.
const STORAGE_KEY = "pulsetensor_ui_config_v3";
const LEGACY_STORAGE_KEYS = ["pulsetensor_ui_config_v2", "pulsetensor_ui_config_v1"] as const;

export function defaultChainConfig(): RuntimeConfig {
  return { ...chainPresets[0] };
}

function parseString(raw: string | null): string | undefined {
  if (!raw) return undefined;
  const trimmed = raw.trim();
  return trimmed.length === 0 ? undefined : trimmed;
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function parseStoredConfig(raw: string, allowLegacyRouteMatch = false): StoredConfig | null {
  try {
    const parsed = asRecord(JSON.parse(raw));
    if (!parsed) return null;

    let preset =
      typeof parsed.presetId === "string"
        ? chainPresets.find((candidate) => candidate.presetId === parsed.presetId)
        : undefined;

    // V1/V2 did not persist presetId. An exact built-in route may be represented by its
    // identifier; every other legacy routing field is intentionally ignored.
    if (
      allowLegacyRouteMatch &&
      !preset &&
      typeof parsed.chainId === "number" &&
      typeof parsed.rpcUrl === "string"
    ) {
      preset = chainPresets.find(
        (candidate) => candidate.chainId === parsed.chainId && candidate.rpcUrl === parsed.rpcUrl
      );
    }

    return {
      ...(preset ? { presetId: preset.presetId } : {}),
      ...(typeof parsed.coreAddress === "string" ? { coreAddress: parsed.coreAddress } : {}),
      ...(typeof parsed.settlementAddress === "string"
        ? { settlementAddress: parsed.settlementAddress }
        : {})
    };
  } catch {
    return null;
  }
}

function runtimeConfigFromStored(stored: StoredConfig): Partial<RuntimeConfig> {
  const preset = chainPresets.find((candidate) => candidate.presetId === stored.presetId);
  return {
    ...(preset
      ? {
          chainId: preset.chainId,
          chainName: preset.chainName,
          rpcUrl: preset.rpcUrl,
          explorerUrl: preset.explorerUrl
        }
      : {}),
    ...(stored.coreAddress !== undefined ? { coreAddress: stored.coreAddress } : {}),
    ...(stored.settlementAddress !== undefined
      ? { settlementAddress: stored.settlementAddress }
      : {})
  };
}

function removeStoredConfig(): void {
  localStorage.removeItem(STORAGE_KEY);
  for (const key of LEGACY_STORAGE_KEYS) localStorage.removeItem(key);
}

function removeLegacyStoredConfig(): void {
  for (const key of LEGACY_STORAGE_KEYS) localStorage.removeItem(key);
}

export function loadSavedConfig(): Partial<RuntimeConfig> {
  try {
    if (isSharedIpfsPathGateway(window.location.pathname)) {
      removeStoredConfig();
      return {};
    }

    const currentRaw = localStorage.getItem(STORAGE_KEY);
    const current = currentRaw ? parseStoredConfig(currentRaw) : null;
    if (current) {
      // Rewriting strips any unknown or old routing fields injected into the current key.
      localStorage.setItem(STORAGE_KEY, JSON.stringify(current));
      removeLegacyStoredConfig();
      return runtimeConfigFromStored(current);
    }
    if (currentRaw) localStorage.removeItem(STORAGE_KEY);

    for (const key of LEGACY_STORAGE_KEYS) {
      const legacyRaw = localStorage.getItem(key);
      if (!legacyRaw) continue;
      const migrated = parseStoredConfig(legacyRaw, true);
      if (!migrated) continue;
      localStorage.setItem(STORAGE_KEY, JSON.stringify(migrated));
      removeLegacyStoredConfig();
      return runtimeConfigFromStored(migrated);
    }

    removeLegacyStoredConfig();
    return {};
  } catch {
    return {};
  }
}

export function saveConfig(
  config: RuntimeConfig
): "preset" | "contracts-only" | "disabled-shared-origin" | "storage-unavailable" {
  try {
    if (isSharedIpfsPathGateway(window.location.pathname)) {
      removeStoredConfig();
      return "disabled-shared-origin";
    }
    removeLegacyStoredConfig();
    const preset = chainPresets.find(
      (candidate) => candidate.chainId === config.chainId && candidate.rpcUrl === config.rpcUrl
    );
    localStorage.setItem(
      STORAGE_KEY,
      JSON.stringify({
        ...(preset ? { presetId: preset.presetId } : {}),
        coreAddress: config.coreAddress,
        settlementAddress: config.settlementAddress
      })
    );
    return preset ? "preset" : "contracts-only";
  } catch {
    return "storage-unavailable";
  }
}

export function loadRuntimeConfigFromUrl(): Partial<RuntimeConfig> {
  const params = new URLSearchParams(window.location.search);
  const presetId = parseString(params.get("preset"));
  const preset = chainPresets.find((candidate) => candidate.presetId === presetId);
  if (!preset) return {};
  return {
    chainId: preset.chainId,
    chainName: preset.chainName,
    rpcUrl: preset.rpcUrl,
    explorerUrl: preset.explorerUrl,
    coreAddress: preset.coreAddress,
    settlementAddress: preset.settlementAddress
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

export function buildSafeExplorerTransactionUrl(rawBase: string, hash: `0x${string}`): string | null {
  if (!rawBase || rawBase !== rawBase.trim() || /[\u0000-\u001f\u007f]/u.test(rawBase)) return null;
  try {
    const url = new URL(rawBase);
    const localhost = url.hostname === "localhost" || url.hostname === "127.0.0.1" || url.hostname === "[::1]";
    if (url.username || url.password) return null;
    if (url.protocol !== "https:" && !(url.protocol === "http:" && localhost)) return null;
    url.search = "";
    url.hash = "";
    url.pathname = `${url.pathname.replace(/\/$/, "")}/tx/${hash}`;
    return url.toString();
  } catch {
    return null;
  }
}

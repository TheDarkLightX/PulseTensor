import assert from "node:assert/strict";
import test from "node:test";

import {
  buildSafeExplorerTransactionUrl,
  chainPresets,
  defaultChainConfig,
  loadRuntimeConfigFromUrl,
  loadSavedConfig,
  saveConfig
} from "../src/lib/chains.ts";

const TX_HASH = `0x${"ab".repeat(32)}` as `0x${string}`;

function installBrowserState(search = "", pathname = "/") {
  const values = new Map<string, string>();
  Object.defineProperty(globalThis, "localStorage", {
    configurable: true,
    value: {
      getItem(key: string) { return values.get(key) ?? null; },
      setItem(key: string, value: string) { values.set(key, value); },
      removeItem(key: string) { values.delete(key); }
    }
  });
  Object.defineProperty(globalThis, "window", {
    configurable: true,
    value: { location: { search, pathname } }
  });
  return values;
}

test("empty URL and empty storage do not overwrite built-in defaults with undefined", () => {
  installBrowserState();
  assert.deepEqual(loadSavedConfig(), {});
  assert.deepEqual(loadRuntimeConfigFromUrl(), {});
  assert.deepEqual({ ...defaultChainConfig(), ...loadSavedConfig(), ...loadRuntimeConfigFromUrl() }, chainPresets[0]);
});

test("URL routing accepts only exact built-in preset IDs", () => {
  installBrowserState("?preset=pulse-testnet");
  const { presetId: _presetId, ...expectedRuntimeConfig } = chainPresets[1];
  assert.deepEqual(loadRuntimeConfigFromUrl(), expectedRuntimeConfig);

  installBrowserState("?rpc=https%3A%2F%2Fuser%3Asecret%40rpc.example.test&core=0xabc");
  assert.deepEqual(loadRuntimeConfigFromUrl(), {});
});

test("preset persistence restores public routing while custom routing stores contracts only", () => {
  const values = installBrowserState();
  const preset = { ...chainPresets[1], coreAddress: "0xcore", settlementAddress: "0xsettlement" };
  assert.equal(saveConfig(preset), "preset");
  assert.deepEqual(JSON.parse(values.get("pulsetensor_ui_config_v3") ?? "null"), {
    presetId: "pulse-testnet",
    coreAddress: "0xcore",
    settlementAddress: "0xsettlement"
  });
  assert.deepEqual(loadSavedConfig(), {
    chainId: preset.chainId,
    chainName: preset.chainName,
    rpcUrl: preset.rpcUrl,
    explorerUrl: preset.explorerUrl,
    coreAddress: "0xcore",
    settlementAddress: "0xsettlement"
  });

  assert.equal(saveConfig({ ...preset, rpcUrl: "https://token.example.test/secret" }), "contracts-only");
  assert.deepEqual(JSON.parse(values.get("pulsetensor_ui_config_v3") ?? "null"), {
    coreAddress: "0xcore",
    settlementAddress: "0xsettlement"
  });
  assert.deepEqual(loadSavedConfig(), { coreAddress: "0xcore", settlementAddress: "0xsettlement" });
});

test("saved routing is derived only from an exact built-in preset ID", () => {
  const values = installBrowserState();
  values.set("pulsetensor_ui_config_v3", JSON.stringify({
    presetId: "pulse-testnet",
    chainId: 1,
    chainName: "Attacker Chain",
    rpcUrl: "https://attacker.example/rpc-token",
    explorerUrl: "https://attacker.example",
    coreAddress: "0xcore",
    settlementAddress: "0xsettlement"
  }));

  const { presetId: _presetId, coreAddress: _core, settlementAddress: _settlement, ...routing } = chainPresets[1];
  assert.deepEqual(loadSavedConfig(), {
    ...routing,
    coreAddress: "0xcore",
    settlementAddress: "0xsettlement"
  });
  assert.deepEqual(JSON.parse(values.get("pulsetensor_ui_config_v3") ?? "null"), {
    presetId: "pulse-testnet",
    coreAddress: "0xcore",
    settlementAddress: "0xsettlement"
  });

  values.set("pulsetensor_ui_config_v3", JSON.stringify({
    chainId: chainPresets[1].chainId,
    rpcUrl: chainPresets[1].rpcUrl,
    coreAddress: "0xcore",
    settlementAddress: "0xsettlement"
  }));
  assert.deepEqual(loadSavedConfig(), {
    coreAddress: "0xcore",
    settlementAddress: "0xsettlement"
  });
});

test("legacy records migrate contract addresses but never arbitrary routing", () => {
  const values = installBrowserState();
  values.set("pulsetensor_ui_config_v2", JSON.stringify({
    chainId: 777,
    chainName: "Untrusted",
    rpcUrl: "https://provider.example/secret-token",
    explorerUrl: "https://untrusted.example",
    coreAddress: "0xlegacycore",
    settlementAddress: "0xlegacysettlement"
  }));

  assert.deepEqual(loadSavedConfig(), {
    coreAddress: "0xlegacycore",
    settlementAddress: "0xlegacysettlement"
  });
  assert.deepEqual(JSON.parse(values.get("pulsetensor_ui_config_v3") ?? "null"), {
    coreAddress: "0xlegacycore",
    settlementAddress: "0xlegacysettlement"
  });
  assert.equal(values.has("pulsetensor_ui_config_v2"), false);
});

test("legacy built-in routes migrate by identifier and discard copied route fields", () => {
  const values = installBrowserState();
  values.set("pulsetensor_ui_config_v2", JSON.stringify({
    chainId: chainPresets[1].chainId,
    chainName: "Tampered display name",
    rpcUrl: chainPresets[1].rpcUrl,
    explorerUrl: "https://untrusted.example",
    coreAddress: "0xlegacycore",
    settlementAddress: "0xlegacysettlement"
  }));

  const { presetId: _presetId, coreAddress: _core, settlementAddress: _settlement, ...routing } = chainPresets[1];
  assert.deepEqual(loadSavedConfig(), {
    ...routing,
    coreAddress: "0xlegacycore",
    settlementAddress: "0xlegacysettlement"
  });
  assert.deepEqual(JSON.parse(values.get("pulsetensor_ui_config_v3") ?? "null"), {
    presetId: "pulse-testnet",
    coreAddress: "0xlegacycore",
    settlementAddress: "0xlegacysettlement"
  });
});

test("shared IPFS path-gateway origins never trust or persist local routing", () => {
  const values = installBrowserState("", "/mirror//IPFS/bafy-example/");
  values.set("pulsetensor_ui_config_v3", JSON.stringify({ presetId: "pulse-testnet" }));
  values.set("pulsetensor_ui_config_v2", JSON.stringify({ coreAddress: "0xattacker" }));
  assert.deepEqual(loadSavedConfig(), {});
  assert.equal(saveConfig({ ...chainPresets[0] }), "disabled-shared-origin");
  assert.equal(values.has("pulsetensor_ui_config_v3"), false);
  assert.equal(values.has("pulsetensor_ui_config_v2"), false);
});

test("storage denial falls back to session defaults without crashing", () => {
  Object.defineProperty(globalThis, "localStorage", {
    configurable: true,
    value: {
      getItem() { throw new DOMException("denied", "SecurityError"); },
      setItem() { throw new DOMException("denied", "SecurityError"); },
      removeItem() { throw new DOMException("denied", "SecurityError"); }
    }
  });
  Object.defineProperty(globalThis, "window", {
    configurable: true,
    value: { location: { search: "", pathname: "/" } }
  });
  assert.deepEqual(loadSavedConfig(), {});
  assert.equal(saveConfig({ ...chainPresets[0] }), "storage-unavailable");
});

test("transaction explorer links accept only credential-free public HTTP origins", () => {
  assert.equal(
    buildSafeExplorerTransactionUrl("https://scan.example.test/base?stale=1#old", TX_HASH),
    `https://scan.example.test/base/tx/${TX_HASH}`
  );
  assert.equal(buildSafeExplorerTransactionUrl("javascript:alert(1)", TX_HASH), null);
  assert.equal(buildSafeExplorerTransactionUrl("https://user:secret@scan.example.test", TX_HASH), null);
  assert.equal(buildSafeExplorerTransactionUrl(" https://scan.example.test", TX_HASH), null);
  assert.equal(buildSafeExplorerTransactionUrl("http://scan.example.test", TX_HASH), null);
  assert.equal(
    buildSafeExplorerTransactionUrl("http://127.0.0.1:8545", TX_HASH),
    `http://127.0.0.1:8545/tx/${TX_HASH}`
  );
});

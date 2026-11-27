#!/usr/bin/env node

import { chmodSync, readFileSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, resolve } from "node:path";
import { pathToFileURL } from "node:url";

function fail(message) {
  throw new Error(`capture-frontend-build-inputs: ${message}`);
}

function parseArguments(raw) {
  if (raw.length % 2 !== 0) fail("every option requires a value");
  const values = new Map();
  for (let index = 0; index < raw.length; index += 2) {
    const name = raw[index];
    const value = raw[index + 1];
    if (!name?.startsWith("--") || value === undefined) fail("malformed arguments");
    if (values.has(name)) fail(`duplicate option ${name}`);
    values.set(name, value);
  }
  return values;
}

function required(values, name) {
  const value = values.get(name);
  if (value === undefined || value.length === 0) fail(`${name} is required`);
  return value;
}

function containsSecretLikeText(value) {
  return [
    /(?:^|[^a-z0-9])(?:api[_-]?key|access[_-]?token|auth[_-]?token|secret|password|passwd|authorization|bearer)[=:/_-]/iu,
    /(?:^|[^a-z0-9])sk-[a-z0-9_-]{16,}/iu,
    /(?:^|[^a-z0-9])gh[pousr]_[a-z0-9]{20,}/iu,
    /(?:^|[^a-z0-9])xox[baprs]-[a-z0-9-]{16,}/iu,
    /(?:^|[^A-Z0-9])AKIA[A-Z0-9]{16}(?:$|[^A-Z0-9])/u
  ].some((pattern) => pattern.test(value));
}

function validateAddress(name, value) {
  if (value === "") return;
  if (!/^0x[0-9a-fA-F]{40}$/.test(value)) {
    fail(`${name} must be empty or a 20-byte 0x-prefixed address`);
  }
  if (/^0x0{40}$/i.test(value)) fail(`${name} must not be the zero address`);
}

function validateDigest(name, value) {
  if (value === "") return;
  if (!/^(?:0x)?[0-9a-fA-F]{64}$/.test(value)) {
    fail(`${name} must be empty or a 32-byte hexadecimal SHA-256 digest`);
  }
}

function validateManifestUrl(raw) {
  if (raw === "") return;
  if (raw.trim() !== raw || /[\s\u0000-\u001f\u007f-\u009f]/u.test(raw)) {
    fail("VITE_EXACT_MANIFEST_URL must not contain whitespace or control characters");
  }
  try {
    if (/[\s\u0000-\u001f\u007f-\u009f]/u.test(decodeURIComponent(raw))) {
      fail("VITE_EXACT_MANIFEST_URL must not contain encoded whitespace or control characters");
    }
  } catch (error) {
    if (error instanceof URIError) fail("VITE_EXACT_MANIFEST_URL contains invalid percent encoding");
    throw error;
  }
  if (/[?#\\]/u.test(raw)) {
    fail("VITE_EXACT_MANIFEST_URL must not contain a query, fragment, or backslash");
  }
  if (!/^https?:\/\//iu.test(raw)) {
    fail("VITE_EXACT_MANIFEST_URL must use an explicit HTTP(S) URL");
  }
  let url;
  try {
    url = new URL(raw);
  } catch {
    fail("VITE_EXACT_MANIFEST_URL must be absolute");
  }
  const localhost = url.hostname === "127.0.0.1" || url.hostname === "localhost" || url.hostname === "[::1]";
  if (url.protocol !== "https:" && !(url.protocol === "http:" && localhost)) {
    fail("VITE_EXACT_MANIFEST_URL must use HTTPS (HTTP is allowed only for localhost)");
  }
  if (url.username || url.password || /^[a-z][a-z0-9+.-]*:\/\/[^/]*@/iu.test(raw)) {
    fail("VITE_EXACT_MANIFEST_URL must not contain credentials or user information");
  }
  if (containsSecretLikeText(raw)) {
    fail("VITE_EXACT_MANIFEST_URL looks like it contains a credential or secret token");
  }
}

const values = parseArguments(process.argv.slice(2));
const expectedOptions = new Set(["--frontend-dir", "--output", "--mode"]);
for (const name of values.keys()) {
  if (!expectedOptions.has(name)) fail(`unknown option ${name}`);
}
for (const name of expectedOptions) required(values, name);

const frontendDir = resolve(required(values, "--frontend-dir"));
const output = resolve(required(values, "--output"));
const mode = required(values, "--mode");
let record;

if (mode === "prebuilt-unknown") {
  record = {
    schema: "pulsetensor/frontend-build-inputs/v1",
    provenance: "unknown-prebuilt-artifact",
    public_vite_inputs: null
  };
} else if (mode === "fresh-build") {
  const requireFromFrontend = createRequire(resolve(frontendDir, "package.json"));
  const vitePackagePath = requireFromFrontend.resolve("vite/package.json");
  const vitePackage = JSON.parse(readFileSync(vitePackagePath, "utf8"));
  const viteImport = vitePackage.exports?.["."]?.import?.default;
  if (typeof viteImport !== "string") fail("installed Vite package does not expose its ESM Node API");
  const { loadEnv } = await import(pathToFileURL(resolve(dirname(vitePackagePath), viteImport)).href);
  const loadedEnvironment = loadEnv("production", frontendDir, "VITE_");
  const publicViteInputs = {
    VITE_DEFAULT_CORE_ADDRESS: loadedEnvironment.VITE_DEFAULT_CORE_ADDRESS ?? "",
    VITE_DEFAULT_SETTLEMENT_ADDRESS: loadedEnvironment.VITE_DEFAULT_SETTLEMENT_ADDRESS ?? "",
    VITE_EXACT_MANIFEST_SHA256: loadedEnvironment.VITE_EXACT_MANIFEST_SHA256 ?? "",
    VITE_EXACT_MANIFEST_URL: loadedEnvironment.VITE_EXACT_MANIFEST_URL ?? ""
  };

  for (const [name, value] of Object.entries(publicViteInputs)) {
    if (typeof value !== "string" || containsSecretLikeText(value)) {
      fail(`${name} contains a secret-like value and must not enter a public bundle`);
    }
  }
  validateAddress("VITE_DEFAULT_CORE_ADDRESS", publicViteInputs.VITE_DEFAULT_CORE_ADDRESS);
  validateAddress("VITE_DEFAULT_SETTLEMENT_ADDRESS", publicViteInputs.VITE_DEFAULT_SETTLEMENT_ADDRESS);
  validateDigest("VITE_EXACT_MANIFEST_SHA256", publicViteInputs.VITE_EXACT_MANIFEST_SHA256);
  validateManifestUrl(publicViteInputs.VITE_EXACT_MANIFEST_URL);

  if ((publicViteInputs.VITE_DEFAULT_CORE_ADDRESS === "") !== (publicViteInputs.VITE_DEFAULT_SETTLEMENT_ADDRESS === "")) {
    fail("VITE_DEFAULT_CORE_ADDRESS and VITE_DEFAULT_SETTLEMENT_ADDRESS must be set together");
  }
  if ((publicViteInputs.VITE_EXACT_MANIFEST_SHA256 === "") !== (publicViteInputs.VITE_EXACT_MANIFEST_URL === "")) {
    fail("VITE_EXACT_MANIFEST_SHA256 and VITE_EXACT_MANIFEST_URL must be set together");
  }

  record = {
    schema: "pulsetensor/frontend-build-inputs/v1",
    provenance: "captured-and-frozen-before-fresh-build",
    public_vite_inputs: publicViteInputs
  };
} else {
  fail("--mode must be fresh-build or prebuilt-unknown");
}

writeFileSync(output, `${JSON.stringify(record, null, 2)}\n`, { flag: "wx", mode: 0o600 });
chmodSync(output, 0o600);

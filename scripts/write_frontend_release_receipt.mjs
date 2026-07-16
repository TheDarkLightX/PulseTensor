#!/usr/bin/env node

import { createHash } from "node:crypto";
import { chmodSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

function fail(message) {
  throw new Error(`write-frontend-release-receipt: ${message}`);
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

function sha256Value(value) {
  return createHash("sha256").update(value).digest("hex");
}

function requireSha256(values, name) {
  const value = required(values, name);
  if (!/^[0-9a-f]{64}$/.test(value)) fail(`${name} must be lowercase SHA-256 hex`);
  return value;
}

function requireInteger(values, name, minimum = 0) {
  const value = required(values, name);
  if (!/^(0|[1-9][0-9]*)$/.test(value)) fail(`${name} must be a canonical non-negative integer`);
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < minimum) fail(`${name} is outside the supported range`);
  return parsed;
}

function exactKeys(value, expected, label) {
  if (typeof value !== "object" || value === null || Array.isArray(value)) fail(`${label} must be an object`);
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  if (JSON.stringify(actual) !== JSON.stringify(wanted)) fail(`${label} has unexpected or missing keys`);
}

const values = parseArguments(process.argv.slice(2));
const expectedOptions = new Set([
  "--output",
  "--build-inputs-file",
  "--generated-at-utc",
  "--git-commit",
  "--git-tree-state",
  "--frontend-source-tree-sha256",
  "--release-tooling-sha256",
  "--package-json-sha256",
  "--package-lock-sha256",
  "--vite-config-sha256",
  "--build-mode",
  "--source-stability",
  "--assurance-context",
  "--node-version",
  "--npm-version",
  "--vite-version",
  "--tar-version",
  "--gzip-version",
  "--tree-sha256",
  "--file-count",
  "--total-bytes",
  "--tarball-sha256"
]);
for (const name of values.keys()) {
  if (!expectedOptions.has(name)) fail(`unknown option ${name}`);
}
for (const name of expectedOptions) required(values, name);

const output = resolve(required(values, "--output"));
const generatedAtUtc = required(values, "--generated-at-utc");
if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(generatedAtUtc) || Number.isNaN(Date.parse(generatedAtUtc))) {
  fail("--generated-at-utc must be a canonical ISO-8601 UTC timestamp");
}
const gitCommit = required(values, "--git-commit");
if (!/^[0-9a-f]{40}$|^[0-9a-f]{64}$/.test(gitCommit)) fail("--git-commit must be lowercase Git object hex");
const gitTreeState = required(values, "--git-tree-state");
if (gitTreeState !== "clean" && gitTreeState !== "dirty") fail("--git-tree-state must be clean or dirty");
const buildMode = required(values, "--build-mode");
if (buildMode !== "fresh-build" && buildMode !== "prebuilt-dist") fail("--build-mode must be fresh-build or prebuilt-dist");
const sourceStability = required(values, "--source-stability");
const expectedSourceStability = buildMode === "fresh-build" ? "matched-before-and-after-build" : "captured-at-packaging-only";
if (sourceStability !== expectedSourceStability) fail("--source-stability does not match build mode");
const assuranceContext = required(values, "--assurance-context");
if (assuranceContext !== "not-run-by-release-script" && assuranceContext !== "caller-reported-make-verify-ui-passed") {
  fail("--assurance-context has an unsupported value");
}

const buildInputs = JSON.parse(readFileSync(resolve(required(values, "--build-inputs-file")), "utf8"));
exactKeys(buildInputs, ["schema", "provenance", "public_vite_inputs"], "build inputs");
if (buildInputs.schema !== "pulsetensor/frontend-build-inputs/v1") fail("unsupported build-input schema");
const publicInputNames = [
  "VITE_DEFAULT_CORE_ADDRESS",
  "VITE_DEFAULT_SETTLEMENT_ADDRESS",
  "VITE_EXACT_MANIFEST_SHA256",
  "VITE_EXACT_MANIFEST_URL"
];
let publicViteInputs = null;
let publicViteInputsSha256 = null;
if (buildMode === "fresh-build") {
  if (buildInputs.provenance !== "captured-and-frozen-before-fresh-build") fail("fresh build inputs lack pre-build provenance");
  exactKeys(buildInputs.public_vite_inputs, publicInputNames, "public_vite_inputs");
  for (const name of publicInputNames) {
    if (typeof buildInputs.public_vite_inputs[name] !== "string") fail(`${name} must be a string`);
  }
  publicViteInputs = buildInputs.public_vite_inputs;
  publicViteInputsSha256 = sha256Value(JSON.stringify(publicViteInputs));
} else {
  if (buildInputs.provenance !== "unknown-prebuilt-artifact" || buildInputs.public_vite_inputs !== null) {
    fail("prebuilt artifacts must not claim current build inputs");
  }
}

const viteVersionArgument = required(values, "--vite-version");
const viteVersion = buildMode === "fresh-build" ? viteVersionArgument : null;
if (buildMode === "prebuilt-dist" && viteVersionArgument !== "not-used-for-prebuilt-packaging") {
  fail("prebuilt packaging must not claim a Vite build version");
}

const receipt = {
  schema: "pulsetensor/frontend-release-receipt/v2",
  status: "candidate-release-kit",
  generated_at_utc: generatedAtUtc,
  source_at_packaging: {
    role: buildMode === "fresh-build" ? "fresh-build-source" : "packaging-context-not-claimed-as-build-source",
    stability: sourceStability,
    git_commit: gitCommit,
    git_tree_state: gitTreeState,
    frontend_source_tree_policy: "regular-files-excluding-node_modules-dist-tsbuildinfo-and-dotenv",
    frontend_source_tree_sha256: requireSha256(values, "--frontend-source-tree-sha256"),
    release_tooling_sha256: requireSha256(values, "--release-tooling-sha256")
  },
  build: {
    mode: buildMode,
    provenance: buildInputs.provenance,
    assurance_context: assuranceContext,
    assurance_context_is_attestation: false,
    public_vite_inputs: publicViteInputs,
    public_vite_inputs_sha256: publicViteInputsSha256
  },
  packaging_environment: {
    role: buildMode === "fresh-build" ? "same-process-build-and-packaging-toolchain" : "packaging-only-not-claimed-as-build-toolchain",
    platform: process.platform,
    architecture: process.arch,
    node_version: required(values, "--node-version"),
    npm_version: required(values, "--npm-version"),
    vite_version: viteVersion,
    package_json_sha256: requireSha256(values, "--package-json-sha256"),
    package_lock_sha256: requireSha256(values, "--package-lock-sha256"),
    vite_config_sha256: requireSha256(values, "--vite-config-sha256")
  },
  archive: {
    source: "single-private-validated-dist-snapshot",
    source_date_epoch: 0,
    tar_format: "ustar",
    directory_mode: "0755",
    regular_file_mode: "0644",
    gzip_no_name: true,
    tar_version: required(values, "--tar-version"),
    gzip_version: required(values, "--gzip-version")
  },
  artifacts: {
    frontend_dist_tree_sha256: requireSha256(values, "--tree-sha256"),
    frontend_dist_file_count: requireInteger(values, "--file-count", 1),
    frontend_dist_total_bytes: requireInteger(values, "--total-bytes"),
    frontend_dist_tarball_sha256: requireSha256(values, "--tarball-sha256"),
    manifest: "frontend_dist.sha256.txt",
    tree_hash: "frontend_dist.tree.sha256",
    stats: "frontend_dist.stats.tsv",
    tarball: "frontend_dist.tar.gz",
    tarball_sha256: "frontend_dist.tar.gz.sha256"
  },
  warning: "This candidate receipt is not a signature or CI attestation; independently authenticate it before trusting the artifacts."
};

writeFileSync(output, `${JSON.stringify(receipt, null, 2)}\n`, { flag: "wx", mode: 0o644 });
chmodSync(output, 0o644);

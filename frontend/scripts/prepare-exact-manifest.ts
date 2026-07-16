import { createHash } from "node:crypto";
import { basename, resolve } from "node:path";
import { readFileSync, writeFileSync } from "node:fs";

import {
  MAX_EXACT_MANIFEST_BYTES,
  parseExactDeploymentManifestBytes
} from "../src/lib/exactManifest.ts";

type Arguments = { input: string; output: string; receipt: string };

function fail(message: string): never {
  throw new Error(`prepare-exact-manifest: ${message}`);
}

function parseArguments(raw: string[]): Arguments {
  const values = new Map<string, string>();
  for (let index = 0; index < raw.length; index += 2) {
    const name = raw[index];
    const value = raw[index + 1];
    if (!name?.startsWith("--") || !value) fail("expected --input, --output, and --receipt values");
    if (!['--input', '--output', '--receipt'].includes(name)) fail(`unknown option ${name}`);
    if (values.has(name)) fail(`duplicate option ${name}`);
    values.set(name, value);
  }
  const input = values.get("--input");
  const output = values.get("--output");
  const receipt = values.get("--receipt");
  if (!input || !output || !receipt) fail("--input, --output, and --receipt are required");
  const paths = [resolve(input), resolve(output), resolve(receipt)];
  if (new Set(paths).size !== paths.length) fail("input, output, and receipt paths must be distinct");
  return { input, output, receipt };
}

const args = parseArguments(process.argv.slice(2));
const raw = readFileSync(args.input);
if (raw.byteLength === 0 || raw.byteLength > MAX_EXACT_MANIFEST_BYTES) {
  fail(`candidate must be between 1 and ${MAX_EXACT_MANIFEST_BYTES} bytes`);
}

const manifest = parseExactDeploymentManifestBytes(raw);
const canonical = `${JSON.stringify(
  manifest,
  (_key, value) => typeof value === "bigint" ? value.toString() : value,
  2
)}\n`;
const canonicalBytes = new TextEncoder().encode(canonical);
parseExactDeploymentManifestBytes(canonicalBytes);
const digest = `0x${createHash("sha256").update(canonicalBytes).digest("hex")}`;

const receipt = {
  schema: "pulsetensor/exact-inference-manifest-receipt/v1",
  status: "candidate-not-endorsement",
  generatedAtUtc: new Date().toISOString(),
  manifestFile: basename(args.output),
  manifestBytes: canonicalBytes.byteLength,
  manifestSha256: digest,
  warning: "Digest matching proves byte integrity only. Independent review establishes authenticity."
};

writeFileSync(args.output, canonicalBytes, { flag: "wx", mode: 0o600 });
try {
  writeFileSync(args.receipt, `${JSON.stringify(receipt, null, 2)}\n`, { flag: "wx", mode: 0o600 });
} catch (error) {
  fail(`manifest was written but receipt creation failed: ${String(error)}`);
}

process.stdout.write(`EXACT_MANIFEST_SHA256=${digest}\n`);
process.stdout.write(`EXACT_MANIFEST_BYTES=${canonicalBytes.byteLength}\n`);
process.stdout.write("Candidate prepared; review and verify on-chain before publishing either file.\n");

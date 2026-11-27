import assert from "node:assert/strict";
import test from "node:test";

import {
  MAX_TASK_ARTIFACT_BYTES,
  base32LowerNoPadding,
  prepareTaskArtifact,
  rawSha256CidV1
} from "../src/lib/artifact.ts";

test("prepares a SHA-256 commitment and raw CIDv1 for exact UTF-8 bytes", async () => {
  const result = await prepareTaskArtifact("hello");
  assert.equal(result.byteLength, 5);
  assert.equal(result.artifactSha256, "0x2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824");
  assert.equal(result.rawCidV1, "bafkreibm6jg3ux5qumhcn2b3flc3tyu6dmlb4xa7u5bf44yegnrjhc4yeq");
});

test("base32 and CID helpers reject malformed input", () => {
  assert.equal(base32LowerNoPadding(new Uint8Array([0x66, 0x6f, 0x6f])), "mzxw6");
  assert.throws(() => rawSha256CidV1(new Uint8Array(31)), /32-byte/);
});

test("artifact size boundaries are fail closed", async () => {
  await assert.rejects(() => prepareTaskArtifact(""), /cannot be empty/);
  const exact = await prepareTaskArtifact("x".repeat(MAX_TASK_ARTIFACT_BYTES));
  assert.equal(exact.byteLength, MAX_TASK_ARTIFACT_BYTES);
  await assert.rejects(() => prepareTaskArtifact("x".repeat(MAX_TASK_ARTIFACT_BYTES + 1)), /exceeds/);
});

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { encodeAbiParameters, hexToBytes, keccak256, sha256, stringToHex, type Hex } from "viem";
import { encodeExactInferencePublicValues } from "../src/lib/exact.ts";

const fixture = (name: string) =>
  `0x${readFileSync(new URL(`../../zk/tests/fixtures/${name}.hex`, import.meta.url), "utf8").trim()}` as Hex;
const domain = (name: string) => keccak256(stringToHex(`PULSETENSOR_EXACT_${name}_V1`));

test("Rust guest vector matches independent ABI commitments and the settlement encoder", () => {
  const witness = hexToBytes(fixture("witness"));
  assert.equal(witness.length, 208);
  const view = new DataView(witness.buffer, witness.byteOffset, witness.byteLength);
  const x = Array.from({ length: 32 }, (_, i) => view.getInt16(2 * i, true));
  const w = Array.from({ length: 4 }, (_, j) =>
    Array.from({ length: 32 }, (_, i) => view.getInt8(64 + 32 * j + i)));
  const b = Array.from({ length: 4 }, (_, j) => view.getInt32(192 + 4 * j, true));
  const scores = w.map((row, j) => row.reduce((score, weight, i) => score + BigInt(weight) * BigInt(x[i]), BigInt(b[j]))) as
    [bigint, bigint, bigint, bigint];
  const classIndex = BigInt(scores.findIndex((score) => scores.every((other) => score >= other)));
  assert.equal(classIndex, 2n);
  assert.equal(scores[2], scores[3]);

  const input = encodeAbiParameters([{ type: "bytes32" }, { type: "uint32" }, { type: "int16[32]" }],
    [domain("INPUT"), 1, x]);
  const model = encodeAbiParameters([{ type: "bytes32" }, { type: "uint32" }, { type: "int8[32][4]" }, { type: "int32[4]" }],
    [domain("MODEL"), 1, w, b]);
  const expected = encodeExactInferencePublicValues({
    chainId: 369n,
    settlement: "0x1111111111111111111111111111111111111111",
    taskId: 7n,
    taskSpecHash: keccak256(stringToHex("task-spec")),
    netuid: 9n,
    mechid: 10n,
    verifierConfigId: 11n,
    relationId: sha256(stringToHex("PULSETENSOR/PT_Q8_LINEAR/1")),
    requestNullifier: keccak256(stringToHex("request-nullifier")),
    inputCommitment: sha256(input),
    modelCommitment: sha256(model),
    protocolFeeBps: 1_200n,
    treasury: "0x2222222222222222222222222222222222222222",
    classIndex,
    scores,
    provider: "0x3333333333333333333333333333333333333333",
    beneficiary: "0x4444444444444444444444444444444444444444"
  });
  assert.equal(expected, fixture("journal"));
});

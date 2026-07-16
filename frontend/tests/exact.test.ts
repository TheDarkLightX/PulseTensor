import assert from "node:assert/strict";
import test from "node:test";
import { sha256, type Hex } from "viem";
import {
  EXACT_MAX_PROOF_BYTES,
  EXACT_PUBLIC_VALUES_BYTES,
  INT64_MAX,
  INT64_MIN,
  UINT256_MAX,
  computeExactOutputCommitment,
  encodeExactInferencePublicValues,
  exactTaskStatusLabel,
  parseExactAddress,
  parseExactBigInt,
  parseExactBytes32,
  parseExactClassIndex,
  parseExactInt64,
  parseExactProof,
  parseExactScores,
  parseExactUint
} from "../src/lib/exact.ts";

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

test("canonical integer parsers preserve uint and int64 boundaries", () => {
  assert.equal(parseExactBigInt("-123"), -123n);
  assert.equal(parseExactUint(UINT256_MAX.toString(), 256), UINT256_MAX);
  assert.equal(parseExactInt64(INT64_MIN.toString()), INT64_MIN);
  assert.equal(parseExactInt64(INT64_MAX.toString()), INT64_MAX);
  assert.deepEqual(parseExactScores(["-7", "12", "42", "42"]), [-7n, 12n, 42n, 42n]);
  assert.equal(parseExactClassIndex("3"), 3n);

  for (const invalid of ["", " 1", "1 ", "+1", "01", "-0", "1.0", "1e3", "0x01"]) {
    assert.throws(() => parseExactBigInt(invalid), /canonical|required|whitespace/);
  }
  for (const invalid of ["-1", "+1", "01", "1.0"]) {
    assert.throws(() => parseExactUint(invalid, 64), /canonical/);
  }
  assert.throws(() => parseExactUint("256", 8), /outside uint8/);
  assert.throws(() => parseExactUint("1", 0), /width/);
  assert.throws(() => parseExactInt64((INT64_MIN - 1n).toString()), /outside int64/);
  assert.throws(() => parseExactInt64((INT64_MAX + 1n).toString()), /outside int64/);
  assert.throws(() => parseExactClassIndex("4"), /between 0 and 3/);
  assert.throws(() => parseExactScores(["1", "2", "3"]), /exactly four/);
});

test("address and bytes32 parsers reject ambiguous or zero identities", () => {
  assert.equal(
    parseExactAddress("0x1111111111111111111111111111111111111111"),
    "0x1111111111111111111111111111111111111111"
  );
  assert.equal(parseExactAddress(ZERO_ADDRESS, "Treasury", true), ZERO_ADDRESS);
  assert.throws(() => parseExactAddress(ZERO_ADDRESS), /zero address/);
  assert.throws(() => parseExactAddress("0x1111"), /valid EVM address/);
  assert.throws(
    () => parseExactAddress("0x52908400098527886E0F7030069857D2E4169Ee7"),
    /valid EVM address/
  );

  const bytes32 = `0x${"aB".repeat(32)}`;
  assert.equal(parseExactBytes32(bytes32), `0x${"ab".repeat(32)}`);
  assert.throws(() => parseExactBytes32("0x12"), /exactly 32 bytes/);
  assert.throws(() => parseExactBytes32(`0x${"00".repeat(32)}`, "Commitment", false), /cannot be zero/);
});

test("proof parser enforces the Solidity byte envelope and optional selector", () => {
  assert.equal(
    parseExactProof("0x73C457BA", { expectedSelector: "0x73c457ba" }),
    "0x73c457ba"
  );
  const maximumProof = `0x73c457ba${"00".repeat(EXACT_MAX_PROOF_BYTES - 4)}`;
  assert.equal((parseExactProof(maximumProof).length - 2) / 2, EXACT_MAX_PROOF_BYTES);

  assert.throws(() => parseExactProof("0x010203"), /between 4 and/);
  assert.throws(() => parseExactProof(`0x${"00".repeat(EXACT_MAX_PROOF_BYTES + 1)}`), /between 4 and/);
  assert.throws(() => parseExactProof("0x1234567"), /even-length/);
  assert.throws(
    () => parseExactProof("0x73c457ba00", { expectedSelector: "0x01020304" }),
    /selector does not match/
  );
  assert.throws(
    () => parseExactProof("0x73c457ba", { expectedSelector: "0x1234" as Hex }),
    /exactly 4 bytes/
  );
  assert.throws(() => parseExactProof("0x73c457ba00", { expectedByteLength: 4 }), /exactly 4 bytes/);
});

test("task status labels match the Solidity enum order and preserve unknowns", () => {
  assert.equal(exactTaskStatusLabel(0), "None");
  assert.equal(exactTaskStatusLabel(1n), "Open");
  assert.equal(exactTaskStatusLabel(2), "Proof settled");
  assert.equal(exactTaskStatusLabel(3), "Expired refund");
  assert.equal(exactTaskStatusLabel(4), "Verifier revoked refund");
  assert.equal(exactTaskStatusLabel(5), "Verifier unavailable refund");
  assert.equal(exactTaskStatusLabel(6), "Unknown (6)");
});

test("output commitment matches an independently ABI-encoded Foundry vector", () => {
  assert.equal(
    computeExactOutputCommitment(2n, [-7n, 12n, 42n, 42n]),
    "0x10a2295c5c6d9570ccbaea00ca50a0b4eba12cd4d22b7e92bd67e21bd59e3f46"
  );
  assert.throws(() => computeExactOutputCommitment(4n, [-7n, 12n, 42n, 42n]), /between 0 and 3/);
  assert.throws(
    () => computeExactOutputCommitment(2n, [INT64_MIN - 1n, 12n, 42n, 42n]),
    /outside int64/
  );
});

test("public-values encoder matches the committed Solidity 736-byte golden vector", () => {
  const encoded = encodeExactInferencePublicValues({
    chainId: 369n,
    settlement: "0x1111111111111111111111111111111111111111",
    taskId: 7n,
    taskSpecHash: "0x4e6f440c6b2fd7fb1b68155401e47f52b7a492b186a112ef5cef1d31807cdb76",
    netuid: 9n,
    mechid: 10n,
    verifierConfigId: 11n,
    relationId: "0x48a3045b928f9e95b25747a674941e3c55668f2bdb53cf4cf4822bc924feed44",
    requestNullifier: "0xa01a5b35be6e012def391c9df3bbda06f72341feef9ea76a3b9703fca18eb681",
    inputCommitment: "0xeee475da7d6fe76d90852dfa97de0e1f047cb72d7d0134552245b7cda9a9fb68",
    modelCommitment: "0x1a1f4502024df8a68d12e64bb2364ad6308d04ed0a7d5e8300a676ec70867140",
    protocolFeeBps: 1_200n,
    treasury: "0x2222222222222222222222222222222222222222",
    classIndex: 2n,
    scores: [-7n, 12n, 42n, 42n],
    provider: "0x3333333333333333333333333333333333333333",
    beneficiary: "0x4444444444444444444444444444444444444444"
  });

  assert.equal((encoded.length - 2) / 2, EXACT_PUBLIC_VALUES_BYTES);
  assert.equal(sha256(encoded), "0xd6bf3e24201d46ca655687be218f9186309e1138e0866073e8fd6fabaaf02067");
});

test("journal encoder rejects states unreachable through exact task admission", () => {
  const valid = {
    chainId: 369n,
    settlement: "0x1111111111111111111111111111111111111111" as const,
    taskId: 7n,
    taskSpecHash: `0x${"01".repeat(32)}` as Hex,
    netuid: 9n,
    mechid: 10n,
    verifierConfigId: 11n,
    relationId: `0x${"02".repeat(32)}` as Hex,
    requestNullifier: `0x${"03".repeat(32)}` as Hex,
    inputCommitment: `0x${"04".repeat(32)}` as Hex,
    modelCommitment: `0x${"05".repeat(32)}` as Hex,
    protocolFeeBps: 0n,
    treasury: ZERO_ADDRESS,
    classIndex: 2n,
    scores: [-7n, 12n, 42n, 42n] as const,
    provider: "0x3333333333333333333333333333333333333333" as const,
    beneficiary: "0x4444444444444444444444444444444444444444" as const
  };

  assert.doesNotThrow(() => encodeExactInferencePublicValues(valid));
  assert.throws(() => encodeExactInferencePublicValues({ ...valid, mechid: 1_024n }), /maximum/);
  assert.throws(() => encodeExactInferencePublicValues({ ...valid, protocolFeeBps: 3_001n }), /maximum/);
  assert.throws(
    () => encodeExactInferencePublicValues({ ...valid, protocolFeeBps: 1n }),
    /Treasury must be zero exactly/
  );
  assert.throws(
    () =>
      encodeExactInferencePublicValues({
        ...valid,
        treasury: "0x2222222222222222222222222222222222222222"
      }),
    /Treasury must be zero exactly/
  );
});

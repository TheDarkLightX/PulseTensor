import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  assertSafeManifestFetchUrl,
  EXACT_MANIFEST_SCHEMA,
  loadDigestPinnedManifest,
  MAX_EXACT_EVIDENCE_URI_LENGTH,
  MAX_EXACT_MANIFEST_BYTES,
  parseDigestPinnedManifestBytes,
  parseExactDeploymentManifest,
  parseExactDeploymentManifestBytes,
  sha256Hex
} from "../src/lib/exactManifest.ts";

const H1 = `0x${"11".repeat(32)}`;
const H2 = `0x${"22".repeat(32)}`;
const H3 = `0x${"33".repeat(32)}`;
const H4 = `0x${"44".repeat(32)}`;
const H5 = `0x${"55".repeat(32)}`;
const H6 = `0x${"66".repeat(32)}`;

function validManifest(): Record<string, unknown> {
  return {
    schema: EXACT_MANIFEST_SCHEMA,
    chainId: 943,
    sourceCommit: "a".repeat(40),
    deploymentAnchor: { blockNumber: "1234", blockHash: H6, minimumConfirmations: 64 },
    core: { address: "0x0000000000000000000000000000000000001001", runtimeCodeHash: H1 },
    exactSettlement: { address: "0x0000000000000000000000000000000000001002", runtimeCodeHash: H2 },
    verifierConfigs: [
      {
        netuid: 1,
        configId: "1",
        adapter: "0x0000000000000000000000000000000000001003",
        adapterRuntimeCodeHash: H3,
        baseVerifier: "0x0000000000000000000000000000000000001004",
        verifierRuntimeCodeHash: H4,
        programId: H5,
        relationId: H6,
        proofSystemId: H1,
        proofSelector: "0x12345678",
        verifierVersionHash: H2,
        proofBytes: 260,
        protocolFeeBps: 300,
        treasury: "0x0000000000000000000000000000000000001005"
      }
    ],
    evidence: {
      guestSourceUri: "https://example.test/guest",
      guestSourceSha256: H1,
      guestBuildRecipeUri: "ipfs://bafy-build-recipe",
      guestBuildRecipeSha256: H2,
      genuineReceiptUri: "https://example.test/genuine-receipt",
      genuineReceiptSha256: H3,
      auditReportUri: "ipfs://bafy-audit",
      auditReportSha256: H4,
      pulsechainTestnetReceiptUri: "https://example.test/pulsechain-testnet-receipt",
      pulsechainTestnetReceiptSha256: H5
    }
  };
}

test("strict manifest parser accepts a complete reviewed identity", () => {
  const manifest = parseExactDeploymentManifest(validManifest());
  assert.equal(manifest.chainId, 943);
  assert.equal(manifest.deploymentAnchor.blockNumber, 1234n);
  assert.equal(manifest.verifierConfigs[0].configId, 1n);
  assert.equal(manifest.verifierConfigs[0].protocolFeeBps, 300);
});

test("strict manifest parser rejects extra fields, multiple configs, and fee routing mismatch", () => {
  const extra = validManifest();
  extra.unreviewed = true;
  assert.throws(() => parseExactDeploymentManifest(extra), /fields must be exactly/);

  const multiple = validManifest();
  const configs = multiple.verifierConfigs as Record<string, unknown>[];
  configs.push({ ...configs[0] });
  assert.throws(() => parseExactDeploymentManifest(multiple), /exactly one reviewed configuration/);

  const empty = validManifest();
  empty.verifierConfigs = [];
  assert.throws(() => parseExactDeploymentManifest(empty), /exactly one reviewed configuration/);

  const badTreasury = validManifest();
  (badTreasury.verifierConfigs as Record<string, unknown>[])[0].protocolFeeBps = 0;
  assert.throws(() => parseExactDeploymentManifest(badTreasury), /treasury must be zero/);
});

test("strict manifest parser rejects credential-bearing and overlong evidence URIs", () => {
  const credentialed = validManifest();
  (credentialed.evidence as Record<string, unknown>).guestBuildRecipeUri =
    "https://reviewer:secret@example.test/build-recipe";
  assert.throws(() => parseExactDeploymentManifest(credentialed), /must not contain credentials/);

  const overlong = validManifest();
  (overlong.evidence as Record<string, unknown>).genuineReceiptUri =
    `https://example.test/${"a".repeat(MAX_EXACT_EVIDENCE_URI_LENGTH)}`;
  assert.throws(() => parseExactDeploymentManifest(overlong), /must not exceed 2048 characters/);

  for (const unsafeUri of [
    " https://example.test/source",
    "https://example.test/source?token=public-secret",
    "https://example.test/source#mutable",
    "ipfs://reviewer@bafy-source"
  ]) {
    const unsafe = validManifest();
    (unsafe.evidence as Record<string, unknown>).guestSourceUri = unsafeUri;
    assert.throws(
      () => parseExactDeploymentManifest(unsafe),
      /whitespace|query, fragment|credentials|user information/
    );
  }
});

test("manifest fetch URLs exclude ambiguous or secret-bearing components", () => {
  assert.equal(
    assertSafeManifestFetchUrl("https://example.test/reviewed-manifest.json").href,
    "https://example.test/reviewed-manifest.json"
  );
  assert.equal(
    assertSafeManifestFetchUrl("http://127.0.0.1:4173/reviewed-manifest.json").href,
    "http://127.0.0.1:4173/reviewed-manifest.json"
  );

  for (const unsafe of [
    " https://example.test/manifest.json",
    "https://example.test/manifest json",
    "https://example.test/manifest%20json",
    "https://example.test/manifest%0ajson"
  ]) {
    assert.throws(() => assertSafeManifestFetchUrl(unsafe), /whitespace or control characters/);
  }
  assert.throws(
    () => assertSafeManifestFetchUrl("https://reviewer:secret@example.test/manifest.json"),
    /credentials/
  );
  assert.throws(
    () => assertSafeManifestFetchUrl("https://example.test/manifest.json?token=secret"),
    /query or fragment/
  );
  assert.throws(
    () => assertSafeManifestFetchUrl("https://example.test/manifest.json#reviewed"),
    /query or fragment/
  );
  assert.throws(
    () => assertSafeManifestFetchUrl("http://example.test/manifest.json"),
    /must use HTTPS/
  );
  for (const ambiguous of [
    "https:example.test/manifest.json",
    "https:\\example.test\\manifest.json",
    "https:///example.test/manifest.json"
  ]) {
    assert.throws(() => assertSafeManifestFetchUrl(ambiguous), /explicit forward-slash|authority is required/);
  }
});

test("loader checks raw-byte digest before parsing", async () => {
  const raw = new TextEncoder().encode(JSON.stringify(validManifest()));
  const digest = await sha256Hex(raw);
  let observedInit: RequestInit | undefined;
  const okFetch: typeof fetch = async (_input, init) => {
    observedInit = init;
    return new Response(raw, { status: 200 });
  };
  const loaded = await loadDigestPinnedManifest("https://example.test/manifest.json", digest, okFetch);
  assert.equal(loaded.manifestSha256, digest);
  assert.equal(observedInit?.cache, "no-store");
  assert.equal(observedInit?.credentials, "omit");
  assert.equal(observedInit?.redirect, "error");
  assert.equal(observedInit?.referrerPolicy, "no-referrer");
  assert.ok(observedInit?.signal instanceof AbortSignal);

  await assert.rejects(
    () => loadDigestPinnedManifest("https://example.test/manifest.json", H6, okFetch),
    /digest mismatch/
  );

  let parseFetchCalled = false;
  const invalidFetch: typeof fetch = async () => {
    parseFetchCalled = true;
    return new Response(new TextEncoder().encode("not-json"), { status: 200 });
  };
  await assert.rejects(
    () => loadDigestPinnedManifest("https://example.test/manifest.json", H6, invalidFetch),
    /digest mismatch/
  );
  assert.equal(parseFetchCalled, true);
});

test("local manifest bytes use the same digest-first strict parser without a host", async () => {
  const raw = new TextEncoder().encode(JSON.stringify(validManifest()));
  const digest = await sha256Hex(raw);
  const loaded = await parseDigestPinnedManifestBytes(raw, digest);
  assert.equal(loaded.manifestSha256, digest);
  assert.equal(loaded.manifest.chainId, 943);
  await assert.rejects(() => parseDigestPinnedManifestBytes(raw, H6), /digest mismatch/);
  await assert.rejects(
    () => parseDigestPinnedManifestBytes(new Uint8Array(MAX_EXACT_MANIFEST_BYTES + 1), digest),
    /between 1 and/
  );
});

test("raw manifest parsing rejects literal, escaped-equivalent, and nested duplicate members", async () => {
  const canonical = JSON.stringify(validManifest());
  const duplicateLiteral = canonical.replace(
    '"chainId":943',
    '"chainId":943,"chainId":369'
  );
  const duplicateRoot = canonical.replace(
    '"chainId":943',
    '"chainId":943,"cha\\u0069nId":369'
  );
  const duplicateNested = canonical.replace(
    `"guestSourceSha256":"${H1}"`,
    `"guestSourceSha256":"${H1}","guest\\u0053ourceSha256":"${H2}"`
  );
  const duplicateSurrogate = `{"𝄞":1,"\\uD834\\uDD1E":2,${canonical.slice(1)}`;

  for (const [source, member] of [
    [duplicateLiteral, "chainId"],
    [duplicateRoot, "chainId"],
    [duplicateNested, "guestSourceSha256"],
    [duplicateSurrogate, "𝄞"]
  ]) {
    const raw = new TextEncoder().encode(source);
    const digest = await sha256Hex(raw);
    assert.throws(
      () => parseExactDeploymentManifestBytes(raw),
      new RegExp(`duplicate member name ${JSON.stringify(member)}`, "u")
    );
    await assert.rejects(
      () => parseDigestPinnedManifestBytes(raw, digest),
      new RegExp(`duplicate member name ${JSON.stringify(member)}`, "u")
    );
  }

  const raw = new TextEncoder().encode(duplicateRoot);
  await assert.rejects(
    () => parseDigestPinnedManifestBytes(raw, H6),
    /digest mismatch/
  );
});

test("strict raw scanner rejects malformed JSON and scopes member names per object", () => {
  for (const malformed of [
    '{"schema":true,}',
    '{"schema":"unterminated}',
    '{"schema":01}',
    '{"schema":"bad\\xescape"}',
    '{"schema":true} trailing'
  ]) {
    assert.throws(
      () => parseExactDeploymentManifestBytes(new TextEncoder().encode(malformed)),
      /not strict UTF-8 JSON/
    );
  }

  const parsed = parseExactDeploymentManifestBytes(
    new TextEncoder().encode(JSON.stringify(validManifest()))
  );
  assert.equal(parsed.core.address, "0x0000000000000000000000000000000000001001");
  assert.equal(parsed.exactSettlement.address, "0x0000000000000000000000000000000000001002");
});

test("prepare-exact-manifest rejects duplicate members before writing either artifact", () => {
  const directory = mkdtempSync(join(tmpdir(), "pulsetensor-exact-manifest-"));
  const input = join(directory, "candidate.json");
  const output = join(directory, "manifest.json");
  const receipt = join(directory, "receipt.json");
  const candidate = JSON.stringify(validManifest()).replace(
    `"guestSourceSha256":"${H1}"`,
    `"guestSourceSha256":"${H1}","guest\\u0053ourceSha256":"${H2}"`
  );
  writeFileSync(input, candidate, "utf8");

  try {
    const result = spawnSync(
      process.execPath,
      [
        "--experimental-strip-types",
        fileURLToPath(new URL("../scripts/prepare-exact-manifest.ts", import.meta.url)),
        "--input",
        input,
        "--output",
        output,
        "--receipt",
        receipt
      ],
      { encoding: "utf8" }
    );
    assert.notEqual(result.status, 0, result.stdout);
    assert.match(`${result.stdout}\n${result.stderr}`, /duplicate member name "guestSourceSha256"/);
    assert.equal(existsSync(output), false);
    assert.equal(existsSync(receipt), false);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("published schema mirrors runtime uint64, nonzero, URI, and fee-routing constraints", () => {
  const schema = JSON.parse(
    readFileSync(new URL("../public/exact-inference-manifest.schema.json", import.meta.url), "utf8")
  ) as Record<string, any>;
  const definitions = schema.$defs as Record<string, any>;
  const uint64 = new RegExp(definitions.uint64String.pattern, "u");

  for (const value of [
    "0",
    "1",
    "9999999999999999999",
    "10000000000000000000",
    "18446744073709551614",
    "18446744073709551615"
  ]) {
    assert.equal(uint64.test(value), true, value);
  }
  for (const value of ["", "00", "01", "-1", "18446744073709551616", "99999999999999999999"]) {
    assert.equal(uint64.test(value), false, value);
  }

  const nonzeroAddress = new RegExp(definitions.nonzeroAddress.pattern, "u");
  const nonzeroBytes32 = new RegExp(definitions.nonzeroBytes32.pattern, "u");
  const nonzeroBytes4 = new RegExp(definitions.nonzeroBytes4.pattern, "u");
  assert.equal(nonzeroAddress.test("0x0000000000000000000000000000000000000000"), false);
  assert.equal(nonzeroAddress.test("0x0000000000000000000000000000000000000001"), true);
  assert.equal(nonzeroBytes32.test(`0x${"0".repeat(64)}`), false);
  assert.equal(nonzeroBytes32.test(H1), true);
  assert.equal(nonzeroBytes4.test("0x00000000"), false);
  assert.equal(nonzeroBytes4.test("0x00000001"), true);

  const evidenceUri = new RegExp(definitions.evidenceUri.pattern, "u");
  for (const value of [
    "https://example.test/evidence",
    "https://example.test/%E2%82%AC",
    "ipfs://bafy-evidence/path"
  ]) {
    assert.equal(evidenceUri.test(value), true, value);
  }
  for (const value of [
    "https:///evidence",
    "https://reviewer@example.test/evidence",
    "https://example.test/evidence?token=secret",
    "https://example.test/evidence#mutable",
    "https://example.test/evidence%20space",
    "https://example.test/evidence%0a",
    "https://example.test/evidence%C2%80",
    "https://example.test/evidence%C2%A0",
    "https://example.test/evidence%E2%80%A8",
    "https://example.test/evidence%EF%BB%BF",
    "https://example.test/evidence%zz",
    "https://example.test/evidence\\path"
  ]) {
    assert.equal(evidenceUri.test(value), false, value);
  }

  assert.equal(
    definitions.verifierConfig.properties.configId.$ref,
    "#/$defs/nonzeroUint64String"
  );
  assert.equal(
    definitions.deploymentAnchor.properties.blockNumber.$ref,
    "#/$defs/uint64String"
  );
  const feeRule = definitions.verifierConfig.allOf[0];
  assert.equal(feeRule.if.properties.protocolFeeBps.const, 0);
  assert.equal(
    feeRule.then.properties.treasury.const,
    "0x0000000000000000000000000000000000000000"
  );
  assert.equal(feeRule.else.properties.treasury.$ref, "#/$defs/nonzeroAddress");
});

function oversizedStreamResponse(contentLength?: string, splitAtLimit = false): Response {
  const chunks = splitAtLimit
    ? [new Uint8Array(MAX_EXACT_MANIFEST_BYTES), new Uint8Array([1])]
    : [new Uint8Array(MAX_EXACT_MANIFEST_BYTES + 1)];
  let index = 0;
  const stream = new ReadableStream<Uint8Array>({
    pull(controller) {
      if (index === chunks.length) {
        controller.close();
        return;
      }
      controller.enqueue(chunks[index]);
      index += 1;
    }
  });
  return new Response(stream, {
    status: 200,
    headers: contentLength === undefined ? undefined : { "content-length": contentLength }
  });
}

test("loader enforces the byte ceiling when Content-Length is absent or lies", async () => {
  const missingLengthFetch: typeof fetch = async () => oversizedStreamResponse(undefined, true);
  await assert.rejects(
    () => loadDigestPinnedManifest("https://example.test/manifest.json", H1, missingLengthFetch),
    new RegExp(`exceeds ${MAX_EXACT_MANIFEST_BYTES} bytes`)
  );

  const lyingLengthFetch: typeof fetch = async () => oversizedStreamResponse("1");
  await assert.rejects(
    () => loadDigestPinnedManifest("https://example.test/manifest.json", H1, lyingLengthFetch),
    new RegExp(`exceeds ${MAX_EXACT_MANIFEST_BYTES} bytes`)
  );

  const declaredOversizedFetch: typeof fetch = async () =>
    new Response(new Uint8Array([1]), {
      status: 200,
      headers: { "content-length": (MAX_EXACT_MANIFEST_BYTES + 1).toString() }
    });
  await assert.rejects(
    () => loadDigestPinnedManifest("https://example.test/manifest.json", H1, declaredOversizedFetch),
    new RegExp(`exceeds ${MAX_EXACT_MANIFEST_BYTES} bytes`)
  );
});

test("loader honors caller abort and owns a bounded timeout", async () => {
  let callerFetchSignal: AbortSignal | null = null;
  const callerBlockedFetch: typeof fetch = async (_input, init) => {
    callerFetchSignal = init?.signal ?? null;
    return new Promise<Response>(() => undefined);
  };
  const caller = new AbortController();
  const callerPending = loadDigestPinnedManifest(
    "https://example.test/manifest.json",
    H1,
    callerBlockedFetch,
    { signal: caller.signal, timeoutMs: 1_000 }
  );
  caller.abort(new Error("caller stopped manifest load"));
  await assert.rejects(() => callerPending, /caller stopped manifest load/);
  assert.equal(callerFetchSignal?.aborted, true);

  let timeoutFetchSignal: AbortSignal | null = null;
  const timeoutBlockedFetch: typeof fetch = async (_input, init) => {
    timeoutFetchSignal = init?.signal ?? null;
    return new Promise<Response>(() => undefined);
  };
  await assert.rejects(
    () =>
      loadDigestPinnedManifest("https://example.test/manifest.json", H1, timeoutBlockedFetch, {
        timeoutMs: 20
      }),
    /timed out after 20 ms/
  );
  assert.equal(timeoutFetchSignal?.aborted, true);
});

test("caller abort and timeout remain live while manifest hashing is pending", async () => {
  const raw = new TextEncoder().encode(JSON.stringify(validManifest()));
  const digest = await sha256Hex(raw);
  const subtle = crypto.subtle;
  const ownDigestDescriptor = Object.getOwnPropertyDescriptor(subtle, "digest");
  let digestStartedResolve: (() => void) | undefined;
  const digestStarted = new Promise<void>((resolve) => {
    digestStartedResolve = resolve;
  });
  Object.defineProperty(subtle, "digest", {
    configurable: true,
    value: () => {
      digestStartedResolve?.();
      return new Promise<ArrayBuffer>(() => undefined);
    }
  });

  try {
    const fetcher: typeof fetch = async () => new Response(raw, { status: 200 });
    const caller = new AbortController();
    const callerPending = loadDigestPinnedManifest(
      "https://example.test/manifest.json",
      digest,
      fetcher,
      { signal: caller.signal, timeoutMs: 1_000 }
    );
    await digestStarted;
    caller.abort(new Error("caller stopped manifest digest"));
    await assert.rejects(() => callerPending, /caller stopped manifest digest/);

    await assert.rejects(
      () =>
        loadDigestPinnedManifest("https://example.test/manifest.json", digest, fetcher, {
          timeoutMs: 20
        }),
      /timed out after 20 ms/
    );
  } finally {
    if (ownDigestDescriptor) Object.defineProperty(subtle, "digest", ownDigestDescriptor);
    else Reflect.deleteProperty(subtle, "digest");
  }
});

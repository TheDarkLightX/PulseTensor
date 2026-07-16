import { getAddress, isAddress, type Address, type Hex } from "viem";
import { bytesToHex } from "./artifact.ts";

export const EXACT_MANIFEST_SCHEMA = "pulsetensor/exact-inference-deployment-manifest/v1";
export const MAX_EXACT_MANIFEST_BYTES = 262_144;
export const MAX_EXACT_EVIDENCE_URI_LENGTH = 2_048;
export const DEFAULT_EXACT_MANIFEST_TIMEOUT_MS = 15_000;
const MAX_PLATFORM_TIMEOUT_MS = 2_147_483_647;

export type ExactManifestLoadOptions = {
  signal?: AbortSignal;
  timeoutMs?: number;
};

export type ExactManifestEvidence = {
  guestSourceUri: string;
  guestSourceSha256: Hex;
  guestBuildRecipeUri: string;
  guestBuildRecipeSha256: Hex;
  genuineReceiptUri: string;
  genuineReceiptSha256: Hex;
  auditReportUri: string;
  auditReportSha256: Hex;
  pulsechainTestnetReceiptUri: string;
  pulsechainTestnetReceiptSha256: Hex;
};

export type ExactManifestVerifierConfig = {
  netuid: number;
  configId: bigint;
  adapter: Address;
  adapterRuntimeCodeHash: Hex;
  baseVerifier: Address;
  verifierRuntimeCodeHash: Hex;
  programId: Hex;
  relationId: Hex;
  proofSystemId: Hex;
  proofSelector: Hex;
  verifierVersionHash: Hex;
  proofBytes: number;
  protocolFeeBps: number;
  treasury: Address;
};

export type ExactDeploymentManifest = {
  schema: typeof EXACT_MANIFEST_SCHEMA;
  chainId: number;
  sourceCommit: string;
  deploymentAnchor: { blockNumber: bigint; blockHash: Hex; minimumConfirmations: number };
  core: { address: Address; runtimeCodeHash: Hex };
  exactSettlement: { address: Address; runtimeCodeHash: Hex };
  verifierConfigs: ExactManifestVerifierConfig[];
  evidence: ExactManifestEvidence;
};

type JsonObject = Record<string, unknown>;

const bytes32Pattern = /^0x[0-9a-fA-F]{64}$/;
const bytes4Pattern = /^0x[0-9a-fA-F]{8}$/;
const commitPattern = /^[0-9a-f]{40}$/;
const uintPattern = /^(0|[1-9][0-9]*)$/;
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const ZERO_HEX_PATTERN = /^0x0+$/;
const MAX_JSON_NESTING_DEPTH = 256;

class DuplicateJsonMemberError extends Error {}

class StrictJsonScanner {
  private index = 0;
  private readonly source: string;

  constructor(source: string) {
    this.source = source;
  }

  scan(): void {
    this.skipWhitespace();
    this.scanValue(0);
    this.skipWhitespace();
    if (this.index !== this.source.length) this.syntaxError();
  }

  private scanValue(depth: number): void {
    if (depth > MAX_JSON_NESTING_DEPTH) this.syntaxError();
    const token = this.source[this.index];
    if (token === "{") {
      this.scanObject(depth);
    } else if (token === "[") {
      this.scanArray(depth);
    } else if (token === '"') {
      this.scanString(false);
    } else if (token === "t") {
      this.scanLiteral("true");
    } else if (token === "f") {
      this.scanLiteral("false");
    } else if (token === "n") {
      this.scanLiteral("null");
    } else if (token === "-" || this.isDigit(token)) {
      this.scanNumber();
    } else {
      this.syntaxError();
    }
  }

  private scanObject(depth: number): void {
    this.index += 1;
    this.skipWhitespace();
    const members = new Set<string>();
    if (this.source[this.index] === "}") {
      this.index += 1;
      return;
    }

    while (true) {
      if (this.source[this.index] !== '"') this.syntaxError();
      const member = this.scanString(true);
      if (members.has(member)) {
        throw new DuplicateJsonMemberError(`Manifest JSON contains duplicate member name ${JSON.stringify(member)}`);
      }
      members.add(member);
      this.skipWhitespace();
      if (this.source[this.index] !== ":") this.syntaxError();
      this.index += 1;
      this.skipWhitespace();
      this.scanValue(depth + 1);
      this.skipWhitespace();
      if (this.source[this.index] === "}") {
        this.index += 1;
        return;
      }
      if (this.source[this.index] !== ",") this.syntaxError();
      this.index += 1;
      this.skipWhitespace();
    }
  }

  private scanArray(depth: number): void {
    this.index += 1;
    this.skipWhitespace();
    if (this.source[this.index] === "]") {
      this.index += 1;
      return;
    }

    while (true) {
      this.scanValue(depth + 1);
      this.skipWhitespace();
      if (this.source[this.index] === "]") {
        this.index += 1;
        return;
      }
      if (this.source[this.index] !== ",") this.syntaxError();
      this.index += 1;
      this.skipWhitespace();
    }
  }

  private scanString(decode: boolean): string {
    let decoded = "";
    this.index += 1;
    while (this.index < this.source.length) {
      const token = this.source[this.index];
      if (token === '"') {
        this.index += 1;
        return decoded;
      }
      if (token === "\\") {
        this.index += 1;
        const escape = this.source[this.index];
        if (escape === "u") {
          let codeUnit = "";
          for (let offset = 1; offset <= 4; offset += 1) {
            const digit = this.source[this.index + offset] ?? "";
            if (!/[0-9a-fA-F]/u.test(digit)) this.syntaxError();
            codeUnit += digit;
          }
          if (decode) decoded += String.fromCharCode(Number.parseInt(codeUnit, 16));
          this.index += 5;
          continue;
        }
        if (!escape || !'"\\/bfnrt'.includes(escape)) this.syntaxError();
        if (decode) {
          const simpleEscapes: Record<string, string> = {
            '"': '"',
            "\\": "\\",
            "/": "/",
            b: "\b",
            f: "\f",
            n: "\n",
            r: "\r",
            t: "\t"
          };
          decoded += simpleEscapes[escape];
        }
        this.index += 1;
        continue;
      }
      if (token.charCodeAt(0) < 0x20) this.syntaxError();
      if (decode) decoded += token;
      this.index += 1;
    }
    this.syntaxError();
  }

  private scanNumber(): void {
    if (this.source[this.index] === "-") this.index += 1;
    if (this.source[this.index] === "0") {
      this.index += 1;
    } else {
      if (!this.isNonzeroDigit(this.source[this.index])) this.syntaxError();
      while (this.isDigit(this.source[this.index])) this.index += 1;
    }
    if (this.source[this.index] === ".") {
      this.index += 1;
      if (!this.isDigit(this.source[this.index])) this.syntaxError();
      while (this.isDigit(this.source[this.index])) this.index += 1;
    }
    if (this.source[this.index] === "e" || this.source[this.index] === "E") {
      this.index += 1;
      if (this.source[this.index] === "+" || this.source[this.index] === "-") this.index += 1;
      if (!this.isDigit(this.source[this.index])) this.syntaxError();
      while (this.isDigit(this.source[this.index])) this.index += 1;
    }
  }

  private scanLiteral(literal: "true" | "false" | "null"): void {
    if (!this.source.startsWith(literal, this.index)) this.syntaxError();
    this.index += literal.length;
  }

  private skipWhitespace(): void {
    while (
      this.source[this.index] === " " ||
      this.source[this.index] === "\t" ||
      this.source[this.index] === "\n" ||
      this.source[this.index] === "\r"
    ) {
      this.index += 1;
    }
  }

  private isDigit(value: string | undefined): boolean {
    return value !== undefined && value >= "0" && value <= "9";
  }

  private isNonzeroDigit(value: string | undefined): boolean {
    return value !== undefined && value >= "1" && value <= "9";
  }

  private syntaxError(): never {
    throw new SyntaxError(`Invalid JSON token at character ${this.index}`);
  }
}

function parseStrictJsonBytes(input: Uint8Array): unknown {
  let source: string;
  try {
    source = new TextDecoder("utf-8", { fatal: true }).decode(input);
  } catch {
    throw new Error("Manifest is not strict UTF-8 JSON");
  }

  try {
    new StrictJsonScanner(source).scan();
    return JSON.parse(source) as unknown;
  } catch (error) {
    if (error instanceof DuplicateJsonMemberError) throw error;
    throw new Error("Manifest is not strict UTF-8 JSON");
  }
}

function objectAt(value: unknown, path: string): JsonObject {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error(`${path} must be an object`);
  }
  return value as JsonObject;
}

function exactKeys(value: JsonObject, expected: readonly string[], path: string): void {
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  if (actual.length !== wanted.length || actual.some((key, index) => key !== wanted[index])) {
    throw new Error(`${path} fields must be exactly: ${wanted.join(", ")}`);
  }
}

function stringAt(value: JsonObject, key: string, path: string): string {
  const result = value[key];
  if (typeof result !== "string" || result.length === 0) throw new Error(`${path}.${key} must be a string`);
  return result;
}

function safeIntegerAt(value: JsonObject, key: string, minimum: number, maximum: number, path: string): number {
  const result = value[key];
  if (!Number.isSafeInteger(result) || (result as number) < minimum || (result as number) > maximum) {
    throw new Error(`${path}.${key} must be an integer between ${minimum} and ${maximum}`);
  }
  return result as number;
}

function addressAt(value: JsonObject, key: string, path: string, allowZero = false): Address {
  const raw = stringAt(value, key, path);
  if (!isAddress(raw)) throw new Error(`${path}.${key} must be an EVM address`);
  const normalized = getAddress(raw);
  if (!allowZero && normalized.toLowerCase() === ZERO_ADDRESS) {
    throw new Error(`${path}.${key} cannot be the zero address`);
  }
  return normalized;
}

function hexAt(value: JsonObject, key: string, pattern: RegExp, label: string, path: string): Hex {
  const raw = stringAt(value, key, path);
  if (!pattern.test(raw)) throw new Error(`${path}.${key} must be ${label}`);
  const normalized = raw.toLowerCase();
  if (ZERO_HEX_PATTERN.test(normalized)) throw new Error(`${path}.${key} cannot be zero`);
  return normalized as Hex;
}

function uriAt(value: JsonObject, key: string, path: string): string {
  const raw = stringAt(value, key, path);
  if (raw.length > MAX_EXACT_EVIDENCE_URI_LENGTH) {
    throw new Error(`${path}.${key} must not exceed ${MAX_EXACT_EVIDENCE_URI_LENGTH} characters`);
  }
  if (/[\s\u0000-\u001f\u007f-\u009f]/u.test(raw)) {
    throw new Error(`${path}.${key} must not contain whitespace or control characters`);
  }
  try {
    if (/[\s\u0000-\u001f\u007f-\u009f]/u.test(decodeURIComponent(raw))) {
      throw new Error(`${path}.${key} must not contain encoded whitespace or control characters`);
    }
  } catch (error) {
    if (error instanceof URIError) throw new Error(`${path}.${key} contains invalid percent encoding`);
    throw error;
  }
  if (/[?#\\]/u.test(raw)) {
    throw new Error(`${path}.${key} must not contain a query, fragment, or backslash`);
  }
  if (!/^https:\/\//u.test(raw) && !/^ipfs:\/\//u.test(raw)) {
    throw new Error(`${path}.${key} must use an explicit https:// or ipfs:// form`);
  }
  const authority = raw.slice(raw.indexOf("://") + 3).split("/", 1)[0];
  if (authority.length === 0) throw new Error(`${path}.${key} authority is required`);
  let parsed: URL;
  try {
    parsed = new URL(raw);
  } catch {
    throw new Error(`${path}.${key} must be an absolute URI`);
  }
  if (parsed.protocol !== "https:" && parsed.protocol !== "ipfs:") {
    throw new Error(`${path}.${key} must use https:// or ipfs://`);
  }
  if (parsed.username || parsed.password) {
    throw new Error(`${path}.${key} must not contain credentials`);
  }
  if (/^[a-z][a-z0-9+.-]*:\/\/[^/]*@/iu.test(raw)) {
    throw new Error(`${path}.${key} must not contain user information`);
  }
  return raw;
}

function parseCodeIdentity(value: unknown, path: string): { address: Address; runtimeCodeHash: Hex } {
  const object = objectAt(value, path);
  exactKeys(object, ["address", "runtimeCodeHash"], path);
  return {
    address: addressAt(object, "address", path),
    runtimeCodeHash: hexAt(object, "runtimeCodeHash", bytes32Pattern, "bytes32 hex", path)
  };
}

function parseDeploymentAnchor(
  value: unknown
): { blockNumber: bigint; blockHash: Hex; minimumConfirmations: number } {
  const path = "manifest.deploymentAnchor";
  const object = objectAt(value, path);
  exactKeys(object, ["blockNumber", "blockHash", "minimumConfirmations"], path);
  const blockNumberRaw = stringAt(object, "blockNumber", path);
  if (!uintPattern.test(blockNumberRaw)) {
    throw new Error(`${path}.blockNumber must be a canonical decimal uint64 string`);
  }
  const blockNumber = BigInt(blockNumberRaw);
  if (blockNumber > (1n << 64n) - 1n) throw new Error(`${path}.blockNumber is outside uint64`);
  return {
    blockNumber,
    blockHash: hexAt(object, "blockHash", bytes32Pattern, "bytes32 hex", path),
    minimumConfirmations: safeIntegerAt(object, "minimumConfirmations", 1, 100_000, path)
  };
}

function parseEvidence(value: unknown): ExactManifestEvidence {
  const path = "manifest.evidence";
  const object = objectAt(value, path);
  exactKeys(
    object,
    [
      "guestSourceUri",
      "guestSourceSha256",
      "guestBuildRecipeUri",
      "guestBuildRecipeSha256",
      "genuineReceiptUri",
      "genuineReceiptSha256",
      "auditReportUri",
      "auditReportSha256",
      "pulsechainTestnetReceiptUri",
      "pulsechainTestnetReceiptSha256"
    ],
    path
  );
  return {
    guestSourceUri: uriAt(object, "guestSourceUri", path),
    guestSourceSha256: hexAt(object, "guestSourceSha256", bytes32Pattern, "bytes32 hex", path),
    guestBuildRecipeUri: uriAt(object, "guestBuildRecipeUri", path),
    guestBuildRecipeSha256: hexAt(object, "guestBuildRecipeSha256", bytes32Pattern, "bytes32 hex", path),
    genuineReceiptUri: uriAt(object, "genuineReceiptUri", path),
    genuineReceiptSha256: hexAt(object, "genuineReceiptSha256", bytes32Pattern, "bytes32 hex", path),
    auditReportUri: uriAt(object, "auditReportUri", path),
    auditReportSha256: hexAt(object, "auditReportSha256", bytes32Pattern, "bytes32 hex", path),
    pulsechainTestnetReceiptUri: uriAt(object, "pulsechainTestnetReceiptUri", path),
    pulsechainTestnetReceiptSha256: hexAt(
      object,
      "pulsechainTestnetReceiptSha256",
      bytes32Pattern,
      "bytes32 hex",
      path
    )
  };
}

function parseVerifierConfig(value: unknown, index: number): ExactManifestVerifierConfig {
  const path = `manifest.verifierConfigs[${index}]`;
  const object = objectAt(value, path);
  exactKeys(
    object,
    [
      "netuid",
      "configId",
      "adapter",
      "adapterRuntimeCodeHash",
      "baseVerifier",
      "verifierRuntimeCodeHash",
      "programId",
      "relationId",
      "proofSystemId",
      "proofSelector",
      "verifierVersionHash",
      "proofBytes",
      "protocolFeeBps",
      "treasury"
    ],
    path
  );

  const configIdRaw = stringAt(object, "configId", path);
  if (!uintPattern.test(configIdRaw)) throw new Error(`${path}.configId must be a canonical decimal uint64 string`);
  const configId = BigInt(configIdRaw);
  if (configId === 0n || configId > (1n << 64n) - 1n) throw new Error(`${path}.configId is outside uint64`);

  const protocolFeeBps = safeIntegerAt(object, "protocolFeeBps", 0, 3_000, path);
  const treasury = addressAt(object, "treasury", path, protocolFeeBps === 0);
  if ((protocolFeeBps === 0) !== (treasury.toLowerCase() === ZERO_ADDRESS)) {
    throw new Error(`${path}.treasury must be zero exactly when protocolFeeBps is zero`);
  }

  return {
    netuid: safeIntegerAt(object, "netuid", 0, 65_535, path),
    configId,
    adapter: addressAt(object, "adapter", path),
    adapterRuntimeCodeHash: hexAt(object, "adapterRuntimeCodeHash", bytes32Pattern, "bytes32 hex", path),
    baseVerifier: addressAt(object, "baseVerifier", path),
    verifierRuntimeCodeHash: hexAt(object, "verifierRuntimeCodeHash", bytes32Pattern, "bytes32 hex", path),
    programId: hexAt(object, "programId", bytes32Pattern, "bytes32 hex", path),
    relationId: hexAt(object, "relationId", bytes32Pattern, "bytes32 hex", path),
    proofSystemId: hexAt(object, "proofSystemId", bytes32Pattern, "bytes32 hex", path),
    proofSelector: hexAt(object, "proofSelector", bytes4Pattern, "bytes4 hex", path),
    verifierVersionHash: hexAt(object, "verifierVersionHash", bytes32Pattern, "bytes32 hex", path),
    proofBytes: safeIntegerAt(object, "proofBytes", 4, 16_384, path),
    protocolFeeBps,
    treasury
  };
}

export function parseExactDeploymentManifest(value: unknown): ExactDeploymentManifest {
  const path = "manifest";
  const object = objectAt(value, path);
  exactKeys(
    object,
    [
      "schema",
      "chainId",
      "sourceCommit",
      "deploymentAnchor",
      "core",
      "exactSettlement",
      "verifierConfigs",
      "evidence"
    ],
    path
  );

  const schema = stringAt(object, "schema", path);
  if (schema !== EXACT_MANIFEST_SCHEMA) throw new Error(`Unsupported exact deployment manifest schema: ${schema}`);
  const sourceCommit = stringAt(object, "sourceCommit", path);
  if (!commitPattern.test(sourceCommit)) throw new Error("manifest.sourceCommit must be a lowercase 40-character Git SHA");

  if (!Array.isArray(object.verifierConfigs) || object.verifierConfigs.length !== 1) {
    throw new Error("manifest.verifierConfigs must contain exactly one reviewed configuration");
  }
  const verifierConfigs = object.verifierConfigs.map(parseVerifierConfig);

  return {
    schema: EXACT_MANIFEST_SCHEMA,
    chainId: safeIntegerAt(object, "chainId", 1, Number.MAX_SAFE_INTEGER, path),
    sourceCommit,
    deploymentAnchor: parseDeploymentAnchor(object.deploymentAnchor),
    core: parseCodeIdentity(object.core, "manifest.core"),
    exactSettlement: parseCodeIdentity(object.exactSettlement, "manifest.exactSettlement"),
    verifierConfigs,
    evidence: parseEvidence(object.evidence)
  };
}

export function normalizeSha256(raw: string): Hex {
  const normalized = raw.trim().toLowerCase();
  const withPrefix = normalized.startsWith("0x") ? normalized : `0x${normalized}`;
  if (!bytes32Pattern.test(withPrefix)) throw new Error("Expected manifest SHA-256 must be 32-byte hex");
  return withPrefix as Hex;
}

export function assertSafeManifestFetchUrl(raw: string): URL {
  if (typeof raw !== "string" || raw.length === 0) throw new Error("Manifest URL is required");
  if (/[\s\u0000-\u001f\u007f-\u009f]/u.test(raw)) {
    throw new Error("Manifest URL must not contain whitespace or control characters");
  }
  try {
    if (/[\s\u0000-\u001f\u007f-\u009f]/u.test(decodeURIComponent(raw))) {
      throw new Error("Manifest URL must not contain encoded whitespace or control characters");
    }
  } catch (error) {
    if (error instanceof URIError) throw new Error("Manifest URL contains invalid percent encoding");
    throw error;
  }
  if (/[?#]/u.test(raw)) throw new Error("Manifest URL must not contain a query or fragment");
  if (/\\/u.test(raw) || (!/^https:\/\//iu.test(raw) && !/^http:\/\//iu.test(raw))) {
    throw new Error("Manifest URL must use an explicit forward-slash HTTP(S) form");
  }
  const authority = raw.slice(raw.indexOf("://") + 3).split("/", 1)[0];
  if (authority.length === 0) throw new Error("Manifest URL authority is required");

  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    throw new Error("Manifest URL must be absolute");
  }
  const localhost = url.hostname === "127.0.0.1" || url.hostname === "localhost" || url.hostname === "[::1]";
  if (url.protocol !== "https:" && !(url.protocol === "http:" && localhost)) {
    throw new Error("Manifest URL must use HTTPS (HTTP is allowed only for localhost)");
  }
  if (url.username || url.password) throw new Error("Manifest URL must not contain credentials");
  if (/^[a-z][a-z0-9+.-]*:\/\/[^/]*@/iu.test(raw)) {
    throw new Error("Manifest URL must not contain user information");
  }
  return url;
}

export async function sha256Hex(bytes: Uint8Array): Promise<Hex> {
  const input = new ArrayBuffer(bytes.byteLength);
  new Uint8Array(input).set(bytes);
  return bytesToHex(new Uint8Array(await crypto.subtle.digest("SHA-256", input)));
}

export function parseExactDeploymentManifestBytes(input: Uint8Array): ExactDeploymentManifest {
  if (input.byteLength === 0 || input.byteLength > MAX_EXACT_MANIFEST_BYTES) {
    throw new Error(`Manifest must be between 1 and ${MAX_EXACT_MANIFEST_BYTES} bytes`);
  }
  return parseExactDeploymentManifest(parseStrictJsonBytes(input));
}

export async function parseDigestPinnedManifestBytes(
  input: Uint8Array,
  rawExpectedSha256: string
): Promise<{ manifest: ExactDeploymentManifest; manifestSha256: Hex; rawBytes: Uint8Array }> {
  if (input.byteLength === 0 || input.byteLength > MAX_EXACT_MANIFEST_BYTES) {
    throw new Error(`Manifest must be between 1 and ${MAX_EXACT_MANIFEST_BYTES} bytes`);
  }
  const rawBytes = input.slice();
  const expectedSha256 = normalizeSha256(rawExpectedSha256);
  const manifestSha256 = await sha256Hex(rawBytes);
  if (manifestSha256 !== expectedSha256) {
    throw new Error(`Manifest digest mismatch: expected ${expectedSha256}, received ${manifestSha256}`);
  }
  return { manifest: parseExactDeploymentManifestBytes(rawBytes), manifestSha256, rawBytes };
}

function abortReason(signal: AbortSignal): Error {
  if (signal.reason instanceof Error) return signal.reason;
  return new DOMException("Manifest load aborted", "AbortError");
}

function throwIfAborted(signal: AbortSignal): void {
  if (signal.aborted) throw abortReason(signal);
}

async function abortable<T>(operation: Promise<T>, signal: AbortSignal): Promise<T> {
  throwIfAborted(signal);
  return new Promise<T>((resolve, reject) => {
    const onAbort = () => reject(abortReason(signal));
    signal.addEventListener("abort", onAbort, { once: true });
    operation.then(
      (value) => {
        signal.removeEventListener("abort", onAbort);
        resolve(value);
      },
      (error: unknown) => {
        signal.removeEventListener("abort", onAbort);
        reject(error);
      }
    );
  });
}

function assertBoundedContentLength(response: Response): void {
  const contentLength = response.headers.get("content-length");
  if (contentLength === null) return;
  if (!/^(0|[1-9][0-9]*)$/u.test(contentLength)) {
    throw new Error("Manifest Content-Length must be a canonical non-negative integer");
  }
  const maximum = MAX_EXACT_MANIFEST_BYTES.toString();
  if (contentLength.length > maximum.length || (contentLength.length === maximum.length && contentLength > maximum)) {
    throw new Error(`Manifest exceeds ${MAX_EXACT_MANIFEST_BYTES} bytes`);
  }
}

async function readBoundedManifestBody(response: Response, signal: AbortSignal): Promise<Uint8Array> {
  try {
    assertBoundedContentLength(response);
  } catch (error) {
    void response.body?.cancel(error).catch(() => undefined);
    throw error;
  }
  if (!response.body) throw new Error(`Manifest must be between 1 and ${MAX_EXACT_MANIFEST_BYTES} bytes`);

  const reader = response.body.getReader();
  const bounded = new Uint8Array(MAX_EXACT_MANIFEST_BYTES);
  let byteLength = 0;
  try {
    while (true) {
      const result = await abortable(reader.read(), signal);
      if (result.done) break;
      const chunk = result.value;
      if (chunk.byteLength > MAX_EXACT_MANIFEST_BYTES - byteLength) {
        void reader.cancel("Manifest byte limit exceeded").catch(() => undefined);
        throw new Error(`Manifest exceeds ${MAX_EXACT_MANIFEST_BYTES} bytes`);
      }
      bounded.set(chunk, byteLength);
      byteLength += chunk.byteLength;
    }
  } catch (error) {
    void reader.cancel(error).catch(() => undefined);
    throw error;
  } finally {
    try {
      reader.releaseLock();
    } catch {
      // An abort can leave a pending read until the underlying source observes cancellation.
    }
  }

  if (byteLength === 0) throw new Error(`Manifest must be between 1 and ${MAX_EXACT_MANIFEST_BYTES} bytes`);
  return bounded.slice(0, byteLength);
}

export async function loadDigestPinnedManifest(
  rawUrl: string,
  rawExpectedSha256: string,
  fetcher: typeof fetch = fetch,
  options: ExactManifestLoadOptions = {}
): Promise<{ manifest: ExactDeploymentManifest; manifestSha256: Hex; rawBytes: Uint8Array }> {
  const url = assertSafeManifestFetchUrl(rawUrl);
  const expectedSha256 = normalizeSha256(rawExpectedSha256);
  const timeoutMs = options.timeoutMs ?? DEFAULT_EXACT_MANIFEST_TIMEOUT_MS;
  if (!Number.isSafeInteger(timeoutMs) || timeoutMs <= 0 || timeoutMs > MAX_PLATFORM_TIMEOUT_MS) {
    throw new Error(`Manifest timeout must be an integer between 1 and ${MAX_PLATFORM_TIMEOUT_MS} milliseconds`);
  }

  const controller = new AbortController();
  let timedOut = false;
  const forwardAbort = () => controller.abort(options.signal?.reason);
  if (options.signal?.aborted) forwardAbort();
  else options.signal?.addEventListener("abort", forwardAbort, { once: true });
  const timeout = setTimeout(() => {
    timedOut = true;
    controller.abort(new DOMException("Manifest fetch timed out", "TimeoutError"));
  }, timeoutMs);

  try {
    const response = await abortable(
      fetcher(url, {
        cache: "no-store",
        credentials: "omit",
        redirect: "error",
        referrerPolicy: "no-referrer",
        signal: controller.signal
      }),
      controller.signal
    );
    if (!response.ok) {
      void response.body?.cancel(`Manifest fetch failed with HTTP ${response.status}`).catch(() => undefined);
      throw new Error(`Manifest fetch failed with HTTP ${response.status}`);
    }

    const rawBytes = await readBoundedManifestBody(response, controller.signal);
    throwIfAborted(controller.signal);
    const result = await abortable(
      parseDigestPinnedManifestBytes(rawBytes, expectedSha256),
      controller.signal
    );
    throwIfAborted(controller.signal);
    return result;
  } catch (error) {
    if (timedOut) throw new Error(`Manifest fetch timed out after ${timeoutMs} ms`);
    throw error;
  } finally {
    clearTimeout(timeout);
    options.signal?.removeEventListener("abort", forwardAbort);
  }
}

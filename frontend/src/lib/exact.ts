import {
  encodeAbiParameters,
  getAddress,
  isAddress,
  keccak256,
  sha256,
  stringToHex,
  type Address,
  type Hex
} from "viem";

export const EXACT_DOMAIN_VERSION = 1;
export const EXACT_MAX_MECHANISM_ID = 1_023n;
export const EXACT_MAX_PROTOCOL_FEE_BPS = 3_000n;
export const EXACT_MAX_PROOF_BYTES = 16_384;
export const EXACT_PUBLIC_VALUES_BYTES = 23 * 32;

export const INT64_MIN = -(1n << 63n);
export const INT64_MAX = (1n << 63n) - 1n;
export const UINT64_MAX = (1n << 64n) - 1n;
export const UINT256_MAX = (1n << 256n) - 1n;

export const EXACT_PUBLIC_VALUES_DOMAIN = keccak256(stringToHex("PULSETENSOR_EXACT_PUBLIC_VALUES_V1"));
export const EXACT_OUTPUT_DOMAIN = keccak256(stringToHex("PULSETENSOR_EXACT_OUTPUT_V1"));

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const ZERO_BYTES32 = `0x${"00".repeat(32)}`;
const canonicalSignedDecimal = /^(0|-?[1-9][0-9]*)$/;
const canonicalUnsignedDecimal = /^(0|[1-9][0-9]*)$/;
const bytes32Pattern = /^0x[0-9a-fA-F]{64}$/;
const proofPattern = /^0x(?:[0-9a-fA-F]{2})+$/;
const selectorPattern = /^0x[0-9a-fA-F]{8}$/;

export type ExactScores = readonly [bigint, bigint, bigint, bigint];

export type ExactInferencePublicValuesInput = {
  chainId: bigint;
  settlement: Address;
  taskId: bigint;
  taskSpecHash: Hex;
  netuid: bigint;
  mechid: bigint;
  verifierConfigId: bigint;
  relationId: Hex;
  requestNullifier: Hex;
  inputCommitment: Hex;
  modelCommitment: Hex;
  protocolFeeBps: bigint;
  treasury: Address;
  classIndex: bigint;
  scores: ExactScores;
  provider: Address;
  beneficiary: Address;
};

export type ExactProofParseOptions = {
  expectedByteLength?: number;
  expectedSelector?: Hex;
  label?: string;
};

function requireString(raw: string, label: string): string {
  if (typeof raw !== "string" || raw.length === 0) throw new Error(`${label} is required`);
  if (raw !== raw.trim()) throw new Error(`${label} must not contain surrounding whitespace`);
  return raw;
}

function requireBigInt(value: bigint, label: string): bigint {
  if (typeof value !== "bigint") throw new Error(`${label} must be a bigint`);
  return value;
}

function requireUint(value: bigint, bits: number, label: string): bigint {
  requireBigInt(value, label);
  if (!Number.isInteger(bits) || bits < 1 || bits > 256) throw new Error("Unsigned integer width is invalid");
  const maximum = (1n << BigInt(bits)) - 1n;
  if (value < 0n || value > maximum) throw new Error(`${label} is outside uint${bits}`);
  return value;
}

function requireInt64(value: bigint, label: string): bigint {
  requireBigInt(value, label);
  if (value < INT64_MIN || value > INT64_MAX) throw new Error(`${label} is outside int64`);
  return value;
}

export function parseExactBigInt(raw: string, label = "Value"): bigint {
  const value = requireString(raw, label);
  if (!canonicalSignedDecimal.test(value)) throw new Error(`${label} must be a canonical decimal integer`);
  return BigInt(value);
}

export function parseExactUint(raw: string, bits: number, label = "Value"): bigint {
  const value = requireString(raw, label);
  if (!canonicalUnsignedDecimal.test(value)) {
    throw new Error(`${label} must be a canonical unsigned decimal integer`);
  }
  return requireUint(BigInt(value), bits, label);
}

export function parseExactInt64(raw: string, label = "Score"): bigint {
  return requireInt64(parseExactBigInt(raw, label), label);
}

export function parseExactScores(raw: readonly string[], label = "Scores"): ExactScores {
  if (!Array.isArray(raw) || raw.length !== 4) throw new Error(`${label} must contain exactly four int64 values`);
  return [
    parseExactInt64(raw[0], `${label}[0]`),
    parseExactInt64(raw[1], `${label}[1]`),
    parseExactInt64(raw[2], `${label}[2]`),
    parseExactInt64(raw[3], `${label}[3]`)
  ];
}

export function parseExactClassIndex(raw: string, label = "Class index"): bigint {
  const value = parseExactUint(raw, 8, label);
  if (value >= 4n) throw new Error(`${label} must be between 0 and 3`);
  return value;
}

export function parseExactAddress(raw: string, label = "Address", allowZero = false): Address {
  const value = requireString(raw, label);
  if (!isAddress(value)) throw new Error(`${label} must be a valid EVM address`);
  const normalized = getAddress(value);
  if (!allowZero && normalized.toLowerCase() === ZERO_ADDRESS) throw new Error(`${label} cannot be the zero address`);
  return normalized;
}

export function parseExactBytes32(raw: string, label = "Commitment", allowZero = true): Hex {
  const value = requireString(raw, label);
  if (!bytes32Pattern.test(value)) throw new Error(`${label} must be exactly 32 bytes of hex`);
  const normalized = value.toLowerCase() as Hex;
  if (!allowZero && normalized === ZERO_BYTES32) throw new Error(`${label} cannot be zero`);
  return normalized;
}

export function parseExactProof(raw: string, options: ExactProofParseOptions = {}): Hex {
  const label = options.label ?? "Proof";
  const value = requireString(raw, label);
  if (!proofPattern.test(value)) throw new Error(`${label} must be a complete even-length hex byte string`);

  const byteLength = (value.length - 2) / 2;
  if (byteLength < 4 || byteLength > EXACT_MAX_PROOF_BYTES) {
    throw new Error(`${label} must contain between 4 and ${EXACT_MAX_PROOF_BYTES} bytes`);
  }
  if (options.expectedByteLength !== undefined) {
    if (
      !Number.isSafeInteger(options.expectedByteLength)
      || options.expectedByteLength < 4
      || options.expectedByteLength > EXACT_MAX_PROOF_BYTES
    ) {
      throw new Error(`Expected proof byte length must be between 4 and ${EXACT_MAX_PROOF_BYTES}`);
    }
    if (byteLength !== options.expectedByteLength) {
      throw new Error(`${label} must contain exactly ${options.expectedByteLength} bytes`);
    }
  }

  const normalized = value.toLowerCase() as Hex;
  if (options.expectedSelector !== undefined) {
    if (!selectorPattern.test(options.expectedSelector)) {
      throw new Error("Expected proof selector must be exactly 4 bytes of hex");
    }
    if (normalized.slice(0, 10) !== options.expectedSelector.toLowerCase()) {
      throw new Error(`${label} selector does not match the reviewed verifier configuration`);
    }
  }
  return normalized;
}

export function parseUint16Strict(raw: string, label = "Value"): number {
  return Number(parseExactUint(raw, 16, label));
}

export function parseUint64Strict(raw: string, label = "Value"): bigint {
  return parseExactUint(raw, 64, label);
}

export function parseUint256Strict(raw: string, label = "Value"): bigint {
  return parseExactUint(raw, 256, label);
}

export function parseInt64Strict(raw: string, label = "Score"): bigint {
  return parseExactInt64(raw, label);
}

export function parseAddressStrict(raw: string, label = "Address", allowZero = false): Address {
  return parseExactAddress(raw, label, allowZero);
}

export function parseBytes32Strict(raw: string, label = "Commitment", allowZero = true): Hex {
  return parseExactBytes32(raw, label, allowZero);
}

export function parseProofHex(raw: string, options: ExactProofParseOptions = {}): Hex {
  return parseExactProof(raw, options);
}

export function exactTaskStatusLabel(status: number | bigint): string {
  let normalized: bigint;
  if (typeof status === "bigint") {
    normalized = status;
  } else {
    if (!Number.isSafeInteger(status) || status < 0) return `Unknown (${String(status)})`;
    normalized = BigInt(status);
  }

  switch (normalized) {
    case 0n:
      return "None";
    case 1n:
      return "Open";
    case 2n:
      return "Proof settled";
    case 3n:
      return "Expired refund";
    case 4n:
      return "Verifier revoked refund";
    case 5n:
      return "Verifier unavailable refund";
    default:
      return `Unknown (${normalized.toString()})`;
  }
}

function normalizePublicValues(input: ExactInferencePublicValuesInput) {
  const chainId = requireUint(input.chainId, 256, "Chain ID");
  const taskId = requireUint(input.taskId, 256, "Task ID");
  const netuid = requireUint(input.netuid, 16, "Subnet ID");
  const mechid = requireUint(input.mechid, 16, "Mechanism ID");
  if (mechid > EXACT_MAX_MECHANISM_ID) throw new Error("Mechanism ID exceeds the exact-settlement maximum");
  const verifierConfigId = requireUint(input.verifierConfigId, 64, "Verifier config ID");
  const protocolFeeBps = requireUint(input.protocolFeeBps, 16, "Protocol fee BPS");
  if (protocolFeeBps > EXACT_MAX_PROTOCOL_FEE_BPS) {
    throw new Error("Protocol fee BPS exceeds the exact-settlement maximum");
  }
  const classIndex = requireUint(input.classIndex, 8, "Class index");
  if (classIndex >= 4n) throw new Error("Class index must be between 0 and 3");
  if (!Array.isArray(input.scores) || input.scores.length !== 4) {
    throw new Error("Scores must contain exactly four int64 values");
  }
  const scores: ExactScores = [
    requireInt64(input.scores[0], "Scores[0]"),
    requireInt64(input.scores[1], "Scores[1]"),
    requireInt64(input.scores[2], "Scores[2]"),
    requireInt64(input.scores[3], "Scores[3]")
  ];

  const treasury = parseExactAddress(input.treasury, "Treasury", true);
  if ((protocolFeeBps === 0n) !== (treasury.toLowerCase() === ZERO_ADDRESS)) {
    throw new Error("Treasury must be zero exactly when protocol fee BPS is zero");
  }

  return {
    domain: EXACT_PUBLIC_VALUES_DOMAIN,
    version: EXACT_DOMAIN_VERSION,
    chainId,
    settlement: parseExactAddress(input.settlement, "Settlement"),
    taskId,
    taskSpecHash: parseExactBytes32(input.taskSpecHash, "Task specification hash"),
    netuid: Number(netuid),
    mechid: Number(mechid),
    verifierConfigId,
    relationId: parseExactBytes32(input.relationId, "Relation ID", false),
    requestNullifier: parseExactBytes32(input.requestNullifier, "Request nullifier"),
    inputCommitment: parseExactBytes32(input.inputCommitment, "Input commitment", false),
    modelCommitment: parseExactBytes32(input.modelCommitment, "Model commitment", false),
    protocolFeeBps: Number(protocolFeeBps),
    treasury,
    classIndex: Number(classIndex),
    scores,
    outputCommitment: computeExactOutputCommitment(classIndex, scores),
    provider: parseExactAddress(input.provider, "Provider"),
    beneficiary: parseExactAddress(input.beneficiary, "Beneficiary")
  };
}

export function computeExactOutputCommitment(classIndex: bigint, scores: ExactScores): Hex {
  requireUint(classIndex, 8, "Class index");
  if (classIndex >= 4n) throw new Error("Class index must be between 0 and 3");
  if (!Array.isArray(scores) || scores.length !== 4) throw new Error("Scores must contain exactly four int64 values");
  const normalizedScores: ExactScores = [
    requireInt64(scores[0], "Scores[0]"),
    requireInt64(scores[1], "Scores[1]"),
    requireInt64(scores[2], "Scores[2]"),
    requireInt64(scores[3], "Scores[3]")
  ];

  const encoded = encodeAbiParameters(
    [
      { type: "bytes32" },
      { type: "uint32" },
      { type: "uint8" },
      { type: "int64[4]" }
    ],
    [EXACT_OUTPUT_DOMAIN, EXACT_DOMAIN_VERSION, Number(classIndex), normalizedScores]
  );
  return sha256(encoded);
}

/** Encodes `abi.encode(ExactInferencePublicValuesV1)` from the Solidity V1 contract. */
export function encodeExactInferencePublicValues(input: ExactInferencePublicValuesInput): Hex {
  const values = normalizePublicValues(input);
  return encodeAbiParameters(
    [
      {
        type: "tuple",
        components: [
          { name: "domain", type: "bytes32" },
          { name: "version", type: "uint32" },
          { name: "chainId", type: "uint256" },
          { name: "settlement", type: "address" },
          { name: "taskId", type: "uint256" },
          { name: "taskSpecHash", type: "bytes32" },
          { name: "netuid", type: "uint16" },
          { name: "mechid", type: "uint16" },
          { name: "verifierConfigId", type: "uint64" },
          { name: "relationId", type: "bytes32" },
          { name: "requestNullifier", type: "bytes32" },
          { name: "inputCommitment", type: "bytes32" },
          { name: "modelCommitment", type: "bytes32" },
          { name: "protocolFeeBps", type: "uint16" },
          { name: "treasury", type: "address" },
          { name: "classIndex", type: "uint8" },
          { name: "scores", type: "int64[4]" },
          { name: "outputCommitment", type: "bytes32" },
          { name: "provider", type: "address" },
          { name: "beneficiary", type: "address" }
        ]
      }
    ],
    [values]
  );
}

import type { Hex } from "viem";

export const MAX_TASK_ARTIFACT_BYTES = 65_536;

export type PreparedTaskArtifact = {
  bytes: Uint8Array;
  byteLength: number;
  artifactSha256: Hex;
  rawCidV1: string;
};

const BASE32_LOWER_ALPHABET = "abcdefghijklmnopqrstuvwxyz234567";

export function bytesToHex(bytes: Uint8Array): Hex {
  let result = "0x";
  for (const value of bytes) result += value.toString(16).padStart(2, "0");
  return result as Hex;
}

export function base32LowerNoPadding(bytes: Uint8Array): string {
  let accumulator = 0;
  let bits = 0;
  let result = "";

  for (const value of bytes) {
    accumulator = (accumulator << 8) | value;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      result += BASE32_LOWER_ALPHABET[(accumulator >>> bits) & 31];
    }
  }

  if (bits > 0) result += BASE32_LOWER_ALPHABET[(accumulator << (5 - bits)) & 31];
  return result;
}

export function rawSha256CidV1(digest: Uint8Array): string {
  if (digest.length !== 32) throw new Error("Raw CID requires a 32-byte SHA-256 digest");

  // CIDv1, raw multicodec (0x55), sha2-256 multihash (0x12), 32-byte digest (0x20).
  const cidBytes = new Uint8Array(4 + digest.length);
  cidBytes.set([0x01, 0x55, 0x12, 0x20]);
  cidBytes.set(digest, 4);
  return `b${base32LowerNoPadding(cidBytes)}`;
}

export async function prepareTaskArtifact(rawText: string): Promise<PreparedTaskArtifact> {
  const bytes = new TextEncoder().encode(rawText);
  if (bytes.length === 0) throw new Error("Task artifact cannot be empty");
  if (bytes.length > MAX_TASK_ARTIFACT_BYTES) {
    throw new Error(`Task artifact exceeds the ${MAX_TASK_ARTIFACT_BYTES}-byte V1 limit`);
  }

  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  return {
    bytes,
    byteLength: bytes.length,
    artifactSha256: bytesToHex(digest),
    rawCidV1: rawSha256CidV1(digest)
  };
}

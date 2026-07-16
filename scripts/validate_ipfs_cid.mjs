#!/usr/bin/env node

import { pathToFileURL } from "node:url";

const BASE32_ALPHABET = "abcdefghijklmnopqrstuvwxyz234567";
const BASE32_VALUES = new Map([...BASE32_ALPHABET].map((character, index) => [character, index]));

function fail(message) {
  throw new Error(`validate-ipfs-cid: ${message}`);
}

function decodeBase32LowerNoPadding(value) {
  if (value.length === 0) fail("base32 payload is empty");
  const bytes = [];
  let accumulator = 0;
  let bits = 0;
  for (const character of value) {
    const digit = BASE32_VALUES.get(character);
    if (digit === undefined) fail("CID must use canonical lowercase base32 without padding");
    accumulator = (accumulator << 5) | digit;
    bits += 5;
    while (bits >= 8) {
      bits -= 8;
      bytes.push((accumulator >>> bits) & 0xff);
      accumulator &= (1 << bits) - 1;
    }
  }
  if (bits > 0 && accumulator !== 0) fail("CID base32 payload has non-zero trailing padding bits");
  return Uint8Array.from(bytes);
}

function encodeBase32LowerNoPadding(bytes) {
  let output = "";
  let accumulator = 0;
  let bits = 0;
  for (const byte of bytes) {
    accumulator = (accumulator << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      output += BASE32_ALPHABET[(accumulator >>> bits) & 31];
      accumulator &= (1 << bits) - 1;
    }
  }
  if (bits > 0) output += BASE32_ALPHABET[(accumulator << (5 - bits)) & 31];
  return output;
}

function encodeVarint(value) {
  if (!Number.isSafeInteger(value) || value < 0) fail("invalid varint value");
  const output = [];
  let remaining = value;
  do {
    let byte = remaining % 128;
    remaining = Math.floor(remaining / 128);
    if (remaining > 0) byte |= 0x80;
    output.push(byte);
  } while (remaining > 0);
  return output;
}

function readCanonicalVarint(bytes, start, label) {
  let value = 0;
  let multiplier = 1;
  let index = start;
  for (; index < bytes.length && index < start + 10; index += 1) {
    const byte = bytes[index];
    value += (byte & 0x7f) * multiplier;
    if (!Number.isSafeInteger(value)) fail(`${label} varint exceeds the safe integer range`);
    if ((byte & 0x80) === 0) {
      const encoded = encodeVarint(value);
      const consumed = [...bytes.slice(start, index + 1)];
      if (encoded.length !== consumed.length || encoded.some((candidate, offset) => candidate !== consumed[offset])) {
        fail(`${label} varint is not canonically encoded`);
      }
      return { value, next: index + 1 };
    }
    multiplier *= 128;
  }
  fail(`${label} varint is truncated or too long`);
}

export function validateKuboCidV1(cid, kind) {
  if (typeof cid !== "string" || cid.length > 128 || !cid.startsWith("b")) {
    fail("CID must be a bounded lowercase-base32 CIDv1 string");
  }
  const bytes = decodeBase32LowerNoPadding(cid.slice(1));
  if (`b${encodeBase32LowerNoPadding(bytes)}` !== cid) fail("CID does not round-trip canonically");

  const version = readCanonicalVarint(bytes, 0, "CID version");
  if (version.value !== 1) fail("CID version must be 1");
  const codec = readCanonicalVarint(bytes, version.next, "multicodec");
  const allowedCodecs = kind === "directory" ? new Set([0x70]) : kind === "file" ? new Set([0x55, 0x70]) : null;
  if (allowedCodecs === null) fail("kind must be directory or file");
  if (!allowedCodecs.has(codec.value)) {
    fail(kind === "directory" ? "directory root CID must use dag-pb" : "file CID must use raw or dag-pb");
  }
  const hashCode = readCanonicalVarint(bytes, codec.next, "multihash code");
  if (hashCode.value !== 0x12) fail("CID multihash must use sha2-256");
  const digestLength = readCanonicalVarint(bytes, hashCode.next, "multihash digest length");
  if (digestLength.value !== 32) fail("CID multihash digest must be 32 bytes");
  if (bytes.length - digestLength.next !== 32) fail("CID contains a truncated digest or trailing bytes");
  return { version: 1, codec: codec.value, multihashCode: 0x12, digestLength: 32 };
}

function parseArguments(raw) {
  if (raw.length !== 4 || raw[0] !== "--kind" || raw[2] !== "--cid") {
    fail("usage: validate_ipfs_cid.mjs --kind <directory|file> --cid <cid>");
  }
  return { kind: raw[1], cid: raw[3] };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const { kind, cid } = parseArguments(process.argv.slice(2));
  const result = validateKuboCidV1(cid, kind);
  process.stdout.write(`${JSON.stringify(result)}\n`);
}

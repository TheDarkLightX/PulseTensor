import assert from "node:assert/strict";
import test from "node:test";

import { formatPls, formatPlsExact } from "../src/lib/format.ts";

test("compact PLS formatting never renders positive dust as zero", () => {
  assert.equal(formatPls(0n), "0 PLS");
  assert.equal(formatPls(1n), "<0.000001 PLS");
  assert.equal(formatPls(999_999_999_999n), "<0.000001 PLS");
  assert.equal(formatPls(1_000_000_000_000n), "0.000001 PLS");
  assert.equal(formatPls(1_234_567_890_123_456_789n), "1.234567 PLS");
});

test("exact PLS formatting exposes full precision and wei", () => {
  assert.equal(formatPlsExact(1n), "0.000000000000000001 PLS (1 wei)");
  assert.equal(formatPlsExact(1_000_000_000_000_000_000n), "1 PLS (1000000000000000000 wei)");
  assert.equal(formatPlsExact(null), "-");
});

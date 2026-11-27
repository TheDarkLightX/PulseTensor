import assert from "node:assert/strict";
import test from "node:test";

import { isSharedIpfsPathGateway } from "../src/lib/hosting.ts";

test("shared IPFS/IPNS path gateways are distinguished from origin-isolated hosting", () => {
  assert.equal(isSharedIpfsPathGateway("/ipfs/bafy-example/"), true);
  assert.equal(isSharedIpfsPathGateway("/ipns/example.eth/"), true);
  assert.equal(isSharedIpfsPathGateway("/app/ipfs/bafy-example/"), true);
  assert.equal(isSharedIpfsPathGateway("//APP///IpFs//bafy-example/"), true);
  assert.equal(isSharedIpfsPathGateway("/mirror/IPNS/example.eth/"), true);
  assert.equal(isSharedIpfsPathGateway("/mirror/%69pfs/bafy-example/"), true);
  assert.equal(isSharedIpfsPathGateway("/mirror/%252FIPNS%252F/example.eth/"), true);
  assert.equal(isSharedIpfsPathGateway("/app/not-ipfs/bafy-example/"), false);
  assert.equal(isSharedIpfsPathGateway("/app/ipfs-mirror/bafy-example/"), false);
  assert.equal(isSharedIpfsPathGateway("/"), false);
});

test("malformed encoded paths fail closed", () => {
  assert.equal(isSharedIpfsPathGateway("/mirror/%E0%A4%A/bafy-example/"), true);
});

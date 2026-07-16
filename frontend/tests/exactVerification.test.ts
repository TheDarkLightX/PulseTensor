import assert from "node:assert/strict";
import test from "node:test";

import { keccak256, toBytes, type Address, type Hex } from "viem";
import { parseExactDeploymentManifest } from "../src/lib/exactManifest.ts";
import {
  verifyExactDeployment,
  verifyExactLivePreflight,
  type ExactReadClient
} from "../src/lib/exactVerification.ts";

const CORE = "0x0000000000000000000000000000000000001001" as Address;
const SETTLEMENT = "0x0000000000000000000000000000000000001002" as Address;
const ADAPTER = "0x0000000000000000000000000000000000001003" as Address;
const VERIFIER = "0x0000000000000000000000000000000000001004" as Address;
const TREASURY = "0x0000000000000000000000000000000000001005" as Address;
const GOVERNANCE = "0x0000000000000000000000000000000000001006" as Address;
const CORE_CODE = "0x6001600055" as Hex;
const SETTLEMENT_CODE = "0x6002600055" as Hex;
const ADAPTER_CODE = "0x6003600055" as Hex;
const VERIFIER_CODE = "0x6004600055" as Hex;
const BLOCK_HASH = `0x${"aa".repeat(32)}` as Hex;
const PROGRAM = `0x${"11".repeat(32)}` as Hex;
const RELATION = `0x${"22".repeat(32)}` as Hex;
const PROOF_SYSTEM = `0x${"33".repeat(32)}` as Hex;
const SELECTOR = "0x12345678" as Hex;
const VERSION_HASH = keccak256(toBytes("3.0.0"));

function manifest() {
  return parseExactDeploymentManifest({
    schema: "pulsetensor/exact-inference-deployment-manifest/v1",
    chainId: 943,
    sourceCommit: "a".repeat(40),
    deploymentAnchor: { blockNumber: "100", blockHash: BLOCK_HASH, minimumConfirmations: 64 },
    core: { address: CORE, runtimeCodeHash: keccak256(CORE_CODE) },
    exactSettlement: { address: SETTLEMENT, runtimeCodeHash: keccak256(SETTLEMENT_CODE) },
    verifierConfigs: [
      {
        netuid: 1,
        configId: "7",
        adapter: ADAPTER,
        adapterRuntimeCodeHash: keccak256(ADAPTER_CODE),
        baseVerifier: VERIFIER,
        verifierRuntimeCodeHash: keccak256(VERIFIER_CODE),
        programId: PROGRAM,
        relationId: RELATION,
        proofSystemId: PROOF_SYSTEM,
        proofSelector: SELECTOR,
        verifierVersionHash: VERSION_HASH,
        proofBytes: 260,
        protocolFeeBps: 300,
        treasury: TREASURY
      }
    ],
    evidence: {
      guestSourceUri: "https://example.test/guest",
      guestSourceSha256: PROGRAM,
      guestBuildRecipeUri: "ipfs://bafy-build-recipe",
      guestBuildRecipeSha256: RELATION,
      genuineReceiptUri: "https://example.test/genuine-receipt",
      genuineReceiptSha256: PROOF_SYSTEM,
      auditReportUri: "ipfs://bafy-audit",
      auditReportSha256: PROGRAM,
      pulsechainTestnetReceiptUri: "https://example.test/pulsechain-testnet-receipt",
      pulsechainTestnetReceiptSha256: RELATION
    }
  });
}

function client(adapterCode: Hex = ADAPTER_CODE, activatedAtBlock = 99n): ExactReadClient {
  const anchoredBytecode = new Map<string, Hex>([
    [CORE.toLowerCase(), CORE_CODE],
    [SETTLEMENT.toLowerCase(), SETTLEMENT_CODE],
    [ADAPTER.toLowerCase(), ADAPTER_CODE],
    [VERIFIER.toLowerCase(), VERIFIER_CODE]
  ]);
  const currentBytecode = new Map(anchoredBytecode);
  currentBytecode.set(ADAPTER.toLowerCase(), adapterCode);
  return {
    async getChainId() { return 943; },
    async getBlockNumber() { return 200n; },
    async getBlock() { return { hash: BLOCK_HASH }; },
    async getBytecode({ address, blockNumber }) {
      return (blockNumber === 100n ? anchoredBytecode : currentBytecode).get(address.toLowerCase());
    },
    async readContract(args) {
      const functionName = args.functionName as string;
      switch (functionName) {
        case "CORE": return CORE;
        case "CORE_RUNTIME_CODE_HASH": return keccak256(CORE_CODE);
        case "verifierConfigs":
          return {
            exists: true,
            revoked: false,
            netuid: 1,
            protocolFeeBps: 300,
            proofSelector: SELECTOR,
            activatedAtBlock,
            stopNewTasksAtBlock: 0n,
            adapter: ADAPTER,
            treasury: TREASURY,
            adapterRuntimeCodeHash: keccak256(ADAPTER_CODE),
            verifierRuntimeCodeHash: keccak256(VERIFIER_CODE),
            programId: PROGRAM,
            relationId: RELATION,
            proofSystemId: PROOF_SYSTEM
          };
        case "RISC_ZERO_VERIFIER": return VERIFIER;
        case "VERIFIER_RUNTIME_CODE_HASH": return keccak256(VERIFIER_CODE);
        case "PROOF_SELECTOR": return SELECTOR;
        case "proofSystemId": return PROOF_SYSTEM;
        case "RISC_ZERO_VERSION_HASH": return VERSION_HASH;
        case "RISC_ZERO_GROTH16_V3_SEAL_BYTES": return 260n;
        case "verifierRuntimeCodeHashMatches": return true;
        case "SELECTOR": return SELECTOR;
        case "VERSION": return "3.0.0";
        case "verifierCodeAvailable": return adapterCode === ADAPTER_CODE;
        case "verifierAcceptsNewTasks": return adapterCode === ADAPTER_CODE;
        case "verifierCanSettleOpenTasks": return adapterCode === ADAPTER_CODE;
        case "subnetPaused": return false;
        case "subnetGovernance": return GOVERNANCE;
        default: throw new Error(`Unexpected mock read: ${functionName}`);
      }
    }
  };
}

test("deployment verifier accepts matching chain, anchor, code and immutable/config identity", async () => {
  const base = client();
  const observedReadBlocks: unknown[] = [];
  const pinned: ExactReadClient = {
    ...base,
    async readContract(args) {
      observedReadBlocks.push(args.blockNumber);
      return base.readContract(args);
    }
  };
  const result = await verifyExactDeployment(pinned, manifest());
  assert.equal(result.settlementIdentityVerified, true);
  assert.equal(result.coreRuntimeCodeHashMatches, true);
  assert.equal(result.identityVerified, true);
  assert.equal(result.admissionVerified, true);
  assert.deepEqual(result.identityIssues, []);
  assert.ok(observedReadBlocks.length > 0);
  assert.ok(observedReadBlocks.every((blockNumber) => blockNumber === 200n));
});

test("adapter drift blocks admission without blocking settlement identity and recovery", async () => {
  const result = await verifyExactDeployment(client("0x6005600055"), manifest());
  assert.equal(result.identityVerified, true);
  assert.equal(result.admissionVerified, false);
  assert.match(result.readinessIssues.join("\n"), /adapter runtime code is unavailable or changed/);
});

test("deployment anchor rejects a verifier configuration activated after the checkpoint", async () => {
  const result = await verifyExactDeployment(client(ADAPTER_CODE, 101n), manifest());
  assert.equal(result.identityVerified, false);
  assert.match(result.identityIssues.join("\n"), /activated at block 101, after deployment anchor 100/);
});

test("current Core drift blocks admission but not immutable settlement identity or recovery", async () => {
  const base = client();
  const drifted: ExactReadClient = {
    ...base,
    async getBytecode(args) {
      if (args.blockNumber !== 100n && args.address.toLowerCase() === CORE.toLowerCase()) {
        return "0x6006600055";
      }
      return base.getBytecode(args);
    }
  };
  const result = await verifyExactDeployment(drifted, manifest());
  assert.equal(result.settlementIdentityVerified, true);
  assert.equal(result.identityVerified, true);
  assert.equal(result.coreRuntimeCodeHashMatches, false);
  assert.equal(result.admissionVerified, false);
  assert.match(result.readinessIssues.join("\n"), /Core runtime code is unavailable or changed/);
});

test("recovery preflight needs no archive, Core runtime, or verifier configuration reads", async () => {
  const base = client();
  const requestedCode: string[] = [];
  const recoveryClient: ExactReadClient = {
    async getChainId() { return 943; },
    async getBlockNumber() { throw new Error("recovery must not read the chain head"); },
    async getBlock() { throw new Error("recovery must not read historical blocks"); },
    async getBytecode(args) {
      if (args.blockNumber !== undefined) throw new Error("recovery must not read historical code");
      requestedCode.push(args.address.toLowerCase());
      if (args.address.toLowerCase() !== SETTLEMENT.toLowerCase()) {
        throw new Error("recovery must not read Core or verifier bytecode");
      }
      return SETTLEMENT_CODE;
    },
    async readContract(args) {
      const functionName = args.functionName as string;
      if (functionName === "CORE" || functionName === "CORE_RUNTIME_CODE_HASH") {
        return base.readContract(args);
      }
      throw new Error(`recovery must not read ${functionName}`);
    }
  };
  const result = await verifyExactLivePreflight(recoveryClient, manifest(), "recovery");
  assert.equal(result.actionVerified, true);
  assert.deepEqual(requestedCode, [SETTLEMENT.toLowerCase()]);
});

test("live settlement preflight checks only the task configuration and rejects verifier drift", async () => {
  const base = client("0x6005600055");
  const settlementClient: ExactReadClient = {
    ...base,
    async getBlockNumber() { throw new Error("settlement preflight must not read the chain head"); },
    async getBlock() { throw new Error("settlement preflight must not read historical blocks"); },
    async getBytecode(args) {
      if (args.blockNumber !== undefined) throw new Error("settlement preflight must not read historical code");
      if (args.address.toLowerCase() === CORE.toLowerCase()) {
        throw new Error("proof settlement must not depend on current Core runtime");
      }
      return base.getBytecode(args);
    },
    async readContract(args) {
      if (args.functionName === "subnetPaused" || args.functionName === "subnetGovernance") {
        throw new Error("proof settlement must not read Core admission state");
      }
      return base.readContract(args);
    }
  };
  const result = await verifyExactLivePreflight(
    settlementClient,
    manifest(),
    "settlement",
    { netuid: 1, configId: 7n }
  );
  assert.equal(result.settlementIdentityVerified, true);
  assert.equal(result.actionVerified, false);
  assert.match(result.actionIssues.join("\n"), /cannot settle open tasks|verifier code is unavailable/);
});

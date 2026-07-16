import {
  getAddress,
  type Address,
  type Hex,
  keccak256,
  toBytes
} from "viem";
import {
  exactCoreReadAbi,
  pulsetensorExactInferenceAbi,
  riscZeroAdapterReadAbi,
  riscZeroBaseVerifierReadAbi
} from "./exactAbi.ts";
import type { ExactDeploymentManifest, ExactManifestVerifierConfig } from "./exactManifest.ts";

export type ExactReadClient = {
  getChainId(): Promise<number>;
  getBlockNumber(): Promise<bigint>;
  getBlock(args: { blockNumber: bigint }): Promise<{ hash: Hex | null }>;
  getBytecode(args: { address: Address; blockNumber?: bigint }): Promise<Hex | undefined>;
  readContract(args: Record<string, unknown>): Promise<unknown>;
};

export type ExactConfigVerification = {
  manifest: ExactManifestVerifierConfig;
  exists: boolean;
  revoked: boolean;
  stopNewTasksAtBlock: bigint;
  codeAvailable: boolean;
  acceptsNewTasks: boolean;
  canSettleOpenTasks: boolean;
  corePaused: boolean;
  governanceConfigured: boolean;
  identityIssues: string[];
  readinessIssues: string[];
};

export type ExactDeploymentVerification = {
  checkedChainId: number;
  checkedBlockNumber: bigint;
  settlementIdentityVerified: boolean;
  coreRuntimeCodeHashMatches: boolean;
  identityVerified: boolean;
  admissionVerified: boolean;
  settlementIdentityIssues: string[];
  identityIssues: string[];
  readinessIssues: string[];
  configs: ExactConfigVerification[];
};

export type ExactWriteGate = "recovery" | "admission" | "settlement";

export type ExactLivePreflight = {
  checkedChainId: number;
  settlementIdentityVerified: boolean;
  actionVerified: boolean;
  actionIssues: string[];
  config?: ExactConfigVerification;
};

type ChainVerifierConfig = {
  exists: boolean;
  revoked: boolean;
  netuid: number;
  protocolFeeBps: number;
  proofSelector: Hex;
  activatedAtBlock: bigint;
  stopNewTasksAtBlock: bigint;
  adapter: Address;
  treasury: Address;
  adapterRuntimeCodeHash: Hex;
  verifierRuntimeCodeHash: Hex;
  programId: Hex;
  relationId: Hex;
  proofSystemId: Hex;
};

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

function sameHex(left: string, right: string): boolean {
  return left.toLowerCase() === right.toLowerCase();
}

function field<T>(value: unknown, name: string, index: number): T {
  if (Array.isArray(value)) return value[index] as T;
  if (typeof value === "object" && value !== null && name in value) {
    return (value as Record<string, unknown>)[name] as T;
  }
  throw new Error(`RPC returned a malformed tuple: missing ${name}`);
}

function normalizeVerifierConfig(value: unknown): ChainVerifierConfig {
  return {
    exists: field(value, "exists", 0),
    revoked: field(value, "revoked", 1),
    netuid: Number(field<bigint | number>(value, "netuid", 2)),
    protocolFeeBps: Number(field<bigint | number>(value, "protocolFeeBps", 3)),
    proofSelector: field(value, "proofSelector", 4),
    activatedAtBlock: BigInt(field<bigint | number>(value, "activatedAtBlock", 5)),
    stopNewTasksAtBlock: BigInt(field<bigint | number>(value, "stopNewTasksAtBlock", 6)),
    adapter: getAddress(field(value, "adapter", 7)),
    treasury: getAddress(field(value, "treasury", 8)),
    adapterRuntimeCodeHash: field(value, "adapterRuntimeCodeHash", 9),
    verifierRuntimeCodeHash: field(value, "verifierRuntimeCodeHash", 10),
    programId: field(value, "programId", 11),
    relationId: field(value, "relationId", 12),
    proofSystemId: field(value, "proofSystemId", 13)
  };
}

async function runtimeCodeHash(
  client: ExactReadClient,
  address: Address,
  blockNumber?: bigint
): Promise<Hex | null> {
  const bytecode = await client.getBytecode({ address, blockNumber });
  if (!bytecode || bytecode === "0x") return null;
  return keccak256(bytecode);
}

function compare(
  issues: string[],
  condition: boolean,
  label: string,
  expected: string | number | bigint,
  actual: string | number | bigint
): void {
  if (!condition) issues.push(`${label}: expected ${expected.toString()}, received ${actual.toString()}`);
}

async function verifyConfig(
  client: ExactReadClient,
  manifest: ExactDeploymentManifest,
  expected: ExactManifestVerifierConfig,
  options: {
    checkHistoricalIdentity: boolean;
    includeCoreAdmission: boolean;
    currentBlockNumber?: bigint;
  }
): Promise<ExactConfigVerification> {
  const identityIssues: string[] = [];
  const readinessIssues: string[] = [];
  const settlement = manifest.exactSettlement.address;
  const rawConfig = await client.readContract({
    address: settlement,
    abi: pulsetensorExactInferenceAbi,
    functionName: "verifierConfigs",
    args: [expected.configId],
    blockNumber: options.currentBlockNumber
  });
  const config = normalizeVerifierConfig(rawConfig);
  const label = `config ${expected.configId.toString()}`;

  compare(identityIssues, config.exists, `${label} exists`, true.toString(), config.exists.toString());
  compare(identityIssues, config.netuid === expected.netuid, `${label} netuid`, expected.netuid, config.netuid);
  compare(
    identityIssues,
    config.protocolFeeBps === expected.protocolFeeBps,
    `${label} protocolFeeBps`,
    expected.protocolFeeBps,
    config.protocolFeeBps
  );
  compare(identityIssues, sameHex(config.proofSelector, expected.proofSelector), `${label} proofSelector`, expected.proofSelector, config.proofSelector);
  compare(identityIssues, sameHex(config.adapter, expected.adapter), `${label} adapter`, expected.adapter, config.adapter);
  compare(identityIssues, sameHex(config.treasury, expected.treasury), `${label} treasury`, expected.treasury, config.treasury);
  compare(identityIssues, sameHex(config.adapterRuntimeCodeHash, expected.adapterRuntimeCodeHash), `${label} adapterRuntimeCodeHash`, expected.adapterRuntimeCodeHash, config.adapterRuntimeCodeHash);
  compare(identityIssues, sameHex(config.verifierRuntimeCodeHash, expected.verifierRuntimeCodeHash), `${label} verifierRuntimeCodeHash`, expected.verifierRuntimeCodeHash, config.verifierRuntimeCodeHash);
  compare(identityIssues, sameHex(config.programId, expected.programId), `${label} programId`, expected.programId, config.programId);
  compare(identityIssues, sameHex(config.relationId, expected.relationId), `${label} relationId`, expected.relationId, config.relationId);
  compare(identityIssues, sameHex(config.proofSystemId, expected.proofSystemId), `${label} proofSystemId`, expected.proofSystemId, config.proofSystemId);
  if (
    options.checkHistoricalIdentity &&
    (config.activatedAtBlock === 0n || config.activatedAtBlock > manifest.deploymentAnchor.blockNumber)
  ) {
    identityIssues.push(
      `${label} activated at block ${config.activatedAtBlock.toString()}, after deployment anchor ${manifest.deploymentAnchor.blockNumber.toString()}`
    );
  }

  if (options.checkHistoricalIdentity) {
    const [historicalAdapterCodeHash, historicalBaseVerifierCodeHash] = await Promise.all([
      runtimeCodeHash(client, expected.adapter, manifest.deploymentAnchor.blockNumber),
      runtimeCodeHash(client, expected.baseVerifier, manifest.deploymentAnchor.blockNumber)
    ]);
    compare(
      identityIssues,
      historicalAdapterCodeHash !== null && sameHex(historicalAdapterCodeHash, expected.adapterRuntimeCodeHash),
      `${label} adapter runtime code hash at deployment anchor`,
      expected.adapterRuntimeCodeHash,
      historicalAdapterCodeHash ?? "no code"
    );
    compare(
      identityIssues,
      historicalBaseVerifierCodeHash !== null &&
        sameHex(historicalBaseVerifierCodeHash, expected.verifierRuntimeCodeHash),
      `${label} base verifier runtime code hash at deployment anchor`,
      expected.verifierRuntimeCodeHash,
      historicalBaseVerifierCodeHash ?? "no code"
    );
  }

  const [adapterCodeHash, baseVerifierCodeHash] = await Promise.all([
    runtimeCodeHash(client, expected.adapter, options.currentBlockNumber),
    runtimeCodeHash(client, expected.baseVerifier, options.currentBlockNumber)
  ]);
  const adapterRuntimeMatches =
    adapterCodeHash !== null && sameHex(adapterCodeHash, expected.adapterRuntimeCodeHash);
  const baseVerifierRuntimeMatches =
    baseVerifierCodeHash !== null && sameHex(baseVerifierCodeHash, expected.verifierRuntimeCodeHash);
  if (!adapterRuntimeMatches) {
    readinessIssues.push(
      `${label} adapter runtime code is unavailable or changed (expected ${expected.adapterRuntimeCodeHash}, received ${adapterCodeHash ?? "no code"})`
    );
  }
  if (!baseVerifierRuntimeMatches) {
    readinessIssues.push(
      `${label} base verifier runtime code is unavailable or changed (expected ${expected.verifierRuntimeCodeHash}, received ${baseVerifierCodeHash ?? "no code"})`
    );
  }

  let adapterHashMatches = false;
  if (adapterRuntimeMatches) {
    const [
      baseVerifier,
      pinnedVerifierHash,
      adapterSelector,
      adapterProofSystemId,
      adapterVersionHash,
      adapterSealBytes,
      currentAdapterHashMatches
    ] = await Promise.all([
      client.readContract({ address: expected.adapter, abi: riscZeroAdapterReadAbi, functionName: "RISC_ZERO_VERIFIER", blockNumber: options.currentBlockNumber }),
      client.readContract({ address: expected.adapter, abi: riscZeroAdapterReadAbi, functionName: "VERIFIER_RUNTIME_CODE_HASH", blockNumber: options.currentBlockNumber }),
      client.readContract({ address: expected.adapter, abi: riscZeroAdapterReadAbi, functionName: "PROOF_SELECTOR", blockNumber: options.currentBlockNumber }),
      client.readContract({ address: expected.adapter, abi: riscZeroAdapterReadAbi, functionName: "proofSystemId", blockNumber: options.currentBlockNumber }),
      client.readContract({ address: expected.adapter, abi: riscZeroAdapterReadAbi, functionName: "RISC_ZERO_VERSION_HASH", blockNumber: options.currentBlockNumber }),
      client.readContract({ address: expected.adapter, abi: riscZeroAdapterReadAbi, functionName: "RISC_ZERO_GROTH16_V3_SEAL_BYTES", blockNumber: options.currentBlockNumber }),
      client.readContract({ address: expected.adapter, abi: riscZeroAdapterReadAbi, functionName: "verifierRuntimeCodeHashMatches", blockNumber: options.currentBlockNumber })
    ]);
    adapterHashMatches = Boolean(currentAdapterHashMatches);
    compare(identityIssues, sameHex(baseVerifier as string, expected.baseVerifier), `${label} adapter base verifier`, expected.baseVerifier, baseVerifier as string);
    compare(identityIssues, sameHex(pinnedVerifierHash as string, expected.verifierRuntimeCodeHash), `${label} pinned verifier hash`, expected.verifierRuntimeCodeHash, pinnedVerifierHash as string);
    compare(identityIssues, sameHex(adapterSelector as string, expected.proofSelector), `${label} adapter selector`, expected.proofSelector, adapterSelector as string);
    compare(identityIssues, sameHex(adapterProofSystemId as string, expected.proofSystemId), `${label} adapter proof system`, expected.proofSystemId, adapterProofSystemId as string);
    compare(identityIssues, sameHex(adapterVersionHash as string, expected.verifierVersionHash), `${label} verifier version hash`, expected.verifierVersionHash, adapterVersionHash as string);
    compare(identityIssues, BigInt(adapterSealBytes as bigint) === BigInt(expected.proofBytes), `${label} seal bytes`, expected.proofBytes, adapterSealBytes as bigint);
  }

  if (baseVerifierRuntimeMatches) {
    const [baseSelector, baseVersion] = await Promise.all([
      client.readContract({ address: expected.baseVerifier, abi: riscZeroBaseVerifierReadAbi, functionName: "SELECTOR", blockNumber: options.currentBlockNumber }),
      client.readContract({ address: expected.baseVerifier, abi: riscZeroBaseVerifierReadAbi, functionName: "VERSION", blockNumber: options.currentBlockNumber })
    ]);
    compare(identityIssues, sameHex(baseSelector as string, expected.proofSelector), `${label} base selector`, expected.proofSelector, baseSelector as string);
    const actualBaseVersionHash = keccak256(toBytes(baseVersion as string));
    compare(identityIssues, sameHex(actualBaseVersionHash, expected.verifierVersionHash), `${label} base version hash`, expected.verifierVersionHash, actualBaseVersionHash);
  }

  const [codeAvailable, acceptsNewTasks, canSettleOpenTasks] = await Promise.all([
    client.readContract({ address: settlement, abi: pulsetensorExactInferenceAbi, functionName: "verifierCodeAvailable", args: [expected.configId], blockNumber: options.currentBlockNumber }),
    client.readContract({ address: settlement, abi: pulsetensorExactInferenceAbi, functionName: "verifierAcceptsNewTasks", args: [expected.configId], blockNumber: options.currentBlockNumber }),
    client.readContract({ address: settlement, abi: pulsetensorExactInferenceAbi, functionName: "verifierCanSettleOpenTasks", args: [expected.configId], blockNumber: options.currentBlockNumber })
  ]);
  let corePaused = false;
  let governanceConfigured = true;
  if (options.includeCoreAdmission) {
    const [paused, governance] = await Promise.all([
      client.readContract({ address: manifest.core.address, abi: exactCoreReadAbi, functionName: "subnetPaused", args: [expected.netuid], blockNumber: options.currentBlockNumber }),
      client.readContract({ address: manifest.core.address, abi: exactCoreReadAbi, functionName: "subnetGovernance", args: [expected.netuid], blockNumber: options.currentBlockNumber })
    ]);
    corePaused = Boolean(paused);
    governanceConfigured = !sameHex(governance as string, ZERO_ADDRESS);
  }
  if (config.revoked) readinessIssues.push(`${label} is permanently revoked`);
  if (config.stopNewTasksAtBlock !== 0n) readinessIssues.push(`${label} is deprecated for new tasks`);
  if (!adapterHashMatches) readinessIssues.push(`${label} base verifier code hash is unavailable`);
  if (!codeAvailable) readinessIssues.push(`${label} verifier code is unavailable`);
  if (!acceptsNewTasks) readinessIssues.push(`${label} does not accept new tasks`);
  if (options.includeCoreAdmission && corePaused) readinessIssues.push(`subnet ${expected.netuid} is paused`);
  if (options.includeCoreAdmission && !governanceConfigured) {
    readinessIssues.push(`subnet ${expected.netuid} has no governance configured`);
  }

  return {
    manifest: expected,
    exists: config.exists,
    revoked: config.revoked,
    stopNewTasksAtBlock: config.stopNewTasksAtBlock,
    codeAvailable: Boolean(codeAvailable),
    acceptsNewTasks: Boolean(acceptsNewTasks),
    canSettleOpenTasks: Boolean(canSettleOpenTasks),
    corePaused: Boolean(corePaused),
    governanceConfigured,
    identityIssues,
    readinessIssues
  };
}

export async function verifyExactDeployment(
  client: ExactReadClient,
  manifest: ExactDeploymentManifest
): Promise<ExactDeploymentVerification> {
  const settlementIdentityIssues: string[] = [];
  const readinessIssues: string[] = [];
  const checkedChainId = await client.getChainId();
  const checkedBlockNumber = await client.getBlockNumber();
  compare(
    settlementIdentityIssues,
    checkedChainId === manifest.chainId,
    "chain ID",
    manifest.chainId,
    checkedChainId
  );

  const anchor = manifest.deploymentAnchor;
  if (checkedBlockNumber < anchor.blockNumber) {
    settlementIdentityIssues.push(
      `chain head ${checkedBlockNumber.toString()} precedes deployment anchor ${anchor.blockNumber.toString()}`
    );
  } else {
    const block = await client.getBlock({ blockNumber: anchor.blockNumber });
    compare(
      settlementIdentityIssues,
      block.hash !== null && sameHex(block.hash, anchor.blockHash),
      "deployment block hash",
      anchor.blockHash,
      block.hash ?? "missing"
    );
    const confirmations = checkedBlockNumber - anchor.blockNumber + 1n;
    if (confirmations < BigInt(anchor.minimumConfirmations)) {
      settlementIdentityIssues.push(
        `deployment anchor has ${confirmations.toString()} confirmations; ${anchor.minimumConfirmations} required`
      );
    }
  }

  const [historicalCoreHash, historicalSettlementHash, coreHash, settlementHash, boundCore, boundCoreHash] = await Promise.all([
    runtimeCodeHash(client, manifest.core.address, anchor.blockNumber),
    runtimeCodeHash(client, manifest.exactSettlement.address, anchor.blockNumber),
    runtimeCodeHash(client, manifest.core.address, checkedBlockNumber),
    runtimeCodeHash(client, manifest.exactSettlement.address, checkedBlockNumber),
    client.readContract({ address: manifest.exactSettlement.address, abi: pulsetensorExactInferenceAbi, functionName: "CORE", blockNumber: checkedBlockNumber }),
    client.readContract({ address: manifest.exactSettlement.address, abi: pulsetensorExactInferenceAbi, functionName: "CORE_RUNTIME_CODE_HASH", blockNumber: checkedBlockNumber })
  ]);
  compare(
    settlementIdentityIssues,
    historicalCoreHash !== null && sameHex(historicalCoreHash, manifest.core.runtimeCodeHash),
    "Core runtime code hash at deployment anchor",
    manifest.core.runtimeCodeHash,
    historicalCoreHash ?? "no code"
  );
  compare(
    settlementIdentityIssues,
    historicalSettlementHash !== null &&
      sameHex(historicalSettlementHash, manifest.exactSettlement.runtimeCodeHash),
    "exact settlement runtime code hash at deployment anchor",
    manifest.exactSettlement.runtimeCodeHash,
    historicalSettlementHash ?? "no code"
  );
  const coreRuntimeCodeHashMatches =
    coreHash !== null && sameHex(coreHash, manifest.core.runtimeCodeHash);
  if (!coreRuntimeCodeHashMatches) {
    readinessIssues.push(
      `Core runtime code is unavailable or changed (expected ${manifest.core.runtimeCodeHash}, received ${coreHash ?? "no code"})`
    );
  }
  compare(
    settlementIdentityIssues,
    settlementHash !== null && sameHex(settlementHash, manifest.exactSettlement.runtimeCodeHash),
    "exact settlement current runtime code hash",
    manifest.exactSettlement.runtimeCodeHash,
    settlementHash ?? "no code"
  );
  compare(
    settlementIdentityIssues,
    sameHex(boundCore as string, manifest.core.address),
    "exact settlement Core binding",
    manifest.core.address,
    boundCore as string
  );
  compare(
    settlementIdentityIssues,
    sameHex(boundCoreHash as string, manifest.core.runtimeCodeHash),
    "exact settlement pinned Core hash",
    manifest.core.runtimeCodeHash,
    boundCoreHash as string
  );

  const configs: ExactConfigVerification[] = [];
  const configIdentityIssues: string[] = [];
  for (const expected of manifest.verifierConfigs) {
    const config = await verifyConfig(client, manifest, expected, {
      checkHistoricalIdentity: true,
      includeCoreAdmission: true,
      currentBlockNumber: checkedBlockNumber
    });
    configs.push(config);
    configIdentityIssues.push(...config.identityIssues);
    readinessIssues.push(...config.readinessIssues);
  }

  const settlementIdentityVerified = settlementIdentityIssues.length === 0;
  const identityIssues = [...settlementIdentityIssues, ...configIdentityIssues];
  const identityVerified = identityIssues.length === 0;

  return {
    checkedChainId,
    checkedBlockNumber,
    settlementIdentityVerified,
    coreRuntimeCodeHashMatches,
    identityVerified,
    admissionVerified:
      identityVerified &&
      coreRuntimeCodeHashMatches &&
      configs.some(
        (config) =>
          config.acceptsNewTasks &&
          config.codeAvailable &&
          !config.revoked &&
          !config.corePaused &&
          config.governanceConfigured
      ),
    settlementIdentityIssues,
    identityIssues,
    readinessIssues,
    configs
  };
}

/**
 * Rechecks only the state that can affect the requested value-moving call through the
 * injected wallet RPC. Historical anchor reads remain part of manifest review above;
 * they are intentionally excluded here so recovery cannot be censored by a pruned RPC.
 */
export async function verifyExactLivePreflight(
  client: ExactReadClient,
  manifest: ExactDeploymentManifest,
  gate: ExactWriteGate,
  gateConfig?: { netuid: number; configId: bigint }
): Promise<ExactLivePreflight> {
  const actionIssues: string[] = [];
  const checkedChainId = await client.getChainId();
  compare(actionIssues, checkedChainId === manifest.chainId, "chain ID", manifest.chainId, checkedChainId);

  const [settlementHash, boundCore, boundCoreHash] = await Promise.all([
    runtimeCodeHash(client, manifest.exactSettlement.address),
    client.readContract({
      address: manifest.exactSettlement.address,
      abi: pulsetensorExactInferenceAbi,
      functionName: "CORE"
    }),
    client.readContract({
      address: manifest.exactSettlement.address,
      abi: pulsetensorExactInferenceAbi,
      functionName: "CORE_RUNTIME_CODE_HASH"
    })
  ]);
  compare(
    actionIssues,
    settlementHash !== null && sameHex(settlementHash, manifest.exactSettlement.runtimeCodeHash),
    "exact settlement current runtime code hash",
    manifest.exactSettlement.runtimeCodeHash,
    settlementHash ?? "no code"
  );
  compare(
    actionIssues,
    sameHex(boundCore as string, manifest.core.address),
    "exact settlement Core binding",
    manifest.core.address,
    boundCore as string
  );
  compare(
    actionIssues,
    sameHex(boundCoreHash as string, manifest.core.runtimeCodeHash),
    "exact settlement pinned Core hash",
    manifest.core.runtimeCodeHash,
    boundCoreHash as string
  );
  const settlementIdentityVerified = actionIssues.length === 0;

  if (gate === "recovery") {
    return {
      checkedChainId,
      settlementIdentityVerified,
      actionVerified: settlementIdentityVerified,
      actionIssues
    };
  }

  if (!gateConfig) {
    actionIssues.push(`${gate} verifier configuration is missing`);
    return {
      checkedChainId,
      settlementIdentityVerified,
      actionVerified: false,
      actionIssues
    };
  }
  const expected = manifest.verifierConfigs.find(
    (item) => item.netuid === gateConfig.netuid && item.configId === gateConfig.configId
  );
  if (!expected) {
    actionIssues.push(
      `${gate} verifier configuration ${gateConfig.netuid}/${gateConfig.configId.toString()} is not in the reviewed manifest`
    );
    return {
      checkedChainId,
      settlementIdentityVerified,
      actionVerified: false,
      actionIssues
    };
  }

  if (gate === "admission") {
    const coreHash = await runtimeCodeHash(client, manifest.core.address);
    compare(
      actionIssues,
      coreHash !== null && sameHex(coreHash, manifest.core.runtimeCodeHash),
      "Core current runtime code hash",
      manifest.core.runtimeCodeHash,
      coreHash ?? "no code"
    );
  }

  const config = await verifyConfig(client, manifest, expected, {
    checkHistoricalIdentity: false,
    includeCoreAdmission: gate === "admission"
  });
  actionIssues.push(...config.identityIssues);
  if (gate === "admission") {
    if (!config.acceptsNewTasks) actionIssues.push("reviewed verifier configuration does not accept new tasks");
    if (!config.codeAvailable) actionIssues.push("reviewed verifier code is unavailable");
    if (config.revoked) actionIssues.push("reviewed verifier configuration is revoked");
    if (config.corePaused) actionIssues.push(`subnet ${config.manifest.netuid} is paused`);
    if (!config.governanceConfigured) {
      actionIssues.push(`subnet ${config.manifest.netuid} has no governance configured`);
    }
  } else {
    if (!config.canSettleOpenTasks) {
      actionIssues.push("reviewed verifier configuration cannot settle open tasks");
    }
    if (!config.codeAvailable) actionIssues.push("reviewed verifier code is unavailable");
  }

  return {
    checkedChainId,
    settlementIdentityVerified,
    actionVerified: actionIssues.length === 0,
    actionIssues,
    config
  };
}

export function findVerifiedConfig(
  verification: ExactDeploymentVerification,
  netuid: number,
  configId: bigint
): ExactConfigVerification | undefined {
  return verification.configs.find(
    (config) => config.manifest.netuid === netuid && config.manifest.configId === configId
  );
}

import { useEffect, useMemo, useRef, useState } from "react";
import {
  type Address,
  type Hex,
  createPublicClient,
  createWalletClient,
  custom,
  http,
  parseEther
} from "viem";
import { prepareTaskArtifact, type PreparedTaskArtifact } from "../lib/artifact.ts";
import {
  exactTaskStatusLabel,
  parseAddressStrict,
  parseBytes32Strict,
  parseExactClassIndex,
  parseExactScores,
  parseProofHex,
  parseUint16Strict,
  parseUint256Strict,
  parseUint64Strict
} from "../lib/exact.ts";
import { pulsetensorExactInferenceAbi } from "../lib/exactAbi.ts";
import {
  loadDigestPinnedManifest,
  MAX_EXACT_MANIFEST_BYTES,
  parseDigestPinnedManifestBytes,
  type ExactDeploymentManifest,
  type ExactManifestVerifierConfig
} from "../lib/exactManifest.ts";
import {
  findVerifiedConfig,
  verifyExactDeployment,
  verifyExactLivePreflight,
  type ExactDeploymentVerification,
  type ExactReadClient
} from "../lib/exactVerification.ts";
import { type RuntimeConfig, toViemChain } from "../lib/chains.ts";
import { formatPls, formatPlsExact, formatShortHash } from "../lib/format.ts";

type StatusKind = "info" | "success" | "error";

type ExactInferenceConsoleProps = {
  config: RuntimeConfig;
  account: Address | null;
  walletChainMatches: boolean;
  isPendingTx: boolean;
  onPendingChange(pending: boolean): void;
  onStatus(kind: StatusKind, message: string, transactionHash?: Hex): void;
  onTransaction(hash: Hex): void;
};

type LoadedManifest = {
  manifest: ExactDeploymentManifest;
  manifestSha256: Hex;
};

type PendingExactIntent = {
  label: string;
  functionName: string;
  chainId: number;
  settlement: Address;
  account: Address;
  arguments: string[];
  valueWei: string;
};

type ExactTaskSnapshot = {
  taskId: bigint;
  status: number;
  netuid: number;
  mechid: number;
  protocolFeeBps: number;
  verifierConfigId: bigint;
  createdAtBlock: bigint;
  deadlineBlock: bigint;
  requester: Address;
  refundTo: Address;
  treasury: Address;
  rewardWei: bigint;
  requestNullifier: Hex;
  inputCommitment: Hex;
  modelCommitment: Hex;
  taskSpecHash: Hex;
};

type ExactSnapshot = {
  blockNumber: bigint;
  nextTaskId: bigint;
  totalOpenTasks: bigint;
  totalOpenEscrowWei: bigint;
  totalClaimableWei: bigint;
  claimableWei: bigint;
  accountingInvariantHolds: boolean;
};

const emptySnapshot: ExactSnapshot = {
  blockNumber: 0n,
  nextTaskId: 1n,
  totalOpenTasks: 0n,
  totalOpenEscrowWei: 0n,
  totalClaimableWei: 0n,
  claimableWei: 0n,
  accountingInvariantHolds: false
};

function asErrorMessage(error: unknown): string {
  if (typeof error === "object" && error !== null) {
    const maybe = error as { shortMessage?: string; message?: string };
    return maybe.shortMessage ?? maybe.message ?? "Unknown error";
  }
  return String(error);
}

function tupleField<T>(value: unknown, name: string, index: number): T {
  if (Array.isArray(value)) return value[index] as T;
  if (typeof value === "object" && value !== null && name in value) {
    return (value as Record<string, unknown>)[name] as T;
  }
  throw new Error(`RPC returned a malformed task tuple: missing ${name}`);
}

function normalizeTask(value: unknown, taskId: bigint): ExactTaskSnapshot {
  return {
    taskId,
    status: Number(tupleField<number | bigint>(value, "status", 0)),
    netuid: Number(tupleField<number | bigint>(value, "netuid", 1)),
    mechid: Number(tupleField<number | bigint>(value, "mechid", 2)),
    protocolFeeBps: Number(tupleField<number | bigint>(value, "protocolFeeBps", 3)),
    verifierConfigId: BigInt(tupleField<number | bigint>(value, "verifierConfigId", 4)),
    createdAtBlock: BigInt(tupleField<number | bigint>(value, "createdAtBlock", 5)),
    deadlineBlock: BigInt(tupleField<number | bigint>(value, "deadlineBlock", 6)),
    requester: tupleField(value, "requester", 7),
    refundTo: tupleField(value, "refundTo", 8),
    treasury: tupleField(value, "treasury", 9),
    rewardWei: BigInt(tupleField<number | bigint>(value, "rewardWei", 10)),
    requestNullifier: tupleField(value, "requestNullifier", 11),
    inputCommitment: tupleField(value, "inputCommitment", 12),
    modelCommitment: tupleField(value, "modelCommitment", 13),
    taskSpecHash: tupleField(value, "taskSpecHash", 14)
  };
}

function configKey(config: ExactManifestVerifierConfig): string {
  return `${config.netuid}:${config.configId.toString()}`;
}

function randomUint64Decimal(): string {
  const bytes = new Uint32Array(2);
  crypto.getRandomValues(bytes);
  return ((BigInt(bytes[0]) << 32n) | BigInt(bytes[1])).toString();
}

function shouldReplaceAutoAddress(value: string, previousAccount: Address | null): boolean {
  return value.trim() === "" || (
    previousAccount !== null && value.toLowerCase() === previousAccount.toLowerCase()
  );
}

function sameTaskIdentity(left: ExactTaskSnapshot, right: ExactTaskSnapshot): boolean {
  return left.taskId === right.taskId &&
    left.status === right.status &&
    left.netuid === right.netuid &&
    left.mechid === right.mechid &&
    left.protocolFeeBps === right.protocolFeeBps &&
    left.verifierConfigId === right.verifierConfigId &&
    left.createdAtBlock === right.createdAtBlock &&
    left.deadlineBlock === right.deadlineBlock &&
    left.requester.toLowerCase() === right.requester.toLowerCase() &&
    left.refundTo.toLowerCase() === right.refundTo.toLowerCase() &&
    left.treasury.toLowerCase() === right.treasury.toLowerCase() &&
    left.rewardWei === right.rewardWei &&
    left.requestNullifier.toLowerCase() === right.requestNullifier.toLowerCase() &&
    left.inputCommitment.toLowerCase() === right.inputCommitment.toLowerCase() &&
    left.modelCommitment.toLowerCase() === right.modelCommitment.toLowerCase() &&
    left.taskSpecHash.toLowerCase() === right.taskSpecHash.toLowerCase();
}

function displayIntentArgument(value: unknown): string {
  if (typeof value === "bigint") return value.toString();
  if (Array.isArray(value)) return `[${value.map(displayIntentArgument).join(", ")}]`;
  return String(value);
}

export function ExactInferenceConsole({
  config,
  account,
  walletChainMatches,
  isPendingTx,
  onPendingChange,
  onStatus,
  onTransaction
}: ExactInferenceConsoleProps) {
  const [manifestUrl, setManifestUrl] = useState(import.meta.env.VITE_EXACT_MANIFEST_URL ?? "");
  const [manifestDigest, setManifestDigest] = useState(import.meta.env.VITE_EXACT_MANIFEST_SHA256 ?? "");
  const [loaded, setLoaded] = useState<LoadedManifest | null>(null);
  const [verification, setVerification] = useState<ExactDeploymentVerification | null>(null);
  const [isManifestLoading, setIsManifestLoading] = useState(false);
  const [pendingIntent, setPendingIntent] = useState<PendingExactIntent | null>(null);
  const manifestRequestGeneration = useRef(0);
  const activeManifestRequest = useRef<AbortController | null>(null);
  const writeInFlight = useRef(false);
  const artifactRequestGeneration = useRef(0);
  const [selectedConfigKey, setSelectedConfigKey] = useState("");
  const [snapshot, setSnapshot] = useState<ExactSnapshot>(emptySnapshot);
  const [taskQuery, setTaskQuery] = useState("");
  const [task, setTask] = useState<ExactTaskSnapshot | null>(null);
  const [lastRefreshAt, setLastRefreshAt] = useState<number | null>(null);

  const [artifactText, setArtifactText] = useState("");
  const [artifact, setArtifact] = useState<PreparedTaskArtifact | null>(null);

  const [createForm, setCreateForm] = useState(() => ({
    mechid: "0",
    inputCommitment: "",
    modelCommitment: "",
    requesterNonce: randomUint64Decimal(),
    deadlineBlock: "",
    refundTo: "",
    rewardPls: "1"
  }));
  const [proofForm, setProofForm] = useState({
    taskId: "",
    provider: "",
    beneficiary: "",
    classIndex: "0",
    scores: ["0", "0", "0", "0"] as [string, string, string, string],
    proof: ""
  });
  const [recoveryTaskId, setRecoveryTaskId] = useState("");
  const [claimForm, setClaimForm] = useState({ to: "", amountPls: "" });

  const publicClient = useMemo(
    () => createPublicClient({
      chain: toViemChain(config),
      ccipRead: false,
      transport: http(config.rpcUrl, {
        fetchOptions: { credentials: "omit", redirect: "error", referrerPolicy: "no-referrer" }
      })
    }),
    [config]
  );
  const routeKey = `${config.chainId}|${config.rpcUrl}`;
  const previousRouteKey = useRef(routeKey);
  const previousAccount = useRef<Address | null>(account);
  const contextKey = `${routeKey}|${loaded?.manifestSha256 ?? "unloaded"}|${account ?? "disconnected"}|${walletChainMatches ? "wallet-match" : "wallet-mismatch"}`;
  const contextKeyRef = useRef(contextKey);
  contextKeyRef.current = contextKey;
  const writeIntentKey = JSON.stringify({
    selectedConfigKey,
    createForm,
    proofForm,
    recoveryTaskId,
    claimForm
  });
  const writeIntentKeyRef = useRef(writeIntentKey);
  writeIntentKeyRef.current = writeIntentKey;

  useEffect(() => {
    if (previousRouteKey.current !== routeKey) {
      previousRouteKey.current = routeKey;
      manifestRequestGeneration.current += 1;
      activeManifestRequest.current?.abort();
      setIsManifestLoading(false);
      setVerification(null);
      onStatus("info", "Chain or browsing RPC changed. Recheck the exact deployment before using marketplace actions.");
    }
  }, [onStatus, routeKey]);

  useEffect(() => {
    manifestRequestGeneration.current += 1;
    activeManifestRequest.current?.abort();
    setIsManifestLoading(false);
    const priorAccount = previousAccount.current;
    previousAccount.current = account;
    setCreateForm((previous) => ({
      ...previous,
      refundTo: shouldReplaceAutoAddress(previous.refundTo, priorAccount) ? account ?? "" : previous.refundTo
    }));
    setProofForm((previous) => ({
      ...previous,
      provider: shouldReplaceAutoAddress(previous.provider, priorAccount) ? account ?? "" : previous.provider,
      beneficiary: shouldReplaceAutoAddress(previous.beneficiary, priorAccount)
        ? account ?? ""
        : previous.beneficiary
    }));
    setClaimForm((previous) => ({
      ...previous,
      to: shouldReplaceAutoAddress(previous.to, priorAccount) ? account ?? "" : previous.to
    }));
    setSnapshot((previous) => ({ ...previous, claimableWei: 0n }));
  }, [account]);

  useEffect(() => () => activeManifestRequest.current?.abort(), []);

  const selectedManifestConfig = useMemo(() => {
    if (!loaded || !selectedConfigKey) return null;
    return loaded.manifest.verifierConfigs.find((item) => configKey(item) === selectedConfigKey) ?? null;
  }, [loaded, selectedConfigKey]);

  async function readSnapshot(
    manifest: ExactDeploymentManifest,
    taskIdRaw = taskQuery,
    requestGeneration = manifestRequestGeneration.current,
    expectedContextKey?: string
  ): Promise<boolean> {
    const address = manifest.exactSettlement.address;
    const observedAccount = account;
    const blockNumber = await publicClient.getBlockNumber();
    const [nextTaskId, totalOpenTasks, totalOpenEscrowWei, totalClaimableWei, accounting] = await Promise.all([
      publicClient.readContract({ address, abi: pulsetensorExactInferenceAbi, functionName: "nextTaskId", blockNumber }),
      publicClient.readContract({ address, abi: pulsetensorExactInferenceAbi, functionName: "totalOpenTasks", blockNumber }),
      publicClient.readContract({ address, abi: pulsetensorExactInferenceAbi, functionName: "totalOpenEscrowWei", blockNumber }),
      publicClient.readContract({ address, abi: pulsetensorExactInferenceAbi, functionName: "totalClaimableWei", blockNumber }),
      publicClient.readContract({ address, abi: pulsetensorExactInferenceAbi, functionName: "accountingInvariantHolds", blockNumber })
    ]);
    const accountClaimable = observedAccount
      ? await publicClient.readContract({
          address,
          abi: pulsetensorExactInferenceAbi,
          functionName: "claimableWei",
          args: [observedAccount],
          blockNumber
        })
      : 0n;

    let normalizedTaskId = taskIdRaw;
    if (normalizedTaskId.trim() === "" && nextTaskId > 1n) normalizedTaskId = (nextTaskId - 1n).toString();
    let nextTask: ExactTaskSnapshot | null = null;
    if (normalizedTaskId.trim() !== "") {
      const taskId = parseUint256Strict(normalizedTaskId, "Task ID");
      const rawTask = await publicClient.readContract({
        address,
        abi: pulsetensorExactInferenceAbi,
        functionName: "exactInferenceTasks",
        args: [taskId],
        blockNumber
      });
      nextTask = normalizeTask(rawTask, taskId);
    }

    if (
      manifestRequestGeneration.current !== requestGeneration ||
      (expectedContextKey !== undefined && contextKeyRef.current !== expectedContextKey)
    ) return false;
    setSnapshot({
      blockNumber,
      nextTaskId,
      totalOpenTasks,
      totalOpenEscrowWei,
      totalClaimableWei,
      claimableWei: accountClaimable,
      accountingInvariantHolds: accounting
    });
    setTask(nextTask);
    if (nextTask) {
      const taskId = nextTask.taskId;
      setTaskQuery(taskId.toString());
      setProofForm((previous) => ({ ...previous, taskId: taskId.toString() }));
      setRecoveryTaskId(taskId.toString());
    }
    setLastRefreshAt(Date.now());
    return true;
  }

  async function retainAndReviewManifest(
    result: { manifest: ExactDeploymentManifest; manifestSha256: Hex },
    requestGeneration: number
  ): Promise<void> {
    if (manifestRequestGeneration.current !== requestGeneration) return;
    setLoaded({ manifest: result.manifest, manifestSha256: result.manifestSha256 });
    setVerification(null);
    const first = result.manifest.verifierConfigs[0];
    setSelectedConfigKey(configKey(first));
    setCreateForm((previous) => ({
      ...previous,
      refundTo: previous.refundTo || account || ""
    }));
    setProofForm((previous) => ({
      ...previous,
      provider: previous.provider || account || "",
      beneficiary: previous.beneficiary || account || ""
    }));
    setClaimForm((previous) => ({ ...previous, to: previous.to || account || "" }));
    onStatus(
      "info",
      "Manifest bytes and reviewed digest match. Running archive-backed deployment/config review; injected-wallet recovery is available even if that review RPC is unavailable."
    );

    let nextVerification: ExactDeploymentVerification;
    try {
      nextVerification = await verifyExactDeployment(
        publicClient as unknown as ExactReadClient,
        result.manifest
      );
    } catch (error) {
      if (manifestRequestGeneration.current !== requestGeneration) return;
      onStatus(
        "error",
        `Manifest digest verified, but full archive-backed review is unavailable: ${asErrorMessage(error)}. Creation/proof remain blocked; recovery still uses live wallet preflight.`
      );
      return;
    }
    if (manifestRequestGeneration.current !== requestGeneration) return;
    setVerification(nextVerification);
    setCreateForm((previous) => ({
      ...previous,
      deadlineBlock: (nextVerification.checkedBlockNumber + 1_200n).toString()
    }));

    try {
      if (!(await readSnapshot(result.manifest, taskQuery, requestGeneration))) return;
    } catch (error) {
      if (manifestRequestGeneration.current !== requestGeneration) return;
      onStatus(
        "error",
        `Deployment review completed, but the marketplace snapshot is unavailable: ${asErrorMessage(error)}. Recovery remains available through wallet preflight.`
      );
      return;
    }
    if (!nextVerification.identityVerified) {
      onStatus("error", `Manifest loaded, but chain identity failed: ${nextVerification.identityIssues[0]}`);
    } else if (!nextVerification.admissionVerified) {
      onStatus("info", "Deployment identity verified. No reviewed configuration currently accepts new tasks.");
    } else {
      onStatus("success", "Deployment identity and at least one exact-ZK admission path verified by browsing RPC.");
    }
  }

  async function loadAndVerifyManifest(): Promise<void> {
    const requestGeneration = manifestRequestGeneration.current + 1;
    manifestRequestGeneration.current = requestGeneration;
    activeManifestRequest.current?.abort();
    const abortController = new AbortController();
    activeManifestRequest.current = abortController;
    setIsManifestLoading(true);
    try {
      onStatus("info", "Fetching and digest-checking the exact-inference manifest.");
      const result = await loadDigestPinnedManifest(manifestUrl, manifestDigest, fetch, {
        signal: abortController.signal
      });
      if (abortController.signal.aborted || manifestRequestGeneration.current !== requestGeneration) return;
      await retainAndReviewManifest(result, requestGeneration);
    } catch (error) {
      if (manifestRequestGeneration.current !== requestGeneration) return;
      setLoaded(null);
      setVerification(null);
      onStatus("error", asErrorMessage(error));
    } finally {
      if (activeManifestRequest.current === abortController) activeManifestRequest.current = null;
      if (manifestRequestGeneration.current === requestGeneration) setIsManifestLoading(false);
    }
  }

  async function loadLocalManifest(file: File): Promise<void> {
    const requestGeneration = manifestRequestGeneration.current + 1;
    manifestRequestGeneration.current = requestGeneration;
    activeManifestRequest.current?.abort();
    setIsManifestLoading(true);
    try {
      if (file.size === 0 || file.size > MAX_EXACT_MANIFEST_BYTES) {
        throw new Error(`Manifest file must be between 1 and ${MAX_EXACT_MANIFEST_BYTES} bytes`);
      }
      onStatus("info", `Digest-checking local manifest ${file.name}.`);
      const bytes = new Uint8Array(await file.arrayBuffer());
      if (manifestRequestGeneration.current !== requestGeneration) return;
      const result = await parseDigestPinnedManifestBytes(bytes, manifestDigest);
      if (manifestRequestGeneration.current !== requestGeneration) return;
      await retainAndReviewManifest(result, requestGeneration);
    } catch (error) {
      if (manifestRequestGeneration.current !== requestGeneration) return;
      setLoaded(null);
      setVerification(null);
      onStatus("error", asErrorMessage(error));
    } finally {
      if (manifestRequestGeneration.current === requestGeneration) setIsManifestLoading(false);
    }
  }

  async function recheckAndRefresh(options: {
    silent?: boolean;
    expectedContextKey?: string;
  } = {}): Promise<boolean> {
    if (!loaded) {
      if (!options.silent) onStatus("error", "Load a digest-pinned manifest first.");
      return false;
    }
    const expectedContextKey = options.expectedContextKey ?? contextKey;
    if (contextKeyRef.current !== expectedContextKey) return false;
    const requestGeneration = manifestRequestGeneration.current + 1;
    manifestRequestGeneration.current = requestGeneration;
    if (!options.silent) setIsManifestLoading(true);
    let verificationCompleted = false;
    try {
      const nextVerification = await verifyExactDeployment(
        publicClient as unknown as ExactReadClient,
        loaded.manifest
      );
      if (
        manifestRequestGeneration.current !== requestGeneration ||
        contextKeyRef.current !== expectedContextKey
      ) return false;
      setVerification(nextVerification);
      verificationCompleted = true;
      if (!(await readSnapshot(loaded.manifest, taskQuery, requestGeneration, expectedContextKey))) return false;
      if (!options.silent) {
        onStatus(
          nextVerification.identityVerified ? "success" : "error",
          nextVerification.identityVerified
            ? "Exact deployment state refreshed."
            : `Exact deployment identity failed: ${nextVerification.identityIssues[0]}`
        );
      }
      return true;
    } catch (error) {
      if (
        manifestRequestGeneration.current !== requestGeneration ||
        contextKeyRef.current !== expectedContextKey
      ) return false;
      if (!verificationCompleted) setVerification(null);
      if (!options.silent) onStatus("error", asErrorMessage(error));
      return false;
    } finally {
      if (!options.silent && manifestRequestGeneration.current === requestGeneration) setIsManifestLoading(false);
    }
  }

  async function refreshObservedMarketplace(): Promise<void> {
    if (!loaded) {
      onStatus("error", "Load a digest-pinned manifest first.");
      return;
    }
    const requestGeneration = manifestRequestGeneration.current + 1;
    manifestRequestGeneration.current = requestGeneration;
    const expectedContextKey = contextKey;
    try {
      if (!(await readSnapshot(loaded.manifest, taskQuery, requestGeneration, expectedContextKey))) return;
      onStatus("success", "Marketplace observation refreshed through the configured browsing RPC.");
    } catch (error) {
      if (
        manifestRequestGeneration.current !== requestGeneration ||
        contextKeyRef.current !== expectedContextKey
      ) return;
      setTask(null);
      onStatus("error", asErrorMessage(error));
    }
  }

  async function runExactWrite({
    label,
    functionName,
    args,
    value,
    gate,
    gateConfig,
    taskId
  }: {
    label: string;
    functionName: "createExactInferenceTask" | "submitExactInferenceProof" | "refundExpired" | "refundRevoked" | "refundVerifierUnavailable" | "claim";
    args: readonly unknown[];
    value?: bigint;
    gate: "recovery" | "admission" | "settlement";
    gateConfig?: { netuid: number; configId: bigint };
    taskId?: bigint;
  }): Promise<boolean> {
    if (!loaded) throw new Error("Load a digest-pinned deployment manifest first");
    if (!window.ethereum) throw new Error("No injected wallet found");
    if (!account) throw new Error("Connect a wallet first");
    if (!walletChainMatches) throw new Error(`Switch the wallet to chain ${config.chainId} first`);
    if (writeInFlight.current) throw new Error("Another exact-settlement transaction is already in progress");

    if (gate === "admission") {
      if (!gateConfig || Number(args[0]) !== gateConfig.netuid || BigInt(args[2] as bigint) !== gateConfig.configId) {
        throw new Error("Admission preflight configuration does not match the transaction calldata");
      }
    }
    if (gate === "settlement" && (taskId === undefined || BigInt(args[0] as bigint) !== taskId)) {
      throw new Error("Proof-settlement preflight task does not match the transaction calldata");
    }

    // Invalidate any older browsing review before capturing the signing intent. That
    // prevents a late observation/status update from visually replacing this write.
    manifestRequestGeneration.current += 1;
    activeManifestRequest.current?.abort();
    activeManifestRequest.current = null;
    setIsManifestLoading(false);
    const expectedContextKey = contextKey;
    const expectedIntentKey = writeIntentKey;
    const expectedGeneration = manifestRequestGeneration.current;
    const expectedAccount = account;
    const assertCurrentIntent = () => {
      if (
        contextKeyRef.current !== expectedContextKey ||
        manifestRequestGeneration.current !== expectedGeneration ||
        writeIntentKeyRef.current !== expectedIntentKey
      ) {
        throw new Error("Wallet, route, manifest, or transaction fields changed during preflight; review and submit again");
      }
    };

    writeInFlight.current = true;
    setPendingIntent({
      label,
      functionName,
      chainId: config.chainId,
      settlement: loaded.manifest.exactSettlement.address,
      account: expectedAccount,
      arguments: args.map(displayIntentArgument),
      valueWei: (value ?? 0n).toString()
    });
    onPendingChange(true);
    let submittedHash: Hex | undefined;
    try {
      assertCurrentIntent();
      const injectedPublicClient = createPublicClient({
        chain: toViemChain(config),
        ccipRead: false,
        transport: custom(window.ethereum)
      });
      let effectiveGateConfig = gateConfig;
      if (gate === "settlement") {
        if (taskId === undefined) throw new Error("Settlement task ID is missing");
        const rawTask = await injectedPublicClient.readContract({
          address: loaded.manifest.exactSettlement.address,
          abi: pulsetensorExactInferenceAbi,
          functionName: "exactInferenceTasks",
          args: [taskId]
        });
        const currentTask = normalizeTask(rawTask, taskId);
        if (currentTask.status !== 1) throw new Error("The exact-inference task is not open");
        if (!task || !sameTaskIdentity(currentTask, task)) {
          throw new Error("Injected-wallet task identity differs from the reviewed browsing snapshot; refresh and inspect before signing");
        }
        effectiveGateConfig = {
          netuid: currentTask.netuid,
          configId: currentTask.verifierConfigId
        };
      }

      const livePreflight = await verifyExactLivePreflight(
        injectedPublicClient as unknown as ExactReadClient,
        loaded.manifest,
        gate,
        effectiveGateConfig
      );
      if (!livePreflight.actionVerified) {
        throw new Error(`Injected-wallet ${gate} preflight failed: ${livePreflight.actionIssues[0]}`);
      }
      assertCurrentIntent();

      const walletClient = createWalletClient({ chain: toViemChain(config), transport: custom(window.ethereum) });
      const [finalChainId, injectedAccounts] = await Promise.all([
        walletClient.getChainId(),
        walletClient.getAddresses()
      ]);
      if (finalChainId !== config.chainId) {
        throw new Error(`Connected wallet changed to chain ${finalChainId}; expected ${config.chainId}`);
      }
      if (!injectedAccounts[0] || injectedAccounts[0].toLowerCase() !== expectedAccount.toLowerCase()) {
        throw new Error("Connected account changed; reconnect before signing");
      }
      assertCurrentIntent();
      onStatus("info", `${label}: injected-wallet action preflight verified; awaiting wallet confirmation.`);
      const simulation = await injectedPublicClient.simulateContract({
        account,
        address: loaded.manifest.exactSettlement.address,
        abi: pulsetensorExactInferenceAbi,
        functionName,
        args: args as never,
        value
      } as never);
      assertCurrentIntent();
      const hash = await (
        walletClient as unknown as { writeContract(request: unknown): Promise<Hex> }
      ).writeContract(simulation.request);
      submittedHash = hash;
      onTransaction(hash);
      onStatus("info", `${label}: submitted ${formatShortHash(hash)}; waiting for confirmation.`, hash);
      const receipt = await injectedPublicClient.waitForTransactionReceipt({ hash });
      if (receipt.status !== "success") throw new Error(`${label}: transaction reverted on-chain`);
      const refreshed = await recheckAndRefresh({ silent: true, expectedContextKey });
      onStatus(
        "success",
        `${label}: confirmed ${formatShortHash(hash)} at block ${receipt.blockNumber.toString()}.${refreshed ? " Marketplace state refreshed." : " Browsing snapshot was not refreshed; do not resubmit this confirmed transaction."}`,
        hash
      );
      return true;
    } catch (error) {
      onStatus("error", asErrorMessage(error), submittedHash);
      return false;
    } finally {
      writeInFlight.current = false;
      setPendingIntent(null);
      onPendingChange(false);
    }
  }

  async function prepareArtifact(): Promise<void> {
    const requestGeneration = artifactRequestGeneration.current + 1;
    artifactRequestGeneration.current = requestGeneration;
    const input = artifactText;
    try {
      const next = await prepareTaskArtifact(input);
      if (artifactRequestGeneration.current !== requestGeneration) return;
      setArtifact(next);
      onStatus("success", "Artifact distribution digest and raw CID computed from exact UTF-8 bytes.");
    } catch (error) {
      if (artifactRequestGeneration.current !== requestGeneration) return;
      setArtifact(null);
      onStatus("error", asErrorMessage(error));
    }
  }

  function downloadArtifact(): void {
    if (!artifact) return;
    const bytes = new ArrayBuffer(artifact.bytes.byteLength);
    new Uint8Array(bytes).set(artifact.bytes);
    const blob = new Blob([bytes], { type: "application/octet-stream" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = "pulsetensor-task-artifact.bin";
    link.click();
    URL.revokeObjectURL(url);
  }

  async function createTask(): Promise<void> {
    try {
      if (!selectedManifestConfig) throw new Error("Select a reviewed verifier configuration");
      const mechid = parseUint16Strict(createForm.mechid, "Mechanism ID");
      if (mechid > 1_023) throw new Error("Mechanism ID must be between 0 and 1023");
      const nonce = parseUint64Strict(createForm.requesterNonce, "Requester nonce");
      const deadline = parseUint64Strict(createForm.deadlineBlock, "Deadline block");
      if (deadline <= snapshot.blockNumber || deadline > snapshot.blockNumber + 200_000n) {
        throw new Error("Deadline must be after the current block and no more than 200,000 blocks ahead");
      }
      const refundTo = parseAddressStrict(createForm.refundTo, "Refund address");
      const inputCommitment = parseBytes32Strict(createForm.inputCommitment, "Input semantic commitment", false);
      const modelCommitment = parseBytes32Strict(createForm.modelCommitment, "Model semantic commitment", false);
      const reward = parseEther(createForm.rewardPls);
      if (reward <= 0n) throw new Error("Reward must be greater than zero PLS");
      const confirmed = await runExactWrite({
        label: "Create exact-inference task",
        functionName: "createExactInferenceTask",
        args: [
          selectedManifestConfig.netuid,
          mechid,
          selectedManifestConfig.configId,
          inputCommitment,
          modelCommitment,
          nonce,
          deadline,
          refundTo
        ],
        value: reward,
        gate: "admission",
        gateConfig: {
          netuid: selectedManifestConfig.netuid,
          configId: selectedManifestConfig.configId
        }
      });
      if (confirmed) {
        setCreateForm((previous) => ({ ...previous, requesterNonce: randomUint64Decimal() }));
      }
    } catch (error) {
      onStatus("error", asErrorMessage(error));
    }
  }

  async function submitProof(): Promise<void> {
    try {
      if (!loaded) throw new Error("Load a digest-pinned manifest first");
      const taskId = parseUint256Strict(proofForm.taskId, "Task ID");
      const knownTask = task && task.taskId === taskId ? task : null;
      if (!knownTask) throw new Error("Refresh this task before submitting its proof");
      const reviewedConfig = loaded.manifest.verifierConfigs.find(
        (item) => item.netuid === knownTask.netuid && item.configId === knownTask.verifierConfigId
      );
      if (!reviewedConfig) throw new Error("Task verifier configuration is not in the reviewed manifest");
      const provider = parseAddressStrict(proofForm.provider, "Provider");
      const beneficiary = parseAddressStrict(proofForm.beneficiary, "Beneficiary");
      const classIndex = parseExactClassIndex(proofForm.classIndex, "Class index");
      const scores = parseExactScores(proofForm.scores, "Scores");
      const proof = parseProofHex(proofForm.proof, {
        label: "RISC Zero seal",
        expectedSelector: reviewedConfig.proofSelector,
        expectedByteLength: reviewedConfig.proofBytes
      });
      await runExactWrite({
        label: "Submit exact-inference proof",
        functionName: "submitExactInferenceProof",
        args: [taskId, provider, beneficiary, Number(classIndex), scores, proof],
        gate: "settlement",
        taskId
      });
    } catch (error) {
      onStatus("error", asErrorMessage(error));
    }
  }

  async function refund(functionName: "refundExpired" | "refundRevoked" | "refundVerifierUnavailable", label: string) {
    try {
      const taskId = parseUint256Strict(recoveryTaskId, "Task ID");
      await runExactWrite({ label, functionName, args: [taskId], gate: "recovery" });
    } catch (error) {
      onStatus("error", asErrorMessage(error));
    }
  }

  async function claim(): Promise<void> {
    try {
      const to = parseAddressStrict(claimForm.to, "Claim recipient");
      const amount = parseEther(claimForm.amountPls);
      if (amount <= 0n) throw new Error("Claim amount must be greater than zero PLS");
      await runExactWrite({ label: "Claim exact-settlement balance", functionName: "claim", args: [to, amount], gate: "recovery" });
    } catch (error) {
      onStatus("error", asErrorMessage(error));
    }
  }

  const selectedVerification =
    verification && selectedManifestConfig
      ? findVerifiedConfig(verification, selectedManifestConfig.netuid, selectedManifestConfig.configId)
      : undefined;
  const selectedAdmissionReady = Boolean(
    account &&
    walletChainMatches &&
    verification?.identityVerified &&
    verification.coreRuntimeCodeHashMatches &&
    selectedVerification?.acceptsNewTasks &&
    selectedVerification.codeAvailable &&
    !selectedVerification.revoked &&
    !selectedVerification.corePaused &&
    selectedVerification.governanceConfigured
  );
  const taskVerification =
    verification && task
      ? findVerifiedConfig(verification, task.netuid, task.verifierConfigId)
      : undefined;
  const proofSubmissionReady = Boolean(
    account &&
    walletChainMatches &&
    verification?.settlementIdentityVerified &&
    taskVerification?.identityIssues.length === 0 &&
    task?.status === 1 &&
    taskVerification?.canSettleOpenTasks &&
    taskVerification.codeAvailable
  );
  const recoveryActionReady = Boolean(loaded && account && walletChainMatches);
  const reviewedConfig = loaded?.manifest.verifierConfigs[0];

  return (
    <fieldset className="fieldset-reset exact-console" disabled={isPendingTx}>
      {pendingIntent ? (
        <section className="card pending-intent" aria-live="polite">
          <h2>Locked Transaction Intent</h2>
          <p className="warning-note">
            Compare this immutable intent with the wallet prompt. Marketplace controls stay frozen until the prompt
            and receipt complete.
          </p>
          <dl>
            <dt>Action</dt><dd>{pendingIntent.label} (<code>{pendingIntent.functionName}</code>)</dd>
            <dt>Chain / account</dt><dd>{pendingIntent.chainId} / <code>{pendingIntent.account}</code></dd>
            <dt>Settlement</dt><dd><code>{pendingIntent.settlement}</code></dd>
            <dt>Value (wei)</dt><dd><code>{pendingIntent.valueWei}</code></dd>
            <dt>Arguments</dt>
            <dd><ol>{pendingIntent.arguments.map((argument, index) => <li key={index}><code>{argument}</code></li>)}</ol></dd>
          </dl>
        </section>
      ) : null}
      <section className="card">
        <h2>Exact-ZK Marketplace Trust Root (Prelaunch)</h2>
        <p className="note">
          The SHA-256 digest is the user/community review root. Matching it proves byte integrity, not that an
          unreviewed publisher is trustworthy. Full review requires an archive-capable browsing RPC; each
          value-moving call is then rechecked through the injected wallet using only its action dependencies.
        </p>
        <p className="warning-note">
          ZK proves the computation relation, not wallet anonymity. Requester, refund, provider, beneficiary and
          treasury addresses, rewards, commitments and transfers are public and linkable on-chain. Separate
          operational wallets can reduce accidental linkage, but do not create anonymity; never enter private keys
          or seed phrases here.
        </p>
        <div className="form-grid">
          <label>
            Manifest HTTPS URL
            <input
              value={manifestUrl}
              onChange={(event) => {
                manifestRequestGeneration.current += 1;
                activeManifestRequest.current?.abort();
                setIsManifestLoading(false);
                setManifestUrl(event.target.value);
                setLoaded(null);
                setVerification(null);
                setTask(null);
              }}
              placeholder="https://.../exact-manifest.json"
            />
          </label>
          <label>
            Reviewed Manifest SHA-256
            <input
              value={manifestDigest}
              onChange={(event) => {
                manifestRequestGeneration.current += 1;
                activeManifestRequest.current?.abort();
                setIsManifestLoading(false);
                setManifestDigest(event.target.value);
                setLoaded(null);
                setVerification(null);
                setTask(null);
              }}
              placeholder="0x..."
            />
          </label>
          <label>
            Local Manifest File (Emergency/Offline Copy)
            <input
              type="file"
              accept="application/json,.json"
              disabled={isPendingTx || isManifestLoading}
              onChange={(event) => {
                const file = event.currentTarget.files?.[0];
                event.currentTarget.value = "";
                if (file) void loadLocalManifest(file);
              }}
            />
          </label>
        </div>
        <div className="button-row">
          <button type="button" onClick={() => void loadAndVerifyManifest()} disabled={isPendingTx || isManifestLoading}>
            {isManifestLoading ? "Verifying…" : "Load & Verify"}
          </button>
          <button type="button" className="secondary" onClick={() => void recheckAndRefresh()} disabled={!loaded || isManifestLoading}>
            Recheck Chain
          </button>
        </div>
        <p className="note">The local-file path never uploads the manifest; it applies the same reviewed SHA-256 and strict parser, so recovery does not depend on the manifest host remaining online.</p>
        <div className="metrics-grid">
          <div><span>Manifest digest</span><strong title={loaded?.manifestSha256}>{loaded ? formatShortHash(loaded.manifestSha256) : "-"}</strong></div>
          <div><span>Source commit</span><strong>{loaded ? formatShortHash(loaded.manifest.sourceCommit) : "-"}</strong></div>
          <div><span>Settlement recovery identity</span><strong>{verification?.settlementIdentityVerified ? "verified" : "blocked"}</strong></div>
          <div><span>Verifier/config identity</span><strong>{verification?.identityVerified ? "verified" : "blocked"}</strong></div>
          <div><span>New-task admission</span><strong>{verification?.admissionVerified ? "available" : "blocked"}</strong></div>
        </div>
        {loaded && reviewedConfig ? (
          <details className="exact-details">
            <summary>Reviewed deployment identity and evidence</summary>
            <dl>
              <dt>Manifest SHA-256</dt><dd><code>{loaded.manifestSha256}</code></dd>
              <dt>Source commit</dt><dd><code>{loaded.manifest.sourceCommit}</code></dd>
              <dt>Chain / anchor / confirmations</dt><dd>{loaded.manifest.chainId} / {loaded.manifest.deploymentAnchor.blockNumber.toString()} / {loaded.manifest.deploymentAnchor.minimumConfirmations}<br /><code>{loaded.manifest.deploymentAnchor.blockHash}</code></dd>
              <dt>Exact settlement</dt><dd><code>{loaded.manifest.exactSettlement.address}</code></dd>
              <dt>Settlement code hash</dt><dd><code>{loaded.manifest.exactSettlement.runtimeCodeHash}</code></dd>
              <dt>Core</dt><dd><code>{loaded.manifest.core.address}</code></dd>
              <dt>Core code hash</dt><dd><code>{loaded.manifest.core.runtimeCodeHash}</code></dd>
              <dt>Subnet / config</dt><dd>{reviewedConfig.netuid} / {reviewedConfig.configId.toString()}</dd>
              <dt>Adapter / code hash</dt><dd><code>{reviewedConfig.adapter}</code><br /><code>{reviewedConfig.adapterRuntimeCodeHash}</code></dd>
              <dt>Base verifier / code hash</dt><dd><code>{reviewedConfig.baseVerifier}</code><br /><code>{reviewedConfig.verifierRuntimeCodeHash}</code></dd>
              <dt>Program / relation</dt><dd><code>{reviewedConfig.programId}</code><br /><code>{reviewedConfig.relationId}</code></dd>
              <dt>Proof system / selector</dt><dd><code>{reviewedConfig.proofSystemId}</code><br /><code>{reviewedConfig.proofSelector}</code></dd>
              <dt>Verifier version / seal</dt><dd><code>{reviewedConfig.verifierVersionHash}</code> / {reviewedConfig.proofBytes} bytes</dd>
              <dt>Fee / treasury</dt><dd>{reviewedConfig.protocolFeeBps} bps / <code>{reviewedConfig.treasury}</code></dd>
              <dt>Guest source (unverified link)</dt><dd className="evidence-item"><a href={loaded.manifest.evidence.guestSourceUri} target="_blank" rel="noreferrer">{loaded.manifest.evidence.guestSourceUri}</a><code>{loaded.manifest.evidence.guestSourceSha256}</code></dd>
              <dt>Build recipe (unverified link)</dt><dd className="evidence-item"><a href={loaded.manifest.evidence.guestBuildRecipeUri} target="_blank" rel="noreferrer">{loaded.manifest.evidence.guestBuildRecipeUri}</a><code>{loaded.manifest.evidence.guestBuildRecipeSha256}</code></dd>
              <dt>Genuine receipt (unverified link)</dt><dd className="evidence-item"><a href={loaded.manifest.evidence.genuineReceiptUri} target="_blank" rel="noreferrer">{loaded.manifest.evidence.genuineReceiptUri}</a><code>{loaded.manifest.evidence.genuineReceiptSha256}</code></dd>
              <dt>Audit report (unverified link)</dt><dd className="evidence-item"><a href={loaded.manifest.evidence.auditReportUri} target="_blank" rel="noreferrer">{loaded.manifest.evidence.auditReportUri}</a><code>{loaded.manifest.evidence.auditReportSha256}</code></dd>
              <dt>Testnet receipt (unverified link)</dt><dd className="evidence-item"><a href={loaded.manifest.evidence.pulsechainTestnetReceiptUri} target="_blank" rel="noreferrer">{loaded.manifest.evidence.pulsechainTestnetReceiptUri}</a><code>{loaded.manifest.evidence.pulsechainTestnetReceiptSha256}</code></dd>
            </dl>
            <p className="note">Opening an evidence link does not verify mutable HTTPS/IPFS gateway bytes. Download with a bounded client and compare SHA-256 to the adjacent reviewed digest before trusting it.</p>
          </details>
        ) : null}
        {verification && verification.identityIssues.length > 0 ? (
          <ul className="assurance-list exact-issues">
            {verification.identityIssues.slice(0, 8).map((issue) => <li key={issue}>{issue}</li>)}
          </ul>
        ) : null}
      </section>

      <section className="card">
        <h2>Marketplace Monitor</h2>
        <div className="inline-form">
          <label>
            Reviewed verifier configuration
            <select value={selectedConfigKey} onChange={(event) => setSelectedConfigKey(event.target.value)} disabled={!loaded}>
              {loaded?.manifest.verifierConfigs.map((item) => (
                <option key={configKey(item)} value={configKey(item)}>
                  subnet {item.netuid} · config {item.configId.toString()} · fee {item.protocolFeeBps} bps
                </option>
              ))}
            </select>
          </label>
          <label>
            Task ID
            <input
              value={taskQuery}
              onChange={(event) => {
                manifestRequestGeneration.current += 1;
                activeManifestRequest.current?.abort();
                setTaskQuery(event.target.value);
                setTask(null);
              }}
              inputMode="numeric"
            />
          </label>
          <button type="button" className="secondary" onClick={() => void refreshObservedMarketplace()} disabled={!loaded}>
            Refresh
          </button>
        </div>
        <div className="metrics-grid">
          <div><span>Observed block</span><strong>{snapshot.blockNumber.toString()}</strong></div>
          <div><span>Next task ID</span><strong>{snapshot.nextTaskId.toString()}</strong></div>
          <div><span>Open tasks</span><strong>{snapshot.totalOpenTasks.toString()}</strong></div>
          <div><span>Open escrow</span><strong title={formatPlsExact(snapshot.totalOpenEscrowWei)}>{formatPls(snapshot.totalOpenEscrowWei)}</strong></div>
          <div><span>Total claimable</span><strong title={formatPlsExact(snapshot.totalClaimableWei)}>{formatPls(snapshot.totalClaimableWei)}</strong></div>
          <div><span>Your claimable</span><strong title={formatPlsExact(snapshot.claimableWei)}>{formatPls(snapshot.claimableWei)}</strong></div>
          <div><span>Accounting invariant</span><strong>{snapshot.accountingInvariantHolds ? "holds" : "not verified"}</strong></div>
          <div><span>Last refresh</span><strong>{lastRefreshAt ? new Date(lastRefreshAt).toLocaleTimeString() : "never"}</strong></div>
        </div>
        {selectedVerification ? (
          <p className="note">
            Selected config: {selectedVerification.revoked ? "revoked" : "not revoked"}; code {selectedVerification.codeAvailable ? "available" : "unavailable"}; new tasks {selectedVerification.acceptsNewTasks ? "accepted" : "blocked"}; open-task proofs {selectedVerification.canSettleOpenTasks ? "accepted" : "blocked"}.
          </p>
        ) : null}
        {task ? (
          <div className="exact-task">
            <strong>Task {task.taskId.toString()}: {exactTaskStatusLabel(task.status)}</strong>
            <span>Subnet / mechanism / config: {task.netuid} / {task.mechid} / {task.verifierConfigId.toString()}</span>
            <span title={formatPlsExact(task.rewardWei)}>Reward: {formatPls(task.rewardWei)} · fee {task.protocolFeeBps} bps</span>
            <span>Created / deadline blocks: {task.createdAtBlock.toString()} / {task.deadlineBlock.toString()}</span>
            <span>Requester: {task.requester}</span>
            <span>Refund to: {task.refundTo}</span>
            <span>Treasury: {task.treasury}</span>
            <span>Request nullifier: {task.requestNullifier}</span>
            <span>Input commitment: {task.inputCommitment}</span>
            <span>Model commitment: {task.modelCommitment}</span>
            <span>Task spec: {task.taskSpecHash}</span>
          </div>
        ) : null}
      </section>

      <section className="card">
        <h2>Optional IPFS Artifact Helper</h2>
        <p className="note">
          This computes a raw CIDv1 and SHA-256 over exact public bytes for distribution integrity only. It does not
          derive the guest-defined semantic input/model commitments. IPFS content and gateway access are public;
          never paste wallet secrets, API keys, private prompts, or personal data.
        </p>
        <label className="proof-label">
          Public artifact bytes (UTF-8)
          <textarea value={artifactText} onChange={(event) => {
            artifactRequestGeneration.current += 1;
            setArtifactText(event.target.value);
            setArtifact(null);
          }} />
        </label>
        <div className="button-row">
          <button type="button" className="secondary" onClick={() => void prepareArtifact()}>Compute Distribution IDs</button>
          <button type="button" className="secondary" onClick={downloadArtifact} disabled={!artifact}>Download Exact Bytes</button>
        </div>
        {artifact ? (
          <div className="exact-artifact">
            <span>Bytes: {artifact.byteLength}</span>
            <span>SHA-256: <code>{artifact.artifactSha256}</code></span>
            <span>Raw CIDv1: <code>{artifact.rawCidV1}</code></span>
          </div>
        ) : null}
      </section>

      <section className="card">
        <h2>Create Exact-Inference Task</h2>
        <p className="note">PLS reward and protocol fee are percentage-native; no USD oracle or promised salary is assumed.</p>
        <div className="form-grid">
          <label>Mechanism ID<input value={createForm.mechid} onChange={(event) => setCreateForm({ ...createForm, mechid: event.target.value })} /></label>
          <label>Reward (PLS)<input value={createForm.rewardPls} onChange={(event) => setCreateForm({ ...createForm, rewardPls: event.target.value })} /></label>
          <label>Deadline block<input value={createForm.deadlineBlock} onChange={(event) => setCreateForm({ ...createForm, deadlineBlock: event.target.value })} /></label>
          <label>Requester nonce<input value={createForm.requesterNonce} onChange={(event) => setCreateForm({ ...createForm, requesterNonce: event.target.value })} /></label>
          <label>Refund address<input value={createForm.refundTo} onChange={(event) => setCreateForm({ ...createForm, refundTo: event.target.value })} /></label>
          <label>Input semantic commitment<input value={createForm.inputCommitment} onChange={(event) => setCreateForm({ ...createForm, inputCommitment: event.target.value })} placeholder="Guest/tool-produced bytes32" /></label>
          <label>Model semantic commitment<input value={createForm.modelCommitment} onChange={(event) => setCreateForm({ ...createForm, modelCommitment: event.target.value })} placeholder="Guest/tool-produced bytes32" /></label>
        </div>
        <div className="button-row">
          <button type="button" onClick={() => void createTask()} disabled={isPendingTx || !selectedAdmissionReady}>Create Funded Task</button>
          <button type="button" className="secondary" onClick={() => setCreateForm({ ...createForm, requesterNonce: randomUint64Decimal() })}>Fresh Public Nonce</button>
        </div>
        {!selectedAdmissionReady ? (
          <p className="disabled-reason">Requires a connected wallet on the target chain and a fully reviewed, live Core/config admission path.</p>
        ) : null}
      </section>

      <section className="card">
        <h2>Submit Keyless ZK Proof</h2>
        <p className="note">No verifier signing keys or three-verifier quorum: the reviewed program/image commitment and pinned verifier code check one deterministic proof relation.</p>
        <div className="form-grid">
          <label>Task ID<input value={proofForm.taskId} onChange={(event) => setProofForm({ ...proofForm, taskId: event.target.value })} /></label>
          <label>Provider identity<input value={proofForm.provider} onChange={(event) => setProofForm({ ...proofForm, provider: event.target.value })} /></label>
          <label>Beneficiary<input value={proofForm.beneficiary} onChange={(event) => setProofForm({ ...proofForm, beneficiary: event.target.value })} /></label>
          <label>Class index (0–3)<input value={proofForm.classIndex} onChange={(event) => setProofForm({ ...proofForm, classIndex: event.target.value })} /></label>
          {proofForm.scores.map((score, index) => (
            <label key={index}>Score {index}<input value={score} onChange={(event) => { const scores = [...proofForm.scores] as [string, string, string, string]; scores[index] = event.target.value; setProofForm({ ...proofForm, scores }); }} /></label>
          ))}
          <label className="proof-label">RISC Zero seal (hex)<textarea value={proofForm.proof} onChange={(event) => setProofForm({ ...proofForm, proof: event.target.value })} /></label>
        </div>
        <button type="button" onClick={() => void submitProof()} disabled={isPendingTx || !proofSubmissionReady}>Verify &amp; Settle</button>
        {!proofSubmissionReady ? (
          <p className="disabled-reason">Refresh an open task whose exact manifest config and live verifier can settle, then connect the wallet on the target chain.</p>
        ) : null}
      </section>

      <section className="card">
        <h2>Refund &amp; Pull Claims</h2>
        <p className="note">Recovery remains available when admission or proof availability is blocked; each call still requires a digest-pinned settlement identity.</p>
        <div className="inline-form">
          <label>Task ID<input value={recoveryTaskId} onChange={(event) => setRecoveryTaskId(event.target.value)} /></label>
          <button type="button" className="secondary" disabled={isPendingTx || !recoveryActionReady} onClick={() => void refund("refundExpired", "Refund expired task")}>Refund Expired</button>
          <button type="button" className="secondary" disabled={isPendingTx || !recoveryActionReady} onClick={() => void refund("refundRevoked", "Refund revoked-verifier task")}>Refund Revoked</button>
          <button type="button" className="secondary" disabled={isPendingTx || !recoveryActionReady} onClick={() => void refund("refundVerifierUnavailable", "Refund unavailable-verifier task")}>Refund Unavailable</button>
        </div>
        <div className="inline-form">
          <label>Claim recipient<input value={claimForm.to} onChange={(event) => setClaimForm({ ...claimForm, to: event.target.value })} /></label>
          <label>Amount (PLS)<input value={claimForm.amountPls} onChange={(event) => setClaimForm({ ...claimForm, amountPls: event.target.value })} /></label>
          <button type="button" onClick={() => void claim()} disabled={isPendingTx || !recoveryActionReady}>Claim</button>
        </div>
        {!recoveryActionReady ? (
          <p className="disabled-reason">Load the reviewed manifest, connect an account, and switch the wallet to its target chain. A broken browsing RPC does not disable recovery.</p>
        ) : null}
      </section>
    </fieldset>
  );
}

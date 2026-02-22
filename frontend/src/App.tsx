import { type FormEvent, useEffect, useMemo, useState } from "react";
import {
  type Abi,
  type Address,
  createPublicClient,
  createWalletClient,
  custom,
  http,
  isAddress,
  parseEther
} from "viem";
import { pulsetensorCoreAbi, pulsetensorSettlementAbi } from "./lib/abi";
import {
  chainPresets,
  defaultChainConfig,
  loadRuntimeConfigFromUrl,
  loadSavedConfig,
  type RuntimeConfig,
  saveConfig,
  toViemChain
} from "./lib/chains";
import { formatPls, formatShortHash, toHexChainId } from "./lib/format";

type StatusKind = "info" | "success" | "error";
type StatusState = { kind: StatusKind; message: string };
type AppPanel = "core" | "settlement";
type Bytes32Hex = `0x${string}`;

type SubnetSnapshot = {
  exists: boolean;
  maxValidators: number;
  ownerFeeBps: number;
  revealDelayBlocks: bigint;
  epochLengthBlocks: bigint;
  minValidatorStake: bigint;
  totalStake: bigint;
  currentEpoch: bigint;
  emissionPool: bigint;
  emissionBase: bigint;
  emissionFloor: bigint;
  emissionHalvingPeriod: bigint;
  emissionStart: bigint;
  smoothDecay: boolean;
  emissionQuote: bigint;
  walletStake: bigint;
  walletCanValidate: boolean;
  walletIsValidator: boolean;
  walletIsMiner: boolean;
  walletChallengeReward: bigint;
};

type SettlementSnapshot = {
  policyEnabled: boolean;
  challengeWindowBlocks: bigint;
  maxBatchItems: number;
  minProposerBondWei: bigint;
  loadedEpoch: bigint;
  batchRoot: Bytes32Hex;
  itemCount: number;
  feeTotal: bigint;
  bond: bigint;
  proposer: Address;
  committedAtBlock: bigint;
  challengeDeadlineBlock: bigint;
  challenged: boolean;
  finalized: boolean;
  walletChallengeReward: bigint;
  walletBondRefund: bigint;
  leafSettled: boolean | null;
};

const UINT64_MAX = (1n << 64n) - 1n;
const UINT32_MAX = 4_294_967_295;
const bytes32Regex = /^0x[0-9a-fA-F]{64}$/;

const emptySnapshot: SubnetSnapshot = {
  exists: false,
  maxValidators: 0,
  ownerFeeBps: 0,
  revealDelayBlocks: 0n,
  epochLengthBlocks: 0n,
  minValidatorStake: 0n,
  totalStake: 0n,
  currentEpoch: 0n,
  emissionPool: 0n,
  emissionBase: 0n,
  emissionFloor: 0n,
  emissionHalvingPeriod: 0n,
  emissionStart: 0n,
  smoothDecay: false,
  emissionQuote: 0n,
  walletStake: 0n,
  walletCanValidate: false,
  walletIsValidator: false,
  walletIsMiner: false,
  walletChallengeReward: 0n
};

const emptySettlementSnapshot: SettlementSnapshot = {
  policyEnabled: false,
  challengeWindowBlocks: 0n,
  maxBatchItems: 0,
  minProposerBondWei: 0n,
  loadedEpoch: 0n,
  batchRoot: "0x0000000000000000000000000000000000000000000000000000000000000000",
  itemCount: 0,
  feeTotal: 0n,
  bond: 0n,
  proposer: "0x0000000000000000000000000000000000000000",
  committedAtBlock: 0n,
  challengeDeadlineBlock: 0n,
  challenged: false,
  finalized: false,
  walletChallengeReward: 0n,
  walletBondRefund: 0n,
  leafSettled: null
};

function asErrorMessage(error: unknown): string {
  if (typeof error === "object" && error !== null) {
    const maybe = error as { shortMessage?: string; message?: string };
    return maybe.shortMessage ?? maybe.message ?? "Unknown error";
  }
  return String(error);
}

function parseUint16(raw: string, label: string): number {
  if (!/^\d+$/.test(raw)) throw new Error(`${label} must be an integer`);
  const value = Number(raw);
  if (!Number.isSafeInteger(value) || value < 0 || value > 65_535) {
    throw new Error(`${label} must be between 0 and 65535`);
  }
  return value;
}

function parseUint32(raw: string, label: string): number {
  if (!/^\d+$/.test(raw)) throw new Error(`${label} must be an integer`);
  const value = Number(raw);
  if (!Number.isSafeInteger(value) || value < 0 || value > UINT32_MAX) {
    throw new Error(`${label} must be between 0 and ${UINT32_MAX}`);
  }
  return value;
}

function parseUint64(raw: string, label: string): bigint {
  if (!/^\d+$/.test(raw)) throw new Error(`${label} must be an integer`);
  const value = BigInt(raw);
  if (value > UINT64_MAX) throw new Error(`${label} exceeds uint64`);
  return value;
}

function parseUint256(raw: string, label: string): bigint {
  if (!/^\d+$/.test(raw)) throw new Error(`${label} must be an integer`);
  return BigInt(raw);
}

function parsePLS(raw: string, label: string): bigint {
  const trimmed = raw.trim();
  if (trimmed.length === 0) throw new Error(`${label} is required`);
  try {
    return parseEther(trimmed);
  } catch {
    throw new Error(`${label} must be a valid decimal amount`);
  }
}

function isBytes32(raw: string): raw is Bytes32Hex {
  return bytes32Regex.test(raw.trim());
}

function parseBytes32(raw: string, label: string): Bytes32Hex {
  const trimmed = raw.trim();
  if (!isBytes32(trimmed)) throw new Error(`${label} must be a 32-byte hex value`);
  return trimmed;
}

function parseBytes32Array(raw: string, label: string): Bytes32Hex[] {
  const trimmed = raw.trim();
  if (trimmed.length === 0) return [];

  let values: unknown[] | null = null;
  if (trimmed.startsWith("[")) {
    try {
      const parsed = JSON.parse(trimmed);
      if (!Array.isArray(parsed)) throw new Error(`${label} must be a JSON array`);
      values = parsed;
    } catch (error) {
      throw new Error(asErrorMessage(error));
    }
  }

  if (!values) {
    values = trimmed
      .split(/[\n,\s]+/)
      .map((value) => value.trim())
      .filter((value) => value.length > 0);
  }

  const normalized: Bytes32Hex[] = [];
  for (const value of values) {
    if (typeof value !== "string") throw new Error(`${label} entries must be strings`);
    normalized.push(parseBytes32(value, `${label} entry`));
  }
  return normalized;
}

function findPresetId(config: RuntimeConfig): string {
  const preset = chainPresets.find((candidate) => {
    return candidate.chainId === config.chainId && candidate.rpcUrl === config.rpcUrl;
  });
  return preset?.presetId ?? "custom";
}

function App() {
  const [activePanel, setActivePanel] = useState<AppPanel>("core");
  const [config, setConfig] = useState<RuntimeConfig>(() => {
    const base = defaultChainConfig();
    return { ...base, ...loadSavedConfig(), ...loadRuntimeConfigFromUrl() };
  });
  const [presetId, setPresetId] = useState<string>(() => findPresetId(config));

  const [account, setAccount] = useState<Address | null>(null);
  const [walletChainId, setWalletChainId] = useState<number | null>(null);
  const [status, setStatus] = useState<StatusState>({
    kind: "info",
    message:
      "Static frontend only. No backend. All reads/writes go directly wallet + RPC to PulseChain contracts."
  });
  const [lastTxHash, setLastTxHash] = useState<`0x${string}` | null>(null);
  const [isPendingTx, setIsPendingTx] = useState(false);

  const [netuidInput, setNetuidInput] = useState("1");
  const [nextNetuid, setNextNetuid] = useState<number | null>(null);
  const [quoteEpochInput, setQuoteEpochInput] = useState("");
  const [subnetSnapshot, setSubnetSnapshot] = useState<SubnetSnapshot>(emptySnapshot);
  const [lastSubnetRefreshAt, setLastSubnetRefreshAt] = useState<number | null>(null);

  const [createSubnetForm, setCreateSubnetForm] = useState({
    maxValidators: "64",
    minValidatorStake: "1",
    ownerFeeBps: "1800",
    revealDelayBlocks: "20",
    epochLengthBlocks: "240"
  });
  const [stakeAmount, setStakeAmount] = useState("1");
  const [removeStakeAmount, setRemoveStakeAmount] = useState("0.2");
  const [fundEmissionAmount, setFundEmissionAmount] = useState("10");
  const [claimRewardAmount, setClaimRewardAmount] = useState("0.1");

  const [mechidInput, setMechidInput] = useState("0");
  const [settlementEpochInput, setSettlementEpochInput] = useState("");
  const [settlementLeafQuery, setSettlementLeafQuery] = useState("");
  const [settlementSnapshot, setSettlementSnapshot] = useState<SettlementSnapshot>(emptySettlementSnapshot);
  const [lastSettlementRefreshAt, setLastSettlementRefreshAt] = useState<number | null>(null);

  const [policyForm, setPolicyForm] = useState({
    enabled: true,
    challengeWindowBlocks: "25",
    maxBatchItems: "64",
    minProposerBond: "0.2"
  });
  const [commitBatchForm, setCommitBatchForm] = useState({
    epoch: "",
    batchRoot: "0x0000000000000000000000000000000000000000000000000000000000000000",
    itemCount: "2",
    feeTotal: "1.0",
    proposerBond: "0.2"
  });
  const [finalizeEpochInput, setFinalizeEpochInput] = useState("");
  const [settleLeafForm, setSettleLeafForm] = useState({
    epoch: "",
    leafHash: "",
    index: "0",
    merkleProof: "[]"
  });
  const [challengeReplayForm, setChallengeReplayForm] = useState({
    epoch: "",
    leafHash: "",
    index: "0",
    merkleProof: "[]",
    priorEpoch: "",
    priorIndex: "0",
    priorMerkleProof: "[]"
  });
  const [challengeDuplicateForm, setChallengeDuplicateForm] = useState({
    epoch: "",
    leafHash: "",
    indexA: "0",
    proofA: "[]",
    indexB: "1",
    proofB: "[]"
  });
  const [claimSettlementRewardAmount, setClaimSettlementRewardAmount] = useState("0.1");
  const [claimBondRefundAmount, setClaimBondRefundAmount] = useState("0.1");

  const coreAddress = isAddress(config.coreAddress) ? (config.coreAddress as Address) : undefined;
  const settlementAddress = isAddress(config.settlementAddress)
    ? (config.settlementAddress as Address)
    : undefined;
  const walletChainMatches = walletChainId === config.chainId;
  const txExplorerUrl = lastTxHash
    ? config.explorerUrl
      ? `${config.explorerUrl.replace(/\/$/, "")}/tx/${lastTxHash}`
      : null
    : null;

  const publicClient = useMemo(() => {
    return createPublicClient({
      chain: toViemChain(config),
      transport: http(config.rpcUrl)
    });
  }, [config]);

  function setStatusState(kind: StatusKind, message: string): void {
    setStatus({ kind, message });
  }

  function parseNetuid(): number {
    return parseUint16(netuidInput, "Subnet netuid");
  }

  function parseMechid(): number {
    return parseUint16(mechidInput, "Mechanism id");
  }

  function parseSettlementEpochOrDefault(raw: string): bigint {
    if (raw.trim() === "") return subnetSnapshot.currentEpoch;
    return parseUint64(raw, "Epoch");
  }

  function resetSettlementFromCurrentContext(): void {
    const fallbackEpoch = subnetSnapshot.currentEpoch.toString();
    setSettlementEpochInput(fallbackEpoch);
    setFinalizeEpochInput(fallbackEpoch);
    setCommitBatchForm((previous) => ({ ...previous, epoch: fallbackEpoch }));
    setSettleLeafForm((previous) => ({ ...previous, epoch: fallbackEpoch }));
    setChallengeReplayForm((previous) => ({ ...previous, epoch: fallbackEpoch, priorEpoch: fallbackEpoch }));
    setChallengeDuplicateForm((previous) => ({ ...previous, epoch: fallbackEpoch }));
  }

  async function connectWallet(): Promise<void> {
    if (!window.ethereum) {
      setStatusState("error", "No injected wallet found. Install MetaMask or an EIP-1193 wallet.");
      return;
    }
    try {
      const accounts = (await window.ethereum.request({
        method: "eth_requestAccounts"
      })) as string[];
      const chainHex = (await window.ethereum.request({ method: "eth_chainId" })) as string;
      const firstAccount = accounts[0];
      if (firstAccount && isAddress(firstAccount)) {
        setAccount(firstAccount as Address);
      } else {
        setAccount(null);
      }
      setWalletChainId(parseInt(chainHex, 16));
      setStatusState("success", "Wallet connected.");
    } catch (error) {
      setStatusState("error", asErrorMessage(error));
    }
  }

  async function switchWalletChain(): Promise<void> {
    if (!window.ethereum) {
      setStatusState("error", "No injected wallet found.");
      return;
    }
    const chainHex = toHexChainId(config.chainId);
    try {
      await window.ethereum.request({
        method: "wallet_switchEthereumChain",
        params: [{ chainId: chainHex }]
      });
      setWalletChainId(config.chainId);
      setStatusState("success", `Wallet switched to chain ${config.chainId}.`);
    } catch (error) {
      const maybe = error as { code?: number };
      if (maybe.code === 4902) {
        try {
          await window.ethereum.request({
            method: "wallet_addEthereumChain",
            params: [
              {
                chainId: chainHex,
                chainName: config.chainName,
                nativeCurrency: { name: "Pulse", symbol: "PLS", decimals: 18 },
                rpcUrls: [config.rpcUrl],
                blockExplorerUrls: config.explorerUrl ? [config.explorerUrl] : []
              }
            ]
          });
          setWalletChainId(config.chainId);
          setStatusState("success", `Wallet added and switched to ${config.chainName}.`);
          return;
        } catch (addError) {
          setStatusState("error", asErrorMessage(addError));
          return;
        }
      }
      setStatusState("error", asErrorMessage(error));
    }
  }

  useEffect(() => {
    if (!window.ethereum?.on) return;
    const handleAccountsChanged = (value: unknown) => {
      if (Array.isArray(value) && value.length > 0 && typeof value[0] === "string" && isAddress(value[0])) {
        setAccount(value[0] as Address);
      } else {
        setAccount(null);
      }
    };
    const handleChainChanged = (value: unknown) => {
      if (typeof value === "string" && value.startsWith("0x")) {
        setWalletChainId(parseInt(value, 16));
      }
    };
    window.ethereum.on("accountsChanged", handleAccountsChanged);
    window.ethereum.on("chainChanged", handleChainChanged);
    return () => {
      window.ethereum?.removeListener?.("accountsChanged", handleAccountsChanged);
      window.ethereum?.removeListener?.("chainChanged", handleChainChanged);
    };
  }, []);

  async function refreshSubnet(): Promise<void> {
    if (!coreAddress) {
      setStatusState("error", "Set a valid PulseTensor Core contract address first.");
      return;
    }
    try {
      const netuid = parseNetuid();

      const next = (await publicClient.readContract({
        address: coreAddress,
        abi: pulsetensorCoreAbi,
        functionName: "nextNetuid"
      })) as number;
      setNextNetuid(next);

      const subnet = (await publicClient.readContract({
        address: coreAddress,
        abi: pulsetensorCoreAbi,
        functionName: "subnets",
        args: [netuid]
      })) as readonly [boolean, number, number, bigint, bigint, bigint, bigint];

      if (!subnet[0]) {
        setSubnetSnapshot({ ...emptySnapshot, exists: false });
        setLastSubnetRefreshAt(Date.now());
        setStatusState("info", `Subnet ${netuid} is not created yet.`);
        return;
      }

      const [
        currentEpoch,
        emissionPool,
        emissionBase,
        emissionFloor,
        emissionHalvingPeriod,
        emissionStart,
        smoothDecay
      ] = (await Promise.all([
        publicClient.readContract({
          address: coreAddress,
          abi: pulsetensorCoreAbi,
          functionName: "currentEpoch",
          args: [netuid]
        }),
        publicClient.readContract({
          address: coreAddress,
          abi: pulsetensorCoreAbi,
          functionName: "subnetEmissionPool",
          args: [netuid]
        }),
        publicClient.readContract({
          address: coreAddress,
          abi: pulsetensorCoreAbi,
          functionName: "subnetEpochEmissionBase",
          args: [netuid]
        }),
        publicClient.readContract({
          address: coreAddress,
          abi: pulsetensorCoreAbi,
          functionName: "subnetEpochEmissionFloor",
          args: [netuid]
        }),
        publicClient.readContract({
          address: coreAddress,
          abi: pulsetensorCoreAbi,
          functionName: "subnetEpochEmissionHalvingPeriod",
          args: [netuid]
        }),
        publicClient.readContract({
          address: coreAddress,
          abi: pulsetensorCoreAbi,
          functionName: "subnetEpochEmissionStart",
          args: [netuid]
        }),
        publicClient.readContract({
          address: coreAddress,
          abi: pulsetensorCoreAbi,
          functionName: "subnetEmissionSmoothDecayEnabled",
          args: [netuid]
        })
      ])) as [bigint, bigint, bigint, bigint, bigint, bigint, boolean];

      const emissionQuote = (await publicClient.readContract({
        address: coreAddress,
        abi: pulsetensorCoreAbi,
        functionName: "quoteSubnetEpochEmission",
        args: [netuid, currentEpoch]
      })) as bigint;

      let walletStake = 0n;
      let walletCanValidate = false;
      let walletIsValidator = false;
      let walletIsMiner = false;
      let walletChallengeReward = 0n;
      if (account) {
        [walletStake, walletCanValidate, walletIsValidator, walletIsMiner, walletChallengeReward] =
          (await Promise.all([
            publicClient.readContract({
              address: coreAddress,
              abi: pulsetensorCoreAbi,
              functionName: "stakeOf",
              args: [netuid, account]
            }),
            publicClient.readContract({
              address: coreAddress,
              abi: pulsetensorCoreAbi,
              functionName: "canValidate",
              args: [netuid, account]
            }),
            publicClient.readContract({
              address: coreAddress,
              abi: pulsetensorCoreAbi,
              functionName: "isValidator",
              args: [netuid, account]
            }),
            publicClient.readContract({
              address: coreAddress,
              abi: pulsetensorCoreAbi,
              functionName: "isMiner",
              args: [netuid, account]
            }),
            publicClient.readContract({
              address: coreAddress,
              abi: pulsetensorCoreAbi,
              functionName: "challengeRewardOf",
              args: [netuid, account]
            })
          ])) as [bigint, boolean, boolean, boolean, bigint];
      }

      setSubnetSnapshot({
        exists: true,
        maxValidators: subnet[1],
        ownerFeeBps: subnet[2],
        revealDelayBlocks: subnet[3],
        epochLengthBlocks: subnet[4],
        minValidatorStake: subnet[5],
        totalStake: subnet[6],
        currentEpoch,
        emissionPool,
        emissionBase,
        emissionFloor,
        emissionHalvingPeriod,
        emissionStart,
        smoothDecay,
        emissionQuote,
        walletStake,
        walletCanValidate,
        walletIsValidator,
        walletIsMiner,
        walletChallengeReward
      });
      setLastSubnetRefreshAt(Date.now());
      setStatusState("success", `Subnet ${netuid} refreshed.`);
    } catch (error) {
      setStatusState("error", asErrorMessage(error));
    }
  }

  async function refreshSettlement(): Promise<void> {
    if (!settlementAddress) {
      setStatusState("error", "Set a valid settlement contract address first.");
      return;
    }
    try {
      const netuid = parseNetuid();
      const mechid = parseMechid();
      const epoch = parseSettlementEpochOrDefault(settlementEpochInput);

      const [policy, batch] = (await Promise.all([
        publicClient.readContract({
          address: settlementAddress,
          abi: pulsetensorSettlementAbi,
          functionName: "batchPolicies",
          args: [netuid, mechid]
        }),
        publicClient.readContract({
          address: settlementAddress,
          abi: pulsetensorSettlementAbi,
          functionName: "inferenceBatches",
          args: [netuid, mechid, epoch]
        })
      ])) as [
        readonly [boolean, bigint, number, bigint],
        readonly [Bytes32Hex, number, bigint, bigint, Address, bigint, bigint, boolean, boolean]
      ];

      let walletChallengeReward = 0n;
      let walletBondRefund = 0n;
      if (account) {
        [walletChallengeReward, walletBondRefund] = (await Promise.all([
          publicClient.readContract({
            address: settlementAddress,
            abi: pulsetensorSettlementAbi,
            functionName: "challengeRewardOf",
            args: [netuid, account]
          }),
          publicClient.readContract({
            address: settlementAddress,
            abi: pulsetensorSettlementAbi,
            functionName: "proposerBondRefundOf",
            args: [netuid, account]
          })
        ])) as [bigint, bigint];
      }

      let leafSettled: boolean | null = null;
      if (settlementLeafQuery.trim() !== "" && isBytes32(settlementLeafQuery.trim())) {
        leafSettled = (await publicClient.readContract({
          address: settlementAddress,
          abi: pulsetensorSettlementAbi,
          functionName: "settledLeaves",
          args: [netuid, mechid, settlementLeafQuery.trim() as Bytes32Hex]
        })) as boolean;
      }

      setSettlementSnapshot({
        policyEnabled: policy[0],
        challengeWindowBlocks: policy[1],
        maxBatchItems: policy[2],
        minProposerBondWei: policy[3],
        loadedEpoch: epoch,
        batchRoot: batch[0],
        itemCount: batch[1],
        feeTotal: batch[2],
        bond: batch[3],
        proposer: batch[4],
        committedAtBlock: batch[5],
        challengeDeadlineBlock: batch[6],
        challenged: batch[7],
        finalized: batch[8],
        walletChallengeReward,
        walletBondRefund,
        leafSettled
      });
      setLastSettlementRefreshAt(Date.now());
      setStatusState("success", `Settlement state refreshed for subnet ${netuid}, mechanism ${mechid}.`);
    } catch (error) {
      setStatusState("error", asErrorMessage(error));
    }
  }

  async function runWriteContract({
    label,
    address,
    abi,
    functionName,
    args,
    value,
    afterConfirm
  }: {
    label: string;
    address: Address | undefined;
    abi: Abi;
    functionName: string;
    args: readonly unknown[];
    value?: bigint;
    afterConfirm?: () => Promise<void>;
  }): Promise<void> {
    if (!address) {
      setStatusState("error", "Set a valid contract address first.");
      return;
    }
    if (!window.ethereum) {
      setStatusState("error", "No injected wallet found.");
      return;
    }
    if (!account) {
      setStatusState("error", "Connect wallet before sending transactions.");
      return;
    }
    if (!walletChainMatches) {
      setStatusState("error", `Wallet chain mismatch. Switch wallet to ${config.chainId} first.`);
      return;
    }

    setIsPendingTx(true);
    try {
      const walletClient = createWalletClient({
        chain: toViemChain(config),
        transport: custom(window.ethereum)
      });
      setStatusState("info", `${label}: awaiting wallet confirmation.`);

      const simulation = await (
        publicClient as unknown as { simulateContract: (request: unknown) => Promise<{ request: unknown }> }
      ).simulateContract({
        account,
        address,
        abi,
        functionName,
        args,
        value
      });
      const txHash = (await (
        walletClient as unknown as { writeContract: (request: unknown) => Promise<`0x${string}`> }
      ).writeContract(simulation.request)) as `0x${string}`;

      setLastTxHash(txHash);
      setStatusState("info", `${label}: submitted ${formatShortHash(txHash)}. Waiting for confirmation.`);
      await publicClient.waitForTransactionReceipt({ hash: txHash });
      setStatusState("success", `${label}: confirmed ${formatShortHash(txHash)}.`);
      if (afterConfirm) await afterConfirm();
    } catch (error) {
      setStatusState("error", asErrorMessage(error));
    } finally {
      setIsPendingTx(false);
    }
  }

  async function runCoreWrite(
    label: string,
    functionName: string,
    args: readonly unknown[],
    value?: bigint
  ): Promise<void> {
    await runWriteContract({
      label,
      address: coreAddress,
      abi: pulsetensorCoreAbi,
      functionName,
      args,
      value,
      afterConfirm: refreshSubnet
    });
  }

  async function runSettlementWrite(
    label: string,
    functionName: string,
    args: readonly unknown[],
    value?: bigint
  ): Promise<void> {
    await runWriteContract({
      label,
      address: settlementAddress,
      abi: pulsetensorSettlementAbi,
      functionName,
      args,
      value,
      afterConfirm: refreshSettlement
    });
  }

  function handlePresetChange(nextPresetId: string): void {
    setPresetId(nextPresetId);
    if (nextPresetId === "custom") return;
    const preset = chainPresets.find((candidate) => candidate.presetId === nextPresetId);
    if (!preset) return;
    setConfig({
      chainId: preset.chainId,
      chainName: preset.chainName,
      rpcUrl: preset.rpcUrl,
      explorerUrl: preset.explorerUrl,
      coreAddress: config.coreAddress,
      settlementAddress: config.settlementAddress
    });
  }

  function updateConfigField<K extends keyof RuntimeConfig>(field: K, value: RuntimeConfig[K]): void {
    setPresetId("custom");
    setConfig((previous) => ({ ...previous, [field]: value }));
  }

  async function submitCreateSubnet(event: FormEvent<HTMLFormElement>): Promise<void> {
    event.preventDefault();
    try {
      const maxValidators = parseUint16(createSubnetForm.maxValidators, "Max validators");
      const ownerFeeBps = parseUint16(createSubnetForm.ownerFeeBps, "Owner fee bps");
      const revealDelayBlocks = parseUint64(createSubnetForm.revealDelayBlocks, "Reveal delay blocks");
      const epochLengthBlocks = parseUint64(createSubnetForm.epochLengthBlocks, "Epoch length blocks");
      if (revealDelayBlocks >= epochLengthBlocks) {
        throw new Error("Reveal delay blocks must be less than epoch length blocks");
      }
      const minValidatorStake = parsePLS(createSubnetForm.minValidatorStake, "Min validator stake");
      await runCoreWrite("Create subnet", "createSubnet", [
        maxValidators,
        minValidatorStake,
        ownerFeeBps,
        revealDelayBlocks,
        epochLengthBlocks
      ]);
      resetSettlementFromCurrentContext();
    } catch (error) {
      setStatusState("error", asErrorMessage(error));
    }
  }

  async function submitQuoteEpoch(): Promise<void> {
    if (!coreAddress) {
      setStatusState("error", "Set a valid PulseTensor Core contract address first.");
      return;
    }
    try {
      const netuid = parseNetuid();
      const epoch = quoteEpochInput.trim() === "" ? subnetSnapshot.currentEpoch : parseUint64(quoteEpochInput, "Epoch");
      const quote = (await publicClient.readContract({
        address: coreAddress,
        abi: pulsetensorCoreAbi,
        functionName: "quoteSubnetEpochEmission",
        args: [netuid, epoch]
      })) as bigint;
      setSubnetSnapshot((previous) => ({ ...previous, emissionQuote: quote }));
      setStatusState("success", `Quoted epoch ${epoch.toString()} emission.`);
    } catch (error) {
      setStatusState("error", asErrorMessage(error));
    }
  }

  async function submitQueuePolicyUpdate(event: FormEvent<HTMLFormElement>): Promise<void> {
    event.preventDefault();
    try {
      const netuid = parseNetuid();
      const mechid = parseMechid();
      if (!policyForm.enabled) {
        await runSettlementWrite("Queue policy update", "queueBatchPolicyUpdate", [netuid, mechid, false, 0n, 0, 0n]);
        return;
      }
      const challengeWindow = parseUint64(policyForm.challengeWindowBlocks, "Challenge window blocks");
      const maxBatchItems = parseUint32(policyForm.maxBatchItems, "Max batch items");
      const minBond = parsePLS(policyForm.minProposerBond, "Min proposer bond");
      await runSettlementWrite("Queue policy update", "queueBatchPolicyUpdate", [
        netuid,
        mechid,
        true,
        challengeWindow,
        maxBatchItems,
        minBond
      ]);
    } catch (error) {
      setStatusState("error", asErrorMessage(error));
    }
  }

  async function configurePolicyNow(): Promise<void> {
    try {
      const netuid = parseNetuid();
      const mechid = parseMechid();
      if (!policyForm.enabled) {
        await runSettlementWrite("Configure policy", "configureBatchPolicy", [netuid, mechid, false, 0n, 0, 0n]);
        return;
      }
      const challengeWindow = parseUint64(policyForm.challengeWindowBlocks, "Challenge window blocks");
      const maxBatchItems = parseUint32(policyForm.maxBatchItems, "Max batch items");
      const minBond = parsePLS(policyForm.minProposerBond, "Min proposer bond");
      await runSettlementWrite("Configure policy", "configureBatchPolicy", [
        netuid,
        mechid,
        true,
        challengeWindow,
        maxBatchItems,
        minBond
      ]);
    } catch (error) {
      setStatusState("error", asErrorMessage(error));
    }
  }

  async function submitCommitBatch(event: FormEvent<HTMLFormElement>): Promise<void> {
    event.preventDefault();
    try {
      const netuid = parseNetuid();
      const mechid = parseMechid();
      const epoch = parseSettlementEpochOrDefault(commitBatchForm.epoch);
      const batchRoot = parseBytes32(commitBatchForm.batchRoot, "Batch root");
      const itemCount = parseUint32(commitBatchForm.itemCount, "Item count");
      const feeTotal = parsePLS(commitBatchForm.feeTotal, "Fee total");
      const proposerBond = parsePLS(commitBatchForm.proposerBond, "Proposer bond");
      await runSettlementWrite(
        "Commit batch root",
        "commitInferenceBatchRoot",
        [netuid, mechid, epoch, batchRoot, itemCount, feeTotal],
        proposerBond
      );
    } catch (error) {
      setStatusState("error", asErrorMessage(error));
    }
  }

  async function finalizeBatchNow(): Promise<void> {
    try {
      const netuid = parseNetuid();
      const mechid = parseMechid();
      const epoch = parseSettlementEpochOrDefault(finalizeEpochInput);
      await runSettlementWrite("Finalize batch", "finalizeInferenceBatch", [netuid, mechid, epoch]);
    } catch (error) {
      setStatusState("error", asErrorMessage(error));
    }
  }

  async function submitSettleLeaf(event: FormEvent<HTMLFormElement>): Promise<void> {
    event.preventDefault();
    try {
      const netuid = parseNetuid();
      const mechid = parseMechid();
      const epoch = parseSettlementEpochOrDefault(settleLeafForm.epoch);
      const leafHash = parseBytes32(settleLeafForm.leafHash, "Leaf hash");
      const index = parseUint256(settleLeafForm.index, "Leaf index");
      const proof = parseBytes32Array(settleLeafForm.merkleProof, "Merkle proof");
      await runSettlementWrite("Settle finalized leaf", "settleFinalizedInferenceLeaf", [
        netuid,
        mechid,
        epoch,
        leafHash,
        index,
        proof
      ]);
    } catch (error) {
      setStatusState("error", asErrorMessage(error));
    }
  }

  async function submitReplayChallenge(event: FormEvent<HTMLFormElement>): Promise<void> {
    event.preventDefault();
    try {
      const netuid = parseNetuid();
      const mechid = parseMechid();
      const epoch = parseSettlementEpochOrDefault(challengeReplayForm.epoch);
      const leafHash = parseBytes32(challengeReplayForm.leafHash, "Leaf hash");
      const index = parseUint256(challengeReplayForm.index, "Leaf index");
      const proof = parseBytes32Array(challengeReplayForm.merkleProof, "Current proof");
      const priorEpoch = parseUint64(challengeReplayForm.priorEpoch, "Prior epoch");
      const priorIndex = parseUint256(challengeReplayForm.priorIndex, "Prior index");
      const priorProof = parseBytes32Array(challengeReplayForm.priorMerkleProof, "Prior proof");
      await runSettlementWrite("Challenge leaf replay", "challengeInferenceLeafReplay", [
        netuid,
        mechid,
        epoch,
        leafHash,
        index,
        proof,
        priorEpoch,
        priorIndex,
        priorProof
      ]);
    } catch (error) {
      setStatusState("error", asErrorMessage(error));
    }
  }

  async function submitDuplicateChallenge(event: FormEvent<HTMLFormElement>): Promise<void> {
    event.preventDefault();
    try {
      const netuid = parseNetuid();
      const mechid = parseMechid();
      const epoch = parseSettlementEpochOrDefault(challengeDuplicateForm.epoch);
      const leafHash = parseBytes32(challengeDuplicateForm.leafHash, "Leaf hash");
      const indexA = parseUint256(challengeDuplicateForm.indexA, "Index A");
      const proofA = parseBytes32Array(challengeDuplicateForm.proofA, "Proof A");
      const indexB = parseUint256(challengeDuplicateForm.indexB, "Index B");
      const proofB = parseBytes32Array(challengeDuplicateForm.proofB, "Proof B");
      await runSettlementWrite("Challenge duplicate leaf", "challengeInferenceLeafDuplicate", [
        netuid,
        mechid,
        epoch,
        leafHash,
        indexA,
        proofA,
        indexB,
        proofB
      ]);
    } catch (error) {
      setStatusState("error", asErrorMessage(error));
    }
  }

  return (
    <main className="app-shell">
      <header className="hero">
        <h1>PulseTensor Interface</h1>
        <p>Host-anywhere static dApp with direct wallet/RPC contract execution and no centralized API layer.</p>
      </header>

      <section className="card">
        <h2>Why This UI Is Stronger</h2>
        <ul className="assurance-list">
          <li>Static build and mirror-friendly deployment model.</li>
          <li>User-controlled chain, RPC, and contract routing.</li>
          <li>Every transaction is simulated client-side before signing.</li>
          <li>Core and settlement operations are both first-class in one console.</li>
          <li>Fail-closed chain mismatch checks before all writes.</li>
        </ul>
      </section>

      <section className={`status status-${status.kind}`} role="status" aria-live="polite">
        <span>{status.message}</span>
        {txExplorerUrl ? (
          <a href={txExplorerUrl} target="_blank" rel="noreferrer">
            View TX
          </a>
        ) : null}
      </section>

      <section className="card">
        <h2>Network & Contracts</h2>
        <div className="form-grid">
          <label>
            Preset
            <select value={presetId} onChange={(event) => handlePresetChange(event.target.value)}>
              {chainPresets.map((preset) => (
                <option key={preset.presetId} value={preset.presetId}>
                  {preset.chainName} ({preset.chainId})
                </option>
              ))}
              <option value="custom">Custom</option>
            </select>
          </label>
          <label>
            Chain ID
            <input
              value={config.chainId}
              onChange={(event) => updateConfigField("chainId", Number(event.target.value) || 0)}
              inputMode="numeric"
            />
          </label>
          <label>
            Chain Name
            <input value={config.chainName} onChange={(event) => updateConfigField("chainName", event.target.value)} />
          </label>
          <label>
            RPC URL
            <input value={config.rpcUrl} onChange={(event) => updateConfigField("rpcUrl", event.target.value)} />
          </label>
          <label>
            Explorer URL
            <input
              value={config.explorerUrl}
              onChange={(event) => updateConfigField("explorerUrl", event.target.value)}
              placeholder="Optional"
            />
          </label>
          <label>
            PulseTensorCore Address
            <input
              value={config.coreAddress}
              onChange={(event) => updateConfigField("coreAddress", event.target.value)}
              placeholder="0x..."
            />
          </label>
          <label>
            Settlement Address
            <input
              value={config.settlementAddress}
              onChange={(event) => updateConfigField("settlementAddress", event.target.value)}
              placeholder="0x..."
            />
          </label>
        </div>
        <div className="button-row">
          <button type="button" onClick={() => saveConfig(config)}>
            Save Local Config
          </button>
          <button type="button" className="secondary" onClick={() => void refreshSubnet()}>
            Refresh Core
          </button>
          <button type="button" className="secondary" onClick={() => void refreshSettlement()}>
            Refresh Settlement
          </button>
        </div>
        <p className="note">
          URL overrides: <code>?chainId=&amp;rpc=&amp;core=&amp;settlement=</code>
        </p>
      </section>

      <section className="card">
        <h2>Wallet</h2>
        <div className="wallet-row">
          <button type="button" onClick={() => void connectWallet()}>
            {account ? "Reconnect Wallet" : "Connect Wallet"}
          </button>
          <div>
            <strong>Account:</strong> {account ?? "-"}
          </div>
          <div>
            <strong>Wallet Chain:</strong> {walletChainId ?? "-"}
          </div>
          <div>
            <strong>Target Chain:</strong> {config.chainId}
          </div>
        </div>
        {!walletChainMatches && account ? (
          <div className="warning-row">
            <span>Wallet and configured chain do not match.</span>
            <button type="button" onClick={() => void switchWalletChain()}>
              Switch Wallet Chain
            </button>
          </div>
        ) : null}
      </section>

      <section className="panel-tabs">
        <button
          type="button"
          className={activePanel === "core" ? "tab-active" : "secondary"}
          onClick={() => setActivePanel("core")}
        >
          Core Console
        </button>
        <button
          type="button"
          className={activePanel === "settlement" ? "tab-active" : "secondary"}
          onClick={() => setActivePanel("settlement")}
        >
          Settlement Console
        </button>
      </section>

      {activePanel === "core" ? (
        <>
          <section className="card">
            <h2>Core Monitor</h2>
            <div className="inline-form">
              <label>
                NetUID
                <input value={netuidInput} onChange={(event) => setNetuidInput(event.target.value)} inputMode="numeric" />
              </label>
              <button type="button" className="secondary" onClick={() => void refreshSubnet()}>
                Refresh
              </button>
              <label>
                Quote Epoch
                <input
                  value={quoteEpochInput}
                  onChange={(event) => setQuoteEpochInput(event.target.value)}
                  inputMode="numeric"
                  placeholder={subnetSnapshot.currentEpoch.toString()}
                />
              </label>
              <button type="button" className="secondary" onClick={() => void submitQuoteEpoch()}>
                Quote Emission
              </button>
            </div>

            <div className="metrics-grid">
              <div>
                <span>Next NetUID</span>
                <strong>{nextNetuid?.toString() ?? "-"}</strong>
              </div>
              <div>
                <span>Subnet Exists</span>
                <strong>{subnetSnapshot.exists ? "Yes" : "No"}</strong>
              </div>
              <div>
                <span>Current Epoch</span>
                <strong>{subnetSnapshot.currentEpoch.toString()}</strong>
              </div>
              <div>
                <span>Emission Quote</span>
                <strong>{formatPls(subnetSnapshot.emissionQuote)}</strong>
              </div>
              <div>
                <span>Emission Pool</span>
                <strong>{formatPls(subnetSnapshot.emissionPool)}</strong>
              </div>
              <div>
                <span>Total Stake</span>
                <strong>{formatPls(subnetSnapshot.totalStake)}</strong>
              </div>
              <div>
                <span>Min Validator Stake</span>
                <strong>{formatPls(subnetSnapshot.minValidatorStake)}</strong>
              </div>
              <div>
                <span>Max Validators</span>
                <strong>{subnetSnapshot.maxValidators.toString()}</strong>
              </div>
              <div>
                <span>Owner Fee</span>
                <strong>{subnetSnapshot.ownerFeeBps.toString()} bps</strong>
              </div>
              <div>
                <span>Epoch Length</span>
                <strong>{subnetSnapshot.epochLengthBlocks.toString()} blocks</strong>
              </div>
              <div>
                <span>Reveal Delay</span>
                <strong>{subnetSnapshot.revealDelayBlocks.toString()} blocks</strong>
              </div>
              <div>
                <span>Smooth Decay</span>
                <strong>{subnetSnapshot.smoothDecay ? "Enabled" : "Disabled"}</strong>
              </div>
              <div>
                <span>Your Stake</span>
                <strong>{formatPls(subnetSnapshot.walletStake)}</strong>
              </div>
              <div>
                <span>Your Challenge Reward</span>
                <strong>{formatPls(subnetSnapshot.walletChallengeReward)}</strong>
              </div>
              <div>
                <span>Can Validate</span>
                <strong>{subnetSnapshot.walletCanValidate ? "Yes" : "No"}</strong>
              </div>
              <div>
                <span>Role Flags</span>
                <strong>{subnetSnapshot.walletIsValidator ? "Validator " : ""}{subnetSnapshot.walletIsMiner ? "Miner" : "-"}</strong>
              </div>
            </div>
            <p className="note">
              Last refreshed: {lastSubnetRefreshAt ? new Date(lastSubnetRefreshAt).toLocaleTimeString() : "never"}
            </p>
          </section>

          <section className="card">
            <h2>Core Actions</h2>
            <form className="form-grid" onSubmit={(event) => void submitCreateSubnet(event)}>
              <label>
                Max Validators
                <input
                  value={createSubnetForm.maxValidators}
                  onChange={(event) =>
                    setCreateSubnetForm((previous) => ({ ...previous, maxValidators: event.target.value }))
                  }
                  inputMode="numeric"
                />
              </label>
              <label>
                Min Validator Stake (PLS)
                <input
                  value={createSubnetForm.minValidatorStake}
                  onChange={(event) =>
                    setCreateSubnetForm((previous) => ({ ...previous, minValidatorStake: event.target.value }))
                  }
                />
              </label>
              <label>
                Owner Fee (bps)
                <input
                  value={createSubnetForm.ownerFeeBps}
                  onChange={(event) =>
                    setCreateSubnetForm((previous) => ({ ...previous, ownerFeeBps: event.target.value }))
                  }
                  inputMode="numeric"
                />
              </label>
              <label>
                Reveal Delay Blocks
                <input
                  value={createSubnetForm.revealDelayBlocks}
                  onChange={(event) =>
                    setCreateSubnetForm((previous) => ({ ...previous, revealDelayBlocks: event.target.value }))
                  }
                  inputMode="numeric"
                />
              </label>
              <label>
                Epoch Length Blocks
                <input
                  value={createSubnetForm.epochLengthBlocks}
                  onChange={(event) =>
                    setCreateSubnetForm((previous) => ({ ...previous, epochLengthBlocks: event.target.value }))
                  }
                  inputMode="numeric"
                />
              </label>
              <button type="submit" disabled={isPendingTx}>
                Create Subnet
              </button>
            </form>

            <div className="action-grid">
              <label>
                Add Stake (PLS)
                <input value={stakeAmount} onChange={(event) => setStakeAmount(event.target.value)} />
                <button
                  type="button"
                  disabled={isPendingTx}
                  onClick={() =>
                    void (async () => {
                      try {
                        await runCoreWrite("Add stake", "addStake", [parseNetuid()], parsePLS(stakeAmount, "Stake amount"));
                      } catch (error) {
                        setStatusState("error", asErrorMessage(error));
                      }
                    })()
                  }
                >
                  Add Stake
                </button>
              </label>
              <label>
                Remove Stake (PLS)
                <input value={removeStakeAmount} onChange={(event) => setRemoveStakeAmount(event.target.value)} />
                <button
                  type="button"
                  disabled={isPendingTx}
                  onClick={() =>
                    void (async () => {
                      try {
                        await runCoreWrite("Remove stake", "removeStake", [
                          parseNetuid(),
                          parsePLS(removeStakeAmount, "Remove stake amount")
                        ]);
                      } catch (error) {
                        setStatusState("error", asErrorMessage(error));
                      }
                    })()
                  }
                >
                  Remove Stake
                </button>
              </label>
              <label>
                Fund Emission Pool (PLS)
                <input value={fundEmissionAmount} onChange={(event) => setFundEmissionAmount(event.target.value)} />
                <button
                  type="button"
                  disabled={isPendingTx}
                  onClick={() =>
                    void (async () => {
                      try {
                        await runCoreWrite(
                          "Fund subnet emission",
                          "fundSubnetEmission",
                          [parseNetuid()],
                          parsePLS(fundEmissionAmount, "Fund amount")
                        );
                      } catch (error) {
                        setStatusState("error", asErrorMessage(error));
                      }
                    })()
                  }
                >
                  Fund Emission
                </button>
              </label>
              <label>
                Claim Challenge Reward (PLS)
                <input value={claimRewardAmount} onChange={(event) => setClaimRewardAmount(event.target.value)} />
                <button
                  type="button"
                  disabled={isPendingTx}
                  onClick={() =>
                    void (async () => {
                      try {
                        await runCoreWrite("Claim reward", "claimChallengeReward", [
                          parseNetuid(),
                          parsePLS(claimRewardAmount, "Reward amount")
                        ]);
                      } catch (error) {
                        setStatusState("error", asErrorMessage(error));
                      }
                    })()
                  }
                >
                  Claim Reward
                </button>
              </label>
            </div>

            <div className="button-row">
              <button
                type="button"
                disabled={isPendingTx}
                onClick={() =>
                  void (async () => {
                    try {
                      await runCoreWrite("Register validator", "registerValidator", [parseNetuid()]);
                    } catch (error) {
                      setStatusState("error", asErrorMessage(error));
                    }
                  })()
                }
              >
                Register Validator
              </button>
              <button
                type="button"
                disabled={isPendingTx}
                onClick={() =>
                  void (async () => {
                    try {
                      await runCoreWrite("Unregister validator", "unregisterValidator", [parseNetuid()]);
                    } catch (error) {
                      setStatusState("error", asErrorMessage(error));
                    }
                  })()
                }
              >
                Unregister Validator
              </button>
              <button
                type="button"
                disabled={isPendingTx}
                onClick={() =>
                  void (async () => {
                    try {
                      await runCoreWrite("Register miner", "registerMiner", [parseNetuid()]);
                    } catch (error) {
                      setStatusState("error", asErrorMessage(error));
                    }
                  })()
                }
              >
                Register Miner
              </button>
              <button
                type="button"
                disabled={isPendingTx}
                onClick={() =>
                  void (async () => {
                    try {
                      await runCoreWrite("Unregister miner", "unregisterMiner", [parseNetuid()]);
                    } catch (error) {
                      setStatusState("error", asErrorMessage(error));
                    }
                  })()
                }
              >
                Unregister Miner
              </button>
            </div>
          </section>
        </>
      ) : (
        <>
          <section className="card">
            <h2>Settlement Monitor</h2>
            <div className="inline-form">
              <label>
                NetUID
                <input value={netuidInput} onChange={(event) => setNetuidInput(event.target.value)} inputMode="numeric" />
              </label>
              <label>
                Mechanism ID
                <input value={mechidInput} onChange={(event) => setMechidInput(event.target.value)} inputMode="numeric" />
              </label>
              <label>
                Epoch
                <input
                  value={settlementEpochInput}
                  onChange={(event) => setSettlementEpochInput(event.target.value)}
                  placeholder={subnetSnapshot.currentEpoch.toString()}
                  inputMode="numeric"
                />
              </label>
              <label>
                Leaf Hash Query
                <input
                  value={settlementLeafQuery}
                  onChange={(event) => setSettlementLeafQuery(event.target.value)}
                  placeholder="0x..."
                />
              </label>
              <button type="button" className="secondary" onClick={() => void refreshSettlement()}>
                Refresh
              </button>
            </div>

            <div className="metrics-grid">
              <div>
                <span>Policy Enabled</span>
                <strong>{settlementSnapshot.policyEnabled ? "Yes" : "No"}</strong>
              </div>
              <div>
                <span>Challenge Window</span>
                <strong>{settlementSnapshot.challengeWindowBlocks.toString()} blocks</strong>
              </div>
              <div>
                <span>Max Batch Items</span>
                <strong>{settlementSnapshot.maxBatchItems.toString()}</strong>
              </div>
              <div>
                <span>Min Proposer Bond</span>
                <strong>{formatPls(settlementSnapshot.minProposerBondWei)}</strong>
              </div>
              <div>
                <span>Loaded Epoch</span>
                <strong>{settlementSnapshot.loadedEpoch.toString()}</strong>
              </div>
              <div>
                <span>Batch Root</span>
                <strong>{formatShortHash(settlementSnapshot.batchRoot)}</strong>
              </div>
              <div>
                <span>Item Count</span>
                <strong>{settlementSnapshot.itemCount.toString()}</strong>
              </div>
              <div>
                <span>Fee Total</span>
                <strong>{formatPls(settlementSnapshot.feeTotal)}</strong>
              </div>
              <div>
                <span>Bond</span>
                <strong>{formatPls(settlementSnapshot.bond)}</strong>
              </div>
              <div>
                <span>Proposer</span>
                <strong>{formatShortHash(settlementSnapshot.proposer)}</strong>
              </div>
              <div>
                <span>Committed At</span>
                <strong>{settlementSnapshot.committedAtBlock.toString()}</strong>
              </div>
              <div>
                <span>Challenge Deadline</span>
                <strong>{settlementSnapshot.challengeDeadlineBlock.toString()}</strong>
              </div>
              <div>
                <span>Challenged</span>
                <strong>{settlementSnapshot.challenged ? "Yes" : "No"}</strong>
              </div>
              <div>
                <span>Finalized</span>
                <strong>{settlementSnapshot.finalized ? "Yes" : "No"}</strong>
              </div>
              <div>
                <span>Your Challenge Reward</span>
                <strong>{formatPls(settlementSnapshot.walletChallengeReward)}</strong>
              </div>
              <div>
                <span>Your Bond Refund</span>
                <strong>{formatPls(settlementSnapshot.walletBondRefund)}</strong>
              </div>
              <div>
                <span>Queried Leaf Settled</span>
                <strong>
                  {settlementSnapshot.leafSettled === null ? "-" : settlementSnapshot.leafSettled ? "Yes" : "No"}
                </strong>
              </div>
            </div>
            <p className="note">
              Last refreshed:{" "}
              {lastSettlementRefreshAt ? new Date(lastSettlementRefreshAt).toLocaleTimeString() : "never"}
            </p>
          </section>

          <section className="card">
            <h2>Settlement Actions</h2>
            <form className="form-grid" onSubmit={(event) => void submitQueuePolicyUpdate(event)}>
              <label className="checkbox-line">
                <input
                  type="checkbox"
                  checked={policyForm.enabled}
                  onChange={(event) =>
                    setPolicyForm((previous) => ({ ...previous, enabled: event.target.checked }))
                  }
                />
                Policy Enabled
              </label>
              <label>
                Challenge Window Blocks
                <input
                  value={policyForm.challengeWindowBlocks}
                  onChange={(event) =>
                    setPolicyForm((previous) => ({ ...previous, challengeWindowBlocks: event.target.value }))
                  }
                  inputMode="numeric"
                  disabled={!policyForm.enabled}
                />
              </label>
              <label>
                Max Batch Items
                <input
                  value={policyForm.maxBatchItems}
                  onChange={(event) => setPolicyForm((previous) => ({ ...previous, maxBatchItems: event.target.value }))}
                  inputMode="numeric"
                  disabled={!policyForm.enabled}
                />
              </label>
              <label>
                Min Proposer Bond (PLS)
                <input
                  value={policyForm.minProposerBond}
                  onChange={(event) =>
                    setPolicyForm((previous) => ({ ...previous, minProposerBond: event.target.value }))
                  }
                  disabled={!policyForm.enabled}
                />
              </label>
              <button type="submit" disabled={isPendingTx}>
                Queue Policy Update
              </button>
              <button type="button" className="secondary" disabled={isPendingTx} onClick={() => void configurePolicyNow()}>
                Configure Policy
              </button>
            </form>

            <form className="form-grid" onSubmit={(event) => void submitCommitBatch(event)}>
              <label>
                Commit Epoch
                <input
                  value={commitBatchForm.epoch}
                  onChange={(event) => setCommitBatchForm((previous) => ({ ...previous, epoch: event.target.value }))}
                  inputMode="numeric"
                  placeholder={subnetSnapshot.currentEpoch.toString()}
                />
              </label>
              <label>
                Batch Root
                <input
                  value={commitBatchForm.batchRoot}
                  onChange={(event) => setCommitBatchForm((previous) => ({ ...previous, batchRoot: event.target.value }))}
                />
              </label>
              <label>
                Item Count
                <input
                  value={commitBatchForm.itemCount}
                  onChange={(event) => setCommitBatchForm((previous) => ({ ...previous, itemCount: event.target.value }))}
                  inputMode="numeric"
                />
              </label>
              <label>
                Fee Total (PLS)
                <input
                  value={commitBatchForm.feeTotal}
                  onChange={(event) => setCommitBatchForm((previous) => ({ ...previous, feeTotal: event.target.value }))}
                />
              </label>
              <label>
                Proposer Bond (PLS)
                <input
                  value={commitBatchForm.proposerBond}
                  onChange={(event) =>
                    setCommitBatchForm((previous) => ({ ...previous, proposerBond: event.target.value }))
                  }
                />
              </label>
              <button type="submit" disabled={isPendingTx}>
                Commit Batch Root
              </button>
            </form>

            <div className="inline-form">
              <label>
                Finalize Epoch
                <input
                  value={finalizeEpochInput}
                  onChange={(event) => setFinalizeEpochInput(event.target.value)}
                  inputMode="numeric"
                  placeholder={settlementSnapshot.loadedEpoch.toString()}
                />
              </label>
              <button type="button" disabled={isPendingTx} onClick={() => void finalizeBatchNow()}>
                Finalize Batch
              </button>
            </div>

            <form className="form-grid" onSubmit={(event) => void submitSettleLeaf(event)}>
              <label>
                Settle Epoch
                <input
                  value={settleLeafForm.epoch}
                  onChange={(event) => setSettleLeafForm((previous) => ({ ...previous, epoch: event.target.value }))}
                  inputMode="numeric"
                  placeholder={settlementSnapshot.loadedEpoch.toString()}
                />
              </label>
              <label>
                Leaf Hash
                <input
                  value={settleLeafForm.leafHash}
                  onChange={(event) => setSettleLeafForm((previous) => ({ ...previous, leafHash: event.target.value }))}
                  placeholder="0x..."
                />
              </label>
              <label>
                Leaf Index
                <input
                  value={settleLeafForm.index}
                  onChange={(event) => setSettleLeafForm((previous) => ({ ...previous, index: event.target.value }))}
                  inputMode="numeric"
                />
              </label>
              <label className="proof-label">
                Merkle Proof (JSON array or comma/newline list)
                <textarea
                  value={settleLeafForm.merkleProof}
                  onChange={(event) =>
                    setSettleLeafForm((previous) => ({ ...previous, merkleProof: event.target.value }))
                  }
                />
              </label>
              <button type="submit" disabled={isPendingTx}>
                Settle Finalized Leaf
              </button>
            </form>

            <form className="form-grid" onSubmit={(event) => void submitReplayChallenge(event)}>
              <label>
                Replay Epoch
                <input
                  value={challengeReplayForm.epoch}
                  onChange={(event) =>
                    setChallengeReplayForm((previous) => ({ ...previous, epoch: event.target.value }))
                  }
                  inputMode="numeric"
                />
              </label>
              <label>
                Replay Leaf Hash
                <input
                  value={challengeReplayForm.leafHash}
                  onChange={(event) =>
                    setChallengeReplayForm((previous) => ({ ...previous, leafHash: event.target.value }))
                  }
                  placeholder="0x..."
                />
              </label>
              <label>
                Current Index
                <input
                  value={challengeReplayForm.index}
                  onChange={(event) => setChallengeReplayForm((previous) => ({ ...previous, index: event.target.value }))}
                  inputMode="numeric"
                />
              </label>
              <label>
                Prior Epoch
                <input
                  value={challengeReplayForm.priorEpoch}
                  onChange={(event) =>
                    setChallengeReplayForm((previous) => ({ ...previous, priorEpoch: event.target.value }))
                  }
                  inputMode="numeric"
                />
              </label>
              <label>
                Prior Index
                <input
                  value={challengeReplayForm.priorIndex}
                  onChange={(event) =>
                    setChallengeReplayForm((previous) => ({ ...previous, priorIndex: event.target.value }))
                  }
                  inputMode="numeric"
                />
              </label>
              <label className="proof-label">
                Current Proof
                <textarea
                  value={challengeReplayForm.merkleProof}
                  onChange={(event) =>
                    setChallengeReplayForm((previous) => ({ ...previous, merkleProof: event.target.value }))
                  }
                />
              </label>
              <label className="proof-label">
                Prior Proof
                <textarea
                  value={challengeReplayForm.priorMerkleProof}
                  onChange={(event) =>
                    setChallengeReplayForm((previous) => ({ ...previous, priorMerkleProof: event.target.value }))
                  }
                />
              </label>
              <button type="submit" disabled={isPendingTx}>
                Challenge Leaf Replay
              </button>
            </form>

            <form className="form-grid" onSubmit={(event) => void submitDuplicateChallenge(event)}>
              <label>
                Duplicate Epoch
                <input
                  value={challengeDuplicateForm.epoch}
                  onChange={(event) =>
                    setChallengeDuplicateForm((previous) => ({ ...previous, epoch: event.target.value }))
                  }
                  inputMode="numeric"
                />
              </label>
              <label>
                Duplicate Leaf Hash
                <input
                  value={challengeDuplicateForm.leafHash}
                  onChange={(event) =>
                    setChallengeDuplicateForm((previous) => ({ ...previous, leafHash: event.target.value }))
                  }
                  placeholder="0x..."
                />
              </label>
              <label>
                Index A
                <input
                  value={challengeDuplicateForm.indexA}
                  onChange={(event) =>
                    setChallengeDuplicateForm((previous) => ({ ...previous, indexA: event.target.value }))
                  }
                  inputMode="numeric"
                />
              </label>
              <label>
                Index B
                <input
                  value={challengeDuplicateForm.indexB}
                  onChange={(event) =>
                    setChallengeDuplicateForm((previous) => ({ ...previous, indexB: event.target.value }))
                  }
                  inputMode="numeric"
                />
              </label>
              <label className="proof-label">
                Proof A
                <textarea
                  value={challengeDuplicateForm.proofA}
                  onChange={(event) =>
                    setChallengeDuplicateForm((previous) => ({ ...previous, proofA: event.target.value }))
                  }
                />
              </label>
              <label className="proof-label">
                Proof B
                <textarea
                  value={challengeDuplicateForm.proofB}
                  onChange={(event) =>
                    setChallengeDuplicateForm((previous) => ({ ...previous, proofB: event.target.value }))
                  }
                />
              </label>
              <button type="submit" disabled={isPendingTx}>
                Challenge Duplicate Leaf
              </button>
            </form>

            <div className="action-grid">
              <label>
                Claim Settlement Challenge Reward (PLS)
                <input
                  value={claimSettlementRewardAmount}
                  onChange={(event) => setClaimSettlementRewardAmount(event.target.value)}
                />
                <button
                  type="button"
                  disabled={isPendingTx}
                  onClick={() =>
                    void (async () => {
                      try {
                        await runSettlementWrite("Claim settlement challenge reward", "claimChallengeReward", [
                          parseNetuid(),
                          parsePLS(claimSettlementRewardAmount, "Reward amount")
                        ]);
                      } catch (error) {
                        setStatusState("error", asErrorMessage(error));
                      }
                    })()
                  }
                >
                  Claim Challenge Reward
                </button>
              </label>
              <label>
                Claim Proposer Bond Refund (PLS)
                <input value={claimBondRefundAmount} onChange={(event) => setClaimBondRefundAmount(event.target.value)} />
                <button
                  type="button"
                  disabled={isPendingTx}
                  onClick={() =>
                    void (async () => {
                      try {
                        await runSettlementWrite("Claim proposer bond refund", "claimProposerBondRefund", [
                          parseNetuid(),
                          parsePLS(claimBondRefundAmount, "Refund amount")
                        ]);
                      } catch (error) {
                        setStatusState("error", asErrorMessage(error));
                      }
                    })()
                  }
                >
                  Claim Bond Refund
                </button>
              </label>
            </div>
          </section>
        </>
      )}
    </main>
  );
}

export default App;

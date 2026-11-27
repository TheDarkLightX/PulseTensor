import { parseAbi } from "viem";

export const pulsetensorExactInferenceAbi = parseAbi([
  "function CORE() view returns (address)",
  "function CORE_RUNTIME_CODE_HASH() view returns (bytes32)",
  "function MAX_TASK_DURATION_BLOCKS() view returns (uint64)",
  "function MAX_PROOF_BYTES() view returns (uint256)",
  "function nextTaskId() view returns (uint256)",
  "function nextVerifierConfigId() view returns (uint64)",
  "function totalOpenTasks() view returns (uint256)",
  "function totalFundedWei() view returns (uint256)",
  "function totalSettledWei() view returns (uint256)",
  "function totalRefundedWei() view returns (uint256)",
  "function totalProtocolFeesWei() view returns (uint256)",
  "function totalClaimedWei() view returns (uint256)",
  "function totalOpenEscrowWei() view returns (uint256)",
  "function totalClaimableWei() view returns (uint256)",
  "function claimableWei(address claimant) view returns (uint256)",
  "function openTaskCountByConfig(uint16 netuid, uint64 configId) view returns (uint256)",
  "function accountingInvariantHolds() view returns (bool)",
  "function verifierConfigs(uint64 configId) view returns ((bool exists, bool revoked, uint16 netuid, uint16 protocolFeeBps, bytes4 proofSelector, uint64 activatedAtBlock, uint64 stopNewTasksAtBlock, address adapter, address treasury, bytes32 adapterRuntimeCodeHash, bytes32 verifierRuntimeCodeHash, bytes32 programId, bytes32 relationId, bytes32 proofSystemId))",
  "function exactInferenceTasks(uint256 taskId) view returns ((uint8 status, uint16 netuid, uint16 mechid, uint16 protocolFeeBps, uint64 verifierConfigId, uint64 createdAtBlock, uint64 deadlineBlock, address requester, address refundTo, address treasury, uint256 rewardWei, bytes32 requestNullifier, bytes32 inputCommitment, bytes32 modelCommitment, bytes32 taskSpecHash))",
  "function verifierCodeAvailable(uint64 configId) view returns (bool)",
  "function verifierAcceptsNewTasks(uint64 configId) view returns (bool)",
  "function verifierCanSettleOpenTasks(uint64 configId) view returns (bool)",
  "function adapterRuntimeCodeHashMatches(uint64 configId) view returns (bool)",
  "function currentAdapterRuntimeCodeHash(uint64 configId) view returns (bytes32)",
  "function createExactInferenceTask(uint16 netuid, uint16 mechid, uint64 verifierConfigId, bytes32 inputCommitment, bytes32 modelCommitment, uint64 requesterNonce, uint64 deadlineBlock, address refundTo) payable returns (uint256 taskId)",
  "function submitExactInferenceProof(uint256 taskId, address provider, address beneficiary, uint8 classIndex, int64[4] scores, bytes proof)",
  "function refundExpired(uint256 taskId)",
  "function refundRevoked(uint256 taskId)",
  "function refundVerifierUnavailable(uint256 taskId)",
  "function claim(address to, uint256 amountWei)"
]);

export const riscZeroAdapterReadAbi = parseAbi([
  "function RISC_ZERO_VERIFIER() view returns (address)",
  "function RISC_ZERO_GROTH16_V3_PROOF_SYSTEM_ID() view returns (bytes32)",
  "function RISC_ZERO_VERSION_HASH() view returns (bytes32)",
  "function RISC_ZERO_GROTH16_V3_SEAL_BYTES() view returns (uint256)",
  "function VERIFIER_RUNTIME_CODE_HASH() view returns (bytes32)",
  "function PROOF_SELECTOR() view returns (bytes4)",
  "function proofSystemId() view returns (bytes32)",
  "function proofSelector() view returns (bytes4)",
  "function verifierRuntimeCodeHash() view returns (bytes32)",
  "function verifierRuntimeCodeHashMatches() view returns (bool)"
]);

export const riscZeroBaseVerifierReadAbi = parseAbi([
  "function SELECTOR() view returns (bytes4)",
  "function VERSION() view returns (string)"
]);

export const exactCoreReadAbi = parseAbi([
  "function subnetGovernance(uint16 netuid) view returns (address)",
  "function subnetPaused(uint16 netuid) view returns (bool)"
]);

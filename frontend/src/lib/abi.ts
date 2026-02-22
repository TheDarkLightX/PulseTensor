import { parseAbi } from "viem";

export const pulsetensorCoreAbi = parseAbi([
  "function nextNetuid() view returns (uint16)",
  "function subnets(uint16 netuid) view returns (bool exists, uint16 maxValidators, uint16 ownerFeeBps, uint64 revealDelayBlocks, uint64 epochLengthBlocks, uint256 minValidatorStake, uint256 totalStake)",
  "function currentEpoch(uint16 netuid) view returns (uint64)",
  "function subnetEmissionPool(uint16 netuid) view returns (uint256)",
  "function subnetEpochEmissionBase(uint16 netuid) view returns (uint256)",
  "function subnetEpochEmissionFloor(uint16 netuid) view returns (uint256)",
  "function subnetEpochEmissionHalvingPeriod(uint16 netuid) view returns (uint64)",
  "function subnetEpochEmissionStart(uint16 netuid) view returns (uint64)",
  "function subnetEmissionSmoothDecayEnabled(uint16 netuid) view returns (bool)",
  "function quoteSubnetEpochEmission(uint16 netuid, uint64 epoch) view returns (uint256)",
  "function stakeOf(uint16 netuid, address staker) view returns (uint256)",
  "function canValidate(uint16 netuid, address validator) view returns (bool)",
  "function isValidator(uint16 netuid, address validator) view returns (bool)",
  "function isMiner(uint16 netuid, address miner) view returns (bool)",
  "function challengeRewardOf(uint16 netuid, address challenger) view returns (uint256)",
  "function createSubnet(uint16 maxValidators, uint256 minValidatorStake, uint16 ownerFeeBps, uint64 revealDelayBlocks, uint64 epochLengthBlocks) returns (uint16)",
  "function addStake(uint16 netuid) payable",
  "function removeStake(uint16 netuid, uint256 amount)",
  "function registerValidator(uint16 netuid)",
  "function unregisterValidator(uint16 netuid)",
  "function registerMiner(uint16 netuid)",
  "function unregisterMiner(uint16 netuid)",
  "function fundSubnetEmission(uint16 netuid) payable",
  "function claimChallengeReward(uint16 netuid, uint256 amount)"
]);

export const pulsetensorSettlementAbi = parseAbi([
  "function batchPolicies(uint16 netuid, uint16 mechid) view returns (bool enabled, uint64 challengeWindowBlocks, uint32 maxBatchItems, uint256 minProposerBondWei)",
  "function inferenceBatches(uint16 netuid, uint16 mechid, uint64 epoch) view returns (bytes32 batchRoot, uint32 itemCount, uint256 feeTotal, uint256 bond, address proposer, uint64 committedAtBlock, uint64 challengeDeadlineBlock, bool challenged, bool finalized)",
  "function challengeRewardOf(uint16 netuid, address challenger) view returns (uint256)",
  "function proposerBondRefundOf(uint16 netuid, address proposer) view returns (uint256)",
  "function settledLeaves(uint16 netuid, uint16 mechid, bytes32 leafHash) view returns (bool)",
  "function queueBatchPolicyUpdate(uint16 netuid, uint16 mechid, bool enabled, uint64 challengeWindowBlocks, uint32 maxBatchItems, uint256 minProposerBondWei) returns (bytes32 actionId, uint64 readyAtBlock)",
  "function configureBatchPolicy(uint16 netuid, uint16 mechid, bool enabled, uint64 challengeWindowBlocks, uint32 maxBatchItems, uint256 minProposerBondWei)",
  "function commitInferenceBatchRoot(uint16 netuid, uint16 mechid, uint64 epoch, bytes32 batchRoot, uint32 itemCount, uint256 feeTotal) payable",
  "function finalizeInferenceBatch(uint16 netuid, uint16 mechid, uint64 epoch)",
  "function settleFinalizedInferenceLeaf(uint16 netuid, uint16 mechid, uint64 epoch, bytes32 leafHash, uint256 index, bytes32[] merkleProof)",
  "function challengeInferenceLeafReplay(uint16 netuid, uint16 mechid, uint64 epoch, bytes32 leafHash, uint256 index, bytes32[] merkleProof, uint64 priorEpoch, uint256 priorIndex, bytes32[] priorMerkleProof)",
  "function challengeInferenceLeafDuplicate(uint16 netuid, uint16 mechid, uint64 epoch, bytes32 leafHash, uint256 indexA, bytes32[] proofA, uint256 indexB, bytes32[] proofB)",
  "function claimChallengeReward(uint16 netuid, uint256 amount)",
  "function claimProposerBondRefund(uint16 netuid, uint256 amount)"
]);

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IPulseTensorCore {
    function subnetGovernance(uint16 netuid) external view returns (address);
    function subnetPaused(uint16 netuid) external view returns (bool);
    function canValidate(uint16 netuid, address validator) external view returns (bool);
    function currentEpoch(uint16 netuid) external view returns (uint64);
}

contract PulseTensorInferenceSettlement {
    uint16 public constant BPS_DENOMINATOR = 10_000;
    uint16 public constant CHALLENGE_REWARD_BPS = 2_000;
    uint64 public constant POLICY_UPDATE_DELAY_BLOCKS = 2;
    uint64 public constant MIN_CHALLENGE_WINDOW_BLOCKS = 1;
    uint64 public constant MAX_CHALLENGE_WINDOW_BLOCKS = 200_000;
    uint32 public constant MAX_BATCH_ITEMS = 4096;

    error UnauthorizedGovernance();
    error GovernanceActionNotReady();
    error InvalidPolicy();
    error InferenceBatchDisabled();
    error CoreSubnetPaused();
    error NotEligibleProposer();
    error InvalidBatchEpoch();
    error InvalidBatchRoot();
    error InvalidBatchItemCount();
    error InvalidBatchIndex();
    error BondTooLow();
    error BatchAlreadyCommitted();
    error BatchNotCommitted();
    error BatchAlreadyFinalized();
    error BatchAlreadyChallenged();
    error ChallengeWindowOpen();
    error ChallengeWindowClosed();
    error BatchNotFinalized();
    error PriorBatchNotCommitted();
    error PriorBatchNotFinalized();
    error InvalidReplayEpoch();
    error InvalidMerkleProof();
    error LeafAlreadySettled();
    error LeafNotSettled();
    error Reentrancy();
    error TransferFailed();

    struct BatchPolicy {
        bool enabled;
        uint64 challengeWindowBlocks;
        uint32 maxBatchItems;
        uint256 minProposerBondWei;
    }

    struct InferenceBatch {
        bytes32 batchRoot;
        uint32 itemCount;
        uint256 feeTotal;
        uint256 bond;
        address proposer;
        uint64 committedAtBlock;
        uint64 challengeDeadlineBlock;
        bool challenged;
        bool finalized;
    }

    IPulseTensorCore public immutable CORE;
    uint256 private lockState = 1;

    mapping(uint16 => mapping(uint16 => BatchPolicy)) public batchPolicies;
    mapping(uint16 => mapping(bytes32 => uint64)) public queuedBatchPolicyReadyAt;
    mapping(uint16 => mapping(uint16 => mapping(uint64 => InferenceBatch))) public inferenceBatches;
    mapping(uint16 => mapping(uint16 => mapping(bytes32 => bool))) public settledLeaves;
    mapping(uint16 => mapping(address => uint256)) public challengeRewardOf;
    mapping(uint16 => mapping(address => uint256)) public proposerBondRefundOf;

    event BatchPolicyConfigured(
        uint16 indexed netuid,
        uint16 indexed mechid,
        bool enabled,
        uint64 challengeWindowBlocks,
        uint32 maxBatchItems,
        uint256 minProposerBondWei
    );
    event BatchPolicyUpdateQueued(
        uint16 indexed netuid,
        uint16 indexed mechid,
        bool enabled,
        uint64 challengeWindowBlocks,
        uint32 maxBatchItems,
        uint256 minProposerBondWei,
        bytes32 actionId,
        uint64 readyAtBlock
    );
    event InferenceBatchCommitted(
        uint16 indexed netuid,
        uint16 indexed mechid,
        uint64 indexed epoch,
        bytes32 batchRoot,
        uint32 itemCount,
        uint256 feeTotal,
        address proposer,
        uint256 bond,
        uint64 challengeDeadlineBlock
    );
    event InferenceBatchFinalized(
        uint16 indexed netuid, uint16 indexed mechid, uint64 indexed epoch, address proposer, uint256 bondRefunded
    );
    event InferenceBatchChallenged(
        uint16 indexed netuid,
        uint16 indexed mechid,
        uint64 indexed epoch,
        address challenger,
        bytes32 challengedLeafHash,
        uint256 challengerRewardAmount,
        uint256 retainedBondAmount
    );
    event InferenceLeafSettled(uint16 indexed netuid, uint16 indexed mechid, uint64 indexed epoch, bytes32 leafHash);
    event ChallengeRewardClaimed(
        uint16 indexed netuid, address indexed challenger, uint256 amount, uint256 remainingClaimableBalance
    );
    event ProposerBondRefundClaimed(
        uint16 indexed netuid, address indexed proposer, uint256 amount, uint256 remainingClaimableBalance
    );

    modifier nonReentrant() {
        if (lockState != 1) revert Reentrancy();
        lockState = 2;
        _;
        lockState = 1;
    }

    constructor(address coreAddress) {
        if (coreAddress == address(0)) revert TransferFailed();
        CORE = IPulseTensorCore(coreAddress);
    }

    function queueBatchPolicyUpdate(
        uint16 netuid,
        uint16 mechid,
        bool enabled,
        uint64 challengeWindowBlocks,
        uint32 maxBatchItems,
        uint256 minProposerBondWei
    ) external returns (bytes32 actionId, uint64 readyAtBlock) {
        if (CORE.subnetGovernance(netuid) != msg.sender) revert UnauthorizedGovernance();
        _validatePolicy(enabled, challengeWindowBlocks, maxBatchItems, minProposerBondWei);

        actionId = _batchPolicyActionId(netuid, mechid, enabled, challengeWindowBlocks, maxBatchItems, minProposerBondWei);
        uint256 readyAt = block.number + POLICY_UPDATE_DELAY_BLOCKS;
        if (readyAt > type(uint64).max) revert InvalidPolicy();
        readyAtBlock = uint64(readyAt);
        queuedBatchPolicyReadyAt[netuid][actionId] = readyAtBlock;

        emit BatchPolicyUpdateQueued(
            netuid,
            mechid,
            enabled,
            challengeWindowBlocks,
            maxBatchItems,
            minProposerBondWei,
            actionId,
            readyAtBlock
        );
    }

    function configureBatchPolicy(
        uint16 netuid,
        uint16 mechid,
        bool enabled,
        uint64 challengeWindowBlocks,
        uint32 maxBatchItems,
        uint256 minProposerBondWei
    ) external {
        if (CORE.subnetGovernance(netuid) != msg.sender) revert UnauthorizedGovernance();
        _validatePolicy(enabled, challengeWindowBlocks, maxBatchItems, minProposerBondWei);

        bytes32 actionId =
            _batchPolicyActionId(netuid, mechid, enabled, challengeWindowBlocks, maxBatchItems, minProposerBondWei);
        uint64 readyAtBlock = queuedBatchPolicyReadyAt[netuid][actionId];
        if (readyAtBlock == 0 || block.number < readyAtBlock) revert GovernanceActionNotReady();
        delete queuedBatchPolicyReadyAt[netuid][actionId];

        batchPolicies[netuid][mechid] = BatchPolicy({
            enabled: enabled,
            challengeWindowBlocks: challengeWindowBlocks,
            maxBatchItems: maxBatchItems,
            minProposerBondWei: minProposerBondWei
        });
        emit BatchPolicyConfigured(netuid, mechid, enabled, challengeWindowBlocks, maxBatchItems, minProposerBondWei);
    }

    function commitInferenceBatchRoot(
        uint16 netuid,
        uint16 mechid,
        uint64 epoch,
        bytes32 batchRoot,
        uint32 itemCount,
        uint256 feeTotal
    ) external payable {
        BatchPolicy memory policy = batchPolicies[netuid][mechid];
        if (!policy.enabled) revert InferenceBatchDisabled();
        if (CORE.subnetPaused(netuid)) revert CoreSubnetPaused();
        if (!CORE.canValidate(netuid, msg.sender)) revert NotEligibleProposer();
        if (epoch != CORE.currentEpoch(netuid)) revert InvalidBatchEpoch();
        if (batchRoot == bytes32(0)) revert InvalidBatchRoot();
        if (itemCount == 0 || itemCount > policy.maxBatchItems) revert InvalidBatchItemCount();
        if (msg.value < policy.minProposerBondWei) revert BondTooLow();

        InferenceBatch storage batch = inferenceBatches[netuid][mechid][epoch];
        if (batch.batchRoot != bytes32(0)) revert BatchAlreadyCommitted();

        uint256 challengeDeadline = block.number + policy.challengeWindowBlocks;
        if (challengeDeadline > type(uint64).max) revert InvalidPolicy();
        inferenceBatches[netuid][mechid][epoch] = InferenceBatch({
            batchRoot: batchRoot,
            itemCount: itemCount,
            feeTotal: feeTotal,
            bond: msg.value,
            proposer: msg.sender,
            committedAtBlock: uint64(block.number),
            challengeDeadlineBlock: uint64(challengeDeadline),
            challenged: false,
            finalized: false
        });

        emit InferenceBatchCommitted(
            netuid, mechid, epoch, batchRoot, itemCount, feeTotal, msg.sender, msg.value, uint64(challengeDeadline)
        );
    }

    function finalizeInferenceBatch(uint16 netuid, uint16 mechid, uint64 epoch) external nonReentrant {
        InferenceBatch storage batch = inferenceBatches[netuid][mechid][epoch];
        if (batch.batchRoot == bytes32(0)) revert BatchNotCommitted();
        if (batch.finalized) revert BatchAlreadyFinalized();
        if (batch.challenged) revert BatchAlreadyChallenged();
        if (block.number <= batch.challengeDeadlineBlock) revert ChallengeWindowOpen();

        batch.finalized = true;
        uint256 bondRefunded = batch.bond;
        batch.bond = 0;
        if (bondRefunded != 0) {
            proposerBondRefundOf[netuid][batch.proposer] += bondRefunded;
        }

        emit InferenceBatchFinalized(netuid, mechid, epoch, batch.proposer, bondRefunded);
    }

    function settleFinalizedInferenceLeaf(
        uint16 netuid,
        uint16 mechid,
        uint64 epoch,
        bytes32 leafHash,
        uint256 index,
        bytes32[] calldata merkleProof
    ) external {
        InferenceBatch storage batch = inferenceBatches[netuid][mechid][epoch];
        if (batch.batchRoot == bytes32(0)) revert BatchNotCommitted();
        if (!batch.finalized) revert BatchNotFinalized();
        if (settledLeaves[netuid][mechid][leafHash]) revert LeafAlreadySettled();
        _validateBatchIndex(index, batch.itemCount);
        if (!_verifyMerkleProof(leafHash, index, merkleProof, batch.batchRoot, batch.itemCount)) revert InvalidMerkleProof();

        settledLeaves[netuid][mechid][leafHash] = true;
        emit InferenceLeafSettled(netuid, mechid, epoch, leafHash);
    }

    function challengeInferenceLeafReplay(
        uint16 netuid,
        uint16 mechid,
        uint64 epoch,
        bytes32 leafHash,
        uint256 index,
        bytes32[] calldata merkleProof,
        uint64 priorEpoch,
        uint256 priorIndex,
        bytes32[] calldata priorMerkleProof
    ) external {
        InferenceBatch storage batch = inferenceBatches[netuid][mechid][epoch];
        if (batch.batchRoot == bytes32(0)) revert BatchNotCommitted();
        if (batch.finalized) revert BatchAlreadyFinalized();
        if (batch.challenged) revert BatchAlreadyChallenged();
        if (block.number > batch.challengeDeadlineBlock) revert ChallengeWindowClosed();
        _validateBatchIndex(index, batch.itemCount);
        if (!_verifyMerkleProof(leafHash, index, merkleProof, batch.batchRoot, batch.itemCount)) revert InvalidMerkleProof();
        if (priorEpoch >= epoch) revert InvalidReplayEpoch();

        InferenceBatch storage priorBatch = inferenceBatches[netuid][mechid][priorEpoch];
        if (priorBatch.batchRoot == bytes32(0)) revert PriorBatchNotCommitted();
        if (!priorBatch.finalized) revert PriorBatchNotFinalized();
        _validateBatchIndex(priorIndex, priorBatch.itemCount);
        if (!_verifyMerkleProof(leafHash, priorIndex, priorMerkleProof, priorBatch.batchRoot, priorBatch.itemCount)) {
            revert InvalidMerkleProof();
        }

        _slashBatchBond(netuid, mechid, epoch, leafHash);
    }

    function challengeInferenceLeafDuplicate(
        uint16 netuid,
        uint16 mechid,
        uint64 epoch,
        bytes32 leafHash,
        uint256 indexA,
        bytes32[] calldata proofA,
        uint256 indexB,
        bytes32[] calldata proofB
    ) external {
        if (indexA == indexB) revert InvalidMerkleProof();
        InferenceBatch storage batch = inferenceBatches[netuid][mechid][epoch];
        if (batch.batchRoot == bytes32(0)) revert BatchNotCommitted();
        if (batch.finalized) revert BatchAlreadyFinalized();
        if (batch.challenged) revert BatchAlreadyChallenged();
        if (block.number > batch.challengeDeadlineBlock) revert ChallengeWindowClosed();
        _validateBatchIndex(indexA, batch.itemCount);
        _validateBatchIndex(indexB, batch.itemCount);
        if (!_verifyMerkleProof(leafHash, indexA, proofA, batch.batchRoot, batch.itemCount)) revert InvalidMerkleProof();
        if (!_verifyMerkleProof(leafHash, indexB, proofB, batch.batchRoot, batch.itemCount)) revert InvalidMerkleProof();

        _slashBatchBond(netuid, mechid, epoch, leafHash);
    }

    function claimChallengeReward(uint16 netuid, uint256 amount) external nonReentrant {
        uint256 claimableAmount = challengeRewardOf[netuid][msg.sender];
        if (amount == 0 || amount > claimableAmount) revert TransferFailed();

        challengeRewardOf[netuid][msg.sender] = claimableAmount - amount;
        _transferValue(payable(msg.sender), amount);
        emit ChallengeRewardClaimed(netuid, msg.sender, amount, challengeRewardOf[netuid][msg.sender]);
    }

    function claimProposerBondRefund(uint16 netuid, uint256 amount) external nonReentrant {
        uint256 claimableAmount = proposerBondRefundOf[netuid][msg.sender];
        if (amount == 0 || amount > claimableAmount) revert TransferFailed();

        proposerBondRefundOf[netuid][msg.sender] = claimableAmount - amount;
        _transferValue(payable(msg.sender), amount);
        emit ProposerBondRefundClaimed(netuid, msg.sender, amount, proposerBondRefundOf[netuid][msg.sender]);
    }

    function _slashBatchBond(uint16 netuid, uint16 mechid, uint64 epoch, bytes32 leafHash) internal {
        InferenceBatch storage batch = inferenceBatches[netuid][mechid][epoch];
        batch.challenged = true;
        uint256 slashedBond = batch.bond;
        batch.bond = 0;

        uint256 challengerRewardAmount = (slashedBond * CHALLENGE_REWARD_BPS) / BPS_DENOMINATOR;
        if (challengerRewardAmount == 0 && slashedBond != 0) {
            challengerRewardAmount = 1;
        }
        if (challengerRewardAmount > slashedBond) {
            challengerRewardAmount = slashedBond;
        }
        uint256 retainedBondAmount = slashedBond - challengerRewardAmount;
        if (challengerRewardAmount != 0) {
            challengeRewardOf[netuid][msg.sender] += challengerRewardAmount;
        }

        emit InferenceBatchChallenged(
            netuid, mechid, epoch, msg.sender, leafHash, challengerRewardAmount, retainedBondAmount
        );
    }

    function _validatePolicy(
        bool enabled,
        uint64 challengeWindowBlocks,
        uint32 maxBatchItems,
        uint256 minProposerBondWei
    ) internal pure {
        if (!enabled) {
            if (challengeWindowBlocks != 0 || maxBatchItems != 0 || minProposerBondWei != 0) {
                revert InvalidPolicy();
            }
            return;
        }

        if (challengeWindowBlocks < MIN_CHALLENGE_WINDOW_BLOCKS || challengeWindowBlocks > MAX_CHALLENGE_WINDOW_BLOCKS)
        {
            revert InvalidPolicy();
        }
        if (maxBatchItems == 0 || maxBatchItems > MAX_BATCH_ITEMS) revert InvalidPolicy();
        if (minProposerBondWei == 0) revert InvalidPolicy();
    }

    function _validateBatchIndex(uint256 index, uint32 itemCount) internal pure {
        if (index >= itemCount) revert InvalidBatchIndex();
    }

    function _batchPolicyActionId(
        uint16 netuid,
        uint16 mechid,
        bool enabled,
        uint64 challengeWindowBlocks,
        uint32 maxBatchItems,
        uint256 minProposerBondWei
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                "BATCH_POLICY",
                netuid,
                mechid,
                enabled,
                challengeWindowBlocks,
                maxBatchItems,
                minProposerBondWei
            )
        );
    }

    function _verifyMerkleProof(
        bytes32 leafHash,
        uint256 index,
        bytes32[] calldata merkleProof,
        bytes32 root,
        uint32 itemCount
    )
        internal
        pure
        returns (bool)
    {
        if (itemCount > 1 && merkleProof.length == 0) {
            return false;
        }
        bytes32 computedHash = leafHash;
        for (uint256 proofIndex = 0; proofIndex < merkleProof.length; proofIndex++) {
            bytes32 proofElement = merkleProof[proofIndex];
            if ((index & 1) == 0) {
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
            index >>= 1;
        }
        if (index != 0) {
            return false;
        }
        return computedHash == root;
    }

    function _transferValue(address payable recipient, uint256 amount) internal {
        (bool sent,) = recipient.call{value: amount}("");
        if (!sent) revert TransferFailed();
    }
}

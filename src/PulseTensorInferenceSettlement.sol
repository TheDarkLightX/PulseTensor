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
    uint16 public constant MAX_PROTOCOL_FEE_BPS = 3_000;
    bytes32 public constant INFERENCE_LEAF_DOMAIN_TAG = keccak256("PULSETENSOR_INFERENCE_LEAF_V1");
    uint64 public constant POLICY_UPDATE_DELAY_BLOCKS = 2;
    uint64 public constant POLICY_UPDATE_EXPIRY_BLOCKS = 200_000;
    uint64 public constant MIN_CHALLENGE_WINDOW_BLOCKS = 1;
    uint64 public constant MAX_CHALLENGE_WINDOW_BLOCKS = 200_000;
    uint32 public constant MAX_BATCH_ITEMS = 4096;

    error UnauthorizedGovernance();
    error GovernanceActionAlreadyQueued();
    error GovernanceActionNotQueued();
    error GovernanceActionNotReady();
    error GovernanceActionExpired();
    error GovernanceActionQueuedByMismatch();
    error InvalidPolicy();
    error InferenceBatchDisabled();
    error CoreSubnetPaused();
    error NotEligibleProposer();
    error InvalidBatchEpoch();
    error InvalidBatchRoot();
    error InvalidBatchItemCount();
    error InvalidBatchIndex();
    error BondTooLow();
    error InvalidFeePolicy();
    error InvalidFeeAmount();
    error FeeFundingExceedsBatchTotal();
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

    struct FeePolicy {
        bool enabled;
        uint16 protocolFeeBps;
        uint16 treasuryFeeBps;
        address treasurySink;
        address minerSink;
    }

    IPulseTensorCore public immutable CORE;
    uint256 private lockState = 1;

    mapping(uint16 => mapping(uint16 => BatchPolicy)) public batchPolicies;
    mapping(uint16 => mapping(bytes32 => uint64)) public queuedBatchPolicyReadyAt;
    mapping(uint16 => mapping(bytes32 => address)) public queuedBatchPolicyQueuedBy;
    mapping(uint16 => mapping(uint16 => FeePolicy)) public feePolicies;
    mapping(uint16 => mapping(bytes32 => uint64)) public queuedFeePolicyReadyAt;
    mapping(uint16 => mapping(bytes32 => address)) public queuedFeePolicyQueuedBy;
    mapping(uint16 => mapping(uint16 => mapping(uint64 => InferenceBatch))) public inferenceBatches;
    mapping(uint16 => mapping(uint16 => mapping(uint64 => uint256))) public batchFeeFunded;
    mapping(uint16 => mapping(uint16 => mapping(uint64 => mapping(address => uint256)))) public batchFeeEscrowOf;
    mapping(uint16 => mapping(uint16 => mapping(uint64 => uint16))) public batchProtocolFeeBps;
    mapping(uint16 => mapping(uint16 => mapping(uint64 => uint16))) public batchTreasuryFeeBps;
    mapping(uint16 => mapping(uint16 => mapping(uint64 => address))) public batchTreasurySink;
    mapping(uint16 => mapping(uint16 => mapping(uint64 => address))) public batchMinerSink;
    mapping(uint16 => mapping(uint16 => mapping(bytes32 => bool))) public settledLeaves;
    mapping(uint16 => mapping(address => uint256)) public challengeRewardOf;
    mapping(uint16 => mapping(address => uint256)) public proposerBondRefundOf;
    mapping(uint16 => mapping(address => uint256)) public inferenceFeeClaimOf;

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
    event BatchPolicyUpdateCancelled(uint16 indexed netuid, uint16 indexed mechid, bytes32 indexed actionId);
    event FeePolicyConfigured(
        uint16 indexed netuid,
        uint16 indexed mechid,
        bool enabled,
        uint16 protocolFeeBps,
        uint16 treasuryFeeBps,
        address treasurySink,
        address minerSink
    );
    event FeePolicyUpdateQueued(
        uint16 indexed netuid,
        uint16 indexed mechid,
        bool enabled,
        uint16 protocolFeeBps,
        uint16 treasuryFeeBps,
        address treasurySink,
        address minerSink,
        bytes32 actionId,
        uint64 readyAtBlock
    );
    event FeePolicyUpdateCancelled(uint16 indexed netuid, uint16 indexed mechid, bytes32 indexed actionId);
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
    event InferenceBatchFeeFunded(
        uint16 indexed netuid,
        uint16 indexed mechid,
        uint64 indexed epoch,
        address funder,
        uint256 amount,
        uint256 fundedTotal,
        uint256 declaredFeeTotal
    );
    event InferenceBatchFeeWithdrawn(
        uint16 indexed netuid,
        uint16 indexed mechid,
        uint64 indexed epoch,
        address funder,
        uint256 amount,
        uint256 fundedTotal
    );
    event InferenceBatchFeesDistributed(
        uint16 indexed netuid,
        uint16 indexed mechid,
        uint64 indexed epoch,
        address proposer,
        address treasurySink,
        address minerSink,
        uint256 fundedTotal,
        uint256 proposerAmount,
        uint256 treasuryAmount,
        uint256 minerAmount
    );
    event InferenceFeeClaimed(
        uint16 indexed netuid, address indexed recipient, uint256 amount, uint256 remainingClaimableBalance
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

        actionId =
            _batchPolicyActionId(netuid, mechid, enabled, challengeWindowBlocks, maxBatchItems, minProposerBondWei);
        uint64 existingReadyAtBlock = queuedBatchPolicyReadyAt[netuid][actionId];
        if (existingReadyAtBlock != 0) {
            if (!_isGovernanceActionExpired(existingReadyAtBlock)) revert GovernanceActionAlreadyQueued();
            delete queuedBatchPolicyReadyAt[netuid][actionId];
            delete queuedBatchPolicyQueuedBy[netuid][actionId];
        }

        uint256 readyAt = block.number + POLICY_UPDATE_DELAY_BLOCKS;
        if (readyAt > type(uint64).max) revert InvalidPolicy();
        readyAtBlock = uint64(readyAt);
        queuedBatchPolicyReadyAt[netuid][actionId] = readyAtBlock;
        queuedBatchPolicyQueuedBy[netuid][actionId] = msg.sender;

        emit BatchPolicyUpdateQueued(
            netuid, mechid, enabled, challengeWindowBlocks, maxBatchItems, minProposerBondWei, actionId, readyAtBlock
        );
    }

    function cancelBatchPolicyUpdate(
        uint16 netuid,
        uint16 mechid,
        bool enabled,
        uint64 challengeWindowBlocks,
        uint32 maxBatchItems,
        uint256 minProposerBondWei
    ) external {
        if (CORE.subnetGovernance(netuid) != msg.sender) revert UnauthorizedGovernance();
        bytes32 actionId =
            _batchPolicyActionId(netuid, mechid, enabled, challengeWindowBlocks, maxBatchItems, minProposerBondWei);
        if (queuedBatchPolicyReadyAt[netuid][actionId] == 0) revert GovernanceActionNotQueued();
        delete queuedBatchPolicyReadyAt[netuid][actionId];
        delete queuedBatchPolicyQueuedBy[netuid][actionId];
        emit BatchPolicyUpdateCancelled(netuid, mechid, actionId);
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
        if (readyAtBlock == 0) revert GovernanceActionNotQueued();
        address queuedBy = queuedBatchPolicyQueuedBy[netuid][actionId];
        if (queuedBy == address(0) || queuedBy != msg.sender) revert GovernanceActionQueuedByMismatch();
        if (block.number < readyAtBlock) revert GovernanceActionNotReady();
        if (_isGovernanceActionExpired(readyAtBlock)) {
            delete queuedBatchPolicyReadyAt[netuid][actionId];
            delete queuedBatchPolicyQueuedBy[netuid][actionId];
            revert GovernanceActionExpired();
        }
        delete queuedBatchPolicyReadyAt[netuid][actionId];
        delete queuedBatchPolicyQueuedBy[netuid][actionId];

        batchPolicies[netuid][mechid] = BatchPolicy({
            enabled: enabled,
            challengeWindowBlocks: challengeWindowBlocks,
            maxBatchItems: maxBatchItems,
            minProposerBondWei: minProposerBondWei
        });
        emit BatchPolicyConfigured(netuid, mechid, enabled, challengeWindowBlocks, maxBatchItems, minProposerBondWei);
    }

    function queueFeePolicyUpdate(
        uint16 netuid,
        uint16 mechid,
        bool enabled,
        uint16 protocolFeeBps,
        uint16 treasuryFeeBps,
        address treasurySink,
        address minerSink
    ) external returns (bytes32 actionId, uint64 readyAtBlock) {
        if (CORE.subnetGovernance(netuid) != msg.sender) revert UnauthorizedGovernance();
        _validateFeePolicy(enabled, protocolFeeBps, treasuryFeeBps, treasurySink, minerSink);

        actionId = _feePolicyActionId(netuid, mechid, enabled, protocolFeeBps, treasuryFeeBps, treasurySink, minerSink);
        uint64 existingReadyAtBlock = queuedFeePolicyReadyAt[netuid][actionId];
        if (existingReadyAtBlock != 0) {
            if (!_isGovernanceActionExpired(existingReadyAtBlock)) revert GovernanceActionAlreadyQueued();
            delete queuedFeePolicyReadyAt[netuid][actionId];
            delete queuedFeePolicyQueuedBy[netuid][actionId];
        }

        uint256 readyAt = block.number + POLICY_UPDATE_DELAY_BLOCKS;
        if (readyAt > type(uint64).max) revert InvalidPolicy();
        readyAtBlock = uint64(readyAt);
        queuedFeePolicyReadyAt[netuid][actionId] = readyAtBlock;
        queuedFeePolicyQueuedBy[netuid][actionId] = msg.sender;

        emit FeePolicyUpdateQueued(
            netuid, mechid, enabled, protocolFeeBps, treasuryFeeBps, treasurySink, minerSink, actionId, readyAtBlock
        );
    }

    function cancelFeePolicyUpdate(
        uint16 netuid,
        uint16 mechid,
        bool enabled,
        uint16 protocolFeeBps,
        uint16 treasuryFeeBps,
        address treasurySink,
        address minerSink
    ) external {
        if (CORE.subnetGovernance(netuid) != msg.sender) revert UnauthorizedGovernance();
        bytes32 actionId =
            _feePolicyActionId(netuid, mechid, enabled, protocolFeeBps, treasuryFeeBps, treasurySink, minerSink);
        if (queuedFeePolicyReadyAt[netuid][actionId] == 0) revert GovernanceActionNotQueued();
        delete queuedFeePolicyReadyAt[netuid][actionId];
        delete queuedFeePolicyQueuedBy[netuid][actionId];
        emit FeePolicyUpdateCancelled(netuid, mechid, actionId);
    }

    function configureFeePolicy(
        uint16 netuid,
        uint16 mechid,
        bool enabled,
        uint16 protocolFeeBps,
        uint16 treasuryFeeBps,
        address treasurySink,
        address minerSink
    ) external {
        if (CORE.subnetGovernance(netuid) != msg.sender) revert UnauthorizedGovernance();
        _validateFeePolicy(enabled, protocolFeeBps, treasuryFeeBps, treasurySink, minerSink);

        bytes32 actionId =
            _feePolicyActionId(netuid, mechid, enabled, protocolFeeBps, treasuryFeeBps, treasurySink, minerSink);
        uint64 readyAtBlock = queuedFeePolicyReadyAt[netuid][actionId];
        if (readyAtBlock == 0) revert GovernanceActionNotQueued();
        address queuedBy = queuedFeePolicyQueuedBy[netuid][actionId];
        if (queuedBy == address(0) || queuedBy != msg.sender) revert GovernanceActionQueuedByMismatch();
        if (block.number < readyAtBlock) revert GovernanceActionNotReady();
        if (_isGovernanceActionExpired(readyAtBlock)) {
            delete queuedFeePolicyReadyAt[netuid][actionId];
            delete queuedFeePolicyQueuedBy[netuid][actionId];
            revert GovernanceActionExpired();
        }
        delete queuedFeePolicyReadyAt[netuid][actionId];
        delete queuedFeePolicyQueuedBy[netuid][actionId];

        feePolicies[netuid][mechid] = FeePolicy({
            enabled: enabled,
            protocolFeeBps: protocolFeeBps,
            treasuryFeeBps: treasuryFeeBps,
            treasurySink: treasurySink,
            minerSink: minerSink
        });
        emit FeePolicyConfigured(netuid, mechid, enabled, protocolFeeBps, treasuryFeeBps, treasurySink, minerSink);
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
        _snapshotFeePolicy(netuid, mechid, epoch);
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

    function fundInferenceBatchFees(uint16 netuid, uint16 mechid, uint64 epoch) external payable {
        if (msg.value == 0) revert InvalidFeeAmount();
        InferenceBatch storage batch = inferenceBatches[netuid][mechid][epoch];
        if (batch.batchRoot == bytes32(0)) revert BatchNotCommitted();
        if (batch.finalized) revert BatchAlreadyFinalized();
        if (batch.challenged) revert BatchAlreadyChallenged();

        uint256 fundedTotal = batchFeeFunded[netuid][mechid][epoch] + msg.value;
        if (fundedTotal > batch.feeTotal) revert FeeFundingExceedsBatchTotal();
        batchFeeFunded[netuid][mechid][epoch] = fundedTotal;
        batchFeeEscrowOf[netuid][mechid][epoch][msg.sender] += msg.value;

        emit InferenceBatchFeeFunded(netuid, mechid, epoch, msg.sender, msg.value, fundedTotal, batch.feeTotal);
    }

    function withdrawInferenceBatchFees(uint16 netuid, uint16 mechid, uint64 epoch, uint256 amount)
        external
        nonReentrant
    {
        if (amount == 0) revert InvalidFeeAmount();
        InferenceBatch storage batch = inferenceBatches[netuid][mechid][epoch];
        if (batch.batchRoot == bytes32(0)) revert BatchNotCommitted();
        if (batch.finalized) revert BatchAlreadyFinalized();

        uint256 escrowed = batchFeeEscrowOf[netuid][mechid][epoch][msg.sender];
        if (amount > escrowed) revert TransferFailed();

        uint256 fundedTotal = batchFeeFunded[netuid][mechid][epoch];
        if (amount > fundedTotal) revert TransferFailed();

        batchFeeEscrowOf[netuid][mechid][epoch][msg.sender] = escrowed - amount;
        fundedTotal -= amount;
        batchFeeFunded[netuid][mechid][epoch] = fundedTotal;

        _transferValue(payable(msg.sender), amount);
        emit InferenceBatchFeeWithdrawn(netuid, mechid, epoch, msg.sender, amount, fundedTotal);
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

        uint256 fundedTotal = batchFeeFunded[netuid][mechid][epoch];
        if (fundedTotal != 0) {
            batchFeeFunded[netuid][mechid][epoch] = 0;
            _distributeBatchFees(netuid, mechid, epoch, batch.proposer, fundedTotal);
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
        if (!_verifyMerkleProof(leafHash, index, merkleProof, batch.batchRoot, batch.itemCount)) {
            revert InvalidMerkleProof();
        }

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
        if (!_verifyMerkleProof(leafHash, index, merkleProof, batch.batchRoot, batch.itemCount)) {
            revert InvalidMerkleProof();
        }
        if (priorEpoch >= epoch) revert InvalidReplayEpoch();

        InferenceBatch storage priorBatch = inferenceBatches[netuid][mechid][priorEpoch];
        if (priorBatch.batchRoot == bytes32(0)) revert PriorBatchNotCommitted();
        if (!priorBatch.finalized) revert PriorBatchNotFinalized();
        if (!settledLeaves[netuid][mechid][leafHash]) revert LeafNotSettled();
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
        if (!_verifyMerkleProof(leafHash, indexA, proofA, batch.batchRoot, batch.itemCount)) {
            revert InvalidMerkleProof();
        }
        if (!_verifyMerkleProof(leafHash, indexB, proofB, batch.batchRoot, batch.itemCount)) {
            revert InvalidMerkleProof();
        }

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

    function claimInferenceFee(uint16 netuid, uint256 amount) external nonReentrant {
        uint256 claimableAmount = inferenceFeeClaimOf[netuid][msg.sender];
        if (amount == 0 || amount > claimableAmount) revert TransferFailed();

        inferenceFeeClaimOf[netuid][msg.sender] = claimableAmount - amount;
        _transferValue(payable(msg.sender), amount);
        emit InferenceFeeClaimed(netuid, msg.sender, amount, inferenceFeeClaimOf[netuid][msg.sender]);
    }

    /// @notice Canonical domain-separated leaf helper for off-chain batch construction.
    /// @dev The settlement contract verifies only merkle inclusion; callers should use this helper
    ///      (or an equivalent domain-separated scheme) to avoid accidental cross-epoch/request collisions.
    function computeInferenceLeaf(uint16 netuid, uint16 mechid, uint64 epoch, bytes32 requestId, bytes32 resultHash)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(INFERENCE_LEAF_DOMAIN_TAG, netuid, mechid, epoch, requestId, resultHash));
    }

    function _slashBatchBond(uint16 netuid, uint16 mechid, uint64 epoch, bytes32 leafHash) internal {
        InferenceBatch storage batch = inferenceBatches[netuid][mechid][epoch];
        batch.challenged = true;
        uint256 slashedBond = batch.bond;
        batch.bond = 0;

        bool selfChallenge = msg.sender == batch.proposer;
        uint256 challengerRewardAmount = 0;
        if (!selfChallenge) {
            challengerRewardAmount = (slashedBond * CHALLENGE_REWARD_BPS) / BPS_DENOMINATOR;
            if (challengerRewardAmount == 0 && slashedBond != 0) {
                challengerRewardAmount = 1;
            }
            if (challengerRewardAmount > slashedBond) {
                challengerRewardAmount = slashedBond;
            }
            if (challengerRewardAmount != 0) {
                challengeRewardOf[netuid][msg.sender] += challengerRewardAmount;
            }
        }

        uint256 retainedBondAmount = slashedBond - challengerRewardAmount;

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

    function _validateFeePolicy(
        bool enabled,
        uint16 protocolFeeBps,
        uint16 treasuryFeeBps,
        address treasurySink,
        address minerSink
    ) internal pure {
        if (!enabled) {
            if (protocolFeeBps != 0 || treasuryFeeBps != 0 || treasurySink != address(0) || minerSink != address(0)) {
                revert InvalidFeePolicy();
            }
            return;
        }

        if (protocolFeeBps > MAX_PROTOCOL_FEE_BPS) revert InvalidFeePolicy();
        if (treasuryFeeBps > BPS_DENOMINATOR) revert InvalidFeePolicy();

        if (protocolFeeBps == 0) {
            if (treasuryFeeBps != 0 || treasurySink != address(0) || minerSink != address(0)) {
                revert InvalidFeePolicy();
            }
            return;
        }
        if (treasurySink == address(0) || minerSink == address(0)) revert InvalidFeePolicy();
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
                "BATCH_POLICY", netuid, mechid, enabled, challengeWindowBlocks, maxBatchItems, minProposerBondWei
            )
        );
    }

    function _feePolicyActionId(
        uint16 netuid,
        uint16 mechid,
        bool enabled,
        uint16 protocolFeeBps,
        uint16 treasuryFeeBps,
        address treasurySink,
        address minerSink
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode("FEE_POLICY", netuid, mechid, enabled, protocolFeeBps, treasuryFeeBps, treasurySink, minerSink)
        );
    }

    function _isGovernanceActionExpired(uint64 readyAtBlock) internal view returns (bool) {
        return block.number > uint256(readyAtBlock) + POLICY_UPDATE_EXPIRY_BLOCKS;
    }

    function batchPolicyQueueState(uint16 netuid, bytes32 actionId)
        external
        view
        returns (uint64 readyAtBlock, address queuedBy, bool queued, bool ready, bool expired)
    {
        readyAtBlock = queuedBatchPolicyReadyAt[netuid][actionId];
        if (readyAtBlock == 0) {
            return (0, address(0), false, false, false);
        }
        queuedBy = queuedBatchPolicyQueuedBy[netuid][actionId];
        queued = true;
        ready = block.number >= readyAtBlock;
        expired = _isGovernanceActionExpired(readyAtBlock);
    }

    function feePolicyQueueState(uint16 netuid, bytes32 actionId)
        external
        view
        returns (uint64 readyAtBlock, address queuedBy, bool queued, bool ready, bool expired)
    {
        readyAtBlock = queuedFeePolicyReadyAt[netuid][actionId];
        if (readyAtBlock == 0) {
            return (0, address(0), false, false, false);
        }
        queuedBy = queuedFeePolicyQueuedBy[netuid][actionId];
        queued = true;
        ready = block.number >= readyAtBlock;
        expired = _isGovernanceActionExpired(readyAtBlock);
    }

    function _snapshotFeePolicy(uint16 netuid, uint16 mechid, uint64 epoch) internal {
        FeePolicy memory policy = feePolicies[netuid][mechid];
        if (!policy.enabled) {
            batchProtocolFeeBps[netuid][mechid][epoch] = 0;
            batchTreasuryFeeBps[netuid][mechid][epoch] = 0;
            batchTreasurySink[netuid][mechid][epoch] = address(0);
            batchMinerSink[netuid][mechid][epoch] = address(0);
            return;
        }

        batchProtocolFeeBps[netuid][mechid][epoch] = policy.protocolFeeBps;
        batchTreasuryFeeBps[netuid][mechid][epoch] = policy.treasuryFeeBps;
        batchTreasurySink[netuid][mechid][epoch] = policy.treasurySink;
        batchMinerSink[netuid][mechid][epoch] = policy.minerSink;
    }

    function _distributeBatchFees(uint16 netuid, uint16 mechid, uint64 epoch, address proposer, uint256 fundedTotal)
        internal
    {
        uint16 protocolFeeBps = batchProtocolFeeBps[netuid][mechid][epoch];
        uint16 treasuryFeeBps = batchTreasuryFeeBps[netuid][mechid][epoch];
        address treasurySink = batchTreasurySink[netuid][mechid][epoch];
        address minerSink = batchMinerSink[netuid][mechid][epoch];

        uint256 protocolAmount = _mulBps(fundedTotal, protocolFeeBps);
        uint256 proposerAmount = fundedTotal - protocolAmount;
        uint256 treasuryAmount = 0;
        uint256 minerAmount = 0;
        if (protocolAmount != 0) {
            treasuryAmount = _mulDualBps(fundedTotal, protocolFeeBps, treasuryFeeBps);
            if (treasuryAmount > protocolAmount) {
                treasuryAmount = protocolAmount;
            }
            minerAmount = protocolAmount - treasuryAmount;
        }

        if (proposerAmount != 0) {
            inferenceFeeClaimOf[netuid][proposer] += proposerAmount;
        }
        if (treasuryAmount != 0) {
            inferenceFeeClaimOf[netuid][treasurySink] += treasuryAmount;
        }
        if (minerAmount != 0) {
            inferenceFeeClaimOf[netuid][minerSink] += minerAmount;
        }

        emit InferenceBatchFeesDistributed(
            netuid,
            mechid,
            epoch,
            proposer,
            treasurySink,
            minerSink,
            fundedTotal,
            proposerAmount,
            treasuryAmount,
            minerAmount
        );
    }

    function _mulBps(uint256 amount, uint16 bps) internal pure returns (uint256) {
        if (amount == 0 || bps == 0) return 0;
        uint256 bpsValue = uint256(bps);
        if (amount > type(uint256).max / bpsValue) revert InvalidFeeAmount();
        return (amount * bpsValue) / BPS_DENOMINATOR;
    }

    function _mulDualBps(uint256 amount, uint16 firstBps, uint16 secondBps) internal pure returns (uint256) {
        if (amount == 0 || firstBps == 0 || secondBps == 0) return 0;
        uint256 combinedBps = uint256(firstBps) * uint256(secondBps);
        if (amount > type(uint256).max / combinedBps) revert InvalidFeeAmount();
        return (amount * combinedBps) / (uint256(BPS_DENOMINATOR) * uint256(BPS_DENOMINATOR));
    }

    function _verifyMerkleProof(
        bytes32 leafHash,
        uint256 index,
        bytes32[] calldata merkleProof,
        bytes32 root,
        uint32 itemCount
    ) internal pure returns (bool) {
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

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {
    IPulseTensorProofVerifier, IPulseTensorProofVerifierMetadata
} from "./interfaces/IPulseTensorProofVerifier.sol";
import {IPulseTensorCoreGovernance} from "./interfaces/IPulseTensorCoreGovernance.sol";

/// @notice Proof-backed, PLS-native exact-inference escrow isolated from optimistic settlement.
/// @dev A proof establishes only the relation implemented by the configured program. Verifier
///      configurations are append-only; lifecycle changes can deprecate or permanently revoke
///      a configuration but can never rewrite its verification or fee parameters.
contract PulseTensorExactInferenceSettlementV1 {
    uint16 public constant BPS_DENOMINATOR = 10_000;
    uint16 public constant MAX_PROTOCOL_FEE_BPS = 3_000;
    uint16 public constant MAX_MECHANISM_ID = 1_023;
    uint32 public constant DOMAIN_VERSION = 1;
    uint64 public constant GOVERNANCE_ACTION_EXPIRY_BLOCKS = 200_000;
    uint64 public constant MAX_TASK_DURATION_BLOCKS = 200_000;
    uint256 public constant MAX_PROOF_BYTES = 16_384;
    uint256 public constant VERIFIER_AVAILABILITY_GAS = 50_000;

    bytes32 public constant VERIFIER_CONFIG_ACTION_DOMAIN = keccak256("PULSETENSOR_EXACT_VERIFIER_CONFIG_ACTION_V1");
    bytes32 public constant VERIFIER_DEPRECATION_ACTION_DOMAIN =
        keccak256("PULSETENSOR_EXACT_VERIFIER_DEPRECATION_ACTION_V1");
    bytes32 public constant REQUEST_NULLIFIER_DOMAIN = keccak256("PULSETENSOR_EXACT_REQUEST_NULLIFIER_V1");
    bytes32 public constant TASK_SPEC_DOMAIN = keccak256("PULSETENSOR_EXACT_TASK_SPEC_V1");
    bytes32 public constant PUBLIC_VALUES_DOMAIN = keccak256("PULSETENSOR_EXACT_PUBLIC_VALUES_V1");
    bytes32 public constant OUTPUT_DOMAIN = keccak256("PULSETENSOR_EXACT_OUTPUT_V1");

    error InvalidCore();
    error CoreRuntimeCodeHashMismatch(bytes32 expected, bytes32 actual);
    error UnauthorizedGovernance();
    error GovernanceNotConfigured();
    error GovernanceGenerationMismatch(uint64 queuedGeneration, uint64 currentGeneration);
    error GovernanceActionAlreadyQueued();
    error GovernanceActionNotQueued();
    error GovernanceActionKindMismatch();
    error GovernanceActionParametersMismatch();
    error GovernanceActionQueuedByMismatch();
    error GovernanceActionNotReady();
    error GovernanceActionExpired();
    error InvalidGovernanceDelay();
    error InvalidVerifierConfig();
    error VerifierConfigNotFound();
    error VerifierConfigNetuidMismatch();
    error VerifierConfigDeprecated();
    error VerifierConfigAlreadyDeprecated();
    error VerifierConfigRevoked();
    error VerifierConfigAlreadyRevoked();
    error AdapterRuntimeCodeHashMismatch(bytes32 expected, bytes32 actual);
    error AdapterMetadataMismatch();
    error VerifierUnavailable();
    error InvalidFeePolicy();
    error CoreSubnetPaused();
    error InvalidTask();
    error InvalidTaskDeadline();
    error InvalidCommitment();
    error RequestNullifierAlreadyUsed();
    error TaskNotOpen();
    error TaskDeadlinePassed();
    error TaskDeadlineNotPassed();
    error InvalidProofResult();
    error InvalidProofSelector();
    error VerifierStillAvailable();
    error InvalidClaim();
    error Reentrancy();
    error TransferFailed();

    enum GovernanceActionKind {
        None,
        AddVerifierConfig,
        DeprecateVerifierConfig
    }

    enum TaskStatus {
        None,
        Open,
        ProofSettled,
        ExpiredRefund,
        VerifierRevokedRefund,
        VerifierUnavailableRefund
    }

    struct VerifierConfigInput {
        uint16 netuid;
        address adapter;
        bytes32 adapterRuntimeCodeHash;
        bytes32 verifierRuntimeCodeHash;
        bytes32 programId;
        bytes32 relationId;
        bytes32 proofSystemId;
        bytes4 proofSelector;
        uint16 protocolFeeBps;
        address treasury;
    }

    struct VerifierConfig {
        bool exists;
        bool revoked;
        uint16 netuid;
        uint16 protocolFeeBps;
        bytes4 proofSelector;
        uint64 activatedAtBlock;
        uint64 stopNewTasksAtBlock;
        address adapter;
        address treasury;
        bytes32 adapterRuntimeCodeHash;
        bytes32 verifierRuntimeCodeHash;
        bytes32 programId;
        bytes32 relationId;
        bytes32 proofSystemId;
    }

    struct QueuedGovernanceAction {
        GovernanceActionKind kind;
        uint16 netuid;
        uint64 governanceGeneration;
        uint64 readyAtBlock;
        address queuedBy;
    }

    struct ExactInferenceTask {
        TaskStatus status;
        uint16 netuid;
        uint16 mechid;
        uint16 protocolFeeBps;
        uint64 verifierConfigId;
        uint64 createdAtBlock;
        uint64 deadlineBlock;
        address requester;
        address refundTo;
        address treasury;
        uint256 rewardWei;
        bytes32 requestNullifier;
        bytes32 inputCommitment;
        bytes32 modelCommitment;
        bytes32 taskSpecHash;
    }

    /// @notice Canonical static ABI journal committed by the proof guest.
    struct ExactInferencePublicValuesV1 {
        bytes32 domain;
        uint32 version;
        uint256 chainId;
        address settlement;
        uint256 taskId;
        bytes32 taskSpecHash;
        uint16 netuid;
        uint16 mechid;
        uint64 verifierConfigId;
        bytes32 relationId;
        bytes32 requestNullifier;
        bytes32 inputCommitment;
        bytes32 modelCommitment;
        uint16 protocolFeeBps;
        address treasury;
        uint8 classIndex;
        int64[4] scores;
        bytes32 outputCommitment;
        address provider;
        address beneficiary;
    }

    IPulseTensorCoreGovernance public immutable CORE;
    bytes32 public immutable CORE_RUNTIME_CODE_HASH;

    uint64 public nextVerifierConfigId = 1;
    uint256 public nextTaskId = 1;
    uint256 private lockState = 1;

    mapping(uint64 => VerifierConfig) private verifierConfigById;
    mapping(bytes32 => QueuedGovernanceAction) private governanceActionById;
    mapping(uint256 => ExactInferenceTask) private taskById;

    mapping(bytes32 => bool) public requestNullifierUsed;
    mapping(address => uint256) public claimableWei;
    mapping(uint16 => mapping(uint64 => uint256)) public openTaskCountByConfig;

    uint256 public totalOpenTasks;
    uint256 public totalFundedWei;
    uint256 public totalSettledWei;
    uint256 public totalRefundedWei;
    uint256 public totalProtocolFeesWei;
    uint256 public totalClaimedWei;
    uint256 public totalOpenEscrowWei;
    uint256 public totalClaimableWei;

    event VerifierConfigAdditionQueued(
        uint16 indexed netuid,
        bytes32 indexed actionId,
        uint64 indexed governanceGeneration,
        uint64 readyAtBlock,
        address adapter,
        bytes32 adapterRuntimeCodeHash,
        bytes32 verifierRuntimeCodeHash,
        bytes32 programId,
        bytes32 relationId,
        bytes32 proofSystemId,
        bytes4 proofSelector,
        uint16 protocolFeeBps,
        address treasury
    );
    event VerifierConfigAdded(
        uint16 indexed netuid,
        uint64 indexed configId,
        address indexed adapter,
        bytes32 adapterRuntimeCodeHash,
        bytes32 verifierRuntimeCodeHash,
        bytes32 programId,
        bytes32 relationId,
        bytes32 proofSystemId,
        bytes4 proofSelector,
        uint16 protocolFeeBps,
        address treasury
    );
    event VerifierConfigDeprecationQueued(
        uint16 indexed netuid,
        uint64 indexed configId,
        bytes32 indexed actionId,
        uint64 governanceGeneration,
        uint64 readyAtBlock
    );
    event VerifierConfigDeprecationActivated(
        uint16 indexed netuid, uint64 indexed configId, uint64 stopNewTasksAtBlock
    );
    event VerifierConfigRevocationActivated(uint16 indexed netuid, uint64 indexed configId, uint256 openTaskCount);
    event GovernanceActionCancelled(uint16 indexed netuid, bytes32 indexed actionId, GovernanceActionKind indexed kind);
    event ExactInferenceTaskCreated(
        uint256 indexed taskId,
        uint16 indexed netuid,
        uint16 indexed mechid,
        uint64 verifierConfigId,
        address requester,
        address refundTo,
        uint256 rewardWei,
        uint64 deadlineBlock,
        bytes32 requestNullifier,
        bytes32 taskSpecHash,
        bytes32 inputCommitment,
        bytes32 modelCommitment,
        uint16 protocolFeeBps,
        address treasury
    );
    event ExactInferenceProofSettled(
        uint256 indexed taskId,
        address indexed provider,
        address indexed beneficiary,
        uint256 beneficiaryAmountWei,
        uint256 protocolFeeWei,
        bytes32 outputCommitment,
        uint8 classIndex
    );
    event ExactInferenceTaskRefunded(
        uint256 indexed taskId, address indexed refundTo, TaskStatus indexed status, uint256 amountWei
    );
    event ClaimWithdrawn(
        address indexed claimant, address indexed to, uint256 amountWei, uint256 remainingClaimableWei
    );

    modifier nonReentrant() {
        if (lockState != 1) revert Reentrancy();
        lockState = 2;
        _;
        lockState = 1;
    }

    constructor(address coreAddress) {
        if (coreAddress == address(0) || coreAddress.code.length == 0) revert InvalidCore();
        CORE = IPulseTensorCoreGovernance(coreAddress);
        CORE_RUNTIME_CODE_HASH = coreAddress.codehash;
    }

    function verifierConfigs(uint64 configId) external view returns (VerifierConfig memory) {
        return verifierConfigById[configId];
    }

    function queuedGovernanceActions(bytes32 actionId) external view returns (QueuedGovernanceAction memory) {
        return governanceActionById[actionId];
    }

    function exactInferenceTasks(uint256 taskId) external view returns (ExactInferenceTask memory) {
        return taskById[taskId];
    }

    function queueVerifierConfig(VerifierConfigInput calldata input)
        external
        returns (bytes32 actionId, uint64 readyAtBlock)
    {
        (address governance, uint64 generation, uint64 delayBlocks) = _currentGovernance(input.netuid);
        _validateVerifierConfig(input);

        actionId = _verifierConfigActionId(input, generation);
        readyAtBlock = _queueGovernanceAction(
            actionId, GovernanceActionKind.AddVerifierConfig, input.netuid, governance, generation, delayBlocks
        );

        emit VerifierConfigAdditionQueued(
            input.netuid,
            actionId,
            generation,
            readyAtBlock,
            input.adapter,
            input.adapterRuntimeCodeHash,
            input.verifierRuntimeCodeHash,
            input.programId,
            input.relationId,
            input.proofSystemId,
            input.proofSelector,
            input.protocolFeeBps,
            input.treasury
        );
    }

    function executeVerifierConfig(VerifierConfigInput calldata input, bytes32 actionId)
        external
        returns (uint64 configId)
    {
        QueuedGovernanceAction memory queued =
            _requireExecutableAction(actionId, input.netuid, GovernanceActionKind.AddVerifierConfig);
        if (_verifierConfigActionId(input, queued.governanceGeneration) != actionId) {
            revert GovernanceActionParametersMismatch();
        }
        _validateVerifierConfig(input);
        delete governanceActionById[actionId];

        configId = nextVerifierConfigId;
        if (configId == type(uint64).max) revert InvalidVerifierConfig();
        nextVerifierConfigId = configId + 1;

        verifierConfigById[configId] = VerifierConfig({
            exists: true,
            revoked: false,
            netuid: input.netuid,
            protocolFeeBps: input.protocolFeeBps,
            proofSelector: input.proofSelector,
            activatedAtBlock: _blockNumberAsUint64(),
            stopNewTasksAtBlock: 0,
            adapter: input.adapter,
            treasury: input.treasury,
            adapterRuntimeCodeHash: input.adapterRuntimeCodeHash,
            verifierRuntimeCodeHash: input.verifierRuntimeCodeHash,
            programId: input.programId,
            relationId: input.relationId,
            proofSystemId: input.proofSystemId
        });

        emit VerifierConfigAdded(
            input.netuid,
            configId,
            input.adapter,
            input.adapterRuntimeCodeHash,
            input.verifierRuntimeCodeHash,
            input.programId,
            input.relationId,
            input.proofSystemId,
            input.proofSelector,
            input.protocolFeeBps,
            input.treasury
        );
    }

    function queueVerifierConfigDeprecation(uint16 netuid, uint64 configId)
        external
        returns (bytes32 actionId, uint64 readyAtBlock)
    {
        (address governance, uint64 generation, uint64 delayBlocks) = _currentGovernance(netuid);
        VerifierConfig storage config = _requireConfig(netuid, configId);
        if (config.revoked) revert VerifierConfigRevoked();
        if (config.stopNewTasksAtBlock != 0) revert VerifierConfigAlreadyDeprecated();

        actionId = _verifierDeprecationActionId(netuid, configId, generation);
        readyAtBlock = _queueGovernanceAction(
            actionId, GovernanceActionKind.DeprecateVerifierConfig, netuid, governance, generation, delayBlocks
        );

        emit VerifierConfigDeprecationQueued(netuid, configId, actionId, generation, readyAtBlock);
    }

    function executeVerifierConfigDeprecation(uint16 netuid, uint64 configId, bytes32 actionId) external {
        QueuedGovernanceAction memory queued =
            _requireExecutableAction(actionId, netuid, GovernanceActionKind.DeprecateVerifierConfig);
        if (_verifierDeprecationActionId(netuid, configId, queued.governanceGeneration) != actionId) {
            revert GovernanceActionParametersMismatch();
        }

        VerifierConfig storage config = _requireConfig(netuid, configId);
        if (config.revoked) revert VerifierConfigRevoked();
        if (config.stopNewTasksAtBlock != 0) revert VerifierConfigAlreadyDeprecated();
        delete governanceActionById[actionId];
        uint64 stopNewTasksAtBlock = _blockNumberAsUint64();
        config.stopNewTasksAtBlock = stopNewTasksAtBlock;
        emit VerifierConfigDeprecationActivated(netuid, configId, stopNewTasksAtBlock);
    }

    function cancelGovernanceAction(bytes32 actionId) external {
        QueuedGovernanceAction memory queued = governanceActionById[actionId];
        if (queued.readyAtBlock == 0) revert GovernanceActionNotQueued();
        _requireCoreRuntimeCodeHash();
        if (CORE.subnetGovernance(queued.netuid) != msg.sender) revert UnauthorizedGovernance();

        delete governanceActionById[actionId];
        emit GovernanceActionCancelled(queued.netuid, actionId, queued.kind);
    }

    /// @notice Permanently prevents proof settlement under a configuration.
    /// @dev This immediate authority can only make open tasks eligible for a full refund.
    function revokeVerifierConfig(uint16 netuid, uint64 configId) external {
        _requireCurrentGovernance(netuid);
        VerifierConfig storage config = _requireConfig(netuid, configId);
        if (config.revoked) revert VerifierConfigAlreadyRevoked();
        config.revoked = true;
        emit VerifierConfigRevocationActivated(netuid, configId, openTaskCountByConfig[netuid][configId]);
    }

    function createExactInferenceTask(
        uint16 netuid,
        uint16 mechid,
        uint64 verifierConfigId,
        bytes32 inputCommitment,
        bytes32 modelCommitment,
        uint64 requesterNonce,
        uint64 deadlineBlock,
        address refundTo
    ) external payable returns (uint256 taskId) {
        _requireCoreRuntimeCodeHash();
        if (CORE.subnetGovernance(netuid) == address(0)) revert GovernanceNotConfigured();
        if (CORE.subnetPaused(netuid)) revert CoreSubnetPaused();
        if (msg.value == 0 || refundTo == address(0) || mechid > MAX_MECHANISM_ID) revert InvalidTask();
        if (inputCommitment == bytes32(0) || modelCommitment == bytes32(0)) revert InvalidCommitment();

        uint256 latestDeadline = block.number + MAX_TASK_DURATION_BLOCKS;
        if (deadlineBlock <= block.number || uint256(deadlineBlock) > latestDeadline) revert InvalidTaskDeadline();

        VerifierConfig storage config = _requireConfig(netuid, verifierConfigId);
        if (config.revoked) revert VerifierConfigRevoked();
        if (config.stopNewTasksAtBlock != 0 && block.number >= config.stopNewTasksAtBlock) {
            revert VerifierConfigDeprecated();
        }
        _requireVerifierAvailable(config);

        bytes32 requestNullifier = keccak256(
            abi.encode(
                REQUEST_NULLIFIER_DOMAIN, DOMAIN_VERSION, block.chainid, address(this), msg.sender, requesterNonce
            )
        );
        if (requestNullifierUsed[requestNullifier]) revert RequestNullifierAlreadyUsed();

        taskId = nextTaskId;
        nextTaskId = taskId + 1;

        ExactInferenceTask memory task = ExactInferenceTask({
            status: TaskStatus.Open,
            netuid: netuid,
            mechid: mechid,
            protocolFeeBps: config.protocolFeeBps,
            verifierConfigId: verifierConfigId,
            createdAtBlock: _blockNumberAsUint64(),
            deadlineBlock: deadlineBlock,
            requester: msg.sender,
            refundTo: refundTo,
            treasury: config.treasury,
            rewardWei: msg.value,
            requestNullifier: requestNullifier,
            inputCommitment: inputCommitment,
            modelCommitment: modelCommitment,
            taskSpecHash: bytes32(0)
        });
        task.taskSpecHash = _computeTaskSpecHash(taskId, task, config);

        requestNullifierUsed[requestNullifier] = true;
        taskById[taskId] = task;

        totalOpenTasks += 1;
        openTaskCountByConfig[netuid][verifierConfigId] += 1;
        totalFundedWei += msg.value;
        totalOpenEscrowWei += msg.value;

        emit ExactInferenceTaskCreated(
            taskId,
            netuid,
            mechid,
            verifierConfigId,
            msg.sender,
            refundTo,
            msg.value,
            deadlineBlock,
            requestNullifier,
            task.taskSpecHash,
            inputCommitment,
            modelCommitment,
            task.protocolFeeBps,
            task.treasury
        );
    }

    /// @notice Verifies a proof before making the task terminal or crediting any value.
    function submitExactInferenceProof(
        uint256 taskId,
        address provider,
        address beneficiary,
        uint8 classIndex,
        int64[4] calldata scores,
        bytes calldata proof
    ) external {
        ExactInferenceTask storage task = _requireOpenTask(taskId);
        if (block.number > task.deadlineBlock) revert TaskDeadlinePassed();
        if (provider == address(0) || beneficiary == address(0) || classIndex >= 4) revert InvalidProofResult();
        if (proof.length < 4 || proof.length > MAX_PROOF_BYTES) revert InvalidProofSelector();

        VerifierConfig storage config = _requireConfig(task.netuid, task.verifierConfigId);
        if (config.revoked) revert VerifierConfigRevoked();
        _requireVerifierAvailable(config);
        if (bytes4(proof[:4]) != config.proofSelector) revert InvalidProofSelector();

        bytes32 outputCommitment = _computeOutputCommitment(classIndex, scores);

        bytes memory publicValues = _encodePublicValues(
            taskId, task, config.relationId, provider, beneficiary, classIndex, scores, outputCommitment
        );

        // This is a STATICCALL. No task or accounting state changes precede successful verification.
        IPulseTensorProofVerifier(config.adapter).verify(config.programId, publicValues, proof);

        uint256 rewardWei = task.rewardWei;
        uint256 protocolFeeWei = _mulBps(rewardWei, task.protocolFeeBps);
        uint256 beneficiaryAmountWei = rewardWei - protocolFeeWei;

        _closeOpenTask(task, TaskStatus.ProofSettled);
        totalSettledWei += rewardWei;
        totalProtocolFeesWei += protocolFeeWei;
        totalClaimableWei += rewardWei;
        claimableWei[beneficiary] += beneficiaryAmountWei;
        if (protocolFeeWei != 0) claimableWei[task.treasury] += protocolFeeWei;

        emit ExactInferenceProofSettled(
            taskId, provider, beneficiary, beneficiaryAmountWei, protocolFeeWei, outputCommitment, classIndex
        );
    }

    function refundExpired(uint256 taskId) external {
        ExactInferenceTask storage task = _requireOpenTask(taskId);
        if (block.number <= task.deadlineBlock) revert TaskDeadlineNotPassed();
        _refund(taskId, task, TaskStatus.ExpiredRefund);
    }

    function refundRevoked(uint256 taskId) external {
        ExactInferenceTask storage task = _requireOpenTask(taskId);
        VerifierConfig storage config = _requireConfig(task.netuid, task.verifierConfigId);
        if (!config.revoked) revert VerifierStillAvailable();
        _refund(taskId, task, TaskStatus.VerifierRevokedRefund);
    }

    function refundVerifierUnavailable(uint256 taskId) external {
        ExactInferenceTask storage task = _requireOpenTask(taskId);
        VerifierConfig storage config = _requireConfig(task.netuid, task.verifierConfigId);
        if (_verifierAvailable(config)) revert VerifierStillAvailable();
        _refund(taskId, task, TaskStatus.VerifierUnavailableRefund);
    }

    function claim(address payable to, uint256 amountWei) external nonReentrant {
        uint256 availableWei = claimableWei[msg.sender];
        if (to == address(0) || amountWei == 0 || amountWei > availableWei) revert InvalidClaim();

        claimableWei[msg.sender] = availableWei - amountWei;
        totalClaimableWei -= amountWei;
        totalClaimedWei += amountWei;

        (bool sent,) = to.call{value: amountWei}("");
        if (!sent) revert TransferFailed();
        emit ClaimWithdrawn(msg.sender, to, amountWei, availableWei - amountWei);
    }

    function encodeExactInferencePublicValues(
        uint256 taskId,
        address provider,
        address beneficiary,
        uint8 classIndex,
        int64[4] calldata scores
    ) external view returns (bytes memory) {
        if (provider == address(0) || beneficiary == address(0) || classIndex >= 4) revert InvalidProofResult();
        ExactInferenceTask storage task = taskById[taskId];
        if (task.status == TaskStatus.None) revert InvalidTask();
        VerifierConfig storage config = _requireConfig(task.netuid, task.verifierConfigId);
        return _encodePublicValues(
            taskId,
            task,
            config.relationId,
            provider,
            beneficiary,
            classIndex,
            scores,
            _computeOutputCommitment(classIndex, scores)
        );
    }

    function computeExactInferenceOutputCommitment(uint8 classIndex, int64[4] calldata scores)
        external
        pure
        returns (bytes32)
    {
        if (classIndex >= 4) revert InvalidProofResult();
        return _computeOutputCommitment(classIndex, scores);
    }

    function computeRequestNullifier(address requester, uint64 requesterNonce) external view returns (bytes32) {
        return keccak256(
            abi.encode(
                REQUEST_NULLIFIER_DOMAIN, DOMAIN_VERSION, block.chainid, address(this), requester, requesterNonce
            )
        );
    }

    function adapterRuntimeCodeHashMatches(uint64 configId) public view returns (bool) {
        VerifierConfig storage config = verifierConfigById[configId];
        return config.exists && config.adapter.codehash == config.adapterRuntimeCodeHash;
    }

    /// @notice Reports only whether the adapter and its pinned base verifier retain their admitted code hashes.
    function verifierCodeAvailable(uint64 configId) external view returns (bool) {
        VerifierConfig storage config = verifierConfigById[configId];
        return config.exists && _verifierAvailable(config);
    }

    /// @notice Reports config-level admission only; callers must separately inspect Core subnet pause state.
    function verifierAcceptsNewTasks(uint64 configId) external view returns (bool) {
        VerifierConfig storage config = verifierConfigById[configId];
        return config.exists && !config.revoked
            && (config.stopNewTasksAtBlock == 0 || block.number < config.stopNewTasksAtBlock) && _verifierAvailable(config);
    }

    /// @notice Reports config-level proof availability only; task status and deadline remain task-specific.
    function verifierCanSettleOpenTasks(uint64 configId) external view returns (bool) {
        VerifierConfig storage config = verifierConfigById[configId];
        return config.exists && !config.revoked && _verifierAvailable(config);
    }

    function currentAdapterRuntimeCodeHash(uint64 configId) external view returns (bytes32) {
        VerifierConfig storage config = verifierConfigById[configId];
        if (!config.exists) revert VerifierConfigNotFound();
        return config.adapter.codehash;
    }

    function accountingInvariantHolds() external view returns (bool) {
        if (totalSettledWei > totalFundedWei || totalRefundedWei > totalFundedWei) return false;
        if (totalProtocolFeesWei > totalSettledWei || totalClaimedWei > totalSettledWei + totalRefundedWei) {
            return false;
        }
        if (totalFundedWei != totalOpenEscrowWei + totalSettledWei + totalRefundedWei) return false;
        if (totalClaimableWei != totalSettledWei + totalRefundedWei - totalClaimedWei) return false;
        return address(this).balance >= totalOpenEscrowWei + totalClaimableWei;
    }

    function _validateVerifierConfig(VerifierConfigInput calldata input) internal view {
        if (
            input.adapter == address(0) || input.adapter.code.length == 0 || input.adapterRuntimeCodeHash == bytes32(0)
                || input.verifierRuntimeCodeHash == bytes32(0) || input.programId == bytes32(0)
                || input.relationId == bytes32(0) || input.proofSystemId == bytes32(0) || input.proofSelector == bytes4(0)
        ) revert InvalidVerifierConfig();
        if (
            input.protocolFeeBps > MAX_PROTOCOL_FEE_BPS || (input.protocolFeeBps == 0) != (input.treasury == address(0))
        ) revert InvalidFeePolicy();

        bytes32 actualAdapterRuntimeCodeHash = input.adapter.codehash;
        if (actualAdapterRuntimeCodeHash != input.adapterRuntimeCodeHash) {
            revert AdapterRuntimeCodeHashMismatch(input.adapterRuntimeCodeHash, actualAdapterRuntimeCodeHash);
        }
        if (
            IPulseTensorProofVerifier(input.adapter).proofSystemId() != input.proofSystemId
                || IPulseTensorProofVerifierMetadata(input.adapter).proofSelector() != input.proofSelector
                || IPulseTensorProofVerifierMetadata(input.adapter).verifierRuntimeCodeHash()
                    != input.verifierRuntimeCodeHash || !_verifierRuntimeCodeHashMatches(input.adapter)
        ) revert AdapterMetadataMismatch();
    }

    function _queueGovernanceAction(
        bytes32 actionId,
        GovernanceActionKind kind,
        uint16 netuid,
        address governance,
        uint64 generation,
        uint64 delayBlocks
    ) internal returns (uint64 readyAtBlock) {
        QueuedGovernanceAction storage existing = governanceActionById[actionId];
        if (existing.readyAtBlock != 0 && !_governanceActionExpired(existing.readyAtBlock)) {
            revert GovernanceActionAlreadyQueued();
        }

        uint256 readyAt = block.number + uint256(delayBlocks);
        if (readyAt > type(uint64).max) revert InvalidGovernanceDelay();
        readyAtBlock = uint64(readyAt);
        governanceActionById[actionId] = QueuedGovernanceAction({
            kind: kind,
            netuid: netuid,
            governanceGeneration: generation,
            readyAtBlock: readyAtBlock,
            queuedBy: governance
        });
    }

    function _requireExecutableAction(bytes32 actionId, uint16 netuid, GovernanceActionKind expectedKind)
        internal
        view
        returns (QueuedGovernanceAction memory queued)
    {
        queued = governanceActionById[actionId];
        if (queued.readyAtBlock == 0) revert GovernanceActionNotQueued();
        if (queued.netuid != netuid || queued.kind != expectedKind) revert GovernanceActionKindMismatch();

        _requireCoreRuntimeCodeHash();
        address governance = CORE.subnetGovernance(netuid);
        if (governance == address(0)) revert GovernanceNotConfigured();
        if (governance != msg.sender) revert UnauthorizedGovernance();
        if (queued.queuedBy != msg.sender) revert GovernanceActionQueuedByMismatch();

        uint64 currentGeneration = CORE.subnetGovernanceGeneration(netuid);
        if (currentGeneration != queued.governanceGeneration) {
            revert GovernanceGenerationMismatch(queued.governanceGeneration, currentGeneration);
        }
        if (block.number < queued.readyAtBlock) revert GovernanceActionNotReady();
        if (_governanceActionExpired(queued.readyAtBlock)) revert GovernanceActionExpired();
    }

    function _currentGovernance(uint16 netuid)
        internal
        view
        returns (address governance, uint64 generation, uint64 delayBlocks)
    {
        _requireCoreRuntimeCodeHash();
        governance = CORE.subnetGovernance(netuid);
        if (governance == address(0)) revert GovernanceNotConfigured();
        if (governance != msg.sender) revert UnauthorizedGovernance();
        generation = CORE.subnetGovernanceGeneration(netuid);
        delayBlocks = CORE.subnetOwnerActionDelayBlocks(netuid);
        if (delayBlocks == 0) revert InvalidGovernanceDelay();
    }

    function _requireCurrentGovernance(uint16 netuid) internal view {
        _requireCoreRuntimeCodeHash();
        address governance = CORE.subnetGovernance(netuid);
        if (governance == address(0)) revert GovernanceNotConfigured();
        if (governance != msg.sender) revert UnauthorizedGovernance();
    }

    function _requireConfig(uint16 netuid, uint64 configId) internal view returns (VerifierConfig storage config) {
        config = verifierConfigById[configId];
        if (!config.exists) revert VerifierConfigNotFound();
        if (config.netuid != netuid) revert VerifierConfigNetuidMismatch();
    }

    function _requireOpenTask(uint256 taskId) internal view returns (ExactInferenceTask storage task) {
        task = taskById[taskId];
        if (task.status != TaskStatus.Open) revert TaskNotOpen();
    }

    function _requireCoreRuntimeCodeHash() internal view {
        bytes32 actualRuntimeCodeHash = address(CORE).codehash;
        if (actualRuntimeCodeHash != CORE_RUNTIME_CODE_HASH) {
            revert CoreRuntimeCodeHashMismatch(CORE_RUNTIME_CODE_HASH, actualRuntimeCodeHash);
        }
    }

    function _requireAdapterRuntimeCodeHash(VerifierConfig storage config) internal view {
        bytes32 actualRuntimeCodeHash = config.adapter.codehash;
        if (actualRuntimeCodeHash != config.adapterRuntimeCodeHash) {
            revert AdapterRuntimeCodeHashMismatch(config.adapterRuntimeCodeHash, actualRuntimeCodeHash);
        }
    }

    function _requireVerifierAvailable(VerifierConfig storage config) internal view {
        _requireAdapterRuntimeCodeHash(config);
        if (!_verifierRuntimeCodeHashMatches(config.adapter)) revert VerifierUnavailable();
    }

    function _verifierAvailable(VerifierConfig storage config) internal view returns (bool) {
        if (config.adapter.codehash != config.adapterRuntimeCodeHash) return false;
        return _verifierRuntimeCodeHashMatches(config.adapter);
    }

    /// @dev Bounds both gas and copied return data. Failure, malformed data, and non-canonical bools are unavailable.
    function _verifierRuntimeCodeHashMatches(address adapter) internal view returns (bool matches) {
        uint256 selector = uint32(IPulseTensorProofVerifierMetadata.verifierRuntimeCodeHashMatches.selector);
        uint256 gasLimit = VERIFIER_AVAILABILITY_GAS;
        // solhint-disable-next-line no-inline-assembly
        assembly ("memory-safe") {
            let pointer := mload(0x40)
            mstore(pointer, shl(224, selector))
            let success := staticcall(gasLimit, adapter, pointer, 4, pointer, 32)
            if and(success, eq(returndatasize(), 32)) { matches := eq(mload(pointer), 1) }
        }
    }

    function _closeOpenTask(ExactInferenceTask storage task, TaskStatus terminalStatus) internal {
        task.status = terminalStatus;
        totalOpenTasks -= 1;
        openTaskCountByConfig[task.netuid][task.verifierConfigId] -= 1;
        totalOpenEscrowWei -= task.rewardWei;
    }

    function _refund(uint256 taskId, ExactInferenceTask storage task, TaskStatus refundStatus) internal {
        uint256 rewardWei = task.rewardWei;
        address refundTo = task.refundTo;
        _closeOpenTask(task, refundStatus);
        totalRefundedWei += rewardWei;
        totalClaimableWei += rewardWei;
        claimableWei[refundTo] += rewardWei;
        emit ExactInferenceTaskRefunded(taskId, refundTo, refundStatus, rewardWei);
    }

    function _encodePublicValues(
        uint256 taskId,
        ExactInferenceTask storage task,
        bytes32 relationId,
        address provider,
        address beneficiary,
        uint8 classIndex,
        int64[4] calldata scores,
        bytes32 outputCommitment
    ) internal view returns (bytes memory) {
        ExactInferencePublicValuesV1 memory values = ExactInferencePublicValuesV1({
            domain: PUBLIC_VALUES_DOMAIN,
            version: DOMAIN_VERSION,
            chainId: block.chainid,
            settlement: address(this),
            taskId: taskId,
            taskSpecHash: task.taskSpecHash,
            netuid: task.netuid,
            mechid: task.mechid,
            verifierConfigId: task.verifierConfigId,
            relationId: relationId,
            requestNullifier: task.requestNullifier,
            inputCommitment: task.inputCommitment,
            modelCommitment: task.modelCommitment,
            protocolFeeBps: task.protocolFeeBps,
            treasury: task.treasury,
            classIndex: classIndex,
            scores: scores,
            outputCommitment: outputCommitment,
            provider: provider,
            beneficiary: beneficiary
        });
        return abi.encode(values);
    }

    function _computeTaskSpecHash(uint256 taskId, ExactInferenceTask memory task, VerifierConfig storage config)
        internal
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                TASK_SPEC_DOMAIN,
                DOMAIN_VERSION,
                block.chainid,
                address(this),
                taskId,
                task.requester,
                task.refundTo,
                task.rewardWei,
                task.createdAtBlock,
                task.deadlineBlock,
                task.netuid,
                task.mechid,
                task.verifierConfigId,
                config.adapter,
                config.adapterRuntimeCodeHash,
                config.verifierRuntimeCodeHash,
                config.programId,
                config.relationId,
                config.proofSystemId,
                config.proofSelector,
                task.protocolFeeBps,
                task.treasury,
                task.requestNullifier,
                task.inputCommitment,
                task.modelCommitment
            )
        );
    }

    function _verifierConfigActionId(VerifierConfigInput calldata input, uint64 governanceGeneration)
        internal
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                VERIFIER_CONFIG_ACTION_DOMAIN, DOMAIN_VERSION, block.chainid, address(this), governanceGeneration, input
            )
        );
    }

    function _verifierDeprecationActionId(uint16 netuid, uint64 configId, uint64 governanceGeneration)
        internal
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                VERIFIER_DEPRECATION_ACTION_DOMAIN,
                DOMAIN_VERSION,
                block.chainid,
                address(this),
                governanceGeneration,
                netuid,
                configId
            )
        );
    }

    function _governanceActionExpired(uint64 readyAtBlock) internal view returns (bool) {
        return block.number > uint256(readyAtBlock) + GOVERNANCE_ACTION_EXPIRY_BLOCKS;
    }

    function _mulBps(uint256 amountWei, uint16 bps) internal pure returns (uint256) {
        // The quotient/remainder decomposition is exact and prevents amountWei * bps overflow.
        // `whole * bps` cannot overflow because whole <= max/10_000 and bps <= 3_000.
        // slither-disable-next-line divide-before-multiply
        uint256 whole = amountWei / BPS_DENOMINATOR;
        uint256 remainder = amountWei % BPS_DENOMINATOR;
        return whole * uint256(bps) + (remainder * uint256(bps)) / BPS_DENOMINATOR;
    }

    function _computeOutputCommitment(uint8 classIndex, int64[4] calldata scores) internal pure returns (bytes32) {
        return sha256(abi.encode(OUTPUT_DOMAIN, DOMAIN_VERSION, classIndex, scores));
    }

    function _blockNumberAsUint64() internal view returns (uint64) {
        if (block.number > type(uint64).max) revert InvalidTaskDeadline();
        return uint64(block.number);
    }
}

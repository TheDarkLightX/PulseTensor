// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";

import {PulseTensorCore} from "../src/PulseTensorCore.sol";
import {PulseTensorExactInferenceSettlementV1} from "../src/PulseTensorExactInferenceSettlementV1.sol";
import {
    IPulseTensorProofVerifier,
    IPulseTensorProofVerifierMetadata
} from "../src/interfaces/IPulseTensorProofVerifier.sol";

/// @dev Test-only verifier that accepts exactly the configured program/public-values digest.
contract ExactInferenceInvariantDigestVerifier is IPulseTensorProofVerifier, IPulseTensorProofVerifierMetadata {
    bytes4 public constant override proofSelector = 0x494e5631;
    bytes32 public constant override verifierRuntimeCodeHash = keccak256("EXACT_INVARIANT_VERIFIER_RUNTIME_V1");
    bytes32 public constant PROOF_SYSTEM_ID = keccak256("EXACT_INVARIANT_PROOF_SYSTEM_V1");

    error InvalidProof();

    function proofSystemId() external pure returns (bytes32) {
        return PROOF_SYSTEM_ID;
    }

    function verifierRuntimeCodeHashMatches() external pure returns (bool) {
        return true;
    }

    function verify(bytes32 programId, bytes calldata publicValues, bytes calldata proof) external pure {
        if (proof.length != 36 || bytes4(proof[:4]) != proofSelector) revert InvalidProof();

        bytes32 suppliedDigest;
        assembly ("memory-safe") {
            suppliedDigest := calldataload(add(proof.offset, 4))
        }
        if (suppliedDigest != keccak256(abi.encode(programId, sha256(publicValues)))) revert InvalidProof();
    }
}

contract PulseTensorExactInferenceSettlementV1InvariantHandler is Test {
    struct TrackedTask {
        uint256 rewardWei;
        uint64 deadlineBlock;
        uint64 configId;
        uint16 protocolFeeBps;
        address refundTo;
        bool isOpen;
        bool isTerminal;
        PulseTensorExactInferenceSettlementV1.TaskStatus terminalStatus;
    }

    PulseTensorExactInferenceSettlementV1 internal immutable settlement;
    uint16 internal immutable netuid;
    uint64 internal immutable settlementConfigId;
    uint64 internal immutable revocableConfigId;
    uint64 internal immutable unavailableConfigId;
    address internal immutable unavailableVerifier;
    bytes32 internal immutable programId;
    bytes4 internal immutable proofSelector;

    address[] internal actors;
    uint256[] internal taskIds;
    mapping(uint256 => TrackedTask) internal trackedTaskById;
    mapping(address => uint64) internal nextNonceByRequester;
    mapping(address => uint256) internal expectedClaimableByActor;
    mapping(uint64 => uint16) internal feeBpsByConfig;
    mapping(uint64 => uint256) internal trackedOpenByConfig;

    bool public revocableConfigRevoked;
    bool public verifierMadeUnavailable;
    uint256 public trackedOpenTasks;
    uint256 public trackedFundedWei;
    uint256 public trackedOpenEscrowWei;
    uint256 public trackedSettledWei;
    uint256 public trackedRefundedWei;
    uint256 public trackedExpectedProtocolFeesWei;
    uint256 public trackedClaimableWei;
    uint256 public trackedClaimedWei;
    uint256 public terminalReplaySuccesses;

    constructor(
        PulseTensorExactInferenceSettlementV1 settlement_,
        uint16 netuid_,
        uint64 settlementConfigId_,
        uint64 revocableConfigId_,
        uint64 unavailableConfigId_,
        address unavailableVerifier_,
        bytes32 programId_,
        bytes4 proofSelector_,
        uint16 settlementFeeBps,
        uint16 revocableFeeBps,
        uint16 unavailableFeeBps,
        address[] memory actors_
    ) {
        settlement = settlement_;
        netuid = netuid_;
        settlementConfigId = settlementConfigId_;
        revocableConfigId = revocableConfigId_;
        unavailableConfigId = unavailableConfigId_;
        unavailableVerifier = unavailableVerifier_;
        programId = programId_;
        proofSelector = proofSelector_;
        feeBpsByConfig[settlementConfigId_] = settlementFeeBps;
        feeBpsByConfig[revocableConfigId_] = revocableFeeBps;
        feeBpsByConfig[unavailableConfigId_] = unavailableFeeBps;

        for (uint256 index = 0; index < actors_.length; index++) {
            actors.push(actors_[index]);
        }
    }

    function createTask(
        uint256 requesterSeed,
        uint256 refundSeed,
        uint256 configSeed,
        uint256 rewardSeed,
        uint256 deadlineSeed
    ) external {
        uint64 configId = _pickAvailableConfig(configSeed);
        address requester = _pickActor(requesterSeed);
        address refundTo = _pickActor(refundSeed);
        uint256 rewardWei = bound(rewardSeed, 1, 10 ether);
        uint64 deadlineBlock = uint64(block.number + bound(deadlineSeed, 1, 50));
        uint64 nonce = nextNonceByRequester[requester];
        nextNonceByRequester[requester] = nonce + 1;
        bytes32 inputCommitment = keccak256(abi.encode("input", requester, nonce, taskIds.length));
        bytes32 modelCommitment = keccak256(abi.encode("model", configId, configSeed));

        vm.prank(requester);
        try settlement.createExactInferenceTask{value: rewardWei}(
            netuid, 1, configId, inputCommitment, modelCommitment, nonce, deadlineBlock, refundTo
        ) returns (uint256 taskId) {
            taskIds.push(taskId);
            trackedTaskById[taskId] = TrackedTask({
                rewardWei: rewardWei,
                deadlineBlock: deadlineBlock,
                configId: configId,
                protocolFeeBps: feeBpsByConfig[configId],
                refundTo: refundTo,
                isOpen: true,
                isTerminal: false,
                terminalStatus: PulseTensorExactInferenceSettlementV1.TaskStatus.None
            });
            trackedOpenTasks += 1;
            trackedOpenByConfig[configId] += 1;
            trackedFundedWei += rewardWei;
            trackedOpenEscrowWei += rewardWei;
        } catch {}
    }

    function settle(uint256 taskSeed, uint256 providerSeed, uint256 beneficiarySeed, uint256 scoreSeed) external {
        (bool found, uint256 taskId) = _pickSettleableTask(taskSeed);
        if (!found) return;

        address provider = _pickActor(providerSeed);
        address beneficiary = _pickActor(beneficiarySeed);
        uint8 classIndex = uint8(scoreSeed % 4);
        int64[4] memory scores = _scores(scoreSeed);

        try settlement.encodeExactInferencePublicValues(taskId, provider, beneficiary, classIndex, scores) returns (
            bytes memory publicValues
        ) {
            bytes memory proof = abi.encodePacked(proofSelector, keccak256(abi.encode(programId, sha256(publicValues))));
            try settlement.submitExactInferenceProof(taskId, provider, beneficiary, classIndex, scores, proof) {
                TrackedTask storage task = trackedTaskById[taskId];
                uint256 protocolFeeWei = task.rewardWei * task.protocolFeeBps / 10_000;
                _trackTerminal(taskId, PulseTensorExactInferenceSettlementV1.TaskStatus.ProofSettled);
                trackedSettledWei += task.rewardWei;
                trackedExpectedProtocolFeesWei += protocolFeeWei;
                trackedClaimableWei += task.rewardWei;
                expectedClaimableByActor[beneficiary] += task.rewardWei - protocolFeeWei;
                if (protocolFeeWei != 0) expectedClaimableByActor[actors[0]] += protocolFeeWei;
            } catch {}
        } catch {}
    }

    function refundExpired(uint256 taskSeed) external {
        (bool found, uint256 taskId) = _pickOpenTask(taskSeed, 0, false);
        if (!found) return;

        TrackedTask storage task = trackedTaskById[taskId];
        if (block.number <= task.deadlineBlock) vm.roll(uint256(task.deadlineBlock) + 1);
        try settlement.refundExpired(taskId) {
            _trackRefund(taskId, PulseTensorExactInferenceSettlementV1.TaskStatus.ExpiredRefund);
        } catch {}
    }

    function revokeRevocableConfig() external {
        if (revocableConfigRevoked || !_hasOpenTaskForConfig(revocableConfigId)) return;
        try settlement.revokeVerifierConfig(netuid, revocableConfigId) {
            revocableConfigRevoked = true;
        } catch {}
    }

    function refundRevoked(uint256 taskSeed) external {
        if (!revocableConfigRevoked) return;
        (bool found, uint256 taskId) = _pickOpenTask(taskSeed, revocableConfigId, true);
        if (!found) return;
        try settlement.refundRevoked(taskId) {
            _trackRefund(taskId, PulseTensorExactInferenceSettlementV1.TaskStatus.VerifierRevokedRefund);
        } catch {}
    }

    function makeVerifierUnavailable() external {
        if (verifierMadeUnavailable || !_hasOpenTaskForConfig(unavailableConfigId)) return;
        vm.etch(unavailableVerifier, hex"00");
        verifierMadeUnavailable = true;
    }

    function refundUnavailable(uint256 taskSeed) external {
        if (!verifierMadeUnavailable) return;
        (bool found, uint256 taskId) = _pickOpenTask(taskSeed, unavailableConfigId, true);
        if (!found) return;
        try settlement.refundVerifierUnavailable(taskId) {
            _trackRefund(taskId, PulseTensorExactInferenceSettlementV1.TaskStatus.VerifierUnavailableRefund);
        } catch {}
    }

    function claim(uint256 actorSeed, uint256 amountSeed) external {
        address actor = _pickActor(actorSeed);
        uint256 availableWei = expectedClaimableByActor[actor];
        if (availableWei == 0) return;
        uint256 amountWei = bound(amountSeed, 1, availableWei);

        vm.prank(actor);
        try settlement.claim(payable(actor), amountWei) {
            expectedClaimableByActor[actor] = availableWei - amountWei;
            trackedClaimableWei -= amountWei;
            trackedClaimedWei += amountWei;
        } catch {}
    }

    function rollBlocks(uint256 blockSeed) external {
        vm.roll(block.number + bound(blockSeed, 1, 25));
    }

    /// @dev Deliberately retries all terminal routes. Every call must fail before changing state.
    function attemptTerminalReplay(uint256 taskSeed, uint256 actionSeed) external {
        (bool found, uint256 taskId) = _pickTerminalTask(taskSeed);
        if (!found) return;

        uint256 action = actionSeed % 4;
        if (action == 0) {
            try settlement.refundExpired(taskId) {
                terminalReplaySuccesses += 1;
            } catch {}
        } else if (action == 1) {
            try settlement.refundRevoked(taskId) {
                terminalReplaySuccesses += 1;
            } catch {}
        } else if (action == 2) {
            try settlement.refundVerifierUnavailable(taskId) {
                terminalReplaySuccesses += 1;
            } catch {}
        } else {
            int64[4] memory scores = _scores(actionSeed);
            address provider = _pickActor(actionSeed);
            address beneficiary = _pickActor(taskSeed);
            try settlement.encodeExactInferencePublicValues(taskId, provider, beneficiary, 0, scores) returns (
                bytes memory publicValues
            ) {
                bytes memory proof =
                    abi.encodePacked(proofSelector, keccak256(abi.encode(programId, sha256(publicValues))));
                try settlement.submitExactInferenceProof(taskId, provider, beneficiary, 0, scores, proof) {
                    terminalReplaySuccesses += 1;
                } catch {}
            } catch {}
        }
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function actorAt(uint256 index) external view returns (address) {
        return actors[index];
    }

    function taskCount() external view returns (uint256) {
        return taskIds.length;
    }

    function taskIdAt(uint256 index) external view returns (uint256) {
        return taskIds[index];
    }

    function expectedClaimable(address actor) external view returns (uint256) {
        return expectedClaimableByActor[actor];
    }

    function trackedOpenForConfig(uint64 configId) external view returns (uint256) {
        return trackedOpenByConfig[configId];
    }

    function trackedTaskState(uint256 taskId)
        external
        view
        returns (bool isOpen, bool isTerminal, PulseTensorExactInferenceSettlementV1.TaskStatus terminalStatus)
    {
        TrackedTask storage task = trackedTaskById[taskId];
        return (task.isOpen, task.isTerminal, task.terminalStatus);
    }

    function _pickActor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _pickAvailableConfig(uint256 seed) internal view returns (uint64) {
        uint256 choice = seed % 3;
        if (choice == 1 && !revocableConfigRevoked) return revocableConfigId;
        if (choice == 2 && !verifierMadeUnavailable) return unavailableConfigId;
        return settlementConfigId;
    }

    function _pickSettleableTask(uint256 seed) internal view returns (bool found, uint256 taskId) {
        uint256 length = taskIds.length;
        if (length == 0) return (false, 0);
        for (uint256 offset = 0; offset < length; offset++) {
            uint256 candidateId = taskIds[addmod(seed, offset, length)];
            TrackedTask storage candidate = trackedTaskById[candidateId];
            if (
                candidate.isOpen && block.number <= candidate.deadlineBlock
                    && !(candidate.configId == revocableConfigId && revocableConfigRevoked)
                    && !(candidate.configId == unavailableConfigId && verifierMadeUnavailable)
            ) return (true, candidateId);
        }
        return (false, 0);
    }

    function _pickOpenTask(uint256 seed, uint64 requiredConfig, bool filterConfig)
        internal
        view
        returns (bool found, uint256 taskId)
    {
        uint256 length = taskIds.length;
        if (length == 0) return (false, 0);
        for (uint256 offset = 0; offset < length; offset++) {
            uint256 candidateId = taskIds[addmod(seed, offset, length)];
            TrackedTask storage candidate = trackedTaskById[candidateId];
            if (candidate.isOpen && (!filterConfig || candidate.configId == requiredConfig)) {
                return (true, candidateId);
            }
        }
        return (false, 0);
    }

    function _pickTerminalTask(uint256 seed) internal view returns (bool found, uint256 taskId) {
        uint256 length = taskIds.length;
        if (length == 0) return (false, 0);
        for (uint256 offset = 0; offset < length; offset++) {
            uint256 candidateId = taskIds[addmod(seed, offset, length)];
            if (trackedTaskById[candidateId].isTerminal) return (true, candidateId);
        }
        return (false, 0);
    }

    function _hasOpenTaskForConfig(uint64 configId) internal view returns (bool) {
        return trackedOpenByConfig[configId] != 0;
    }

    function _trackTerminal(uint256 taskId, PulseTensorExactInferenceSettlementV1.TaskStatus terminalStatus) internal {
        TrackedTask storage task = trackedTaskById[taskId];
        task.isOpen = false;
        task.isTerminal = true;
        task.terminalStatus = terminalStatus;
        trackedOpenTasks -= 1;
        trackedOpenByConfig[task.configId] -= 1;
        trackedOpenEscrowWei -= task.rewardWei;
    }

    function _trackRefund(uint256 taskId, PulseTensorExactInferenceSettlementV1.TaskStatus terminalStatus) internal {
        TrackedTask storage task = trackedTaskById[taskId];
        _trackTerminal(taskId, terminalStatus);
        trackedRefundedWei += task.rewardWei;
        trackedClaimableWei += task.rewardWei;
        expectedClaimableByActor[task.refundTo] += task.rewardWei;
    }

    function _scores(uint256 seed) internal pure returns (int64[4] memory scores) {
        int64 base = int64(uint64(seed % uint256(int256(type(int64).max))));
        scores[0] = base;
        scores[1] = base / 2;
        scores[2] = -base / 3;
        scores[3] = 1;
    }
}

contract PulseTensorExactInferenceSettlementV1InvariantTest is StdInvariant, Test {
    bytes32 internal constant PROGRAM_ID = keccak256("PT_Q8_LINEAR_PROGRAM_INVARIANT_V1");
    bytes32 internal constant RELATION_ID = keccak256("PT_Q8_LINEAR_RELATION_INVARIANT_V1");
    uint16 internal constant SETTLEMENT_FEE_BPS = 3_000;
    uint16 internal constant REVOCABLE_FEE_BPS = 777;
    uint16 internal constant UNAVAILABLE_FEE_BPS = 2_500;

    PulseTensorCore internal core;
    PulseTensorExactInferenceSettlementV1 internal settlement;
    ExactInferenceInvariantDigestVerifier internal settlementVerifier;
    ExactInferenceInvariantDigestVerifier internal revocableVerifier;
    ExactInferenceInvariantDigestVerifier internal unavailableVerifier;
    PulseTensorExactInferenceSettlementV1InvariantHandler internal handler;
    uint16 internal netuid;
    uint64 internal settlementConfigId;
    uint64 internal revocableConfigId;
    uint64 internal unavailableConfigId;
    address[] internal actors;

    function setUp() public {
        core = new PulseTensorCore();
        settlement = new PulseTensorExactInferenceSettlementV1(address(core));
        settlementVerifier = new ExactInferenceInvariantDigestVerifier();
        revocableVerifier = new ExactInferenceInvariantDigestVerifier();
        unavailableVerifier = new ExactInferenceInvariantDigestVerifier();

        netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        core.configureSubnetGovernance(netuid, address(this), 2);

        actors = new address[](6);
        for (uint256 index = 0; index < actors.length; index++) {
            actors[index] = makeAddr(string.concat("exact-invariant-actor-", vm.toString(index)));
            vm.deal(actors[index], 10_000 ether);
        }

        settlementConfigId = _activateConfig(address(settlementVerifier), SETTLEMENT_FEE_BPS);
        revocableConfigId = _activateConfig(address(revocableVerifier), REVOCABLE_FEE_BPS);
        unavailableConfigId = _activateConfig(address(unavailableVerifier), UNAVAILABLE_FEE_BPS);

        handler = new PulseTensorExactInferenceSettlementV1InvariantHandler(
            settlement,
            netuid,
            settlementConfigId,
            revocableConfigId,
            unavailableConfigId,
            address(unavailableVerifier),
            PROGRAM_ID,
            settlementVerifier.proofSelector(),
            SETTLEMENT_FEE_BPS,
            REVOCABLE_FEE_BPS,
            UNAVAILABLE_FEE_BPS,
            actors
        );
        core.configureSubnetGovernance(netuid, address(handler), 2);

        // Begin every campaign with one task under each lifecycle configuration.
        handler.createTask(0, 1, 0, 101, 50);
        handler.createTask(1, 2, 1, 202, 50);
        handler.createTask(2, 3, 2, 303, 50);

        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = handler.createTask.selector;
        selectors[1] = handler.settle.selector;
        selectors[2] = handler.refundExpired.selector;
        selectors[3] = handler.revokeRevocableConfig.selector;
        selectors[4] = handler.refundRevoked.selector;
        selectors[5] = handler.makeVerifierUnavailable.selector;
        selectors[6] = handler.refundUnavailable.selector;
        selectors[7] = handler.claim.selector;
        selectors[8] = handler.rollBlocks.selector;
        selectors[9] = handler.attemptTerminalReplay.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_FundedValueIsPartitionedExactly() external view {
        assertEq(
            settlement.totalFundedWei(),
            settlement.totalOpenEscrowWei() + settlement.totalSettledWei() + settlement.totalRefundedWei()
        );
        assertEq(settlement.totalFundedWei(), handler.trackedFundedWei());
        assertEq(settlement.totalOpenEscrowWei(), handler.trackedOpenEscrowWei());
        assertEq(settlement.totalSettledWei(), handler.trackedSettledWei());
        assertEq(settlement.totalRefundedWei(), handler.trackedRefundedWei());
    }

    function invariant_ClaimableValueIsDerivedExactly() external view {
        assertEq(
            settlement.totalClaimableWei(),
            settlement.totalSettledWei() + settlement.totalRefundedWei() - settlement.totalClaimedWei()
        );
        assertEq(settlement.totalClaimableWei(), handler.trackedClaimableWei());
        assertEq(settlement.totalClaimedWei(), handler.trackedClaimedWei());

        uint256 actorCount = handler.actorCount();
        uint256 summedClaimable;
        for (uint256 index = 0; index < actorCount; index++) {
            address actor = handler.actorAt(index);
            uint256 expected = handler.expectedClaimable(actor);
            assertEq(settlement.claimableWei(actor), expected);
            summedClaimable += expected;
        }
        assertEq(settlement.totalClaimableWei(), summedClaimable);
    }

    function invariant_SettlementRemainsSolvent() external view {
        assertGe(address(settlement).balance, settlement.totalOpenEscrowWei() + settlement.totalClaimableWei());
        assertTrue(settlement.accountingInvariantHolds());
    }

    function invariant_OpenTaskCountersMatchTrackedOpenSet() external view {
        assertEq(settlement.totalOpenTasks(), handler.trackedOpenTasks());
        assertEq(
            settlement.openTaskCountByConfig(netuid, settlementConfigId),
            handler.trackedOpenForConfig(settlementConfigId)
        );
        assertEq(
            settlement.openTaskCountByConfig(netuid, revocableConfigId), handler.trackedOpenForConfig(revocableConfigId)
        );
        assertEq(
            settlement.openTaskCountByConfig(netuid, unavailableConfigId),
            handler.trackedOpenForConfig(unavailableConfigId)
        );

        uint256 taskCount = handler.taskCount();
        uint256 countedOpen;
        for (uint256 index = 0; index < taskCount; index++) {
            uint256 taskId = handler.taskIdAt(index);
            (bool isOpen,,) = handler.trackedTaskState(taskId);
            PulseTensorExactInferenceSettlementV1.TaskStatus actualStatus =
                settlement.exactInferenceTasks(taskId).status;
            if (isOpen) {
                countedOpen += 1;
                assertEq(uint256(actualStatus), uint256(PulseTensorExactInferenceSettlementV1.TaskStatus.Open));
            }
        }
        assertEq(countedOpen, handler.trackedOpenTasks());
    }

    function invariant_TerminalTasksNeverTransitionAgain() external view {
        assertEq(handler.terminalReplaySuccesses(), 0);
        uint256 taskCount = handler.taskCount();
        for (uint256 index = 0; index < taskCount; index++) {
            uint256 taskId = handler.taskIdAt(index);
            (, bool isTerminal, PulseTensorExactInferenceSettlementV1.TaskStatus terminalStatus) =
                handler.trackedTaskState(taskId);
            if (isTerminal) {
                assertEq(uint256(settlement.exactInferenceTasks(taskId).status), uint256(terminalStatus));
            }
        }
    }

    function invariant_FeesComeOnlyFromSettledTasks() external view {
        assertLe(settlement.totalProtocolFeesWei(), settlement.totalSettledWei());
        assertEq(settlement.totalProtocolFeesWei(), handler.trackedExpectedProtocolFeesWei());
    }

    function _activateConfig(address verifier, uint16 protocolFeeBps) internal returns (uint64 configId) {
        PulseTensorExactInferenceSettlementV1.VerifierConfigInput memory input = PulseTensorExactInferenceSettlementV1
            .VerifierConfigInput({
            netuid: netuid,
            adapter: verifier,
            adapterRuntimeCodeHash: verifier.codehash,
            verifierRuntimeCodeHash: IPulseTensorProofVerifierMetadata(verifier).verifierRuntimeCodeHash(),
            programId: PROGRAM_ID,
            relationId: RELATION_ID,
            proofSystemId: IPulseTensorProofVerifier(verifier).proofSystemId(),
            proofSelector: IPulseTensorProofVerifierMetadata(verifier).proofSelector(),
            protocolFeeBps: protocolFeeBps,
            treasury: actors[0]
        });

        (bytes32 actionId, uint64 readyAtBlock) = settlement.queueVerifierConfig(input);
        vm.roll(readyAtBlock);
        configId = settlement.executeVerifierConfig(input, actionId);
    }
}

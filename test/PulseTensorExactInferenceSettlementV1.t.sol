// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {PulseTensorCore} from "../src/PulseTensorCore.sol";
import {PulseTensorExactInferenceSettlementV1} from "../src/PulseTensorExactInferenceSettlementV1.sol";
import {RiscZeroVerifierAdapter} from "../src/adapters/RiscZeroVerifierAdapter.sol";
import {
    IPulseTensorProofVerifier,
    IPulseTensorProofVerifierMetadata
} from "../src/interfaces/IPulseTensorProofVerifier.sol";
import {IRiscZeroVerifierWithSelector} from "../src/interfaces/IRiscZeroVerifier.sol";

contract ExactInferenceGovernanceActor {}

/// @dev A test-only verifier that accepts a proof only when it binds the exact program and public values.
contract StrictDigestVerifier is IPulseTensorProofVerifier, IPulseTensorProofVerifierMetadata {
    bytes4 public constant override proofSelector = 0x50544e31;
    bytes32 public constant override verifierRuntimeCodeHash = keccak256("STRICT_DIGEST_UNDERLYING_V1");
    bytes32 public constant PROOF_SYSTEM_ID = keccak256("STRICT_DIGEST_PROOF_SYSTEM_V1");

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
        bytes32 expectedDigest = keccak256(abi.encode(programId, sha256(publicValues)));
        if (suppliedDigest != expectedDigest) revert InvalidProof();
    }
}

/// @dev Deliberate counterexample: runtime codehash does not bind mutable storage semantics.
contract StorageMutableVerifier is IPulseTensorProofVerifier, IPulseTensorProofVerifierMetadata {
    bytes4 public constant override proofSelector = 0x4d555431;
    bytes32 public constant override verifierRuntimeCodeHash = keccak256("MUTABLE_UNDERLYING_V1");
    bytes32 public constant PROOF_SYSTEM_ID = keccak256("MUTABLE_PROOF_SYSTEM_V1");

    bool public acceptsAnything;
    bool public malformedAvailability;

    error Rejected();

    function setAcceptsAnything(bool nextValue) external {
        acceptsAnything = nextValue;
    }

    function setMalformedAvailability(bool nextValue) external {
        malformedAvailability = nextValue;
    }

    function proofSystemId() external pure returns (bytes32) {
        return PROOF_SYSTEM_ID;
    }

    function verifierRuntimeCodeHashMatches() external view returns (bool) {
        if (malformedAvailability) {
            assembly ("memory-safe") {
                return(0, 0)
            }
        }
        return true;
    }

    function verify(bytes32, bytes calldata, bytes calldata proof) external view {
        if (!acceptsAnything || proof.length != 4 || bytes4(proof[:4]) != proofSelector) revert Rejected();
    }
}

contract MockRiscZeroBaseVerifier is IRiscZeroVerifierWithSelector {
    string public constant override VERSION = "3.0.0";
    bytes4 public immutable override SELECTOR;
    bytes32 public immutable expectedImageId;
    bytes32 public immutable expectedJournalDigest;
    bytes32 public immutable expectedSealHash;

    error InvalidReceipt();

    constructor(bytes4 selector, bytes32 imageId, bytes32 journalDigest, bytes32 sealHash) {
        SELECTOR = selector;
        expectedImageId = imageId;
        expectedJournalDigest = journalDigest;
        expectedSealHash = sealHash;
    }

    function verify(bytes calldata seal, bytes32 imageId, bytes32 journalDigest) external view {
        if (
            seal.length < 4 || bytes4(seal[:4]) != SELECTOR || imageId != expectedImageId
                || journalDigest != expectedJournalDigest || keccak256(seal) != expectedSealHash
        ) revert InvalidReceipt();
    }
}

/// @dev Deliberate counterexample implementations used behind a mutable proxy.
abstract contract ProxyVerifierMetadata is IPulseTensorProofVerifier, IPulseTensorProofVerifierMetadata {
    bytes4 public constant override proofSelector = 0x50525831;
    bytes32 public constant override verifierRuntimeCodeHash = keccak256("PROXY_UNDERLYING_V1");
    bytes32 public constant PROOF_SYSTEM_ID = keccak256("PROXY_PROOF_SYSTEM_V1");

    function proofSystemId() external pure returns (bytes32) {
        return PROOF_SYSTEM_ID;
    }

    function verifierRuntimeCodeHashMatches() external pure returns (bool) {
        return true;
    }
}

contract RejectingProxyVerifierImplementation is ProxyVerifierMetadata {
    error Rejected();

    function verify(bytes32, bytes calldata, bytes calldata) external pure override {
        revert Rejected();
    }
}

contract AcceptingProxyVerifierImplementation is ProxyVerifierMetadata {
    error InvalidProof();

    function verify(bytes32, bytes calldata, bytes calldata proof) external pure override {
        if (proof.length != 4 || bytes4(proof) != proofSelector) revert InvalidProof();
    }
}

/// @dev Deliberately unsafe proxy: its stable runtime hash does not bind implementation semantics.
contract MutableVerifierProxy {
    address public implementation;

    constructor(address initialImplementation) {
        implementation = initialImplementation;
    }

    function upgradeTo(address nextImplementation) external {
        implementation = nextImplementation;
    }

    fallback() external {
        address target = implementation;
        assembly ("memory-safe") {
            calldatacopy(0, 0, calldatasize())
            let success := delegatecall(gas(), target, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            if iszero(success) { revert(0, returndatasize()) }
            return(0, returndatasize())
        }
    }
}

/// @dev A malicious verifier that attempts to reenter settlement before accepting its outer proof.
contract ReentrantProofVerifier is IPulseTensorProofVerifier, IPulseTensorProofVerifierMetadata {
    bytes4 public constant override proofSelector = 0x52454e31;
    bytes32 public constant override verifierRuntimeCodeHash = keccak256("REENTRANT_UNDERLYING_V1");
    bytes32 public constant PROOF_SYSTEM_ID = keccak256("REENTRANT_PROOF_SYSTEM_V1");

    PulseTensorExactInferenceSettlementV1 public immutable settlement;
    uint256 public immutable taskId;

    error InvalidProof();
    error ReentryUnexpectedlySucceeded();

    constructor(PulseTensorExactInferenceSettlementV1 settlement_, uint256 taskId_) {
        settlement = settlement_;
        taskId = taskId_;
    }

    function proofSystemId() external pure returns (bytes32) {
        return PROOF_SYSTEM_ID;
    }

    function verifierRuntimeCodeHashMatches() external pure returns (bool) {
        return true;
    }

    function verify(bytes32, bytes calldata, bytes calldata proof) external view {
        if (proof.length != 4 || bytes4(proof) != proofSelector) revert InvalidProof();
        int64[4] memory scores;
        (bool succeeded,) = address(settlement).staticcall{gas: 100_000}(
            abi.encodeCall(
                PulseTensorExactInferenceSettlementV1.submitExactInferenceProof,
                (taskId, address(this), address(this), 0, scores, abi.encodePacked(proofSelector))
            )
        );
        if (succeeded) revert ReentryUnexpectedlySucceeded();
    }
}

/// @dev Deliberately violates the settlement's 50,000-gas availability-probe compatibility bound.
contract GasHungryAvailabilityVerifier is IPulseTensorProofVerifier, IPulseTensorProofVerifierMetadata {
    bytes4 public constant override proofSelector = 0x47415331;
    bytes32 public constant override verifierRuntimeCodeHash = keccak256("GAS_HUNGRY_UNDERLYING_V1");
    bytes32 public constant PROOF_SYSTEM_ID = keccak256("GAS_HUNGRY_PROOF_SYSTEM_V1");

    function proofSystemId() external pure returns (bytes32) {
        return PROOF_SYSTEM_ID;
    }

    function verifierRuntimeCodeHashMatches() external pure returns (bool) {
        bytes32 accumulator;
        for (uint256 index; index < 2_048; ++index) {
            accumulator = keccak256(abi.encode(accumulator, index));
        }
        return accumulator != bytes32(0);
    }

    function verify(bytes32, bytes calldata, bytes calldata) external pure {}
}

contract RejectingPLSReceiver {
    receive() external payable {
        revert("reject PLS");
    }
}

contract ReentrantClaimant {
    PulseTensorExactInferenceSettlementV1 public immutable settlement;
    bool public attemptedReentry;
    bool public reentrySucceeded;
    uint256 public receivedWei;

    constructor(PulseTensorExactInferenceSettlementV1 settlement_) {
        settlement = settlement_;
    }

    function withdraw(uint256 amountWei) external {
        settlement.claim(payable(address(this)), amountWei);
    }

    receive() external payable {
        receivedWei += msg.value;
        if (!attemptedReentry) {
            attemptedReentry = true;
            (reentrySucceeded,) = address(settlement).call(
                abi.encodeCall(PulseTensorExactInferenceSettlementV1.claim, (payable(address(this)), 1))
            );
        }
    }
}

contract PulseTensorExactInferenceSettlementV1Test is Test {
    bytes32 internal constant PROGRAM_ID = keccak256("PT_Q8_LINEAR_PROGRAM_V1");
    bytes32 internal constant RELATION_ID = 0x48a3045b928f9e95b25747a674941e3c55668f2bdb53cf4cf4822bc924feed44;
    bytes32 internal constant INPUT_COMMITMENT = 0xeee475da7d6fe76d90852dfa97de0e1f047cb72d7d0134552245b7cda9a9fb68;
    bytes32 internal constant MODEL_COMMITMENT = 0x1a1f4502024df8a68d12e64bb2364ad6308d04ed0a7d5e8300a676ec70867140;

    address internal constant REQUESTER = address(0x1001);
    address internal constant SECOND_REQUESTER = address(0x1002);
    address internal constant REFUND_TO = address(0x2001);
    address internal constant PROVIDER = address(0x3001);
    address internal constant BENEFICIARY = address(0x4001);
    address internal constant OTHER_BENEFICIARY = address(0x4002);
    address internal constant TREASURY = address(0x5001);
    address internal constant RELAYER = address(0x6001);
    address internal constant PAYOUT = address(0x7001);

    PulseTensorCore internal core;
    PulseTensorExactInferenceSettlementV1 internal settlement;
    StrictDigestVerifier internal strictVerifier;
    ExactInferenceGovernanceActor internal governanceA;
    ExactInferenceGovernanceActor internal governanceB;
    uint16 internal netuid;

    function setUp() public {
        core = new PulseTensorCore();
        settlement = new PulseTensorExactInferenceSettlementV1(address(core));
        strictVerifier = new StrictDigestVerifier();
        governanceA = new ExactInferenceGovernanceActor();
        governanceB = new ExactInferenceGovernanceActor();

        netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        core.configureSubnetGovernance(netuid, address(governanceA), 2);
    }

    function testQueueDelayAndExecuteVerifierConfig() public {
        PulseTensorExactInferenceSettlementV1.VerifierConfigInput memory input =
            _configInput(address(strictVerifier), 3_000, TREASURY);

        vm.prank(address(governanceA));
        (bytes32 actionId, uint64 readyAtBlock) = settlement.queueVerifierConfig(input);

        vm.prank(address(governanceA));
        vm.expectRevert(PulseTensorExactInferenceSettlementV1.GovernanceActionNotReady.selector);
        settlement.executeVerifierConfig(input, actionId);

        vm.roll(readyAtBlock);
        vm.prank(address(governanceA));
        uint64 configId = settlement.executeVerifierConfig(input, actionId);

        PulseTensorExactInferenceSettlementV1.VerifierConfig memory config = settlement.verifierConfigs(configId);
        assertTrue(config.exists);
        assertFalse(config.revoked);
        assertEq(config.netuid, netuid);
        assertEq(config.adapter, address(strictVerifier));
        assertEq(config.adapterRuntimeCodeHash, address(strictVerifier).codehash);
        assertEq(config.programId, PROGRAM_ID);
        assertEq(config.relationId, RELATION_ID);
        assertEq(config.protocolFeeBps, 3_000);
        assertEq(config.treasury, TREASURY);
        assertEq(settlement.currentAdapterRuntimeCodeHash(configId), address(strictVerifier).codehash);
    }

    function testUnauthorizedCallerCannotManageVerifierConfigs() public {
        PulseTensorExactInferenceSettlementV1.VerifierConfigInput memory input =
            _configInput(address(strictVerifier), 0, address(0));

        vm.prank(RELAYER);
        vm.expectRevert(PulseTensorExactInferenceSettlementV1.UnauthorizedGovernance.selector);
        settlement.queueVerifierConfig(input);

        vm.prank(address(governanceA));
        (bytes32 additionActionId, uint64 additionReadyAtBlock) = settlement.queueVerifierConfig(input);
        vm.roll(additionReadyAtBlock);

        vm.prank(RELAYER);
        vm.expectRevert(PulseTensorExactInferenceSettlementV1.UnauthorizedGovernance.selector);
        settlement.executeVerifierConfig(input, additionActionId);

        vm.prank(RELAYER);
        vm.expectRevert(PulseTensorExactInferenceSettlementV1.UnauthorizedGovernance.selector);
        settlement.cancelGovernanceAction(additionActionId);

        vm.prank(address(governanceA));
        uint64 configId = settlement.executeVerifierConfig(input, additionActionId);

        vm.prank(RELAYER);
        vm.expectRevert(PulseTensorExactInferenceSettlementV1.UnauthorizedGovernance.selector);
        settlement.queueVerifierConfigDeprecation(netuid, configId);

        vm.prank(address(governanceA));
        (bytes32 deprecationActionId, uint64 deprecationReadyAtBlock) =
            settlement.queueVerifierConfigDeprecation(netuid, configId);
        vm.roll(deprecationReadyAtBlock);

        vm.prank(RELAYER);
        vm.expectRevert(PulseTensorExactInferenceSettlementV1.UnauthorizedGovernance.selector);
        settlement.executeVerifierConfigDeprecation(netuid, configId, deprecationActionId);

        vm.prank(RELAYER);
        vm.expectRevert(PulseTensorExactInferenceSettlementV1.UnauthorizedGovernance.selector);
        settlement.revokeVerifierConfig(netuid, configId);
    }

    function testGovernanceGenerationRejectsAtoBtoAQueuedActionRevival() public {
        PulseTensorExactInferenceSettlementV1.VerifierConfigInput memory input =
            _configInput(address(strictVerifier), 0, address(0));

        vm.prank(address(governanceA));
        (bytes32 actionId, uint64 readyAtBlock) = settlement.queueVerifierConfig(input);
        assertEq(core.subnetGovernanceGeneration(netuid), 1);

        core.configureSubnetGovernance(netuid, address(governanceB), 2);
        core.configureSubnetGovernance(netuid, address(governanceA), 2);
        assertEq(core.subnetGovernanceGeneration(netuid), 3);

        vm.roll(readyAtBlock);
        vm.prank(address(governanceA));
        vm.expectRevert(
            abi.encodeWithSelector(
                PulseTensorExactInferenceSettlementV1.GovernanceGenerationMismatch.selector, uint64(1), uint64(3)
            )
        );
        settlement.executeVerifierConfig(input, actionId);
    }

    function testGovernanceGenerationRejectsAtoBtoADeprecationRevival() public {
        uint64 configId = _activateConfig(address(strictVerifier), 0, address(0));

        vm.prank(address(governanceA));
        (bytes32 actionId, uint64 readyAtBlock) = settlement.queueVerifierConfigDeprecation(netuid, configId);
        assertEq(core.subnetGovernanceGeneration(netuid), 1);

        core.configureSubnetGovernance(netuid, address(governanceB), 2);
        core.configureSubnetGovernance(netuid, address(governanceA), 2);
        assertEq(core.subnetGovernanceGeneration(netuid), 3);

        vm.roll(readyAtBlock);
        vm.prank(address(governanceA));
        vm.expectRevert(
            abi.encodeWithSelector(
                PulseTensorExactInferenceSettlementV1.GovernanceGenerationMismatch.selector, uint64(1), uint64(3)
            )
        );
        settlement.executeVerifierConfigDeprecation(netuid, configId, actionId);
    }

    function testGovernanceCanCancelExactConfigActionAndRequeue() public {
        PulseTensorExactInferenceSettlementV1.VerifierConfigInput memory input =
            _configInput(address(strictVerifier), 0, address(0));

        vm.prank(address(governanceA));
        (bytes32 actionId,) = settlement.queueVerifierConfig(input);

        vm.prank(address(governanceA));
        settlement.cancelGovernanceAction(actionId);
        vm.prank(address(governanceA));
        vm.expectRevert(PulseTensorExactInferenceSettlementV1.GovernanceActionNotQueued.selector);
        settlement.executeVerifierConfig(input, actionId);

        vm.prank(address(governanceA));
        (bytes32 requeuedActionId, uint64 readyAtBlock) = settlement.queueVerifierConfig(input);
        assertEq(requeuedActionId, actionId);
        vm.roll(readyAtBlock);
        vm.prank(address(governanceA));
        uint64 configId = settlement.executeVerifierConfig(input, requeuedActionId);
        assertTrue(settlement.verifierConfigs(configId).exists);
    }

    function testVerifierConfigGovernanceActionExpiresAndCanBeRequeued() public {
        PulseTensorExactInferenceSettlementV1.VerifierConfigInput memory input =
            _configInput(address(strictVerifier), 0, address(0));

        vm.prank(address(governanceA));
        (bytes32 actionId, uint64 readyAtBlock) = settlement.queueVerifierConfig(input);
        vm.roll(uint256(readyAtBlock) + settlement.GOVERNANCE_ACTION_EXPIRY_BLOCKS() + 1);

        vm.prank(address(governanceA));
        vm.expectRevert(PulseTensorExactInferenceSettlementV1.GovernanceActionExpired.selector);
        settlement.executeVerifierConfig(input, actionId);

        vm.prank(address(governanceA));
        (bytes32 requeuedActionId, uint64 requeuedReadyAtBlock) = settlement.queueVerifierConfig(input);
        assertEq(requeuedActionId, actionId);
        assertGt(requeuedReadyAtBlock, readyAtBlock);
        vm.roll(requeuedReadyAtBlock);
        vm.prank(address(governanceA));
        uint64 configId = settlement.executeVerifierConfig(input, requeuedActionId);
        assertTrue(settlement.verifierConfigs(configId).exists);
    }

    function testRequesterScopedNoncePreventsSelfReplayWithoutCrossRequesterGriefing() public {
        uint64 configId = _activateConfig(address(strictVerifier), 0, address(0));
        uint64 deadlineBlock = uint64(block.number + 100);

        uint256 firstTask = _createTask(REQUESTER, configId, 7, deadlineBlock, REFUND_TO, 1 ether);
        bytes32 firstNullifier = settlement.exactInferenceTasks(firstTask).requestNullifier;

        vm.deal(REQUESTER, 10 ether);
        vm.prank(REQUESTER);
        vm.expectRevert(PulseTensorExactInferenceSettlementV1.RequestNullifierAlreadyUsed.selector);
        settlement.createExactInferenceTask{value: 1 ether}(
            netuid, 1, configId, INPUT_COMMITMENT, MODEL_COMMITMENT, 7, deadlineBlock, REFUND_TO
        );

        uint256 secondTask = _createTask(SECOND_REQUESTER, configId, 7, deadlineBlock, REFUND_TO, 1 ether);
        bytes32 secondNullifier = settlement.exactInferenceTasks(secondTask).requestNullifier;

        assertNotEq(firstNullifier, secondNullifier);
        assertTrue(settlement.requestNullifierUsed(firstNullifier));
        assertTrue(settlement.requestNullifierUsed(secondNullifier));
        assertEq(settlement.totalOpenTasks(), 2);
        assertEq(settlement.openTaskCountByConfig(netuid, configId), 2);
        assertTrue(settlement.accountingInvariantHolds());
    }

    function testCopiedProofRelayerPaysProvedBeneficiaryAndConservesFee() public {
        uint64 configId = _activateConfig(address(strictVerifier), 3_000, TREASURY);
        uint256 rewardWei = 10_001;
        uint256 taskId = _createTask(REQUESTER, configId, 1, uint64(block.number + 100), REFUND_TO, rewardWei);
        int64[4] memory scores = _scores();
        bytes memory proof = _strictProof(taskId, PROVIDER, BENEFICIARY, 2, scores);

        vm.prank(RELAYER);
        settlement.submitExactInferenceProof(taskId, PROVIDER, BENEFICIARY, 2, scores, proof);

        uint256 expectedFee = 3_000;
        assertEq(settlement.claimableWei(BENEFICIARY), rewardWei - expectedFee);
        assertEq(settlement.claimableWei(TREASURY), expectedFee);
        assertEq(settlement.claimableWei(RELAYER), 0);
        assertEq(settlement.totalSettledWei(), rewardWei);
        assertEq(settlement.totalProtocolFeesWei(), expectedFee);
        assertEq(settlement.totalOpenEscrowWei(), 0);
        assertEq(settlement.totalClaimableWei(), rewardWei);
        assertEq(settlement.totalOpenTasks(), 0);
        assertEq(settlement.openTaskCountByConfig(netuid, configId), 0);
        assertEq(
            uint256(settlement.exactInferenceTasks(taskId).status),
            uint256(PulseTensorExactInferenceSettlementV1.TaskStatus.ProofSettled)
        );
        assertTrue(settlement.accountingInvariantHolds());
    }

    function testStrictDigestProofRejectsChangedBeneficiaryWithoutStateChange() public {
        uint64 configId = _activateConfig(address(strictVerifier), 0, address(0));
        uint256 rewardWei = 2 ether;
        uint256 taskId = _createTask(REQUESTER, configId, 2, uint64(block.number + 100), REFUND_TO, rewardWei);
        int64[4] memory scores = _scores();
        bytes memory proof = _strictProof(taskId, PROVIDER, BENEFICIARY, 2, scores);

        vm.expectRevert(StrictDigestVerifier.InvalidProof.selector);
        settlement.submitExactInferenceProof(taskId, PROVIDER, OTHER_BENEFICIARY, 2, scores, proof);

        assertEq(
            uint256(settlement.exactInferenceTasks(taskId).status),
            uint256(PulseTensorExactInferenceSettlementV1.TaskStatus.Open)
        );
        assertEq(settlement.totalOpenTasks(), 1);
        assertEq(settlement.totalOpenEscrowWei(), rewardWei);
        assertEq(settlement.totalSettledWei(), 0);
        assertEq(settlement.totalClaimableWei(), 0);
        assertEq(settlement.claimableWei(BENEFICIARY), 0);
        assertEq(settlement.claimableWei(OTHER_BENEFICIARY), 0);
        assertTrue(settlement.accountingInvariantHolds());
    }

    function testEveryCanonicalPublicValueWordAndProgramMutationIsRejected() public {
        uint64 configId = _activateConfig(address(strictVerifier), 0, address(0));
        uint256 taskId = _createTask(REQUESTER, configId, 26, uint64(block.number + 100), REFUND_TO, 2 ether);
        int64[4] memory scores = _scores();
        bytes memory canonical = settlement.encodeExactInferencePublicValues(taskId, PROVIDER, BENEFICIARY, 2, scores);
        assertEq(canonical.length, 23 * 32);

        for (uint256 wordIndex; wordIndex < 23; ++wordIndex) {
            bytes memory mutated = settlement.encodeExactInferencePublicValues(taskId, PROVIDER, BENEFICIARY, 2, scores);
            uint256 byteIndex = (wordIndex + 1) * 32 - 1;
            mutated[byteIndex] = bytes1(uint8(mutated[byteIndex]) ^ 1);
            bytes memory proof =
                abi.encodePacked(strictVerifier.proofSelector(), keccak256(abi.encode(PROGRAM_ID, sha256(mutated))));

            vm.expectRevert(StrictDigestVerifier.InvalidProof.selector);
            settlement.submitExactInferenceProof(taskId, PROVIDER, BENEFICIARY, 2, scores, proof);
        }

        bytes memory wrongProgramProof = abi.encodePacked(
            strictVerifier.proofSelector(), keccak256(abi.encode(keccak256("WRONG_PROGRAM"), sha256(canonical)))
        );
        vm.expectRevert(StrictDigestVerifier.InvalidProof.selector);
        settlement.submitExactInferenceProof(taskId, PROVIDER, BENEFICIARY, 2, scores, wrongProgramProof);

        bytes memory mutatedProof = _strictProof(taskId, PROVIDER, BENEFICIARY, 2, scores);
        mutatedProof[mutatedProof.length - 1] = bytes1(uint8(mutatedProof[mutatedProof.length - 1]) ^ 1);
        vm.expectRevert(StrictDigestVerifier.InvalidProof.selector);
        settlement.submitExactInferenceProof(taskId, PROVIDER, BENEFICIARY, 2, scores, mutatedProof);

        assertEq(
            uint256(settlement.exactInferenceTasks(taskId).status),
            uint256(PulseTensorExactInferenceSettlementV1.TaskStatus.Open)
        );
        assertEq(settlement.totalOpenEscrowWei(), 2 ether);
        assertEq(settlement.totalClaimableWei(), 0);
        assertTrue(settlement.accountingInvariantHolds());
    }

    function testExpiredTaskRefundsFullEscrowWithoutFeeAndCannotCloseTwice() public {
        uint64 configId = _activateConfig(address(strictVerifier), 3_000, TREASURY);
        uint256 rewardWei = 10_001;
        uint64 deadlineBlock = uint64(block.number + 2);
        uint256 taskId = _createTask(REQUESTER, configId, 3, deadlineBlock, REFUND_TO, rewardWei);

        vm.roll(uint256(deadlineBlock) + 1);
        vm.prank(RELAYER);
        settlement.refundExpired(taskId);

        _assertFullRefund(taskId, configId, rewardWei, PulseTensorExactInferenceSettlementV1.TaskStatus.ExpiredRefund);

        vm.expectRevert(PulseTensorExactInferenceSettlementV1.TaskNotOpen.selector);
        settlement.refundExpired(taskId);
        vm.expectRevert(PulseTensorExactInferenceSettlementV1.TaskNotOpen.selector);
        settlement.refundRevoked(taskId);
    }

    function testProofCanSettleAtDeadlineWhileExpiryRefundCannot() public {
        uint64 configId = _activateConfig(address(strictVerifier), 0, address(0));
        uint64 deadlineBlock = uint64(block.number + 2);
        uint256 taskId = _createTask(REQUESTER, configId, 32, deadlineBlock, REFUND_TO, 1 ether);
        int64[4] memory scores = _scores();
        bytes memory proof = _strictProof(taskId, PROVIDER, BENEFICIARY, 2, scores);

        vm.roll(deadlineBlock);
        vm.expectRevert(PulseTensorExactInferenceSettlementV1.TaskDeadlineNotPassed.selector);
        settlement.refundExpired(taskId);

        settlement.submitExactInferenceProof(taskId, PROVIDER, BENEFICIARY, 2, scores, proof);

        assertEq(
            uint256(settlement.exactInferenceTasks(taskId).status),
            uint256(PulseTensorExactInferenceSettlementV1.TaskStatus.ProofSettled)
        );
        assertEq(settlement.claimableWei(BENEFICIARY), 1 ether);
        assertEq(settlement.totalRefundedWei(), 0);
        assertTrue(settlement.accountingInvariantHolds());
    }

    function testRevokedTaskRefundsFullEscrowWithoutFee() public {
        uint64 configId = _activateConfig(address(strictVerifier), 3_000, TREASURY);
        uint256 rewardWei = 10_001;
        uint256 taskId = _createTask(REQUESTER, configId, 4, uint64(block.number + 100), REFUND_TO, rewardWei);

        vm.prank(address(governanceA));
        settlement.revokeVerifierConfig(netuid, configId);
        vm.prank(RELAYER);
        settlement.refundRevoked(taskId);

        _assertFullRefund(
            taskId, configId, rewardWei, PulseTensorExactInferenceSettlementV1.TaskStatus.VerifierRevokedRefund
        );
    }

    function testAdapterCodeDriftRefundsFullEscrowWithoutFee() public {
        uint64 configId = _activateConfig(address(strictVerifier), 3_000, TREASURY);
        uint256 rewardWei = 10_001;
        uint256 taskId = _createTask(REQUESTER, configId, 5, uint64(block.number + 100), REFUND_TO, rewardWei);

        vm.etch(address(strictVerifier), hex"00");
        assertFalse(settlement.adapterRuntimeCodeHashMatches(configId));
        vm.prank(RELAYER);
        settlement.refundVerifierUnavailable(taskId);

        _assertFullRefund(
            taskId, configId, rewardWei, PulseTensorExactInferenceSettlementV1.TaskStatus.VerifierUnavailableRefund
        );
    }

    function testDeprecationBlocksNewTasksButExistingTaskCanSettle() public {
        uint64 configId = _activateConfig(address(strictVerifier), 0, address(0));
        uint256 oldTaskId = _createTask(REQUESTER, configId, 6, uint64(block.number + 100), REFUND_TO, 1 ether);

        vm.prank(address(governanceA));
        (bytes32 actionId, uint64 readyAtBlock) = settlement.queueVerifierConfigDeprecation(netuid, configId);

        vm.roll(readyAtBlock);
        vm.prank(address(governanceA));
        settlement.executeVerifierConfigDeprecation(netuid, configId, actionId);
        assertEq(settlement.verifierConfigs(configId).stopNewTasksAtBlock, readyAtBlock);
        assertFalse(settlement.verifierAcceptsNewTasks(configId));
        assertTrue(settlement.verifierCanSettleOpenTasks(configId));

        vm.deal(SECOND_REQUESTER, 10 ether);
        vm.prank(SECOND_REQUESTER);
        vm.expectRevert(PulseTensorExactInferenceSettlementV1.VerifierConfigDeprecated.selector);
        settlement.createExactInferenceTask{value: 1 ether}(
            netuid, 1, configId, INPUT_COMMITMENT, MODEL_COMMITMENT, 1, uint64(block.number + 100), REFUND_TO
        );

        int64[4] memory scores = _scores();
        bytes memory proof = _strictProof(oldTaskId, PROVIDER, BENEFICIARY, 2, scores);
        settlement.submitExactInferenceProof(oldTaskId, PROVIDER, BENEFICIARY, 2, scores, proof);

        assertEq(
            uint256(settlement.exactInferenceTasks(oldTaskId).status),
            uint256(PulseTensorExactInferenceSettlementV1.TaskStatus.ProofSettled)
        );
        assertEq(settlement.totalOpenTasks(), 0);
        assertTrue(settlement.accountingInvariantHolds());
    }

    function testLateDeprecationExecutionStopsNewTasksAtExecutionBlock() public {
        uint64 configId = _activateConfig(address(strictVerifier), 0, address(0));

        vm.prank(address(governanceA));
        (bytes32 actionId, uint64 readyAtBlock) = settlement.queueVerifierConfigDeprecation(netuid, configId);

        uint64 executionBlock = readyAtBlock + 17;
        vm.roll(executionBlock);
        vm.prank(address(governanceA));
        settlement.executeVerifierConfigDeprecation(netuid, configId, actionId);

        assertEq(settlement.verifierConfigs(configId).stopNewTasksAtBlock, executionBlock);
        assertGt(executionBlock, readyAtBlock);
        assertFalse(settlement.verifierAcceptsNewTasks(configId));

        vm.deal(SECOND_REQUESTER, 1 ether);
        vm.prank(SECOND_REQUESTER);
        vm.expectRevert(PulseTensorExactInferenceSettlementV1.VerifierConfigDeprecated.selector);
        settlement.createExactInferenceTask{value: 1 ether}(
            netuid, 1, configId, INPUT_COMMITMENT, MODEL_COMMITMENT, 33, uint64(block.number + 100), REFUND_TO
        );
    }

    function testPartialAndFailedClaimKeepAccountingExact() public {
        uint64 configId = _activateConfig(address(strictVerifier), 0, address(0));
        uint256 rewardWei = 100;
        uint256 taskId = _createTask(REQUESTER, configId, 8, uint64(block.number + 100), REFUND_TO, rewardWei);
        int64[4] memory scores = _scores();
        settlement.submitExactInferenceProof(
            taskId, PROVIDER, BENEFICIARY, 2, scores, _strictProof(taskId, PROVIDER, BENEFICIARY, 2, scores)
        );

        RejectingPLSReceiver rejectingReceiver = new RejectingPLSReceiver();
        vm.prank(BENEFICIARY);
        vm.expectRevert(PulseTensorExactInferenceSettlementV1.TransferFailed.selector);
        settlement.claim(payable(address(rejectingReceiver)), 40);
        assertEq(settlement.claimableWei(BENEFICIARY), rewardWei);
        assertEq(settlement.totalClaimedWei(), 0);
        assertEq(settlement.totalClaimableWei(), rewardWei);

        vm.prank(BENEFICIARY);
        settlement.claim(payable(PAYOUT), 40);
        assertEq(PAYOUT.balance, 40);
        assertEq(settlement.claimableWei(BENEFICIARY), 60);
        assertEq(settlement.totalClaimedWei(), 40);
        assertEq(settlement.totalClaimableWei(), 60);
        assertEq(address(settlement).balance, 60);
        assertTrue(settlement.accountingInvariantHolds());
    }

    function testClaimZeroExactAndOverBalanceBoundaries() public {
        uint64 configId = _activateConfig(address(strictVerifier), 0, address(0));
        uint256 taskId = _createTask(REQUESTER, configId, 29, uint64(block.number + 100), REFUND_TO, 100);
        int64[4] memory scores = _scores();
        settlement.submitExactInferenceProof(
            taskId, PROVIDER, BENEFICIARY, 2, scores, _strictProof(taskId, PROVIDER, BENEFICIARY, 2, scores)
        );

        vm.startPrank(BENEFICIARY);
        vm.expectRevert(PulseTensorExactInferenceSettlementV1.InvalidClaim.selector);
        settlement.claim(payable(PAYOUT), 0);
        vm.expectRevert(PulseTensorExactInferenceSettlementV1.InvalidClaim.selector);
        settlement.claim(payable(PAYOUT), 101);
        settlement.claim(payable(PAYOUT), 100);
        vm.stopPrank();

        assertEq(PAYOUT.balance, 100);
        assertEq(settlement.claimableWei(BENEFICIARY), 0);
        assertEq(settlement.totalClaimedWei(), 100);
        assertEq(settlement.totalClaimableWei(), 0);
        assertTrue(settlement.accountingInvariantHolds());
    }

    function testReentrantClaimCannotWithdrawTwice() public {
        uint64 configId = _activateConfig(address(strictVerifier), 0, address(0));
        ReentrantClaimant claimant = new ReentrantClaimant(settlement);
        uint256 rewardWei = 100;
        uint256 taskId = _createTask(REQUESTER, configId, 9, uint64(block.number + 100), REFUND_TO, rewardWei);
        int64[4] memory scores = _scores();
        settlement.submitExactInferenceProof(
            taskId, PROVIDER, address(claimant), 2, scores, _strictProof(taskId, PROVIDER, address(claimant), 2, scores)
        );

        claimant.withdraw(60);

        assertTrue(claimant.attemptedReentry());
        assertFalse(claimant.reentrySucceeded());
        assertEq(claimant.receivedWei(), 60);
        assertEq(settlement.claimableWei(address(claimant)), 40);
        assertEq(settlement.totalClaimedWei(), 60);
        assertEq(settlement.totalClaimableWei(), 40);
        assertEq(address(settlement).balance, 40);
        assertTrue(settlement.accountingInvariantHolds());
    }

    function testAccountingIdentitiesAcrossSettlementExpiryAndRevocation() public {
        uint64 configId = _activateConfig(address(strictVerifier), 1_000, TREASURY);
        uint256 settledReward = 101;
        uint256 expiredReward = 202;
        uint256 revokedReward = 303;

        uint256 settledTask = _createTask(REQUESTER, configId, 10, uint64(block.number + 100), REFUND_TO, settledReward);
        uint64 shortDeadline = uint64(block.number + 3);
        uint256 expiredTask = _createTask(REQUESTER, configId, 11, shortDeadline, REFUND_TO, expiredReward);
        uint256 revokedTask = _createTask(REQUESTER, configId, 12, uint64(block.number + 100), REFUND_TO, revokedReward);
        assertEq(settlement.totalOpenTasks(), 3);
        assertEq(settlement.openTaskCountByConfig(netuid, configId), 3);

        int64[4] memory scores = _scores();
        settlement.submitExactInferenceProof(
            settledTask, PROVIDER, BENEFICIARY, 2, scores, _strictProof(settledTask, PROVIDER, BENEFICIARY, 2, scores)
        );
        vm.roll(uint256(shortDeadline) + 1);
        settlement.refundExpired(expiredTask);
        vm.prank(address(governanceA));
        settlement.revokeVerifierConfig(netuid, configId);
        settlement.refundRevoked(revokedTask);

        uint256 funded = settledReward + expiredReward + revokedReward;
        assertEq(settlement.totalFundedWei(), funded);
        assertEq(settlement.totalOpenEscrowWei(), 0);
        assertEq(settlement.totalSettledWei(), settledReward);
        assertEq(settlement.totalRefundedWei(), expiredReward + revokedReward);
        assertEq(settlement.totalProtocolFeesWei(), 10);
        assertEq(settlement.totalClaimableWei(), funded);
        assertEq(settlement.totalOpenTasks(), 0);
        assertEq(settlement.openTaskCountByConfig(netuid, configId), 0);
        assertEq(address(settlement).balance, funded);
        assertTrue(settlement.accountingInvariantHolds());
    }

    function testVerifierConfigFeeBoundaryAndTreasuryCoupling() public {
        PulseTensorExactInferenceSettlementV1.VerifierConfigInput memory input =
            _configInput(address(strictVerifier), 3_001, TREASURY);
        vm.prank(address(governanceA));
        vm.expectRevert(PulseTensorExactInferenceSettlementV1.InvalidFeePolicy.selector);
        settlement.queueVerifierConfig(input);

        input.protocolFeeBps = 1;
        input.treasury = address(0);
        vm.prank(address(governanceA));
        vm.expectRevert(PulseTensorExactInferenceSettlementV1.InvalidFeePolicy.selector);
        settlement.queueVerifierConfig(input);

        input.protocolFeeBps = 0;
        input.treasury = TREASURY;
        vm.prank(address(governanceA));
        vm.expectRevert(PulseTensorExactInferenceSettlementV1.InvalidFeePolicy.selector);
        settlement.queueVerifierConfig(input);
    }

    function testTaskAndProofBoundariesFailClosed() public {
        uint64 configId = _activateConfig(address(strictVerifier), 0, address(0));
        uint64 validDeadline = uint64(block.number + 100);
        uint64 maxDuration = settlement.MAX_TASK_DURATION_BLOCKS();
        vm.deal(REQUESTER, 10 ether);

        vm.prank(REQUESTER);
        vm.expectRevert(PulseTensorExactInferenceSettlementV1.InvalidTask.selector);
        settlement.createExactInferenceTask(
            netuid, 1_023, configId, INPUT_COMMITMENT, MODEL_COMMITMENT, 19, validDeadline, REFUND_TO
        );

        vm.prank(REQUESTER);
        vm.expectRevert(PulseTensorExactInferenceSettlementV1.InvalidTask.selector);
        settlement.createExactInferenceTask{value: 1 ether}(
            netuid, 1_024, configId, INPUT_COMMITMENT, MODEL_COMMITMENT, 20, validDeadline, REFUND_TO
        );

        vm.prank(REQUESTER);
        vm.expectRevert(PulseTensorExactInferenceSettlementV1.InvalidCommitment.selector);
        settlement.createExactInferenceTask{value: 1 ether}(
            netuid, 1_023, configId, bytes32(0), MODEL_COMMITMENT, 21, validDeadline, REFUND_TO
        );

        vm.prank(REQUESTER);
        vm.expectRevert(PulseTensorExactInferenceSettlementV1.InvalidTaskDeadline.selector);
        settlement.createExactInferenceTask{value: 1 ether}(
            netuid, 1_023, configId, INPUT_COMMITMENT, MODEL_COMMITMENT, 22, uint64(block.number), REFUND_TO
        );

        vm.prank(REQUESTER);
        vm.expectRevert(PulseTensorExactInferenceSettlementV1.InvalidTaskDeadline.selector);
        settlement.createExactInferenceTask{value: 1 ether}(
            netuid,
            1_023,
            configId,
            INPUT_COMMITMENT,
            MODEL_COMMITMENT,
            24,
            uint64(block.number + maxDuration + 1),
            REFUND_TO
        );

        uint256 taskId;
        vm.prank(REQUESTER);
        taskId = settlement.createExactInferenceTask{value: 1 ether}(
            netuid,
            1_023,
            configId,
            INPUT_COMMITMENT,
            MODEL_COMMITMENT,
            23,
            uint64(block.number + maxDuration),
            REFUND_TO
        );
        assertEq(settlement.exactInferenceTasks(taskId).mechid, 1_023);

        int64[4] memory scores = _scores();
        vm.expectRevert(PulseTensorExactInferenceSettlementV1.InvalidProofSelector.selector);
        settlement.submitExactInferenceProof(taskId, PROVIDER, BENEFICIARY, 2, scores, hex"010203");

        vm.expectRevert(PulseTensorExactInferenceSettlementV1.InvalidProofSelector.selector);
        settlement.submitExactInferenceProof(taskId, PROVIDER, BENEFICIARY, 2, scores, hex"ffffffff");

        bytes memory oversizedProof = new bytes(settlement.MAX_PROOF_BYTES() + 1);
        vm.expectRevert(PulseTensorExactInferenceSettlementV1.InvalidProofSelector.selector);
        settlement.submitExactInferenceProof(taskId, PROVIDER, BENEFICIARY, 2, scores, oversizedProof);

        vm.expectRevert(PulseTensorExactInferenceSettlementV1.InvalidProofResult.selector);
        settlement.submitExactInferenceProof(taskId, PROVIDER, BENEFICIARY, 4, scores, hex"01020304");

        assertEq(
            uint256(settlement.exactInferenceTasks(taskId).status),
            uint256(PulseTensorExactInferenceSettlementV1.TaskStatus.Open)
        );
        assertTrue(settlement.accountingInvariantHolds());
    }

    function testMalformedAvailabilityResponseUnlocksFailClosedRefund() public {
        StorageMutableVerifier mutableVerifier = new StorageMutableVerifier();
        uint64 configId = _activateConfig(address(mutableVerifier), 0, address(0));
        uint256 rewardWei = 1 ether;
        uint256 taskId = _createTask(REQUESTER, configId, 25, uint64(block.number + 100), REFUND_TO, rewardWei);

        mutableVerifier.setMalformedAvailability(true);
        assertFalse(settlement.verifierCodeAvailable(configId));
        settlement.refundVerifierUnavailable(taskId);

        _assertFullRefund(
            taskId, configId, rewardWei, PulseTensorExactInferenceSettlementV1.TaskStatus.VerifierUnavailableRefund
        );
    }

    function testAvailabilityProbeGasBoundFailsClosedAtAdmission() public {
        GasHungryAvailabilityVerifier gasHungryVerifier = new GasHungryAvailabilityVerifier();
        PulseTensorExactInferenceSettlementV1.VerifierConfigInput memory input =
            _configInput(address(gasHungryVerifier), 0, address(0));

        vm.prank(address(governanceA));
        vm.expectRevert(PulseTensorExactInferenceSettlementV1.AdapterMetadataMismatch.selector);
        settlement.queueVerifierConfig(input);
    }

    function testCanonicalPublicValuesGoldenVector() public pure {
        int64[4] memory scores;
        scores[0] = -7;
        scores[1] = 12;
        scores[2] = 42;
        scores[3] = 42;
        bytes32 outputCommitment =
            sha256(abi.encode(keccak256("PULSETENSOR_EXACT_OUTPUT_V1"), uint32(1), uint8(2), scores));
        PulseTensorExactInferenceSettlementV1.ExactInferencePublicValuesV1 memory values =
        PulseTensorExactInferenceSettlementV1.ExactInferencePublicValuesV1({
            domain: keccak256("PULSETENSOR_EXACT_PUBLIC_VALUES_V1"),
            version: 1,
            chainId: 369,
            settlement: address(0x1111111111111111111111111111111111111111),
            taskId: 7,
            taskSpecHash: keccak256("task-spec"),
            netuid: 9,
            mechid: 10,
            verifierConfigId: 11,
            relationId: RELATION_ID,
            requestNullifier: keccak256("request-nullifier"),
            inputCommitment: INPUT_COMMITMENT,
            modelCommitment: MODEL_COMMITMENT,
            protocolFeeBps: 1_200,
            treasury: address(0x2222222222222222222222222222222222222222),
            classIndex: 2,
            scores: scores,
            outputCommitment: outputCommitment,
            provider: address(0x3333333333333333333333333333333333333333),
            beneficiary: address(0x4444444444444444444444444444444444444444)
        });

        bytes memory encoded = abi.encode(values);
        assertEq(encoded.length, 23 * 32);
        assertEq(sha256(encoded), 0xd6bf3e24201d46ca655687be218f9186309e1138e0866073e8fd6fabaaf02067);
    }

    function testPublicCommitmentHelpersMatchCanonicalDefinitions() public view {
        int64[4] memory scores = _scores();
        bytes32 expectedOutput =
            sha256(abi.encode(settlement.OUTPUT_DOMAIN(), settlement.DOMAIN_VERSION(), uint8(2), scores));
        assertEq(settlement.computeExactInferenceOutputCommitment(2, scores), expectedOutput);

        bytes32 expectedNullifier = keccak256(
            abi.encode(
                settlement.REQUEST_NULLIFIER_DOMAIN(),
                settlement.DOMAIN_VERSION(),
                block.chainid,
                address(settlement),
                REQUESTER,
                uint64(31)
            )
        );
        assertEq(settlement.computeRequestNullifier(REQUESTER, 31), expectedNullifier);
    }

    function testRiscZeroAdapterBindsSelectorJournalAndBaseCodehash() public {
        bytes4 selector = 0x73c457ba;
        bytes32 imageId = keccak256("risc-zero-image");
        bytes memory publicValues = abi.encode(bytes32("journal"), uint256(7));
        bytes memory seal = abi.encodePacked(selector, new bytes(8 * 32));
        MockRiscZeroBaseVerifier base =
            new MockRiscZeroBaseVerifier(selector, imageId, sha256(publicValues), keccak256(seal));
        bytes32 baseRuntimeCodeHash = address(base).codehash;

        vm.mockCall(
            address(base), abi.encodeWithSelector(IRiscZeroVerifierWithSelector.VERSION.selector), abi.encode("2.3.1")
        );
        vm.expectRevert(RiscZeroVerifierAdapter.VerifierVersionMismatch.selector);
        new RiscZeroVerifierAdapter(address(base), selector, baseRuntimeCodeHash);
        vm.clearMockedCalls();

        RiscZeroVerifierAdapter adapter = new RiscZeroVerifierAdapter(address(base), selector, baseRuntimeCodeHash);

        adapter.verify(imageId, publicValues, seal);

        bytes memory wrongSelectorSeal = abi.encodePacked(bytes4(0x01020304), new bytes(8 * 32));
        vm.expectRevert(RiscZeroVerifierAdapter.InvalidProofSelector.selector);
        adapter.verify(imageId, publicValues, wrongSelectorSeal);

        bytes memory truncatedSeal = abi.encodePacked(selector, new bytes(8 * 32 - 1));
        vm.expectRevert(RiscZeroVerifierAdapter.InvalidProofSelector.selector);
        adapter.verify(imageId, publicValues, truncatedSeal);

        bytes memory trailingSeal = abi.encodePacked(selector, new bytes(8 * 32 + 1));
        vm.expectRevert(RiscZeroVerifierAdapter.InvalidProofSelector.selector);
        adapter.verify(imageId, publicValues, trailingSeal);

        vm.etch(address(base), hex"60006000fd");
        vm.expectRevert(
            abi.encodeWithSelector(
                RiscZeroVerifierAdapter.VerifierRuntimeCodeHashMismatch.selector,
                baseRuntimeCodeHash,
                address(base).codehash
            )
        );
        adapter.verify(imageId, publicValues, seal);
    }

    function testRiscZeroAdapterConstructorAndProgramBoundariesFailClosed() public {
        bytes4 selector = 0x73c457ba;
        bytes32 imageId = keccak256("risc-zero-image");
        bytes memory publicValues = abi.encode(bytes32("journal"), uint256(8));
        bytes memory seal = abi.encodePacked(selector, new bytes(8 * 32));
        MockRiscZeroBaseVerifier base =
            new MockRiscZeroBaseVerifier(selector, imageId, sha256(publicValues), keccak256(seal));
        bytes32 runtimeCodeHash = address(base).codehash;

        vm.expectRevert(RiscZeroVerifierAdapter.InvalidVerifier.selector);
        new RiscZeroVerifierAdapter(address(0), selector, runtimeCodeHash);
        vm.expectRevert(RiscZeroVerifierAdapter.InvalidVerifier.selector);
        new RiscZeroVerifierAdapter(address(0xBEEF), selector, runtimeCodeHash);
        vm.expectRevert(RiscZeroVerifierAdapter.InvalidVerifier.selector);
        new RiscZeroVerifierAdapter(address(base), bytes4(0), runtimeCodeHash);
        vm.expectRevert(RiscZeroVerifierAdapter.InvalidVerifier.selector);
        new RiscZeroVerifierAdapter(address(base), selector, bytes32(0));

        bytes32 wrongRuntimeCodeHash = keccak256("wrong-runtime");
        vm.expectRevert(
            abi.encodeWithSelector(
                RiscZeroVerifierAdapter.VerifierRuntimeCodeHashMismatch.selector, wrongRuntimeCodeHash, runtimeCodeHash
            )
        );
        new RiscZeroVerifierAdapter(address(base), selector, wrongRuntimeCodeHash);
        bytes4 wrongSelector = 0x01020304;
        vm.expectRevert(
            abi.encodeWithSelector(RiscZeroVerifierAdapter.VerifierSelectorMismatch.selector, wrongSelector, selector)
        );
        new RiscZeroVerifierAdapter(address(base), wrongSelector, runtimeCodeHash);

        RiscZeroVerifierAdapter adapter = new RiscZeroVerifierAdapter(address(base), selector, runtimeCodeHash);
        vm.expectRevert(RiscZeroVerifierAdapter.InvalidProgramId.selector);
        adapter.verify(bytes32(0), publicValues, seal);
    }

    function testRiscZeroBaseCodeDriftBlocksUseAndUnlocksImmediateFullRefund() public {
        bytes4 selector = 0x73c457ba;
        bytes32 imageId = PROGRAM_ID;
        bytes memory placeholderJournal = abi.encode(bytes32("placeholder"));
        bytes memory placeholderSeal = abi.encodePacked(selector, new bytes(8 * 32));
        MockRiscZeroBaseVerifier base =
            new MockRiscZeroBaseVerifier(selector, imageId, sha256(placeholderJournal), keccak256(placeholderSeal));
        RiscZeroVerifierAdapter adapter = new RiscZeroVerifierAdapter(address(base), selector, address(base).codehash);
        uint64 configId = _activateConfig(address(adapter), 3_000, TREASURY);
        uint256 rewardWei = 10_001;
        uint256 taskId = _createTask(REQUESTER, configId, 14, uint64(block.number + 100), REFUND_TO, rewardWei);

        vm.etch(address(base), hex"60006000fd");
        assertFalse(adapter.verifierRuntimeCodeHashMatches());

        vm.deal(SECOND_REQUESTER, 10 ether);
        vm.prank(SECOND_REQUESTER);
        vm.expectRevert(PulseTensorExactInferenceSettlementV1.VerifierUnavailable.selector);
        settlement.createExactInferenceTask{value: 1 ether}(
            netuid, 1, configId, INPUT_COMMITMENT, MODEL_COMMITMENT, 14, uint64(block.number + 100), REFUND_TO
        );

        int64[4] memory scores = _scores();
        vm.expectRevert(PulseTensorExactInferenceSettlementV1.VerifierUnavailable.selector);
        settlement.submitExactInferenceProof(taskId, PROVIDER, BENEFICIARY, 2, scores, placeholderSeal);
        assertEq(
            uint256(settlement.exactInferenceTasks(taskId).status),
            uint256(PulseTensorExactInferenceSettlementV1.TaskStatus.Open)
        );

        vm.prank(RELAYER);
        settlement.refundVerifierUnavailable(taskId);
        _assertFullRefund(
            taskId, configId, rewardWei, PulseTensorExactInferenceSettlementV1.TaskStatus.VerifierUnavailableRefund
        );
    }

    function testCounterexampleMutableVerifierChangesSemanticsWithoutChangingCodehash() public {
        StorageMutableVerifier mutableVerifier = new StorageMutableVerifier();
        bytes32 runtimeCodeHash = address(mutableVerifier).codehash;
        uint64 configId = _activateConfig(address(mutableVerifier), 0, address(0));
        uint256 taskId = _createTask(REQUESTER, configId, 13, uint64(block.number + 100), REFUND_TO, 1 ether);
        int64[4] memory scores = _scores();
        bytes memory arbitraryProof = abi.encodePacked(mutableVerifier.proofSelector());

        vm.expectRevert(StorageMutableVerifier.Rejected.selector);
        settlement.submitExactInferenceProof(taskId, PROVIDER, BENEFICIARY, 2, scores, arbitraryProof);
        assertEq(address(mutableVerifier).codehash, runtimeCodeHash);
        assertTrue(settlement.adapterRuntimeCodeHashMatches(configId));

        mutableVerifier.setAcceptsAnything(true);
        assertEq(address(mutableVerifier).codehash, runtimeCodeHash);
        assertTrue(settlement.adapterRuntimeCodeHashMatches(configId));
        settlement.submitExactInferenceProof(taskId, PROVIDER, BENEFICIARY, 2, scores, arbitraryProof);

        assertEq(
            uint256(settlement.exactInferenceTasks(taskId).status),
            uint256(PulseTensorExactInferenceSettlementV1.TaskStatus.ProofSettled)
        );
        assertTrue(settlement.accountingInvariantHolds());
    }

    function testCounterexampleProxyUpgradeChangesSemanticsWithoutChangingCodehash() public {
        RejectingProxyVerifierImplementation rejecting = new RejectingProxyVerifierImplementation();
        AcceptingProxyVerifierImplementation accepting = new AcceptingProxyVerifierImplementation();
        MutableVerifierProxy proxy = new MutableVerifierProxy(address(rejecting));
        bytes32 stableProxyRuntimeCodeHash = address(proxy).codehash;
        uint64 configId = _activateConfig(address(proxy), 0, address(0));
        uint256 taskId = _createTask(REQUESTER, configId, 27, uint64(block.number + 100), REFUND_TO, 1 ether);
        int64[4] memory scores = _scores();
        bytes memory arbitraryProof = abi.encodePacked(ProxyVerifierMetadata(address(proxy)).proofSelector());

        vm.expectRevert(RejectingProxyVerifierImplementation.Rejected.selector);
        settlement.submitExactInferenceProof(taskId, PROVIDER, BENEFICIARY, 2, scores, arbitraryProof);

        proxy.upgradeTo(address(accepting));
        assertEq(address(proxy).codehash, stableProxyRuntimeCodeHash);
        assertTrue(settlement.verifierCodeAvailable(configId));
        settlement.submitExactInferenceProof(taskId, PROVIDER, BENEFICIARY, 2, scores, arbitraryProof);

        assertEq(
            uint256(settlement.exactInferenceTasks(taskId).status),
            uint256(PulseTensorExactInferenceSettlementV1.TaskStatus.ProofSettled)
        );
        assertTrue(settlement.accountingInvariantHolds());
    }

    function testMaliciousVerifierReentryCannotChangeSettlementState() public {
        ReentrantProofVerifier verifier = new ReentrantProofVerifier(settlement, settlement.nextTaskId());
        uint64 configId = _activateConfig(address(verifier), 0, address(0));
        uint256 taskId = _createTask(REQUESTER, configId, 28, uint64(block.number + 100), REFUND_TO, 1 ether);
        assertEq(taskId, verifier.taskId());
        int64[4] memory scores;

        settlement.submitExactInferenceProof(
            taskId, PROVIDER, BENEFICIARY, 0, scores, abi.encodePacked(verifier.proofSelector())
        );

        assertEq(
            uint256(settlement.exactInferenceTasks(taskId).status),
            uint256(PulseTensorExactInferenceSettlementV1.TaskStatus.ProofSettled)
        );
        assertEq(settlement.claimableWei(BENEFICIARY), 1 ether);
        assertEq(settlement.totalOpenEscrowWei(), 0);
        assertEq(settlement.totalClaimableWei(), 1 ether);
        assertTrue(settlement.accountingInvariantHolds());
    }

    function _activateConfig(address adapter, uint16 protocolFeeBps, address treasury)
        internal
        returns (uint64 configId)
    {
        PulseTensorExactInferenceSettlementV1.VerifierConfigInput memory input =
            _configInput(adapter, protocolFeeBps, treasury);
        vm.prank(address(governanceA));
        (bytes32 actionId, uint64 readyAtBlock) = settlement.queueVerifierConfig(input);
        vm.roll(readyAtBlock);
        vm.prank(address(governanceA));
        configId = settlement.executeVerifierConfig(input, actionId);
    }

    function _configInput(address adapter, uint16 protocolFeeBps, address treasury)
        internal
        view
        returns (PulseTensorExactInferenceSettlementV1.VerifierConfigInput memory input)
    {
        input = PulseTensorExactInferenceSettlementV1.VerifierConfigInput({
            netuid: netuid,
            adapter: adapter,
            adapterRuntimeCodeHash: adapter.codehash,
            verifierRuntimeCodeHash: IPulseTensorProofVerifierMetadata(adapter).verifierRuntimeCodeHash(),
            programId: PROGRAM_ID,
            relationId: RELATION_ID,
            proofSystemId: IPulseTensorProofVerifier(adapter).proofSystemId(),
            proofSelector: IPulseTensorProofVerifierMetadata(adapter).proofSelector(),
            protocolFeeBps: protocolFeeBps,
            treasury: treasury
        });
    }

    function _createTask(
        address requester,
        uint64 configId,
        uint64 requesterNonce,
        uint64 deadlineBlock,
        address refundTo,
        uint256 rewardWei
    ) internal returns (uint256 taskId) {
        vm.deal(requester, 100 ether);
        vm.prank(requester);
        taskId = settlement.createExactInferenceTask{value: rewardWei}(
            netuid, 1, configId, INPUT_COMMITMENT, MODEL_COMMITMENT, requesterNonce, deadlineBlock, refundTo
        );
    }

    function _strictProof(
        uint256 taskId,
        address provider,
        address beneficiary,
        uint8 classIndex,
        int64[4] memory scores
    ) internal view returns (bytes memory) {
        bytes memory publicValues =
            settlement.encodeExactInferencePublicValues(taskId, provider, beneficiary, classIndex, scores);
        bytes32 digest = keccak256(abi.encode(PROGRAM_ID, sha256(publicValues)));
        return abi.encodePacked(strictVerifier.proofSelector(), digest);
    }

    function _scores() internal pure returns (int64[4] memory scores) {
        scores[0] = -7;
        scores[1] = 12;
        scores[2] = 42;
        scores[3] = 42;
    }

    function _assertFullRefund(
        uint256 taskId,
        uint64 configId,
        uint256 rewardWei,
        PulseTensorExactInferenceSettlementV1.TaskStatus expectedStatus
    ) internal view {
        assertEq(uint256(settlement.exactInferenceTasks(taskId).status), uint256(expectedStatus));
        assertEq(settlement.claimableWei(REFUND_TO), rewardWei);
        assertEq(settlement.claimableWei(TREASURY), 0);
        assertEq(settlement.totalProtocolFeesWei(), 0);
        assertEq(settlement.totalRefundedWei(), rewardWei);
        assertEq(settlement.totalOpenEscrowWei(), 0);
        assertEq(settlement.totalClaimableWei(), rewardWei);
        assertEq(settlement.totalOpenTasks(), 0);
        assertEq(settlement.openTaskCountByConfig(netuid, configId), 0);
        assertEq(address(settlement).balance, rewardWei);
        assertTrue(settlement.accountingInvariantHolds());
    }
}

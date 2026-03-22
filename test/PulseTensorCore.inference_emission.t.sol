// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PulseTensorCore} from "../src/PulseTensorCore.sol";
import {PulseTensorInferenceSettlement} from "../src/PulseTensorInferenceSettlement.sol";

interface Vm {
    function roll(uint256 newHeight) external;
    function deal(address who, uint256 newBalance) external;
}

contract FeatureActor {
    function addStake(PulseTensorCore core, uint16 netuid) external payable {
        core.addStake{value: msg.value}(netuid);
    }

    function registerValidator(PulseTensorCore core, uint16 netuid) external {
        core.registerValidator(netuid);
    }

    function queueSubnetEmissionScheduleUpdate(
        PulseTensorCore core,
        uint16 netuid,
        uint256 baseEmissionPerEpoch,
        uint256 floorEmissionPerEpoch,
        uint64 halvingPeriodEpochs,
        uint64 startEpoch
    ) external returns (uint64 readyAtBlock) {
        (, readyAtBlock) = core.queueSubnetEmissionScheduleUpdate(
            netuid, baseEmissionPerEpoch, floorEmissionPerEpoch, halvingPeriodEpochs, startEpoch
        );
    }

    function configureSubnetEmissionSchedule(
        PulseTensorCore core,
        uint16 netuid,
        uint256 baseEmissionPerEpoch,
        uint256 floorEmissionPerEpoch,
        uint64 halvingPeriodEpochs,
        uint64 startEpoch
    ) external {
        core.configureSubnetEmissionSchedule(
            netuid, baseEmissionPerEpoch, floorEmissionPerEpoch, halvingPeriodEpochs, startEpoch
        );
    }

    function queueSubnetEmissionSmoothingUpdate(PulseTensorCore core, uint16 netuid, bool smoothDecayEnabled)
        external
        returns (uint64 readyAtBlock)
    {
        (, readyAtBlock) = core.queueSubnetEmissionSmoothingUpdate(netuid, smoothDecayEnabled);
    }

    function configureSubnetEmissionSmoothing(PulseTensorCore core, uint16 netuid, bool smoothDecayEnabled) external {
        core.configureSubnetEmissionSmoothing(netuid, smoothDecayEnabled);
    }

    function queueMechanismEmissionScheduleUpdate(
        PulseTensorCore core,
        uint16 netuid,
        uint16 mechid,
        uint256 baseEmissionPerEpoch,
        uint256 floorEmissionPerEpoch,
        uint64 halvingPeriodEpochs,
        uint64 startEpoch
    ) external returns (uint64 readyAtBlock) {
        (, readyAtBlock) = core.queueMechanismEmissionScheduleUpdate(
            netuid, mechid, baseEmissionPerEpoch, floorEmissionPerEpoch, halvingPeriodEpochs, startEpoch
        );
    }

    function configureMechanismEmissionSchedule(
        PulseTensorCore core,
        uint16 netuid,
        uint16 mechid,
        uint256 baseEmissionPerEpoch,
        uint256 floorEmissionPerEpoch,
        uint64 halvingPeriodEpochs,
        uint64 startEpoch
    ) external {
        core.configureMechanismEmissionSchedule(
            netuid, mechid, baseEmissionPerEpoch, floorEmissionPerEpoch, halvingPeriodEpochs, startEpoch
        );
    }

    function queueMechanismEmissionSmoothingUpdate(
        PulseTensorCore core,
        uint16 netuid,
        uint16 mechid,
        bool smoothDecayEnabled
    ) external returns (uint64 readyAtBlock) {
        (, readyAtBlock) = core.queueMechanismEmissionSmoothingUpdate(netuid, mechid, smoothDecayEnabled);
    }

    function configureMechanismEmissionSmoothing(
        PulseTensorCore core,
        uint16 netuid,
        uint16 mechid,
        bool smoothDecayEnabled
    ) external {
        core.configureMechanismEmissionSmoothing(netuid, mechid, smoothDecayEnabled);
    }

    function queueInferenceBatchPolicyUpdate(
        PulseTensorInferenceSettlement settlement,
        uint16 netuid,
        uint16 mechid,
        bool enabled,
        uint64 challengeWindowBlocks,
        uint32 maxBatchItems,
        uint256 minProposerBondWei
    ) external returns (uint64 readyAtBlock) {
        (, readyAtBlock) = settlement.queueBatchPolicyUpdate(
            netuid, mechid, enabled, challengeWindowBlocks, maxBatchItems, minProposerBondWei
        );
    }

    function queueInferenceBatchPolicyUpdateWithAction(
        PulseTensorInferenceSettlement settlement,
        uint16 netuid,
        uint16 mechid,
        bool enabled,
        uint64 challengeWindowBlocks,
        uint32 maxBatchItems,
        uint256 minProposerBondWei
    ) external returns (bytes32 actionId, uint64 readyAtBlock) {
        (actionId, readyAtBlock) = settlement.queueBatchPolicyUpdate(
            netuid, mechid, enabled, challengeWindowBlocks, maxBatchItems, minProposerBondWei
        );
    }

    function configureInferenceBatchPolicy(
        PulseTensorInferenceSettlement settlement,
        uint16 netuid,
        uint16 mechid,
        bool enabled,
        uint64 challengeWindowBlocks,
        uint32 maxBatchItems,
        uint256 minProposerBondWei
    ) external {
        settlement.configureBatchPolicy(
            netuid, mechid, enabled, challengeWindowBlocks, maxBatchItems, minProposerBondWei
        );
    }

    function cancelInferenceBatchPolicyUpdate(
        PulseTensorInferenceSettlement settlement,
        uint16 netuid,
        uint16 mechid,
        bool enabled,
        uint64 challengeWindowBlocks,
        uint32 maxBatchItems,
        uint256 minProposerBondWei
    ) external {
        settlement.cancelBatchPolicyUpdate(
            netuid, mechid, enabled, challengeWindowBlocks, maxBatchItems, minProposerBondWei
        );
    }

    function queueInferenceFeePolicyUpdate(
        PulseTensorInferenceSettlement settlement,
        uint16 netuid,
        uint16 mechid,
        bool enabled,
        uint16 protocolFeeBps,
        uint16 treasuryFeeBps,
        address treasurySink,
        address minerSink
    ) external returns (uint64 readyAtBlock) {
        (, readyAtBlock) = settlement.queueFeePolicyUpdate(
            netuid, mechid, enabled, protocolFeeBps, treasuryFeeBps, treasurySink, minerSink
        );
    }

    function queueInferenceFeePolicyUpdateWithAction(
        PulseTensorInferenceSettlement settlement,
        uint16 netuid,
        uint16 mechid,
        bool enabled,
        uint16 protocolFeeBps,
        uint16 treasuryFeeBps,
        address treasurySink,
        address minerSink
    ) external returns (bytes32 actionId, uint64 readyAtBlock) {
        (actionId, readyAtBlock) = settlement.queueFeePolicyUpdate(
            netuid, mechid, enabled, protocolFeeBps, treasuryFeeBps, treasurySink, minerSink
        );
    }

    function configureInferenceFeePolicy(
        PulseTensorInferenceSettlement settlement,
        uint16 netuid,
        uint16 mechid,
        bool enabled,
        uint16 protocolFeeBps,
        uint16 treasuryFeeBps,
        address treasurySink,
        address minerSink
    ) external {
        settlement.configureFeePolicy(netuid, mechid, enabled, protocolFeeBps, treasuryFeeBps, treasurySink, minerSink);
    }

    function cancelInferenceFeePolicyUpdate(
        PulseTensorInferenceSettlement settlement,
        uint16 netuid,
        uint16 mechid,
        bool enabled,
        uint16 protocolFeeBps,
        uint16 treasuryFeeBps,
        address treasurySink,
        address minerSink
    ) external {
        settlement.cancelFeePolicyUpdate(
            netuid, mechid, enabled, protocolFeeBps, treasuryFeeBps, treasurySink, minerSink
        );
    }

    function commitInferenceBatchRoot(
        PulseTensorInferenceSettlement settlement,
        uint16 netuid,
        uint16 mechid,
        uint64 epoch,
        bytes32 batchRoot,
        uint32 itemCount,
        uint256 feeTotal
    ) external payable {
        settlement.commitInferenceBatchRoot{value: msg.value}(netuid, mechid, epoch, batchRoot, itemCount, feeTotal);
    }

    function fundInferenceBatchFees(
        PulseTensorInferenceSettlement settlement,
        uint16 netuid,
        uint16 mechid,
        uint64 epoch
    ) external payable {
        settlement.fundInferenceBatchFees{value: msg.value}(netuid, mechid, epoch);
    }

    function withdrawInferenceBatchFees(
        PulseTensorInferenceSettlement settlement,
        uint16 netuid,
        uint16 mechid,
        uint64 epoch,
        uint256 amount
    ) external {
        settlement.withdrawInferenceBatchFees(netuid, mechid, epoch, amount);
    }

    function challengeInferenceLeafReplay(
        PulseTensorInferenceSettlement settlement,
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
        settlement.challengeInferenceLeafReplay(
            netuid, mechid, epoch, leafHash, index, merkleProof, priorEpoch, priorIndex, priorMerkleProof
        );
    }

    function challengeInferenceLeafDuplicate(
        PulseTensorInferenceSettlement settlement,
        uint16 netuid,
        uint16 mechid,
        uint64 epoch,
        bytes32 leafHash,
        uint256 indexA,
        bytes32[] calldata proofA,
        uint256 indexB,
        bytes32[] calldata proofB
    ) external {
        settlement.challengeInferenceLeafDuplicate(netuid, mechid, epoch, leafHash, indexA, proofA, indexB, proofB);
    }

    function claimChallengeReward(PulseTensorInferenceSettlement settlement, uint16 netuid, uint256 amount) external {
        settlement.claimChallengeReward(netuid, amount);
    }

    function claimProposerBondRefund(PulseTensorInferenceSettlement settlement, uint16 netuid, uint256 amount)
        external
    {
        settlement.claimProposerBondRefund(netuid, amount);
    }

    function claimInferenceFee(PulseTensorInferenceSettlement settlement, uint16 netuid, uint256 amount) external {
        settlement.claimInferenceFee(netuid, amount);
    }

    receive() external payable {}
}

contract RevertingFeatureActor {
    function addStake(PulseTensorCore core, uint16 netuid) external payable {
        core.addStake{value: msg.value}(netuid);
    }

    function registerValidator(PulseTensorCore core, uint16 netuid) external {
        core.registerValidator(netuid);
    }

    function commitInferenceBatchRoot(
        PulseTensorInferenceSettlement settlement,
        uint16 netuid,
        uint16 mechid,
        uint64 epoch,
        bytes32 batchRoot,
        uint32 itemCount,
        uint256 feeTotal
    ) external payable {
        settlement.commitInferenceBatchRoot{value: msg.value}(netuid, mechid, epoch, batchRoot, itemCount, feeTotal);
    }

    receive() external payable {
        revert("reject-eth");
    }
}

contract PulseTensorCoreInferenceEmissionTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    PulseTensorCore internal core;
    PulseTensorInferenceSettlement internal settlement;

    function setUp() public {
        core = new PulseTensorCore();
        settlement = new PulseTensorInferenceSettlement(address(core));
        vm.deal(address(this), 1_000 ether);
    }

    function testComputeInferenceLeafDomainSeparatesEpochAndRequest() public view {
        bytes32 requestId = keccak256("request-1");
        bytes32 resultHash = keccak256("result-1");

        bytes32 baseLeaf = settlement.computeInferenceLeaf(7, 3, 11, requestId, resultHash);
        bytes32 sameLeaf = settlement.computeInferenceLeaf(7, 3, 11, requestId, resultHash);
        bytes32 epochLeaf = settlement.computeInferenceLeaf(7, 3, 12, requestId, resultHash);
        bytes32 requestLeaf = settlement.computeInferenceLeaf(7, 3, 11, keccak256("request-2"), resultHash);

        assert(baseLeaf == sameLeaf);
        assert(baseLeaf != epochLeaf);
        assert(baseLeaf != requestLeaf);
    }

    function _hashPair(bytes32 left, bytes32 right) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(left, right));
    }

    function _setupGovernanceAndValidator(uint16 netuid)
        internal
        returns (FeatureActor governance, FeatureActor validator)
    {
        governance = new FeatureActor();
        validator = new FeatureActor();

        core.configureSubnetGovernance(netuid, address(governance), 2);

        vm.deal(address(validator), 10 ether);
        validator.addStake{value: 2 ether}(core, netuid);
        validator.registerValidator(core, netuid);
    }

    function testSubnetEmissionSmoothingCanBeGovernedAndQuotesSmoothly() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        FeatureActor governance = new FeatureActor();
        core.configureSubnetGovernance(netuid, address(governance), 2);

        uint64 scheduleReadyAt = governance.queueSubnetEmissionScheduleUpdate(core, netuid, 1 ether, 0.125 ether, 4, 0);
        uint64 smoothingReadyAt = governance.queueSubnetEmissionSmoothingUpdate(core, netuid, true);
        vm.roll(scheduleReadyAt > smoothingReadyAt ? scheduleReadyAt : smoothingReadyAt);
        governance.configureSubnetEmissionSchedule(core, netuid, 1 ether, 0.125 ether, 4, 0);
        governance.configureSubnetEmissionSmoothing(core, netuid, true);

        assert(core.subnetEmissionSmoothDecayEnabled(netuid));
        assert(core.quoteSubnetEpochEmission(netuid, 0) == 1 ether);
        assert(core.quoteSubnetEpochEmission(netuid, 1) == 0.875 ether);
        assert(core.quoteSubnetEpochEmission(netuid, 2) == 0.75 ether);
        assert(core.quoteSubnetEpochEmission(netuid, 3) == 0.625 ether);
        assert(core.quoteSubnetEpochEmission(netuid, 4) == 0.5 ether);
        assert(core.quoteSubnetEpochEmission(netuid, 64) == 0.125 ether);

        uint64 disableReadyAt = governance.queueSubnetEmissionSmoothingUpdate(core, netuid, false);
        vm.roll(disableReadyAt);
        governance.configureSubnetEmissionSmoothing(core, netuid, false);
        assert(!core.subnetEmissionSmoothDecayEnabled(netuid));
        assert(core.quoteSubnetEpochEmission(netuid, 1) == 1 ether);
        assert(core.quoteSubnetEpochEmission(netuid, 4) == 0.5 ether);
    }

    function testMechanismEmissionSmoothingCanBeGoverned() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        FeatureActor governance = new FeatureActor();
        core.configureSubnetGovernance(netuid, address(governance), 2);
        uint16 mechid = 3;

        uint64 scheduleReadyAt =
            governance.queueMechanismEmissionScheduleUpdate(core, netuid, mechid, 8 ether, 1 ether, 2, 0);
        uint64 smoothingReadyAt = governance.queueMechanismEmissionSmoothingUpdate(core, netuid, mechid, true);
        vm.roll(scheduleReadyAt > smoothingReadyAt ? scheduleReadyAt : smoothingReadyAt);
        governance.configureMechanismEmissionSchedule(core, netuid, mechid, 8 ether, 1 ether, 2, 0);
        governance.configureMechanismEmissionSmoothing(core, netuid, mechid, true);

        assert(core.mechanismEmissionSmoothDecayEnabled(netuid, mechid));
        assert(core.quoteMechanismEpochEmission(netuid, mechid, 0) == 8 ether);
        assert(core.quoteMechanismEpochEmission(netuid, mechid, 1) == 6 ether);
        assert(core.quoteMechanismEpochEmission(netuid, mechid, 2) == 4 ether);

        uint64 disableReadyAt = governance.queueMechanismEmissionSmoothingUpdate(core, netuid, mechid, false);
        vm.roll(disableReadyAt);
        governance.configureMechanismEmissionSmoothing(core, netuid, mechid, false);
        assert(!core.mechanismEmissionSmoothDecayEnabled(netuid, mechid));
        assert(core.quoteMechanismEpochEmission(netuid, mechid, 1) == 8 ether);
    }

    function testInferenceBatchCommitFinalizeAndLeafSettlement() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        (FeatureActor governance, FeatureActor validator) = _setupGovernanceAndValidator(netuid);
        uint16 mechid = 1;

        uint64 readyAt = governance.queueInferenceBatchPolicyUpdate(settlement, netuid, mechid, true, 5, 8, 0.1 ether);
        vm.roll(readyAt);
        governance.configureInferenceBatchPolicy(settlement, netuid, mechid, true, 5, 8, 0.1 ether);

        bytes32 leafA = keccak256("leaf-a");
        uint64 epoch = core.currentEpoch(netuid);
        validator.commitInferenceBatchRoot{value: 0.2 ether}(settlement, netuid, mechid, epoch, leafA, 1, 1 ether);

        (bytes32 root,, uint256 feeTotal, uint256 bond, address proposer,, uint64 challengeDeadline,, bool finalized) =
            settlement.inferenceBatches(netuid, mechid, epoch);
        assert(root == leafA);
        assert(feeTotal == 1 ether);
        assert(bond == 0.2 ether);
        assert(proposer == address(validator));
        assert(!finalized);

        bool earlyFinalizeReverted = false;
        try settlement.finalizeInferenceBatch(netuid, mechid, epoch) {}
        catch {
            earlyFinalizeReverted = true;
        }
        assert(earlyFinalizeReverted);

        uint256 validatorBalanceBefore = address(validator).balance;
        vm.roll(challengeDeadline + 1);
        settlement.finalizeInferenceBatch(netuid, mechid, epoch);
        assert(settlement.proposerBondRefundOf(netuid, address(validator)) == 0.2 ether);
        validator.claimProposerBondRefund(settlement, netuid, 0.2 ether);
        assert(address(validator).balance == validatorBalanceBefore + 0.2 ether);
        assert(settlement.proposerBondRefundOf(netuid, address(validator)) == 0);

        bytes32[] memory emptyProof = new bytes32[](0);
        settlement.settleFinalizedInferenceLeaf(netuid, mechid, epoch, leafA, 0, emptyProof);
        assert(settlement.settledLeaves(netuid, mechid, leafA));

        bool duplicateSettlementReverted = false;
        try settlement.settleFinalizedInferenceLeaf(netuid, mechid, epoch, leafA, 0, emptyProof) {}
        catch {
            duplicateSettlementReverted = true;
        }
        assert(duplicateSettlementReverted);
    }

    function testInferenceFeePolicyRequiresQueuedGovernanceAction() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        FeatureActor governance = new FeatureActor();
        FeatureActor treasurySink = new FeatureActor();
        FeatureActor minerSink = new FeatureActor();
        core.configureSubnetGovernance(netuid, address(governance), 2);
        uint16 mechid = 16;

        bool immediateConfigureReverted = false;
        try governance.configureInferenceFeePolicy(
            settlement, netuid, mechid, true, 1_200, 3_500, address(treasurySink), address(minerSink)
        ) {} catch {
            immediateConfigureReverted = true;
        }
        assert(immediateConfigureReverted);

        uint64 readyAt = governance.queueInferenceFeePolicyUpdate(
            settlement, netuid, mechid, true, 1_200, 3_500, address(treasurySink), address(minerSink)
        );

        bool prematureConfigureReverted = false;
        try governance.configureInferenceFeePolicy(
            settlement, netuid, mechid, true, 1_200, 3_500, address(treasurySink), address(minerSink)
        ) {} catch {
            prematureConfigureReverted = true;
        }
        assert(prematureConfigureReverted);

        vm.roll(readyAt);
        governance.configureInferenceFeePolicy(
            settlement, netuid, mechid, true, 1_200, 3_500, address(treasurySink), address(minerSink)
        );
        (bool enabled, uint16 protocolFeeBps, uint16 treasuryFeeBps, address treasury, address miner) =
            settlement.feePolicies(netuid, mechid);
        assert(enabled);
        assert(protocolFeeBps == 1_200);
        assert(treasuryFeeBps == 3_500);
        assert(treasury == address(treasurySink));
        assert(miner == address(minerSink));
    }

    function testInferenceBatchPolicyQueueCanBeCancelled() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        FeatureActor governance = new FeatureActor();
        core.configureSubnetGovernance(netuid, address(governance), 2);
        uint16 mechid = 22;

        governance.queueInferenceBatchPolicyUpdate(settlement, netuid, mechid, true, 6, 8, 0.1 ether);
        governance.cancelInferenceBatchPolicyUpdate(settlement, netuid, mechid, true, 6, 8, 0.1 ether);

        bool configureAfterCancelReverted = false;
        try governance.configureInferenceBatchPolicy(settlement, netuid, mechid, true, 6, 8, 0.1 ether) {}
        catch {
            configureAfterCancelReverted = true;
        }
        assert(configureAfterCancelReverted);

        uint64 readyAt = governance.queueInferenceBatchPolicyUpdate(settlement, netuid, mechid, true, 6, 8, 0.1 ether);
        vm.roll(readyAt);
        governance.configureInferenceBatchPolicy(settlement, netuid, mechid, true, 6, 8, 0.1 ether);

        (bool enabled, uint64 challengeWindowBlocks, uint32 maxBatchItems, uint256 minProposerBondWei) =
            settlement.batchPolicies(netuid, mechid);
        assert(enabled);
        assert(challengeWindowBlocks == 6);
        assert(maxBatchItems == 8);
        assert(minProposerBondWei == 0.1 ether);
    }

    function testInferenceBatchPolicyQueueBindsToQueuingGovernanceAfterRotation() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        FeatureActor governanceA = new FeatureActor();
        FeatureActor governanceB = new FeatureActor();
        core.configureSubnetGovernance(netuid, address(governanceA), 2);
        uint16 mechid = 24;

        (bytes32 actionId, uint64 readyAt) =
            governanceA.queueInferenceBatchPolicyUpdateWithAction(settlement, netuid, mechid, true, 6, 8, 0.1 ether);
        (uint64 queuedReadyAt, address queuedBy, bool queued, bool ready, bool expired) =
            settlement.batchPolicyQueueState(netuid, actionId);
        assert(queuedReadyAt == readyAt);
        assert(queuedBy == address(governanceA));
        assert(queued);
        assert(!ready);
        assert(!expired);

        core.configureSubnetGovernance(netuid, address(governanceB), 2);
        vm.roll(readyAt);

        bool executeByNewGovernanceReverted = false;
        try governanceB.configureInferenceBatchPolicy(settlement, netuid, mechid, true, 6, 8, 0.1 ether) {}
        catch {
            executeByNewGovernanceReverted = true;
        }
        assert(executeByNewGovernanceReverted);

        governanceB.cancelInferenceBatchPolicyUpdate(settlement, netuid, mechid, true, 6, 8, 0.1 ether);
        (queuedReadyAt, queuedBy, queued, ready, expired) = settlement.batchPolicyQueueState(netuid, actionId);
        assert(queuedReadyAt == 0);
        assert(queuedBy == address(0));
        assert(!queued);
        assert(!ready);
        assert(!expired);

        uint64 replacementReadyAt =
            governanceB.queueInferenceBatchPolicyUpdate(settlement, netuid, mechid, true, 6, 8, 0.1 ether);
        vm.roll(replacementReadyAt);
        governanceB.configureInferenceBatchPolicy(settlement, netuid, mechid, true, 6, 8, 0.1 ether);
        (bool enabled, uint64 challengeWindowBlocks, uint32 maxBatchItems, uint256 minProposerBondWei) =
            settlement.batchPolicies(netuid, mechid);
        assert(enabled);
        assert(challengeWindowBlocks == 6);
        assert(maxBatchItems == 8);
        assert(minProposerBondWei == 0.1 ether);
    }

    function testInferenceFeePolicyQueueExpiresAndCanBeRequeued() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        FeatureActor governance = new FeatureActor();
        FeatureActor treasurySink = new FeatureActor();
        FeatureActor minerSink = new FeatureActor();
        core.configureSubnetGovernance(netuid, address(governance), 2);
        uint16 mechid = 23;

        (bytes32 actionId, uint64 readyAt) = governance.queueInferenceFeePolicyUpdateWithAction(
            settlement, netuid, mechid, true, 1_200, 3_500, address(treasurySink), address(minerSink)
        );
        vm.roll(uint256(readyAt) + settlement.POLICY_UPDATE_EXPIRY_BLOCKS() + 1);
        (uint64 queuedReadyAt, address queuedBy, bool queued, bool ready, bool expired) =
            settlement.feePolicyQueueState(netuid, actionId);
        assert(queuedReadyAt == readyAt);
        assert(queuedBy == address(governance));
        assert(queued);
        assert(ready);
        assert(expired);

        bool expiredConfigureReverted = false;
        try governance.configureInferenceFeePolicy(
            settlement, netuid, mechid, true, 1_200, 3_500, address(treasurySink), address(minerSink)
        ) {} catch {
            expiredConfigureReverted = true;
        }
        assert(expiredConfigureReverted);
        (queuedReadyAt, queuedBy, queued, ready, expired) = settlement.feePolicyQueueState(netuid, actionId);
        assert(queuedReadyAt == readyAt);
        assert(queuedBy == address(governance));
        assert(queued);
        assert(ready);
        assert(expired);

        uint64 requeueReadyAt = governance.queueInferenceFeePolicyUpdate(
            settlement, netuid, mechid, true, 1_200, 3_500, address(treasurySink), address(minerSink)
        );
        vm.roll(requeueReadyAt);
        governance.configureInferenceFeePolicy(
            settlement, netuid, mechid, true, 1_200, 3_500, address(treasurySink), address(minerSink)
        );

        (bool enabled, uint16 protocolFeeBps, uint16 treasuryFeeBps, address treasury, address miner) =
            settlement.feePolicies(netuid, mechid);
        assert(enabled);
        assert(protocolFeeBps == 1_200);
        assert(treasuryFeeBps == 3_500);
        assert(treasury == address(treasurySink));
        assert(miner == address(minerSink));
    }

    function testInferenceFeePolicyQueueBindsToQueuingGovernanceAfterRotation() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        FeatureActor governanceA = new FeatureActor();
        FeatureActor governanceB = new FeatureActor();
        FeatureActor treasurySink = new FeatureActor();
        FeatureActor minerSink = new FeatureActor();
        core.configureSubnetGovernance(netuid, address(governanceA), 2);
        uint16 mechid = 25;

        (bytes32 actionId, uint64 readyAt) = governanceA.queueInferenceFeePolicyUpdateWithAction(
            settlement, netuid, mechid, true, 1_200, 3_500, address(treasurySink), address(minerSink)
        );
        (uint64 queuedReadyAt, address queuedBy, bool queued, bool ready, bool expired) =
            settlement.feePolicyQueueState(netuid, actionId);
        assert(queuedReadyAt == readyAt);
        assert(queuedBy == address(governanceA));
        assert(queued);
        assert(!ready);
        assert(!expired);

        core.configureSubnetGovernance(netuid, address(governanceB), 2);
        vm.roll(readyAt);

        bool executeByNewGovernanceReverted = false;
        try governanceB.configureInferenceFeePolicy(
            settlement, netuid, mechid, true, 1_200, 3_500, address(treasurySink), address(minerSink)
        ) {} catch {
            executeByNewGovernanceReverted = true;
        }
        assert(executeByNewGovernanceReverted);

        governanceB.cancelInferenceFeePolicyUpdate(
            settlement, netuid, mechid, true, 1_200, 3_500, address(treasurySink), address(minerSink)
        );
        (queuedReadyAt, queuedBy, queued, ready, expired) = settlement.feePolicyQueueState(netuid, actionId);
        assert(queuedReadyAt == 0);
        assert(queuedBy == address(0));
        assert(!queued);
        assert(!ready);
        assert(!expired);

        uint64 replacementReadyAt = governanceB.queueInferenceFeePolicyUpdate(
            settlement, netuid, mechid, true, 1_200, 3_500, address(treasurySink), address(minerSink)
        );
        vm.roll(replacementReadyAt);
        governanceB.configureInferenceFeePolicy(
            settlement, netuid, mechid, true, 1_200, 3_500, address(treasurySink), address(minerSink)
        );

        (bool enabled, uint16 protocolFeeBps, uint16 treasuryFeeBps, address treasury, address miner) =
            settlement.feePolicies(netuid, mechid);
        assert(enabled);
        assert(protocolFeeBps == 1_200);
        assert(treasuryFeeBps == 3_500);
        assert(treasury == address(treasurySink));
        assert(miner == address(minerSink));
    }

    function testInferenceBatchFeeFundingWithdrawAndFinalizeDistribution() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        (FeatureActor governance, FeatureActor validator) = _setupGovernanceAndValidator(netuid);
        FeatureActor payer = new FeatureActor();
        FeatureActor treasurySink = new FeatureActor();
        FeatureActor minerSink = new FeatureActor();
        vm.deal(address(payer), 10 ether);
        uint16 mechid = 17;

        uint64 batchReadyAt =
            governance.queueInferenceBatchPolicyUpdate(settlement, netuid, mechid, true, 4, 8, 0.1 ether);
        uint64 feeReadyAt = governance.queueInferenceFeePolicyUpdate(
            settlement, netuid, mechid, true, 1_500, 4_000, address(treasurySink), address(minerSink)
        );
        vm.roll(batchReadyAt > feeReadyAt ? batchReadyAt : feeReadyAt);
        governance.configureInferenceBatchPolicy(settlement, netuid, mechid, true, 4, 8, 0.1 ether);
        governance.configureInferenceFeePolicy(
            settlement, netuid, mechid, true, 1_500, 4_000, address(treasurySink), address(minerSink)
        );

        uint64 epoch = core.currentEpoch(netuid);
        bytes32 leaf = keccak256("funded-leaf");
        validator.commitInferenceBatchRoot{value: 0.2 ether}(settlement, netuid, mechid, epoch, leaf, 1, 1 ether);

        payer.fundInferenceBatchFees{value: 0.8 ether}(settlement, netuid, mechid, epoch);
        assert(settlement.batchFeeFunded(netuid, mechid, epoch) == 0.8 ether);
        assert(settlement.batchFeeEscrowOf(netuid, mechid, epoch, address(payer)) == 0.8 ether);

        payer.withdrawInferenceBatchFees(settlement, netuid, mechid, epoch, 0.2 ether);
        assert(settlement.batchFeeFunded(netuid, mechid, epoch) == 0.6 ether);
        assert(settlement.batchFeeEscrowOf(netuid, mechid, epoch, address(payer)) == 0.6 ether);

        payer.fundInferenceBatchFees{value: 0.4 ether}(settlement, netuid, mechid, epoch);
        assert(settlement.batchFeeFunded(netuid, mechid, epoch) == 1 ether);
        assert(settlement.batchFeeEscrowOf(netuid, mechid, epoch, address(payer)) == 1 ether);

        (,,,,,, uint64 challengeDeadline,,) = settlement.inferenceBatches(netuid, mechid, epoch);
        vm.roll(challengeDeadline + 1);
        settlement.finalizeInferenceBatch(netuid, mechid, epoch);

        uint256 protocolAmount = (1 ether * 1_500) / 10_000;
        uint256 treasuryAmount = (protocolAmount * 4_000) / 10_000;
        uint256 minerAmount = protocolAmount - treasuryAmount;
        uint256 proposerAmount = 1 ether - protocolAmount;

        assert(settlement.batchFeeFunded(netuid, mechid, epoch) == 0);
        assert(settlement.inferenceFeeClaimOf(netuid, address(validator)) == proposerAmount);
        assert(settlement.inferenceFeeClaimOf(netuid, address(treasurySink)) == treasuryAmount);
        assert(settlement.inferenceFeeClaimOf(netuid, address(minerSink)) == minerAmount);

        uint256 proposerBalanceBefore = address(validator).balance;
        uint256 treasuryBalanceBefore = address(treasurySink).balance;
        uint256 minerBalanceBefore = address(minerSink).balance;

        validator.claimInferenceFee(settlement, netuid, proposerAmount);
        treasurySink.claimInferenceFee(settlement, netuid, treasuryAmount);
        minerSink.claimInferenceFee(settlement, netuid, minerAmount);

        assert(address(validator).balance == proposerBalanceBefore + proposerAmount);
        assert(address(treasurySink).balance == treasuryBalanceBefore + treasuryAmount);
        assert(address(minerSink).balance == minerBalanceBefore + minerAmount);
        assert(settlement.inferenceFeeClaimOf(netuid, address(validator)) == 0);
        assert(settlement.inferenceFeeClaimOf(netuid, address(treasurySink)) == 0);
        assert(settlement.inferenceFeeClaimOf(netuid, address(minerSink)) == 0);
    }

    function testInferenceBatchFeeFundingCannotExceedDeclaredTotal() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        (FeatureActor governance, FeatureActor validator) = _setupGovernanceAndValidator(netuid);
        FeatureActor payer = new FeatureActor();
        vm.deal(address(payer), 10 ether);
        uint16 mechid = 18;

        uint64 readyAt = governance.queueInferenceBatchPolicyUpdate(settlement, netuid, mechid, true, 4, 8, 0.1 ether);
        vm.roll(readyAt);
        governance.configureInferenceBatchPolicy(settlement, netuid, mechid, true, 4, 8, 0.1 ether);

        uint64 epoch = core.currentEpoch(netuid);
        validator.commitInferenceBatchRoot{value: 0.2 ether}(
            settlement, netuid, mechid, epoch, keccak256("cap"), 1, 1 ether
        );
        payer.fundInferenceBatchFees{value: 0.8 ether}(settlement, netuid, mechid, epoch);

        bool overflowFundingReverted = false;
        try payer.fundInferenceBatchFees{value: 0.3 ether}(settlement, netuid, mechid, epoch) {}
        catch {
            overflowFundingReverted = true;
        }
        assert(overflowFundingReverted);
    }

    function testInferenceFeePolicyIsSnapshottedAtCommit() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        (FeatureActor governance, FeatureActor validator) = _setupGovernanceAndValidator(netuid);
        FeatureActor payer = new FeatureActor();
        FeatureActor treasurySinkA = new FeatureActor();
        FeatureActor minerSinkA = new FeatureActor();
        FeatureActor treasurySinkB = new FeatureActor();
        FeatureActor minerSinkB = new FeatureActor();
        vm.deal(address(payer), 10 ether);
        uint16 mechid = 21;

        uint64 batchReadyAt =
            governance.queueInferenceBatchPolicyUpdate(settlement, netuid, mechid, true, 12, 8, 0.1 ether);
        uint64 feeReadyAt = governance.queueInferenceFeePolicyUpdate(
            settlement, netuid, mechid, true, 1_000, 5_000, address(treasurySinkA), address(minerSinkA)
        );
        vm.roll(batchReadyAt > feeReadyAt ? batchReadyAt : feeReadyAt);
        governance.configureInferenceBatchPolicy(settlement, netuid, mechid, true, 12, 8, 0.1 ether);
        governance.configureInferenceFeePolicy(
            settlement, netuid, mechid, true, 1_000, 5_000, address(treasurySinkA), address(minerSinkA)
        );

        uint64 epoch = core.currentEpoch(netuid);
        validator.commitInferenceBatchRoot{value: 0.2 ether}(
            settlement, netuid, mechid, epoch, keccak256("snapshotted-policy"), 1, 1 ether
        );

        uint64 feeUpdateReadyAt = governance.queueInferenceFeePolicyUpdate(
            settlement, netuid, mechid, true, 2_500, 8_000, address(treasurySinkB), address(minerSinkB)
        );
        vm.roll(feeUpdateReadyAt);
        governance.configureInferenceFeePolicy(
            settlement, netuid, mechid, true, 2_500, 8_000, address(treasurySinkB), address(minerSinkB)
        );

        payer.fundInferenceBatchFees{value: 1 ether}(settlement, netuid, mechid, epoch);

        (,,,,,, uint64 challengeDeadline,,) = settlement.inferenceBatches(netuid, mechid, epoch);
        vm.roll(challengeDeadline + 1);
        settlement.finalizeInferenceBatch(netuid, mechid, epoch);

        uint256 expectedProtocol = (1 ether * 1_000) / 10_000;
        uint256 expectedTreasury = (expectedProtocol * 5_000) / 10_000;
        uint256 expectedMiner = expectedProtocol - expectedTreasury;
        uint256 expectedProposer = 1 ether - expectedProtocol;

        assert(settlement.inferenceFeeClaimOf(netuid, address(validator)) == expectedProposer);
        assert(settlement.inferenceFeeClaimOf(netuid, address(treasurySinkA)) == expectedTreasury);
        assert(settlement.inferenceFeeClaimOf(netuid, address(minerSinkA)) == expectedMiner);
        assert(settlement.inferenceFeeClaimOf(netuid, address(treasurySinkB)) == 0);
        assert(settlement.inferenceFeeClaimOf(netuid, address(minerSinkB)) == 0);
    }

    function testInferenceFeeWithdrawBlockedAfterFinalize() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        (FeatureActor governance, FeatureActor validator) = _setupGovernanceAndValidator(netuid);
        FeatureActor payer = new FeatureActor();
        vm.deal(address(payer), 10 ether);
        uint16 mechid = 19;

        uint64 readyAt = governance.queueInferenceBatchPolicyUpdate(settlement, netuid, mechid, true, 4, 8, 0.1 ether);
        vm.roll(readyAt);
        governance.configureInferenceBatchPolicy(settlement, netuid, mechid, true, 4, 8, 0.1 ether);

        uint64 epoch = core.currentEpoch(netuid);
        validator.commitInferenceBatchRoot{value: 0.2 ether}(
            settlement, netuid, mechid, epoch, keccak256("withdraw-after-finalize"), 1, 1 ether
        );
        payer.fundInferenceBatchFees{value: 0.5 ether}(settlement, netuid, mechid, epoch);

        (,,,,,, uint64 challengeDeadline,,) = settlement.inferenceBatches(netuid, mechid, epoch);
        vm.roll(challengeDeadline + 1);
        settlement.finalizeInferenceBatch(netuid, mechid, epoch);

        bool withdrawReverted = false;
        try payer.withdrawInferenceBatchFees(settlement, netuid, mechid, epoch, 0.1 ether) {}
        catch {
            withdrawReverted = true;
        }
        assert(withdrawReverted);
    }

    function testInferenceBatchReplayChallengeSlashesBond() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        (FeatureActor governance, FeatureActor validator) = _setupGovernanceAndValidator(netuid);
        uint16 mechid = 2;

        uint64 readyAt = governance.queueInferenceBatchPolicyUpdate(settlement, netuid, mechid, true, 8, 8, 0.1 ether);
        vm.roll(readyAt);
        governance.configureInferenceBatchPolicy(settlement, netuid, mechid, true, 8, 8, 0.1 ether);

        bytes32 leaf = keccak256("replay-leaf");
        uint64 firstEpoch = core.currentEpoch(netuid);
        validator.commitInferenceBatchRoot{value: 0.2 ether}(settlement, netuid, mechid, firstEpoch, leaf, 1, 1 ether);

        (,,,,,, uint64 firstDeadline,,) = settlement.inferenceBatches(netuid, mechid, firstEpoch);
        vm.roll(firstDeadline + 1);
        settlement.finalizeInferenceBatch(netuid, mechid, firstEpoch);
        bytes32[] memory emptyProof = new bytes32[](0);
        settlement.settleFinalizedInferenceLeaf(netuid, mechid, firstEpoch, leaf, 0, emptyProof);

        vm.roll(16);
        uint64 secondEpoch = core.currentEpoch(netuid);
        validator.commitInferenceBatchRoot{value: 0.2 ether}(settlement, netuid, mechid, secondEpoch, leaf, 1, 2 ether);
        settlement.challengeInferenceLeafReplay(
            netuid, mechid, secondEpoch, leaf, 0, emptyProof, firstEpoch, 0, emptyProof
        );

        (,,,,,,, bool challenged, bool finalized) = settlement.inferenceBatches(netuid, mechid, secondEpoch);
        assert(challenged);
        assert(!finalized);
        assert(settlement.challengeRewardOf(netuid, address(this)) > 0);

        bool finalizeReverted = false;
        try settlement.finalizeInferenceBatch(netuid, mechid, secondEpoch) {}
        catch {
            finalizeReverted = true;
        }
        assert(finalizeReverted);
    }


    function testInferenceReplayChallengeRequiresPriorSettledLeaf() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        (FeatureActor governance, FeatureActor validator) = _setupGovernanceAndValidator(netuid);
        uint16 mechid = 22;

        uint64 readyAt = governance.queueInferenceBatchPolicyUpdate(settlement, netuid, mechid, true, 8, 8, 0.1 ether);
        vm.roll(readyAt);
        governance.configureInferenceBatchPolicy(settlement, netuid, mechid, true, 8, 8, 0.1 ether);

        bytes32 leaf = keccak256("unsettled-prior-leaf");
        uint64 firstEpoch = core.currentEpoch(netuid);
        validator.commitInferenceBatchRoot{value: 0.2 ether}(settlement, netuid, mechid, firstEpoch, leaf, 1, 1 ether);

        (,,,,,, uint64 firstDeadline,,) = settlement.inferenceBatches(netuid, mechid, firstEpoch);
        vm.roll(firstDeadline + 1);
        settlement.finalizeInferenceBatch(netuid, mechid, firstEpoch);

        vm.roll(16);
        uint64 secondEpoch = core.currentEpoch(netuid);
        validator.commitInferenceBatchRoot{value: 0.2 ether}(settlement, netuid, mechid, secondEpoch, leaf, 1, 2 ether);

        bytes32[] memory emptyProof = new bytes32[](0);
        vm.expectRevert(PulseTensorInferenceSettlement.LeafNotSettled.selector);
        settlement.challengeInferenceLeafReplay(
            netuid, mechid, secondEpoch, leaf, 0, emptyProof, firstEpoch, 0, emptyProof
        );
    }

    function testInferenceReplayChallengeRequiresFinalizedPriorBatch() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        (FeatureActor governance, FeatureActor validator) = _setupGovernanceAndValidator(netuid);
        uint16 mechid = 11;

        uint64 readyAt = governance.queueInferenceBatchPolicyUpdate(settlement, netuid, mechid, true, 8, 8, 0.1 ether);
        vm.roll(readyAt);
        governance.configureInferenceBatchPolicy(settlement, netuid, mechid, true, 8, 8, 0.1 ether);

        bytes32 leaf = keccak256("unfinalized-prior-replay");
        uint64 firstEpoch = core.currentEpoch(netuid);
        validator.commitInferenceBatchRoot{value: 0.2 ether}(settlement, netuid, mechid, firstEpoch, leaf, 1, 1 ether);

        vm.roll(16);
        uint64 secondEpoch = core.currentEpoch(netuid);
        validator.commitInferenceBatchRoot{value: 0.2 ether}(settlement, netuid, mechid, secondEpoch, leaf, 1, 2 ether);

        bytes32[] memory emptyProof = new bytes32[](0);
        bool replayChallengeReverted = false;
        try settlement.challengeInferenceLeafReplay(
            netuid, mechid, secondEpoch, leaf, 0, emptyProof, firstEpoch, 0, emptyProof
        ) {} catch {
            replayChallengeReverted = true;
        }
        assert(replayChallengeReverted);
    }

    function testInferenceFinalizeCreditsRefundEvenIfProposerRejectsEth() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        FeatureActor governance = new FeatureActor();
        RevertingFeatureActor validator = new RevertingFeatureActor();
        core.configureSubnetGovernance(netuid, address(governance), 2);

        vm.deal(address(validator), 10 ether);
        validator.addStake{value: 2 ether}(core, netuid);
        validator.registerValidator(core, netuid);

        uint16 mechid = 12;
        uint64 readyAt = governance.queueInferenceBatchPolicyUpdate(settlement, netuid, mechid, true, 5, 8, 0.1 ether);
        vm.roll(readyAt);
        governance.configureInferenceBatchPolicy(settlement, netuid, mechid, true, 5, 8, 0.1 ether);

        bytes32 leaf = keccak256("reverting-proposer");
        uint64 epoch = core.currentEpoch(netuid);
        validator.commitInferenceBatchRoot{value: 0.2 ether}(settlement, netuid, mechid, epoch, leaf, 1, 1 ether);

        (,,,,,, uint64 challengeDeadline,,) = settlement.inferenceBatches(netuid, mechid, epoch);
        vm.roll(challengeDeadline + 1);
        settlement.finalizeInferenceBatch(netuid, mechid, epoch);
        assert(settlement.proposerBondRefundOf(netuid, address(validator)) == 0.2 ether);
    }

    function testInferenceBatchDuplicateLeafChallengeSlashesBond() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        (FeatureActor governance, FeatureActor validator) = _setupGovernanceAndValidator(netuid);
        uint16 mechid = 7;

        uint64 readyAt = governance.queueInferenceBatchPolicyUpdate(settlement, netuid, mechid, true, 6, 8, 0.1 ether);
        vm.roll(readyAt);
        governance.configureInferenceBatchPolicy(settlement, netuid, mechid, true, 6, 8, 0.1 ether);

        bytes32 leaf = keccak256("duplicate-leaf");
        bytes32 root = _hashPair(leaf, leaf);
        uint64 epoch = core.currentEpoch(netuid);
        validator.commitInferenceBatchRoot{value: 0.2 ether}(settlement, netuid, mechid, epoch, root, 2, 3 ether);

        bytes32[] memory proofIndex0 = new bytes32[](1);
        proofIndex0[0] = leaf;
        bytes32[] memory proofIndex1 = new bytes32[](1);
        proofIndex1[0] = leaf;

        settlement.challengeInferenceLeafDuplicate(netuid, mechid, epoch, leaf, 0, proofIndex0, 1, proofIndex1);
        (,,,,,,, bool challenged, bool finalized) = settlement.inferenceBatches(netuid, mechid, epoch);
        assert(challenged);
        assert(!finalized);
        assert(settlement.challengeRewardOf(netuid, address(this)) > 0);
    }

    function testInferenceSelfChallengeGetsNoBounty() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        (FeatureActor governance, FeatureActor validator) = _setupGovernanceAndValidator(netuid);
        uint16 mechid = 20;

        uint64 readyAt = governance.queueInferenceBatchPolicyUpdate(settlement, netuid, mechid, true, 6, 8, 0.1 ether);
        vm.roll(readyAt);
        governance.configureInferenceBatchPolicy(settlement, netuid, mechid, true, 6, 8, 0.1 ether);

        bytes32 leaf = keccak256("self-challenge");
        bytes32 root = _hashPair(leaf, leaf);
        uint64 epoch = core.currentEpoch(netuid);
        validator.commitInferenceBatchRoot{value: 0.2 ether}(settlement, netuid, mechid, epoch, root, 2, 1 ether);

        bytes32[] memory proofIndex0 = new bytes32[](1);
        proofIndex0[0] = leaf;
        bytes32[] memory proofIndex1 = new bytes32[](1);
        proofIndex1[0] = leaf;

        validator.challengeInferenceLeafDuplicate(
            settlement, netuid, mechid, epoch, leaf, 0, proofIndex0, 1, proofIndex1
        );
        assert(settlement.challengeRewardOf(netuid, address(validator)) == 0);
    }

    function testInferenceBatchPolicyRequiresQueuedGovernanceAction() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        FeatureActor governance = new FeatureActor();
        core.configureSubnetGovernance(netuid, address(governance), 2);
        uint16 mechid = 5;

        bool immediateConfigureReverted = false;
        try governance.configureInferenceBatchPolicy(settlement, netuid, mechid, true, 4, 4, 0.1 ether) {}
        catch {
            immediateConfigureReverted = true;
        }
        assert(immediateConfigureReverted);

        uint64 readyAt = governance.queueInferenceBatchPolicyUpdate(settlement, netuid, mechid, true, 4, 4, 0.1 ether);
        bool prematureConfigureReverted = false;
        try governance.configureInferenceBatchPolicy(settlement, netuid, mechid, true, 4, 4, 0.1 ether) {}
        catch {
            prematureConfigureReverted = true;
        }
        assert(prematureConfigureReverted);

        vm.roll(readyAt);
        governance.configureInferenceBatchPolicy(settlement, netuid, mechid, true, 4, 4, 0.1 ether);
        (bool enabled, uint64 challengeWindowBlocks, uint32 maxBatchItems, uint256 minProposerBondWei) =
            settlement.batchPolicies(netuid, mechid);
        assert(enabled);
        assert(challengeWindowBlocks == 4);
        assert(maxBatchItems == 4);
        assert(minProposerBondWei == 0.1 ether);
    }

    function testInferenceBatchPolicyBoundaryValuesAndDisabledMode() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        (FeatureActor governance, FeatureActor validator) = _setupGovernanceAndValidator(netuid);

        uint16 mechidMin = 41;
        uint64 readyAt = governance.queueInferenceBatchPolicyUpdate(
            settlement,
            netuid,
            mechidMin,
            true,
            settlement.MIN_CHALLENGE_WINDOW_BLOCKS(),
            1,
            1
        );
        vm.roll(readyAt);
        governance.configureInferenceBatchPolicy(
            settlement,
            netuid,
            mechidMin,
            true,
            settlement.MIN_CHALLENGE_WINDOW_BLOCKS(),
            1,
            1
        );
        (bool minEnabled, uint64 minWindow, uint32 minItems, uint256 minBond) = settlement.batchPolicies(netuid, mechidMin);
        assert(minEnabled);
        assert(minWindow == settlement.MIN_CHALLENGE_WINDOW_BLOCKS());
        assert(minItems == 1);
        assert(minBond == 1);

        uint16 mechidMax = 42;
        readyAt = governance.queueInferenceBatchPolicyUpdate(
            settlement,
            netuid,
            mechidMax,
            true,
            settlement.MAX_CHALLENGE_WINDOW_BLOCKS(),
            settlement.MAX_BATCH_ITEMS(),
            1
        );
        vm.roll(readyAt);
        governance.configureInferenceBatchPolicy(
            settlement,
            netuid,
            mechidMax,
            true,
            settlement.MAX_CHALLENGE_WINDOW_BLOCKS(),
            settlement.MAX_BATCH_ITEMS(),
            1
        );
        (bool maxEnabled, uint64 maxWindow, uint32 maxItems, uint256 maxBond) = settlement.batchPolicies(netuid, mechidMax);
        assert(maxEnabled);
        assert(maxWindow == settlement.MAX_CHALLENGE_WINDOW_BLOCKS());
        assert(maxItems == settlement.MAX_BATCH_ITEMS());
        assert(maxBond == 1);

        uint16 mechidDisabled = 43;
        readyAt = governance.queueInferenceBatchPolicyUpdate(settlement, netuid, mechidDisabled, false, 0, 0, 0);
        vm.roll(readyAt);
        governance.configureInferenceBatchPolicy(settlement, netuid, mechidDisabled, false, 0, 0, 0);
        (bool disabledEnabled, uint64 disabledWindow, uint32 disabledItems, uint256 disabledBond) =
            settlement.batchPolicies(netuid, mechidDisabled);
        assert(!disabledEnabled);
        assert(disabledWindow == 0);
        assert(disabledItems == 0);
        assert(disabledBond == 0);

        uint64 epoch = core.currentEpoch(netuid);
        bool disabledCommitReverted = false;
        try validator.commitInferenceBatchRoot{value: 0.2 ether}(
            settlement, netuid, mechidDisabled, epoch, keccak256("disabled-policy"), 1, 1 ether
        ) {} catch {
            disabledCommitReverted = true;
        }
        assert(disabledCommitReverted);
    }

    function testInferenceBatchPolicyBoundaryValueRejections() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        FeatureActor governance = new FeatureActor();
        core.configureSubnetGovernance(netuid, address(governance), 2);
        uint16 mechid = 44;

        bool reverted = false;
        try governance.queueInferenceBatchPolicyUpdate(settlement, netuid, mechid, true, 0, 8, 1) {}
        catch {
            reverted = true;
        }
        assert(reverted);

        reverted = false;
        try governance.queueInferenceBatchPolicyUpdate(
            settlement, netuid, mechid, true, settlement.MAX_CHALLENGE_WINDOW_BLOCKS() + 1, 8, 1
        ) {} catch {
            reverted = true;
        }
        assert(reverted);

        reverted = false;
        try governance.queueInferenceBatchPolicyUpdate(
            settlement, netuid, mechid, true, settlement.MIN_CHALLENGE_WINDOW_BLOCKS(), 0, 1
        ) {} catch {
            reverted = true;
        }
        assert(reverted);

        reverted = false;
        try governance.queueInferenceBatchPolicyUpdate(
            settlement, netuid, mechid, true, settlement.MIN_CHALLENGE_WINDOW_BLOCKS(), settlement.MAX_BATCH_ITEMS() + 1, 1
        ) {} catch {
            reverted = true;
        }
        assert(reverted);

        reverted = false;
        try governance.queueInferenceBatchPolicyUpdate(
            settlement, netuid, mechid, true, settlement.MIN_CHALLENGE_WINDOW_BLOCKS(), 8, 0
        ) {} catch {
            reverted = true;
        }
        assert(reverted);

        reverted = false;
        try governance.queueInferenceBatchPolicyUpdate(settlement, netuid, mechid, false, 1, 0, 0) {}
        catch {
            reverted = true;
        }
        assert(reverted);
    }

    function testInferenceFeePolicyBoundaryValuesAndRejections() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        FeatureActor governance = new FeatureActor();
        FeatureActor treasurySink = new FeatureActor();
        FeatureActor minerSink = new FeatureActor();
        core.configureSubnetGovernance(netuid, address(governance), 2);

        uint16 mechidMax = 45;
        uint64 readyAt = governance.queueInferenceFeePolicyUpdate(
            settlement,
            netuid,
            mechidMax,
            true,
            settlement.MAX_PROTOCOL_FEE_BPS(),
            settlement.BPS_DENOMINATOR(),
            address(treasurySink),
            address(minerSink)
        );
        vm.roll(readyAt);
        governance.configureInferenceFeePolicy(
            settlement,
            netuid,
            mechidMax,
            true,
            settlement.MAX_PROTOCOL_FEE_BPS(),
            settlement.BPS_DENOMINATOR(),
            address(treasurySink),
            address(minerSink)
        );
        (bool maxEnabled, uint16 maxProtocolFeeBps, uint16 maxTreasuryFeeBps, address treasury, address miner) =
            settlement.feePolicies(netuid, mechidMax);
        assert(maxEnabled);
        assert(maxProtocolFeeBps == settlement.MAX_PROTOCOL_FEE_BPS());
        assert(maxTreasuryFeeBps == settlement.BPS_DENOMINATOR());
        assert(treasury == address(treasurySink));
        assert(miner == address(minerSink));

        uint16 mechidZeroProtocol = 46;
        readyAt =
            governance.queueInferenceFeePolicyUpdate(settlement, netuid, mechidZeroProtocol, true, 0, 0, address(0), address(0));
        vm.roll(readyAt);
        governance.configureInferenceFeePolicy(
            settlement, netuid, mechidZeroProtocol, true, 0, 0, address(0), address(0)
        );
        (bool zeroEnabled, uint16 zeroProtocolFeeBps, uint16 zeroTreasuryFeeBps, address zeroTreasury, address zeroMiner) =
            settlement.feePolicies(netuid, mechidZeroProtocol);
        assert(zeroEnabled);
        assert(zeroProtocolFeeBps == 0);
        assert(zeroTreasuryFeeBps == 0);
        assert(zeroTreasury == address(0));
        assert(zeroMiner == address(0));

        uint16 mechidRevert = 47;
        bool reverted = false;
        try governance.queueInferenceFeePolicyUpdate(
            settlement,
            netuid,
            mechidRevert,
            true,
            settlement.MAX_PROTOCOL_FEE_BPS() + 1,
            0,
            address(treasurySink),
            address(minerSink)
        ) {} catch {
            reverted = true;
        }
        assert(reverted);

        reverted = false;
        try governance.queueInferenceFeePolicyUpdate(
            settlement,
            netuid,
            mechidRevert,
            true,
            settlement.MAX_PROTOCOL_FEE_BPS(),
            settlement.BPS_DENOMINATOR() + 1,
            address(treasurySink),
            address(minerSink)
        ) {} catch {
            reverted = true;
        }
        assert(reverted);

        reverted = false;
        try governance.queueInferenceFeePolicyUpdate(
            settlement, netuid, mechidRevert, true, 0, 1, address(0), address(0)
        ) {} catch {
            reverted = true;
        }
        assert(reverted);

        reverted = false;
        try governance.queueInferenceFeePolicyUpdate(
            settlement, netuid, mechidRevert, true, 100, 0, address(0), address(minerSink)
        ) {} catch {
            reverted = true;
        }
        assert(reverted);

        reverted = false;
        try governance.queueInferenceFeePolicyUpdate(
            settlement, netuid, mechidRevert, false, 1, 0, address(0), address(0)
        ) {} catch {
            reverted = true;
        }
        assert(reverted);
    }

    function testInferenceBatchItemCountBoundaryValues() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        (FeatureActor governance, FeatureActor validator) = _setupGovernanceAndValidator(netuid);
        uint16 mechid = 48;

        uint64 readyAt = governance.queueInferenceBatchPolicyUpdate(settlement, netuid, mechid, true, 5, 2, 0.1 ether);
        vm.roll(readyAt);
        governance.configureInferenceBatchPolicy(settlement, netuid, mechid, true, 5, 2, 0.1 ether);

        uint64 epoch = core.currentEpoch(netuid);
        bool zeroCountReverted = false;
        try validator.commitInferenceBatchRoot{value: 0.2 ether}(
            settlement, netuid, mechid, epoch, keccak256("item-count-zero"), 0, 1 ether
        ) {} catch {
            zeroCountReverted = true;
        }
        assert(zeroCountReverted);

        bool overMaxReverted = false;
        try validator.commitInferenceBatchRoot{value: 0.2 ether}(
            settlement, netuid, mechid, epoch, keccak256("item-count-over-max"), 3, 1 ether
        ) {} catch {
            overMaxReverted = true;
        }
        assert(overMaxReverted);

        validator.commitInferenceBatchRoot{value: 0.2 ether}(
            settlement, netuid, mechid, epoch, keccak256("item-count-max"), 2, 1 ether
        );
        (, uint32 itemCount,,,,,,,) = settlement.inferenceBatches(netuid, mechid, epoch);
        assert(itemCount == 2);
    }

    function testInferenceBatchCommitRequiresCurrentEpoch() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        (FeatureActor governance, FeatureActor validator) = _setupGovernanceAndValidator(netuid);
        uint16 mechid = 8;
        uint64 readyAt = governance.queueInferenceBatchPolicyUpdate(settlement, netuid, mechid, true, 5, 8, 0.1 ether);
        vm.roll(readyAt);
        governance.configureInferenceBatchPolicy(settlement, netuid, mechid, true, 5, 8, 0.1 ether);

        uint64 currentEpoch = core.currentEpoch(netuid);
        bool futureEpochCommitReverted = false;
        try validator.commitInferenceBatchRoot{value: 0.2 ether}(
            settlement, netuid, mechid, currentEpoch + 1, keccak256("future"), 1, 1 ether
        ) {} catch {
            futureEpochCommitReverted = true;
        }
        assert(futureEpochCommitReverted);
    }

    function testInferenceSettlementRejectsOutOfRangeLeafIndex() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        (FeatureActor governance, FeatureActor validator) = _setupGovernanceAndValidator(netuid);
        uint16 mechid = 9;
        uint64 readyAt = governance.queueInferenceBatchPolicyUpdate(settlement, netuid, mechid, true, 5, 8, 0.1 ether);
        vm.roll(readyAt);
        governance.configureInferenceBatchPolicy(settlement, netuid, mechid, true, 5, 8, 0.1 ether);

        bytes32 leaf = keccak256("leaf-index");
        uint64 epoch = core.currentEpoch(netuid);
        validator.commitInferenceBatchRoot{value: 0.2 ether}(settlement, netuid, mechid, epoch, leaf, 1, 1 ether);
        (,,,,,, uint64 challengeDeadline,,) = settlement.inferenceBatches(netuid, mechid, epoch);
        vm.roll(challengeDeadline + 1);
        settlement.finalizeInferenceBatch(netuid, mechid, epoch);

        bytes32[] memory emptyProof = new bytes32[](0);
        bool outOfRangeReverted = false;
        try settlement.settleFinalizedInferenceLeaf(netuid, mechid, epoch, leaf, 1, emptyProof) {}
        catch {
            outOfRangeReverted = true;
        }
        assert(outOfRangeReverted);
    }

    function testInferenceDuplicateChallengeRejectsOutOfRangeIndex() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        (FeatureActor governance, FeatureActor validator) = _setupGovernanceAndValidator(netuid);
        uint16 mechid = 10;
        uint64 readyAt = governance.queueInferenceBatchPolicyUpdate(settlement, netuid, mechid, true, 5, 8, 0.1 ether);
        vm.roll(readyAt);
        governance.configureInferenceBatchPolicy(settlement, netuid, mechid, true, 5, 8, 0.1 ether);

        bytes32 leaf = keccak256("duplicate-index");
        bytes32 root = _hashPair(leaf, leaf);
        uint64 epoch = core.currentEpoch(netuid);
        validator.commitInferenceBatchRoot{value: 0.2 ether}(settlement, netuid, mechid, epoch, root, 2, 1 ether);

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = leaf;
        bool outOfRangeReverted = false;
        try settlement.challengeInferenceLeafDuplicate(netuid, mechid, epoch, leaf, 0, proof, 2, proof) {}
        catch {
            outOfRangeReverted = true;
        }
        assert(outOfRangeReverted);
    }

    function testInferenceDuplicateChallengeRejectsEmptyProofForgery() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        (FeatureActor governance, FeatureActor validator) = _setupGovernanceAndValidator(netuid);
        uint16 mechid = 13;
        uint64 readyAt = governance.queueInferenceBatchPolicyUpdate(settlement, netuid, mechid, true, 5, 8, 0.1 ether);
        vm.roll(readyAt);
        governance.configureInferenceBatchPolicy(settlement, netuid, mechid, true, 5, 8, 0.1 ether);

        bytes32 forgedRoot = keccak256("forged-root");
        uint64 epoch = core.currentEpoch(netuid);
        validator.commitInferenceBatchRoot{value: 0.2 ether}(settlement, netuid, mechid, epoch, forgedRoot, 2, 1 ether);

        bytes32[] memory emptyProof = new bytes32[](0);
        bool forgedChallengeReverted = false;
        try settlement.challengeInferenceLeafDuplicate(netuid, mechid, epoch, forgedRoot, 0, emptyProof, 1, emptyProof)
        {} catch {
            forgedChallengeReverted = true;
        }
        assert(forgedChallengeReverted);
    }

    function testInferenceSettlementRejectsEmptyProofForgeryForNonZeroIndex() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        (FeatureActor governance, FeatureActor validator) = _setupGovernanceAndValidator(netuid);
        uint16 mechid = 14;
        uint64 readyAt = governance.queueInferenceBatchPolicyUpdate(settlement, netuid, mechid, true, 5, 8, 0.1 ether);
        vm.roll(readyAt);
        governance.configureInferenceBatchPolicy(settlement, netuid, mechid, true, 5, 8, 0.1 ether);

        bytes32 forgedRoot = keccak256("forged-settlement-root");
        uint64 epoch = core.currentEpoch(netuid);
        validator.commitInferenceBatchRoot{value: 0.2 ether}(settlement, netuid, mechid, epoch, forgedRoot, 2, 1 ether);
        (,,,,,, uint64 challengeDeadline,,) = settlement.inferenceBatches(netuid, mechid, epoch);
        vm.roll(challengeDeadline + 1);
        settlement.finalizeInferenceBatch(netuid, mechid, epoch);

        bytes32[] memory emptyProof = new bytes32[](0);
        bool forgedSettlementReverted = false;
        try settlement.settleFinalizedInferenceLeaf(netuid, mechid, epoch, forgedRoot, 1, emptyProof) {}
        catch {
            forgedSettlementReverted = true;
        }
        assert(forgedSettlementReverted);
    }

    function testInferenceSettlementRejectsEmptyProofForgeryForIndexZero() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        (FeatureActor governance, FeatureActor validator) = _setupGovernanceAndValidator(netuid);
        uint16 mechid = 15;
        uint64 readyAt = governance.queueInferenceBatchPolicyUpdate(settlement, netuid, mechid, true, 5, 8, 0.1 ether);
        vm.roll(readyAt);
        governance.configureInferenceBatchPolicy(settlement, netuid, mechid, true, 5, 8, 0.1 ether);

        bytes32 forgedRoot = keccak256("forged-settlement-root-index-zero");
        uint64 epoch = core.currentEpoch(netuid);
        validator.commitInferenceBatchRoot{value: 0.2 ether}(settlement, netuid, mechid, epoch, forgedRoot, 2, 1 ether);
        (,,,,,, uint64 challengeDeadline,,) = settlement.inferenceBatches(netuid, mechid, epoch);
        vm.roll(challengeDeadline + 1);
        settlement.finalizeInferenceBatch(netuid, mechid, epoch);

        bytes32[] memory emptyProof = new bytes32[](0);
        bool forgedSettlementReverted = false;
        try settlement.settleFinalizedInferenceLeaf(netuid, mechid, epoch, forgedRoot, 0, emptyProof) {}
        catch {
            forgedSettlementReverted = true;
        }
        assert(forgedSettlementReverted);
    }
}

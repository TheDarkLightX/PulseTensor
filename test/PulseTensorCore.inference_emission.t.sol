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

    function configureInferenceBatchPolicy(
        PulseTensorInferenceSettlement settlement,
        uint16 netuid,
        uint16 mechid,
        bool enabled,
        uint64 challengeWindowBlocks,
        uint32 maxBatchItems,
        uint256 minProposerBondWei
    ) external {
        settlement.configureBatchPolicy(netuid, mechid, enabled, challengeWindowBlocks, maxBatchItems, minProposerBondWei);
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

    function claimChallengeReward(PulseTensorInferenceSettlement settlement, uint16 netuid, uint256 amount) external {
        settlement.claimChallengeReward(netuid, amount);
    }

    function claimProposerBondRefund(PulseTensorInferenceSettlement settlement, uint16 netuid, uint256 amount) external {
        settlement.claimProposerBondRefund(netuid, amount);
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

        uint64 readyAt =
            governance.queueInferenceBatchPolicyUpdate(settlement, netuid, mechid, true, 5, 8, 0.1 ether);
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

    function testInferenceBatchReplayChallengeSlashesBond() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        (FeatureActor governance, FeatureActor validator) = _setupGovernanceAndValidator(netuid);
        uint16 mechid = 2;

        uint64 readyAt =
            governance.queueInferenceBatchPolicyUpdate(settlement, netuid, mechid, true, 8, 8, 0.1 ether);
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
            netuid,
            mechid,
            secondEpoch,
            leaf,
            0,
            emptyProof,
            firstEpoch,
            0,
            emptyProof
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

    function testInferenceReplayChallengeRequiresFinalizedPriorBatch() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        (FeatureActor governance, FeatureActor validator) = _setupGovernanceAndValidator(netuid);
        uint16 mechid = 11;

        uint64 readyAt =
            governance.queueInferenceBatchPolicyUpdate(settlement, netuid, mechid, true, 8, 8, 0.1 ether);
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
            netuid,
            mechid,
            secondEpoch,
            leaf,
            0,
            emptyProof,
            firstEpoch,
            0,
            emptyProof
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
        uint64 readyAt =
            governance.queueInferenceBatchPolicyUpdate(settlement, netuid, mechid, true, 5, 8, 0.1 ether);
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

        uint64 readyAt =
            governance.queueInferenceBatchPolicyUpdate(settlement, netuid, mechid, true, 6, 8, 0.1 ether);
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

        uint64 readyAt =
            governance.queueInferenceBatchPolicyUpdate(settlement, netuid, mechid, true, 4, 4, 0.1 ether);
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

    function testInferenceBatchCommitRequiresCurrentEpoch() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        (FeatureActor governance, FeatureActor validator) = _setupGovernanceAndValidator(netuid);
        uint16 mechid = 8;
        uint64 readyAt =
            governance.queueInferenceBatchPolicyUpdate(settlement, netuid, mechid, true, 5, 8, 0.1 ether);
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
        uint64 readyAt =
            governance.queueInferenceBatchPolicyUpdate(settlement, netuid, mechid, true, 5, 8, 0.1 ether);
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
        uint64 readyAt =
            governance.queueInferenceBatchPolicyUpdate(settlement, netuid, mechid, true, 5, 8, 0.1 ether);
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
        uint64 readyAt =
            governance.queueInferenceBatchPolicyUpdate(settlement, netuid, mechid, true, 5, 8, 0.1 ether);
        vm.roll(readyAt);
        governance.configureInferenceBatchPolicy(settlement, netuid, mechid, true, 5, 8, 0.1 ether);

        bytes32 forgedRoot = keccak256("forged-root");
        uint64 epoch = core.currentEpoch(netuid);
        validator.commitInferenceBatchRoot{value: 0.2 ether}(settlement, netuid, mechid, epoch, forgedRoot, 2, 1 ether);

        bytes32[] memory emptyProof = new bytes32[](0);
        bool forgedChallengeReverted = false;
        try settlement.challengeInferenceLeafDuplicate(netuid, mechid, epoch, forgedRoot, 0, emptyProof, 1, emptyProof) {}
        catch {
            forgedChallengeReverted = true;
        }
        assert(forgedChallengeReverted);
    }

    function testInferenceSettlementRejectsEmptyProofForgeryForNonZeroIndex() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        (FeatureActor governance, FeatureActor validator) = _setupGovernanceAndValidator(netuid);
        uint16 mechid = 14;
        uint64 readyAt =
            governance.queueInferenceBatchPolicyUpdate(settlement, netuid, mechid, true, 5, 8, 0.1 ether);
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
        uint64 readyAt =
            governance.queueInferenceBatchPolicyUpdate(settlement, netuid, mechid, true, 5, 8, 0.1 ether);
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

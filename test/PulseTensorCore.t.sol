// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PulseTensorCore} from "../src/PulseTensorCore.sol";

interface Vm {
    function roll(uint256 newHeight) external;
    function deal(address who, uint256 newBalance) external;
}

contract StakeActor {
    function addStake(PulseTensorCore core, uint16 netuid) external payable {
        core.addStake{value: msg.value}(netuid);
    }

    function removeStake(PulseTensorCore core, uint16 netuid, uint256 amount) external {
        core.removeStake(netuid, amount);
    }

    function registerValidator(PulseTensorCore core, uint16 netuid) external {
        core.registerValidator(netuid);
    }

    function unregisterValidator(PulseTensorCore core, uint16 netuid) external {
        core.unregisterValidator(netuid);
    }

    function registerMiner(PulseTensorCore core, uint16 netuid) external {
        core.registerMiner(netuid);
    }

    function unregisterMiner(PulseTensorCore core, uint16 netuid) external {
        core.unregisterMiner(netuid);
    }

    function setSubnetPaused(PulseTensorCore core, uint16 netuid, bool paused) external {
        core.setSubnetPaused(netuid, paused);
    }

    function queueSubnetPause(PulseTensorCore core, uint16 netuid, bool paused) external returns (bytes32, uint64) {
        return core.queueSubnetPause(netuid, paused);
    }

    function queueSubnetConfigUpdate(
        PulseTensorCore core,
        uint16 netuid,
        uint256 minValidatorStake,
        uint16 ownerFeeBps,
        uint64 revealDelayBlocks,
        uint64 epochLengthBlocks
    ) external returns (bytes32, uint64) {
        return
            core.queueSubnetConfigUpdate(netuid, minValidatorStake, ownerFeeBps, revealDelayBlocks, epochLengthBlocks);
    }

    function cancelSubnetOwnerAction(PulseTensorCore core, uint16 netuid, bytes32 actionId) external {
        core.cancelSubnetOwnerAction(netuid, actionId);
    }

    function configureSubnetGovernance(PulseTensorCore core, uint16 netuid, address governance, uint64 delayBlocks)
        external
    {
        core.configureSubnetGovernance(netuid, governance, delayBlocks);
    }

    function initiateSubnetOwnerTransfer(PulseTensorCore core, uint16 netuid, address newOwner) external {
        core.initiateSubnetOwnerTransfer(netuid, newOwner);
    }

    function acceptSubnetOwnerTransfer(PulseTensorCore core, uint16 netuid) external {
        core.acceptSubnetOwnerTransfer(netuid);
    }

    function updateSubnetConfig(
        PulseTensorCore core,
        uint16 netuid,
        uint256 minValidatorStake,
        uint16 ownerFeeBps,
        uint64 revealDelayBlocks,
        uint64 epochLengthBlocks
    ) external {
        core.updateSubnetConfig(netuid, minValidatorStake, ownerFeeBps, revealDelayBlocks, epochLengthBlocks);
    }

    function commitWeights(PulseTensorCore core, uint16 netuid, bytes32 commitment) external {
        core.commitWeights(netuid, commitment);
    }

    function commitMechanismWeights(PulseTensorCore core, uint16 netuid, uint16 mechid, bytes32 commitment) external {
        core.commitMechanismWeights(netuid, mechid, commitment);
    }

    function fundSubnetEmission(PulseTensorCore core, uint16 netuid) external payable {
        core.fundSubnetEmission{value: msg.value}(netuid);
    }

    function fundMechanismEmission(PulseTensorCore core, uint16 netuid, uint16 mechid) external payable {
        core.fundMechanismEmission{value: msg.value}(netuid, mechid);
    }

    function queueSubnetEmissionPayout(PulseTensorCore core, uint16 netuid, address recipient, uint256 amount)
        external
        returns (bytes32, uint64)
    {
        return core.queueSubnetEmissionPayout(netuid, recipient, amount);
    }

    function queueSubnetEmissionSplitPayout(
        PulseTensorCore core,
        uint16 netuid,
        address validatorRecipient,
        address minerRecipient,
        address ownerRecipient,
        uint256 totalAmount
    ) external returns (bytes32, uint64) {
        return
            core.queueSubnetEmissionSplitPayout(netuid, validatorRecipient, minerRecipient, ownerRecipient, totalAmount);
    }

    function queueMechanismEmissionPayout(
        PulseTensorCore core,
        uint16 netuid,
        uint16 mechid,
        address recipient,
        uint256 amount
    ) external returns (bytes32, uint64) {
        return core.queueMechanismEmissionPayout(netuid, mechid, recipient, amount);
    }

    function queueMechanismEmissionSplitPayout(
        PulseTensorCore core,
        uint16 netuid,
        uint16 mechid,
        address validatorRecipient,
        address minerRecipient,
        address ownerRecipient,
        uint256 totalAmount
    ) external returns (bytes32, uint64) {
        return core.queueMechanismEmissionSplitPayout(
            netuid, mechid, validatorRecipient, minerRecipient, ownerRecipient, totalAmount
        );
    }

    function queueSubnetEmissionScheduleUpdate(
        PulseTensorCore core,
        uint16 netuid,
        uint256 baseEmissionPerEpoch,
        uint256 floorEmissionPerEpoch,
        uint64 halvingPeriodEpochs,
        uint64 startEpoch
    ) external returns (bytes32, uint64) {
        return core.queueSubnetEmissionScheduleUpdate(
            netuid, baseEmissionPerEpoch, floorEmissionPerEpoch, halvingPeriodEpochs, startEpoch
        );
    }

    function queueMechanismEmissionScheduleUpdate(
        PulseTensorCore core,
        uint16 netuid,
        uint16 mechid,
        uint256 baseEmissionPerEpoch,
        uint256 floorEmissionPerEpoch,
        uint64 halvingPeriodEpochs,
        uint64 startEpoch
    ) external returns (bytes32, uint64) {
        return core.queueMechanismEmissionScheduleUpdate(
            netuid, mechid, baseEmissionPerEpoch, floorEmissionPerEpoch, halvingPeriodEpochs, startEpoch
        );
    }

    function queueSubnetEpochEmissionPayout(
        PulseTensorCore core,
        uint16 netuid,
        uint64 epoch,
        address validatorRecipient,
        address minerRecipient,
        address ownerRecipient
    ) external returns (bytes32, uint64) {
        return core.queueSubnetEpochEmissionPayout(netuid, epoch, validatorRecipient, minerRecipient, ownerRecipient);
    }

    function queueMechanismEpochEmissionPayout(
        PulseTensorCore core,
        uint16 netuid,
        uint16 mechid,
        uint64 epoch,
        address validatorRecipient,
        address minerRecipient,
        address ownerRecipient
    ) external returns (bytes32, uint64) {
        return core.queueMechanismEpochEmissionPayout(
            netuid, mechid, epoch, validatorRecipient, minerRecipient, ownerRecipient
        );
    }

    function payoutSubnetEmission(PulseTensorCore core, uint16 netuid, address payable recipient, uint256 amount)
        external
    {
        core.payoutSubnetEmission(netuid, recipient, amount);
    }

    function payoutSubnetEmissionSplit(
        PulseTensorCore core,
        uint16 netuid,
        address payable validatorRecipient,
        address payable minerRecipient,
        address payable ownerRecipient,
        uint256 totalAmount
    ) external {
        core.payoutSubnetEmissionSplit(netuid, validatorRecipient, minerRecipient, ownerRecipient, totalAmount);
    }

    function payoutMechanismEmission(
        PulseTensorCore core,
        uint16 netuid,
        uint16 mechid,
        address payable recipient,
        uint256 amount
    ) external {
        core.payoutMechanismEmission(netuid, mechid, recipient, amount);
    }

    function payoutMechanismEmissionSplit(
        PulseTensorCore core,
        uint16 netuid,
        uint16 mechid,
        address payable validatorRecipient,
        address payable minerRecipient,
        address payable ownerRecipient,
        uint256 totalAmount
    ) external {
        core.payoutMechanismEmissionSplit(
            netuid, mechid, validatorRecipient, minerRecipient, ownerRecipient, totalAmount
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

    function payoutSubnetEpochEmission(
        PulseTensorCore core,
        uint16 netuid,
        uint64 epoch,
        address payable validatorRecipient,
        address payable minerRecipient,
        address payable ownerRecipient
    ) external {
        core.payoutSubnetEpochEmission(netuid, epoch, validatorRecipient, minerRecipient, ownerRecipient);
    }

    function payoutMechanismEpochEmission(
        PulseTensorCore core,
        uint16 netuid,
        uint16 mechid,
        uint64 epoch,
        address payable validatorRecipient,
        address payable minerRecipient,
        address payable ownerRecipient
    ) external {
        core.payoutMechanismEpochEmission(netuid, mechid, epoch, validatorRecipient, minerRecipient, ownerRecipient);
    }

    function claimChallengeReward(PulseTensorCore core, uint16 netuid, uint256 amount) external {
        core.claimChallengeReward(netuid, amount);
    }

    function revealWeights(PulseTensorCore core, uint16 netuid, uint64 epoch, bytes32 weightsHash, bytes32 salt)
        external
    {
        core.revealWeights(netuid, epoch, weightsHash, salt);
    }

    function revealMechanismWeights(
        PulseTensorCore core,
        uint16 netuid,
        uint16 mechid,
        uint64 epoch,
        bytes32 weightsHash,
        bytes32 salt
    ) external {
        core.revealMechanismWeights(netuid, mechid, epoch, weightsHash, salt);
    }

    function challengeExpiredCommit(PulseTensorCore core, uint16 netuid, uint64 epoch, address validator)
        external
        returns (uint256, bool)
    {
        return core.challengeExpiredCommit(netuid, epoch, validator);
    }

    function challengeExpiredMechanismCommit(
        PulseTensorCore core,
        uint16 netuid,
        uint16 mechid,
        uint64 epoch,
        address validator
    ) external returns (uint256, bool) {
        return core.challengeExpiredMechanismCommit(netuid, mechid, epoch, validator);
    }

    receive() external payable {}
}

contract ReentrantWithdrawActor {
    PulseTensorCore internal target;
    uint16 internal targetNetuid;
    uint256 internal targetAmount;
    bool internal attacking;
    bool public reenterAttempted;
    bool public reenterBlocked;

    function addStake(PulseTensorCore core, uint16 netuid) external payable {
        core.addStake{value: msg.value}(netuid);
    }

    function attackWithdraw(PulseTensorCore core, uint16 netuid, uint256 amount) external {
        target = core;
        targetNetuid = netuid;
        targetAmount = amount;
        attacking = true;
        reenterAttempted = false;
        reenterBlocked = false;
        core.removeStake(netuid, amount);
        attacking = false;
    }

    receive() external payable {
        if (attacking && !reenterAttempted) {
            reenterAttempted = true;
            try target.removeStake(targetNetuid, targetAmount) {
                // not expected
            } catch {
                reenterBlocked = true;
            }
        }
    }
}

contract PulseTensorCoreTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    PulseTensorCore internal core;

    function setUp() public {
        core = new PulseTensorCore();
        vm.deal(address(this), 1_000 ether);
    }

    function testSubnetLifecycleAndStakeAccounting() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);

        StakeActor actor = new StakeActor();
        vm.deal(address(actor), 10 ether);

        actor.addStake{value: 3 ether}(core, netuid);
        (,,,,,, uint256 totalStakeAfterAdd) = core.subnets(netuid);
        assert(totalStakeAfterAdd == 3 ether);
        assert(core.stakeOf(netuid, address(actor)) == 3 ether);

        actor.removeStake(core, netuid, 1 ether);
        (,,,,,, uint256 totalStakeAfterRemove) = core.subnets(netuid);
        assert(totalStakeAfterRemove == 2 ether);
        assert(core.stakeOf(netuid, address(actor)) == 2 ether);
    }

    function testCommitRevealFlow() public {
        uint16 netuid = core.createSubnet(64, 2 ether, 500, 2, 16);

        StakeActor actor = new StakeActor();
        vm.deal(address(actor), 10 ether);
        actor.addStake{value: 2 ether}(core, netuid);
        actor.registerValidator(core, netuid);

        uint64 epoch = core.currentEpoch(netuid);
        bytes32 weightsHash = keccak256(abi.encodePacked("weights-v1"));
        bytes32 salt = bytes32(uint256(1234));
        bytes32 commitment = core.computeCommitment(weightsHash, salt, address(actor), netuid, epoch);

        actor.commitWeights(core, netuid, commitment);
        (bytes32 pendingCommitment, uint64 revealAtBlock, uint64 expireAtBlock) =
            core.epochCommitments(netuid, epoch, address(actor));
        assert(pendingCommitment == commitment);
        assert(revealAtBlock > block.number);
        assert(expireAtBlock >= revealAtBlock);

        vm.roll(block.number + 3);
        actor.revealWeights(core, netuid, epoch, weightsHash, salt);
        (bytes32 afterReveal,,) = core.epochCommitments(netuid, epoch, address(actor));
        assert(afterReveal == bytes32(0));
        assert(core.epochRevealed(netuid, epoch, address(actor)));
    }

    function testMechanismCommitRevealFlow() public {
        uint16 netuid = core.createSubnet(64, 2 ether, 500, 2, 16);
        uint16 mechid = 3;

        StakeActor actor = new StakeActor();
        vm.deal(address(actor), 10 ether);
        actor.addStake{value: 2 ether}(core, netuid);
        actor.registerValidator(core, netuid);

        uint64 epoch = core.currentEpoch(netuid);
        bytes32 weightsHash = keccak256(abi.encodePacked("mech-weights-v1"));
        bytes32 salt = bytes32(uint256(4321));
        bytes32 commitment = core.computeMechanismCommitment(weightsHash, salt, address(actor), netuid, mechid, epoch);

        actor.commitMechanismWeights(core, netuid, mechid, commitment);
        (bytes32 pendingCommitment, uint64 revealAtBlock, uint64 expireAtBlock) =
            core.mechanismEpochCommitments(netuid, mechid, epoch, address(actor));
        assert(pendingCommitment == commitment);
        assert(revealAtBlock > block.number);
        assert(expireAtBlock >= revealAtBlock);
        assert(core.pendingCommitmentCount(netuid, address(actor)) == 1);

        vm.roll(block.number + 3);
        actor.revealMechanismWeights(core, netuid, mechid, epoch, weightsHash, salt);
        (bytes32 afterReveal,,) = core.mechanismEpochCommitments(netuid, mechid, epoch, address(actor));
        assert(afterReveal == bytes32(0));
        assert(core.mechanismEpochRevealed(netuid, mechid, epoch, address(actor)));
        assert(core.pendingCommitmentCount(netuid, address(actor)) == 0);
    }

    function testMechanismCommitmentIncludesMechanismId() public {
        uint16 netuid = core.createSubnet(64, 2 ether, 500, 2, 16);
        uint16 mechid = 4;

        StakeActor actor = new StakeActor();
        vm.deal(address(actor), 10 ether);
        actor.addStake{value: 2 ether}(core, netuid);
        actor.registerValidator(core, netuid);

        uint64 epoch = core.currentEpoch(netuid);
        bytes32 weightsHash = keccak256(abi.encodePacked("mech-mismatch"));
        bytes32 salt = bytes32(uint256(4433));
        bytes32 mechanismCommitment =
            core.computeMechanismCommitment(weightsHash, salt, address(actor), netuid, mechid, epoch);
        actor.commitMechanismWeights(core, netuid, mechid, mechanismCommitment);
        vm.roll(block.number + 3);

        bool reverted = false;
        try actor.revealMechanismWeights(core, netuid, mechid + 1, epoch, weightsHash, salt) {}
        catch {
            reverted = true;
        }
        assert(reverted);

        actor.revealMechanismWeights(core, netuid, mechid, epoch, weightsHash, salt);
        assert(core.mechanismEpochRevealed(netuid, mechid, epoch, address(actor)));
    }

    function testValidatorCannotWithdrawBelowMinimumStake() public {
        uint16 netuid = core.createSubnet(64, 2 ether, 500, 2, 16);

        StakeActor actor = new StakeActor();
        vm.deal(address(actor), 10 ether);
        actor.addStake{value: 2 ether}(core, netuid);
        actor.registerValidator(core, netuid);

        bool reverted = false;
        try actor.removeStake(core, netuid, 1 ether) {}
        catch {
            reverted = true;
        }
        assert(reverted);
    }

    function testValidatorCannotWithdrawWithPendingCommitment() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        StakeActor actor = new StakeActor();
        vm.deal(address(actor), 10 ether);
        actor.addStake{value: 2 ether}(core, netuid);
        actor.registerValidator(core, netuid);

        uint64 epoch = core.currentEpoch(netuid);
        bytes32 weightsHash = keccak256(abi.encodePacked("pending-withdraw"));
        bytes32 salt = bytes32(uint256(91));
        bytes32 commitment = core.computeCommitment(weightsHash, salt, address(actor), netuid, epoch);
        actor.commitWeights(core, netuid, commitment);

        bool revertedWhilePending = false;
        try actor.removeStake(core, netuid, 0.5 ether) {}
        catch {
            revertedWhilePending = true;
        }
        assert(revertedWhilePending);
        assert(core.stakeOf(netuid, address(actor)) == 2 ether);

        vm.roll(block.number + 3);
        actor.revealWeights(core, netuid, epoch, weightsHash, salt);

        actor.removeStake(core, netuid, 0.5 ether);
        assert(core.stakeOf(netuid, address(actor)) == 1.5 ether);
    }

    function testValidatorCannotUnregisterWithPendingCommitment() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 4);
        StakeActor actor = new StakeActor();
        vm.deal(address(actor), 10 ether);
        actor.addStake{value: 2 ether}(core, netuid);
        actor.registerValidator(core, netuid);

        uint64 epoch = core.currentEpoch(netuid);
        bytes32 weightsHash = keccak256(abi.encodePacked("pending-unregister"));
        bytes32 salt = bytes32(uint256(93));
        bytes32 commitment = core.computeCommitment(weightsHash, salt, address(actor), netuid, epoch);
        actor.commitWeights(core, netuid, commitment);

        bool revertedWhilePending = false;
        try actor.unregisterValidator(core, netuid) {}
        catch {
            revertedWhilePending = true;
        }
        assert(revertedWhilePending);
        assert(core.isValidator(netuid, address(actor)));

        vm.roll(block.number + 5);
        core.challengeExpiredCommit(netuid, epoch, address(actor));

        actor.unregisterValidator(core, netuid);
        assert(!core.isValidator(netuid, address(actor)));
    }

    function testValidatorCannotWithdrawWithPendingMechanismCommitment() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 4);
        uint16 mechid = 6;
        StakeActor actor = new StakeActor();
        vm.deal(address(actor), 10 ether);
        actor.addStake{value: 2 ether}(core, netuid);
        actor.registerValidator(core, netuid);

        uint64 epoch = core.currentEpoch(netuid);
        bytes32 weightsHash = keccak256(abi.encodePacked("pending-mech-withdraw"));
        bytes32 salt = bytes32(uint256(94));
        bytes32 commitment = core.computeMechanismCommitment(weightsHash, salt, address(actor), netuid, mechid, epoch);
        actor.commitMechanismWeights(core, netuid, mechid, commitment);

        bool revertedWhilePending = false;
        try actor.removeStake(core, netuid, 0.5 ether) {}
        catch {
            revertedWhilePending = true;
        }
        assert(revertedWhilePending);
        assert(core.stakeOf(netuid, address(actor)) == 2 ether);

        vm.roll(block.number + 5);
        core.challengeExpiredMechanismCommit(netuid, mechid, epoch, address(actor));

        actor.removeStake(core, netuid, 0.5 ether);
        assert(core.stakeOf(netuid, address(actor)) == 1.4 ether);
    }

    function testOnlyOwnerCanConfigureSubnetGovernance() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        StakeActor governance = new StakeActor();
        StakeActor actor = new StakeActor();

        bool reverted = false;
        try actor.configureSubnetGovernance(core, netuid, address(governance), 2) {}
        catch {
            reverted = true;
        }
        assert(reverted);

        core.configureSubnetGovernance(netuid, address(governance), 2);
        assert(core.subnetGovernance(netuid) == address(governance));
        assert(core.subnetOwnerActionDelayBlocks(netuid) == 2);
    }

    function testGovernanceContractRequired() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        bool reverted = false;
        try core.configureSubnetGovernance(netuid, address(0xBEEF), 2) {}
        catch {
            reverted = true;
        }
        assert(reverted);
    }

    function testGovernanceDelayBoundsAreEnforced() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        StakeActor governance = new StakeActor();

        bool lowDelayReverted = false;
        try core.configureSubnetGovernance(netuid, address(governance), 1) {}
        catch {
            lowDelayReverted = true;
        }
        assert(lowDelayReverted);

        bool highDelayReverted = false;
        try core.configureSubnetGovernance(netuid, address(governance), 200_001) {}
        catch {
            highDelayReverted = true;
        }
        assert(highDelayReverted);
    }

    function testGovernanceCanPauseSubnetAfterDelay() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        StakeActor governance = new StakeActor();
        core.configureSubnetGovernance(netuid, address(governance), 2);

        governance.queueSubnetPause(core, netuid, true);

        bool earlyReverted = false;
        try governance.setSubnetPaused(core, netuid, true) {}
        catch {
            earlyReverted = true;
        }
        assert(earlyReverted);

        vm.roll(block.number + 2);
        governance.setSubnetPaused(core, netuid, true);
        assert(core.subnetPaused(netuid));

        StakeActor actor = new StakeActor();
        vm.deal(address(actor), 10 ether);
        bool reverted = false;
        try actor.addStake{value: 1 ether}(core, netuid) {}
        catch {
            reverted = true;
        }
        assert(reverted);
    }

    function testGovernanceCannotExecuteWithoutQueue() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        StakeActor governance = new StakeActor();
        core.configureSubnetGovernance(netuid, address(governance), 2);

        bool pauseReverted = false;
        try governance.setSubnetPaused(core, netuid, true) {}
        catch {
            pauseReverted = true;
        }
        assert(pauseReverted);

        bool configReverted = false;
        try governance.updateSubnetConfig(core, netuid, 2 ether, 600, 3, 20) {}
        catch {
            configReverted = true;
        }
        assert(configReverted);
    }

    function testOnlyGovernanceCanQueuePause() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        StakeActor governance = new StakeActor();
        StakeActor actor = new StakeActor();
        core.configureSubnetGovernance(netuid, address(governance), 2);

        bool reverted = false;
        try actor.queueSubnetPause(core, netuid, true) {}
        catch {
            reverted = true;
        }
        assert(reverted);
    }

    function testGovernanceCanCancelQueuedOwnerAction() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        StakeActor governance = new StakeActor();
        core.configureSubnetGovernance(netuid, address(governance), 2);

        (bytes32 actionId,) = governance.queueSubnetPause(core, netuid, true);
        governance.cancelSubnetOwnerAction(core, netuid, actionId);

        vm.roll(block.number + 3);
        bool reverted = false;
        try governance.setSubnetPaused(core, netuid, true) {}
        catch {
            reverted = true;
        }
        assert(reverted);
    }

    function testMinerRegisterAndUnregister() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        StakeActor actor = new StakeActor();

        actor.registerMiner(core, netuid);
        assert(core.isMiner(netuid, address(actor)));

        actor.unregisterMiner(core, netuid);
        assert(!core.isMiner(netuid, address(actor)));
    }

    function testRegisterValidatorRequiresMinStake() public {
        uint16 netuid = core.createSubnet(64, 2 ether, 500, 2, 16);
        StakeActor actor = new StakeActor();
        vm.deal(address(actor), 10 ether);
        actor.addStake{value: 1 ether}(core, netuid);

        bool reverted = false;
        try actor.registerValidator(core, netuid) {}
        catch {
            reverted = true;
        }
        assert(reverted);
    }

    function testValidatorCapacityEnforced() public {
        uint16 netuid = core.createSubnet(1, 1 ether, 500, 2, 16);
        StakeActor actorOne = new StakeActor();
        StakeActor actorTwo = new StakeActor();
        vm.deal(address(actorOne), 10 ether);
        vm.deal(address(actorTwo), 10 ether);
        actorOne.addStake{value: 1 ether}(core, netuid);
        actorTwo.addStake{value: 1 ether}(core, netuid);
        actorOne.registerValidator(core, netuid);

        bool reverted = false;
        try actorTwo.registerValidator(core, netuid) {}
        catch {
            reverted = true;
        }
        assert(reverted);
    }

    function testOnlyGovernanceCanQueueSubnetConfigUpdate() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        StakeActor governance = new StakeActor();
        StakeActor actor = new StakeActor();
        core.configureSubnetGovernance(netuid, address(governance), 2);

        bool reverted = false;
        try actor.queueSubnetConfigUpdate(core, netuid, 2 ether, 600, 3, 20) {}
        catch {
            reverted = true;
        }
        assert(reverted);
    }

    function testGovernanceCanUpdateSubnetConfigAfterDelay() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        StakeActor governance = new StakeActor();
        core.configureSubnetGovernance(netuid, address(governance), 2);

        governance.queueSubnetConfigUpdate(core, netuid, 3 ether, 700, 4, 24);

        bool earlyReverted = false;
        try governance.updateSubnetConfig(core, netuid, 3 ether, 700, 4, 24) {}
        catch {
            earlyReverted = true;
        }
        assert(earlyReverted);

        vm.roll(block.number + 2);
        governance.updateSubnetConfig(core, netuid, 3 ether, 700, 4, 24);
        (
            ,
            uint16 maxValidators,
            uint16 ownerFeeBps,
            uint64 revealDelayBlocks,
            uint64 epochLengthBlocks,
            uint256 minStake,
        ) = core.subnets(netuid);
        assert(maxValidators == 64);
        assert(ownerFeeBps == 700);
        assert(revealDelayBlocks == 4);
        assert(epochLengthBlocks == 24);
        assert(minStake == 3 ether);
    }

    function testSubnetOwnerTransferIsTwoStep() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        StakeActor newOwner = new StakeActor();
        StakeActor actor = new StakeActor();

        core.initiateSubnetOwnerTransfer(netuid, address(newOwner));
        assert(core.pendingSubnetOwner(netuid) == address(newOwner));

        bool reverted = false;
        try actor.acceptSubnetOwnerTransfer(core, netuid) {}
        catch {
            reverted = true;
        }
        assert(reverted);

        newOwner.acceptSubnetOwnerTransfer(core, netuid);
        assert(core.subnetOwner(netuid) == address(newOwner));

        StakeActor governance = new StakeActor();
        newOwner.configureSubnetGovernance(core, netuid, address(governance), 2);
        assert(core.subnetGovernance(netuid) == address(governance));
    }

    function testNonValidatorCannotCommitWeights() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        StakeActor actor = new StakeActor();
        vm.deal(address(actor), 10 ether);
        actor.addStake{value: 1 ether}(core, netuid);

        bytes32 commitment = keccak256("x");
        bool reverted = false;
        try actor.commitWeights(core, netuid, commitment) {}
        catch {
            reverted = true;
        }
        assert(reverted);
    }

    function testDuplicateCommitInSameEpochReverts() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        StakeActor actor = new StakeActor();
        vm.deal(address(actor), 10 ether);
        actor.addStake{value: 1 ether}(core, netuid);
        actor.registerValidator(core, netuid);
        uint64 epoch = core.currentEpoch(netuid);
        bytes32 weightsHash = keccak256(abi.encodePacked("w"));
        bytes32 salt = bytes32(uint256(11));
        bytes32 commitment = core.computeCommitment(weightsHash, salt, address(actor), netuid, epoch);
        actor.commitWeights(core, netuid, commitment);

        bool reverted = false;
        try actor.commitWeights(core, netuid, commitment) {}
        catch {
            reverted = true;
        }
        assert(reverted);
    }

    function testRevealWrongSaltReverts() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        StakeActor actor = new StakeActor();
        vm.deal(address(actor), 10 ether);
        actor.addStake{value: 1 ether}(core, netuid);
        actor.registerValidator(core, netuid);
        uint64 epoch = core.currentEpoch(netuid);
        bytes32 weightsHash = keccak256(abi.encodePacked("w"));
        bytes32 salt = bytes32(uint256(11));
        bytes32 commitment = core.computeCommitment(weightsHash, salt, address(actor), netuid, epoch);
        actor.commitWeights(core, netuid, commitment);
        vm.roll(block.number + 3);

        bool reverted = false;
        try actor.revealWeights(core, netuid, epoch, weightsHash, bytes32(uint256(999))) {}
        catch {
            reverted = true;
        }
        assert(reverted);
        (bytes32 pending,,) = core.epochCommitments(netuid, epoch, address(actor));
        assert(pending == commitment);
    }

    function testRevealFutureEpochReverts() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        StakeActor actor = new StakeActor();
        vm.deal(address(actor), 10 ether);
        actor.addStake{value: 1 ether}(core, netuid);
        actor.registerValidator(core, netuid);
        uint64 epoch = core.currentEpoch(netuid);
        bytes32 weightsHash = keccak256(abi.encodePacked("w"));
        bytes32 salt = bytes32(uint256(11));
        bytes32 commitment = core.computeCommitment(weightsHash, salt, address(actor), netuid, epoch);
        actor.commitWeights(core, netuid, commitment);

        bool reverted = false;
        try actor.revealWeights(core, netuid, epoch + 1, weightsHash, salt) {}
        catch {
            reverted = true;
        }
        assert(reverted);
    }

    function testDoubleRevealReverts() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        StakeActor actor = new StakeActor();
        vm.deal(address(actor), 10 ether);
        actor.addStake{value: 1 ether}(core, netuid);
        actor.registerValidator(core, netuid);
        uint64 epoch = core.currentEpoch(netuid);
        bytes32 weightsHash = keccak256(abi.encodePacked("w"));
        bytes32 salt = bytes32(uint256(11));
        bytes32 commitment = core.computeCommitment(weightsHash, salt, address(actor), netuid, epoch);
        actor.commitWeights(core, netuid, commitment);
        vm.roll(block.number + 3);
        actor.revealWeights(core, netuid, epoch, weightsHash, salt);

        bool reverted = false;
        try actor.revealWeights(core, netuid, epoch, weightsHash, salt) {}
        catch {
            reverted = true;
        }
        assert(reverted);
    }

    function testCommitCanResumeAfterExpiredPendingCommitment() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 4);
        StakeActor actor = new StakeActor();
        vm.deal(address(actor), 10 ether);
        actor.addStake{value: 2 ether}(core, netuid);
        actor.registerValidator(core, netuid);
        uint64 epoch0 = core.currentEpoch(netuid);

        bytes32 firstWeightsHash = keccak256(abi.encodePacked("w0"));
        bytes32 salt = bytes32(uint256(11));
        bytes32 firstCommitment = core.computeCommitment(firstWeightsHash, salt, address(actor), netuid, epoch0);
        actor.commitWeights(core, netuid, firstCommitment);

        vm.roll(block.number + 4);
        uint64 epoch1 = core.currentEpoch(netuid);
        bytes32 secondWeightsHash = keccak256(abi.encodePacked("w1"));
        bytes32 secondCommitment = core.computeCommitment(secondWeightsHash, salt, address(actor), netuid, epoch1);
        bool blockedUntilChallenged = false;
        try actor.commitWeights(core, netuid, secondCommitment) {}
        catch {
            blockedUntilChallenged = true;
        }
        assert(blockedUntilChallenged);

        (uint256 slashedAmount, bool validatorUnregistered) =
            actor.challengeExpiredCommit(core, netuid, epoch0, address(actor));
        assert(slashedAmount == 0.1 ether);
        assert(!validatorUnregistered);
        assert(core.challengeRewardOf(netuid, address(actor)) == 0);
        assert(core.subnetEmissionPool(netuid) == 0.1 ether);

        actor.commitWeights(core, netuid, secondCommitment);

        (bytes32 pendingCommitment,,) = core.epochCommitments(netuid, epoch1, address(actor));
        assert(pendingCommitment == secondCommitment);
        assert(core.stakeOf(netuid, address(actor)) == 1.9 ether);
    }

    function testSelfChallengeRoutesFullSlashToEmissionPool() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 4);
        StakeActor actor = new StakeActor();
        vm.deal(address(actor), 10 ether);
        actor.addStake{value: 2 ether}(core, netuid);
        actor.registerValidator(core, netuid);

        uint64 epoch = core.currentEpoch(netuid);
        bytes32 weightsHash = keccak256(abi.encodePacked("self-challenge-subnet"));
        bytes32 salt = bytes32(uint256(311));
        bytes32 commitment = core.computeCommitment(weightsHash, salt, address(actor), netuid, epoch);
        actor.commitWeights(core, netuid, commitment);

        vm.roll(block.number + 5);
        (uint256 slashedAmount,) = actor.challengeExpiredCommit(core, netuid, epoch, address(actor));
        assert(slashedAmount == 0.1 ether);
        assert(core.challengeRewardOf(netuid, address(actor)) == 0);
        assert(core.subnetEmissionPool(netuid) == 0.1 ether);
    }

    function testSelfChallengeMechanismRoutesFullSlashToEmissionPool() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 4);
        uint16 mechid = 12;
        StakeActor actor = new StakeActor();
        vm.deal(address(actor), 10 ether);
        actor.addStake{value: 2 ether}(core, netuid);
        actor.registerValidator(core, netuid);

        uint64 epoch = core.currentEpoch(netuid);
        bytes32 weightsHash = keccak256(abi.encodePacked("self-challenge-mechanism"));
        bytes32 salt = bytes32(uint256(313));
        bytes32 commitment = core.computeMechanismCommitment(weightsHash, salt, address(actor), netuid, mechid, epoch);
        actor.commitMechanismWeights(core, netuid, mechid, commitment);

        vm.roll(block.number + 5);
        (uint256 slashedAmount,) = actor.challengeExpiredMechanismCommit(core, netuid, mechid, epoch, address(actor));
        assert(slashedAmount == 0.1 ether);
        assert(core.challengeRewardOf(netuid, address(actor)) == 0);
        assert(core.subnetEmissionPool(netuid) == 0.1 ether);
    }

    function testRevealStillWorksAfterEpochLengthIncrease() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        StakeActor governance = new StakeActor();
        StakeActor validator = new StakeActor();
        core.configureSubnetGovernance(netuid, address(governance), 2);
        vm.deal(address(validator), 10 ether);
        validator.addStake{value: 2 ether}(core, netuid);
        validator.registerValidator(core, netuid);

        vm.roll(48);
        uint64 committedEpoch = core.currentEpoch(netuid);
        assert(committedEpoch == 3);

        bytes32 weightsHash = keccak256(abi.encodePacked("epoch-drift-reveal"));
        bytes32 salt = bytes32(uint256(991));
        bytes32 commitment = core.computeCommitment(weightsHash, salt, address(validator), netuid, committedEpoch);
        validator.commitWeights(core, netuid, commitment);

        governance.queueSubnetConfigUpdate(core, netuid, 1 ether, 500, 2, 120_000);
        vm.roll(block.number + 2);
        governance.updateSubnetConfig(core, netuid, 1 ether, 500, 2, 120_000);
        assert(core.currentEpoch(netuid) == 0);

        vm.roll(block.number + 1);
        validator.revealWeights(core, netuid, committedEpoch, weightsHash, salt);
        assert(core.epochRevealed(netuid, committedEpoch, address(validator)));
    }

    function testMechanismRevealStillWorksAfterEpochLengthIncrease() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        uint16 mechid = 14;
        StakeActor governance = new StakeActor();
        StakeActor validator = new StakeActor();
        core.configureSubnetGovernance(netuid, address(governance), 2);
        vm.deal(address(validator), 10 ether);
        validator.addStake{value: 2 ether}(core, netuid);
        validator.registerValidator(core, netuid);

        vm.roll(48);
        uint64 committedEpoch = core.currentEpoch(netuid);
        assert(committedEpoch == 3);

        bytes32 weightsHash = keccak256(abi.encodePacked("epoch-drift-mechanism-reveal"));
        bytes32 salt = bytes32(uint256(993));
        bytes32 commitment =
            core.computeMechanismCommitment(weightsHash, salt, address(validator), netuid, mechid, committedEpoch);
        validator.commitMechanismWeights(core, netuid, mechid, commitment);

        governance.queueSubnetConfigUpdate(core, netuid, 1 ether, 500, 2, 120_000);
        vm.roll(block.number + 2);
        governance.updateSubnetConfig(core, netuid, 1 ether, 500, 2, 120_000);
        assert(core.currentEpoch(netuid) == 0);

        vm.roll(block.number + 1);
        validator.revealMechanismWeights(core, netuid, mechid, committedEpoch, weightsHash, salt);
        assert(core.mechanismEpochRevealed(netuid, mechid, committedEpoch, address(validator)));
    }

    function testRevealStillWorksAfterEpochLengthDecrease() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        StakeActor governance = new StakeActor();
        StakeActor validator = new StakeActor();
        core.configureSubnetGovernance(netuid, address(governance), 2);
        vm.deal(address(validator), 10 ether);
        validator.addStake{value: 2 ether}(core, netuid);
        validator.registerValidator(core, netuid);

        vm.roll(48);
        uint64 committedEpoch = core.currentEpoch(netuid);
        assert(committedEpoch == 3);

        bytes32 weightsHash = keccak256(abi.encodePacked("epoch-drift-decrease-reveal"));
        bytes32 salt = bytes32(uint256(997));
        bytes32 commitment = core.computeCommitment(weightsHash, salt, address(validator), netuid, committedEpoch);
        validator.commitWeights(core, netuid, commitment);

        governance.queueSubnetConfigUpdate(core, netuid, 1 ether, 500, 2, 4);
        vm.roll(block.number + 2);
        governance.updateSubnetConfig(core, netuid, 1 ether, 500, 2, 4);
        assert(core.currentEpoch(netuid) > committedEpoch);

        vm.roll(block.number + 1);
        validator.revealWeights(core, netuid, committedEpoch, weightsHash, salt);
        assert(core.epochRevealed(netuid, committedEpoch, address(validator)));
    }

    function testMechanismRevealStillWorksAfterEpochLengthDecrease() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        uint16 mechid = 17;
        StakeActor governance = new StakeActor();
        StakeActor validator = new StakeActor();
        core.configureSubnetGovernance(netuid, address(governance), 2);
        vm.deal(address(validator), 10 ether);
        validator.addStake{value: 2 ether}(core, netuid);
        validator.registerValidator(core, netuid);

        vm.roll(48);
        uint64 committedEpoch = core.currentEpoch(netuid);
        assert(committedEpoch == 3);

        bytes32 weightsHash = keccak256(abi.encodePacked("epoch-drift-mechanism-decrease-reveal"));
        bytes32 salt = bytes32(uint256(999));
        bytes32 commitment =
            core.computeMechanismCommitment(weightsHash, salt, address(validator), netuid, mechid, committedEpoch);
        validator.commitMechanismWeights(core, netuid, mechid, commitment);

        governance.queueSubnetConfigUpdate(core, netuid, 1 ether, 500, 2, 4);
        vm.roll(block.number + 2);
        governance.updateSubnetConfig(core, netuid, 1 ether, 500, 2, 4);
        assert(core.currentEpoch(netuid) > committedEpoch);

        vm.roll(block.number + 1);
        validator.revealMechanismWeights(core, netuid, mechid, committedEpoch, weightsHash, salt);
        assert(core.mechanismEpochRevealed(netuid, mechid, committedEpoch, address(validator)));
    }

    function testValidatorStaysRegisteredWhileOtherPendingCommitmentExists() public {
        uint16 netuid = core.createSubnet(64, 2 ether, 500, 2, 8);
        uint16 mechid = 15;
        StakeActor actor = new StakeActor();
        vm.deal(address(actor), 10 ether);
        actor.addStake{value: 2 ether}(core, netuid);
        actor.registerValidator(core, netuid);

        uint64 subnetEpoch = core.currentEpoch(netuid);
        bytes32 subnetHash = keccak256(abi.encodePacked("deferred-unregister-subnet"));
        bytes32 subnetSalt = bytes32(uint256(501));
        bytes32 subnetCommit = core.computeCommitment(subnetHash, subnetSalt, address(actor), netuid, subnetEpoch);
        actor.commitWeights(core, netuid, subnetCommit);

        vm.roll(block.number + 8);
        uint64 mechanismEpoch = core.currentEpoch(netuid);
        bytes32 mechanismHash = keccak256(abi.encodePacked("deferred-unregister-mech"));
        bytes32 mechanismSalt = bytes32(uint256(502));
        bytes32 mechanismCommit = core.computeMechanismCommitment(
            mechanismHash, mechanismSalt, address(actor), netuid, mechid, mechanismEpoch
        );
        actor.commitMechanismWeights(core, netuid, mechid, mechanismCommit);
        assert(core.pendingCommitmentCount(netuid, address(actor)) == 2);

        (uint256 slashedAmount, bool validatorUnregistered) =
            core.challengeExpiredCommit(netuid, subnetEpoch, address(actor));
        assert(slashedAmount == 0.1 ether);
        assert(!validatorUnregistered);
        assert(core.pendingCommitmentCount(netuid, address(actor)) == 1);
        assert(core.isValidator(netuid, address(actor)));

        (, uint64 mechanismRevealAtBlock,) =
            core.mechanismEpochCommitments(netuid, mechid, mechanismEpoch, address(actor));
        vm.roll(uint256(mechanismRevealAtBlock) + 1);
        actor.revealMechanismWeights(core, netuid, mechid, mechanismEpoch, mechanismHash, mechanismSalt);
        assert(core.pendingCommitmentCount(netuid, address(actor)) == 0);
        assert(!core.isValidator(netuid, address(actor)));
        assert(core.validatorCount(netuid) == 0);
    }

    function testFinalPendingChallengeAutoUnregistersValidator() public {
        uint16 netuid = core.createSubnet(64, 2 ether, 500, 2, 8);
        uint16 mechid = 16;
        StakeActor actor = new StakeActor();
        vm.deal(address(actor), 10 ether);
        actor.addStake{value: 2 ether}(core, netuid);
        actor.registerValidator(core, netuid);

        uint64 subnetEpoch = core.currentEpoch(netuid);
        bytes32 subnetHash = keccak256(abi.encodePacked("final-unregister-subnet"));
        bytes32 subnetSalt = bytes32(uint256(601));
        bytes32 subnetCommit = core.computeCommitment(subnetHash, subnetSalt, address(actor), netuid, subnetEpoch);
        actor.commitWeights(core, netuid, subnetCommit);

        vm.roll(block.number + 8);
        uint64 mechanismEpoch = core.currentEpoch(netuid);
        bytes32 mechanismHash = keccak256(abi.encodePacked("final-unregister-mech"));
        bytes32 mechanismSalt = bytes32(uint256(602));
        bytes32 mechanismCommit = core.computeMechanismCommitment(
            mechanismHash, mechanismSalt, address(actor), netuid, mechid, mechanismEpoch
        );
        actor.commitMechanismWeights(core, netuid, mechid, mechanismCommit);

        (, bool firstUnregister) = core.challengeExpiredCommit(netuid, subnetEpoch, address(actor));
        assert(!firstUnregister);
        assert(core.isValidator(netuid, address(actor)));
        assert(core.pendingCommitmentCount(netuid, address(actor)) == 1);

        (,, uint64 mechanismExpireAtBlock) =
            core.mechanismEpochCommitments(netuid, mechid, mechanismEpoch, address(actor));
        vm.roll(uint256(mechanismExpireAtBlock) + 1);
        (, bool secondUnregister) = core.challengeExpiredMechanismCommit(netuid, mechid, mechanismEpoch, address(actor));
        assert(secondUnregister);
        assert(!core.isValidator(netuid, address(actor)));
        assert(core.pendingCommitmentCount(netuid, address(actor)) == 0);
        assert(core.validatorCount(netuid) == 0);
    }

    function testCommitTooLateInEpochReverts() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 4);
        StakeActor actor = new StakeActor();
        vm.deal(address(actor), 10 ether);
        actor.addStake{value: 1 ether}(core, netuid);
        actor.registerValidator(core, netuid);

        vm.roll(block.number + 6);
        uint64 epoch = core.currentEpoch(netuid);
        bytes32 weightsHash = keccak256(abi.encodePacked("late"));
        bytes32 salt = bytes32(uint256(99));
        bytes32 commitment = core.computeCommitment(weightsHash, salt, address(actor), netuid, epoch);

        bool reverted = false;
        try actor.commitWeights(core, netuid, commitment) {}
        catch {
            reverted = true;
        }
        assert(reverted);
    }

    function testChallengeExpiredCommitSlashesStakeAndClearsPending() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 4);
        StakeActor actor = new StakeActor();
        vm.deal(address(actor), 10 ether);
        actor.addStake{value: 2 ether}(core, netuid);
        actor.registerValidator(core, netuid);

        uint64 epoch = core.currentEpoch(netuid);
        bytes32 weightsHash = keccak256(abi.encodePacked("challenge-1"));
        bytes32 salt = bytes32(uint256(17));
        bytes32 commitment = core.computeCommitment(weightsHash, salt, address(actor), netuid, epoch);
        actor.commitWeights(core, netuid, commitment);

        vm.roll(block.number + 5);
        (uint256 slashedAmount, bool validatorUnregistered) = core.challengeExpiredCommit(netuid, epoch, address(actor));
        assert(slashedAmount == 0.1 ether);
        assert(!validatorUnregistered);
        assert(core.challengeRewardOf(netuid, address(this)) == 0.02 ether);
        assert(core.subnetEmissionPool(netuid) == 0.08 ether);

        (bytes32 pending,,) = core.epochCommitments(netuid, epoch, address(actor));
        assert(pending == bytes32(0));
        assert(core.activeCommitEpoch(netuid, address(actor)) == 0);
        assert(core.stakeOf(netuid, address(actor)) == 1.9 ether);
        assert(core.isValidator(netuid, address(actor)));
    }

    function testChallengeExpiredMechanismCommitSlashesStakeAndClearsPending() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 4);
        uint16 mechid = 2;
        StakeActor actor = new StakeActor();
        vm.deal(address(actor), 10 ether);
        actor.addStake{value: 2 ether}(core, netuid);
        actor.registerValidator(core, netuid);

        uint64 epoch = core.currentEpoch(netuid);
        bytes32 weightsHash = keccak256(abi.encodePacked("mech-challenge-1"));
        bytes32 salt = bytes32(uint256(27));
        bytes32 commitment = core.computeMechanismCommitment(weightsHash, salt, address(actor), netuid, mechid, epoch);
        actor.commitMechanismWeights(core, netuid, mechid, commitment);

        vm.roll(block.number + 5);
        (uint256 slashedAmount, bool validatorUnregistered) =
            core.challengeExpiredMechanismCommit(netuid, mechid, epoch, address(actor));
        assert(slashedAmount == 0.1 ether);
        assert(!validatorUnregistered);
        assert(core.challengeRewardOf(netuid, address(this)) == 0.02 ether);
        assert(core.subnetEmissionPool(netuid) == 0.08 ether);

        (bytes32 pending,,) = core.mechanismEpochCommitments(netuid, mechid, epoch, address(actor));
        assert(pending == bytes32(0));
        assert(core.mechanismActiveCommitEpoch(netuid, mechid, address(actor)) == 0);
        assert(core.pendingCommitmentCount(netuid, address(actor)) == 0);
        assert(core.stakeOf(netuid, address(actor)) == 1.9 ether);
        assert(core.isValidator(netuid, address(actor)));
    }

    function testChallengeExpiredCommitBeforeExpiryReverts() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 8);
        StakeActor actor = new StakeActor();
        vm.deal(address(actor), 10 ether);
        actor.addStake{value: 2 ether}(core, netuid);
        actor.registerValidator(core, netuid);

        uint64 epoch = core.currentEpoch(netuid);
        bytes32 weightsHash = keccak256(abi.encodePacked("challenge-2"));
        bytes32 salt = bytes32(uint256(21));
        bytes32 commitment = core.computeCommitment(weightsHash, salt, address(actor), netuid, epoch);
        actor.commitWeights(core, netuid, commitment);

        bool reverted = false;
        try core.challengeExpiredCommit(netuid, epoch, address(actor)) {}
        catch {
            reverted = true;
        }
        assert(reverted);
    }

    function testChallengeExpiredCommitCanUnregisterValidator() public {
        uint16 netuid = core.createSubnet(64, 2 ether, 500, 2, 4);
        StakeActor actor = new StakeActor();
        vm.deal(address(actor), 10 ether);
        actor.addStake{value: 2 ether}(core, netuid);
        actor.registerValidator(core, netuid);

        uint64 epoch = core.currentEpoch(netuid);
        bytes32 weightsHash = keccak256(abi.encodePacked("challenge-3"));
        bytes32 salt = bytes32(uint256(33));
        bytes32 commitment = core.computeCommitment(weightsHash, salt, address(actor), netuid, epoch);
        actor.commitWeights(core, netuid, commitment);

        vm.roll(block.number + 5);
        (uint256 slashedAmount, bool validatorUnregistered) = core.challengeExpiredCommit(netuid, epoch, address(actor));
        assert(slashedAmount == 0.1 ether);
        assert(validatorUnregistered);
        assert(core.challengeRewardOf(netuid, address(this)) == 0.02 ether);
        assert(core.subnetEmissionPool(netuid) == 0.08 ether);
        assert(!core.isValidator(netuid, address(actor)));
        assert(core.validatorCount(netuid) == 0);
        assert(core.stakeOf(netuid, address(actor)) == 1.9 ether);
    }

    function testChallengeExpiredCommitCannotBeAppliedTwice() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 4);
        StakeActor actor = new StakeActor();
        vm.deal(address(actor), 10 ether);
        actor.addStake{value: 2 ether}(core, netuid);
        actor.registerValidator(core, netuid);

        uint64 epoch = core.currentEpoch(netuid);
        bytes32 weightsHash = keccak256(abi.encodePacked("challenge-4"));
        bytes32 salt = bytes32(uint256(35));
        bytes32 commitment = core.computeCommitment(weightsHash, salt, address(actor), netuid, epoch);
        actor.commitWeights(core, netuid, commitment);

        vm.roll(block.number + 5);
        core.challengeExpiredCommit(netuid, epoch, address(actor));

        bool reverted = false;
        try core.challengeExpiredCommit(netuid, epoch, address(actor)) {}
        catch {
            reverted = true;
        }
        assert(reverted);
    }

    function testRevealWeightsWorksWhileSubnetPaused() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 8);
        StakeActor governance = new StakeActor();
        core.configureSubnetGovernance(netuid, address(governance), 2);

        StakeActor actor = new StakeActor();
        vm.deal(address(actor), 10 ether);
        actor.addStake{value: 2 ether}(core, netuid);
        actor.registerValidator(core, netuid);

        uint64 epoch = core.currentEpoch(netuid);
        bytes32 weightsHash = keccak256(abi.encodePacked("reveal-paused"));
        bytes32 salt = bytes32(uint256(145));
        bytes32 commitment = core.computeCommitment(weightsHash, salt, address(actor), netuid, epoch);
        actor.commitWeights(core, netuid, commitment);

        governance.queueSubnetPause(core, netuid, true);
        vm.roll(block.number + 2);
        governance.setSubnetPaused(core, netuid, true);
        assert(core.subnetPaused(netuid));

        vm.roll(block.number + 1);
        actor.revealWeights(core, netuid, epoch, weightsHash, salt);

        assert(core.epochRevealed(netuid, epoch, address(actor)));
        (bytes32 pending,,) = core.epochCommitments(netuid, epoch, address(actor));
        assert(pending == bytes32(0));
        assert(core.pendingCommitmentCount(netuid, address(actor)) == 0);
    }

    function testRevealMechanismWeightsWorksWhileSubnetPaused() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 8);
        StakeActor governance = new StakeActor();
        core.configureSubnetGovernance(netuid, address(governance), 2);

        StakeActor actor = new StakeActor();
        vm.deal(address(actor), 10 ether);
        actor.addStake{value: 2 ether}(core, netuid);
        actor.registerValidator(core, netuid);

        uint16 mechid = 7;
        uint64 epoch = core.currentEpoch(netuid);
        bytes32 weightsHash = keccak256(abi.encodePacked("reveal-mechanism-paused"));
        bytes32 salt = bytes32(uint256(246));
        bytes32 commitment = core.computeMechanismCommitment(weightsHash, salt, address(actor), netuid, mechid, epoch);
        actor.commitMechanismWeights(core, netuid, mechid, commitment);

        governance.queueSubnetPause(core, netuid, true);
        vm.roll(block.number + 2);
        governance.setSubnetPaused(core, netuid, true);
        assert(core.subnetPaused(netuid));

        vm.roll(block.number + 1);
        actor.revealMechanismWeights(core, netuid, mechid, epoch, weightsHash, salt);

        assert(core.mechanismEpochRevealed(netuid, mechid, epoch, address(actor)));
        (bytes32 pending,,) = core.mechanismEpochCommitments(netuid, mechid, epoch, address(actor));
        assert(pending == bytes32(0));
        assert(core.pendingCommitmentCount(netuid, address(actor)) == 0);
    }

    function testChallengeExpiredCommitWorksWhileSubnetPaused() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 4);
        StakeActor governance = new StakeActor();
        core.configureSubnetGovernance(netuid, address(governance), 2);

        StakeActor actor = new StakeActor();
        vm.deal(address(actor), 10 ether);
        actor.addStake{value: 2 ether}(core, netuid);
        actor.registerValidator(core, netuid);

        uint64 epoch = core.currentEpoch(netuid);
        bytes32 weightsHash = keccak256(abi.encodePacked("challenge-paused"));
        bytes32 salt = bytes32(uint256(44));
        bytes32 commitment = core.computeCommitment(weightsHash, salt, address(actor), netuid, epoch);
        actor.commitWeights(core, netuid, commitment);

        governance.queueSubnetPause(core, netuid, true);
        vm.roll(block.number + 2);
        governance.setSubnetPaused(core, netuid, true);
        assert(core.subnetPaused(netuid));

        vm.roll(block.number + 1);
        (uint256 slashedAmount,) = core.challengeExpiredCommit(netuid, epoch, address(actor));
        assert(slashedAmount == 0.1 ether);
        assert(core.challengeRewardOf(netuid, address(this)) == 0.02 ether);
        assert(core.subnetEmissionPool(netuid) == 0.08 ether);
        (bytes32 pending,,) = core.epochCommitments(netuid, epoch, address(actor));
        assert(pending == bytes32(0));
    }

    function testChallengerCanClaimAccruedReward() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 4);
        StakeActor validator = new StakeActor();
        StakeActor challenger = new StakeActor();
        vm.deal(address(validator), 10 ether);
        vm.deal(address(challenger), 1 ether);

        validator.addStake{value: 2 ether}(core, netuid);
        validator.registerValidator(core, netuid);

        uint64 epoch = core.currentEpoch(netuid);
        bytes32 weightsHash = keccak256(abi.encodePacked("challenge-reward"));
        bytes32 salt = bytes32(uint256(66));
        bytes32 commitment = core.computeCommitment(weightsHash, salt, address(validator), netuid, epoch);
        validator.commitWeights(core, netuid, commitment);

        vm.roll(block.number + 5);
        challenger.challengeExpiredCommit(core, netuid, epoch, address(validator));

        assert(core.challengeRewardOf(netuid, address(challenger)) == 0.02 ether);
        uint256 balanceBeforeClaim = address(challenger).balance;
        challenger.claimChallengeReward(core, netuid, 0.02 ether);
        assert(address(challenger).balance == balanceBeforeClaim + 0.02 ether);
        assert(core.challengeRewardOf(netuid, address(challenger)) == 0);
    }

    function testCannotClaimChallengeRewardAboveBalance() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 4);
        StakeActor validator = new StakeActor();
        vm.deal(address(validator), 10 ether);
        validator.addStake{value: 2 ether}(core, netuid);
        validator.registerValidator(core, netuid);

        uint64 epoch = core.currentEpoch(netuid);
        bytes32 weightsHash = keccak256(abi.encodePacked("challenge-overclaim"));
        bytes32 salt = bytes32(uint256(77));
        bytes32 commitment = core.computeCommitment(weightsHash, salt, address(validator), netuid, epoch);
        validator.commitWeights(core, netuid, commitment);

        vm.roll(block.number + 5);
        core.challengeExpiredCommit(netuid, epoch, address(validator));

        bool reverted = false;
        try core.claimChallengeReward(netuid, 0.03 ether) {}
        catch {
            reverted = true;
        }
        assert(reverted);
    }

    function testOnlyGovernanceCanQueueEmissionPayout() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        StakeActor governance = new StakeActor();
        StakeActor actor = new StakeActor();
        core.configureSubnetGovernance(netuid, address(governance), 2);

        bool reverted = false;
        try actor.queueSubnetEmissionPayout(core, netuid, address(actor), 1 ether) {}
        catch {
            reverted = true;
        }
        assert(reverted);
    }

    function testGovernanceCanPayoutEmissionAfterDelay() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        StakeActor governance = new StakeActor();
        StakeActor recipient = new StakeActor();
        core.configureSubnetGovernance(netuid, address(governance), 2);
        core.fundSubnetEmission{value: 1 ether}(netuid);

        governance.queueSubnetEmissionPayout(core, netuid, address(recipient), 0.4 ether);
        bool earlyReverted = false;
        try governance.payoutSubnetEmission(core, netuid, payable(address(recipient)), 0.4 ether) {}
        catch {
            earlyReverted = true;
        }
        assert(earlyReverted);

        vm.roll(block.number + 2);
        uint256 balanceBeforePayout = address(recipient).balance;
        governance.payoutSubnetEmission(core, netuid, payable(address(recipient)), 0.4 ether);
        assert(address(recipient).balance == balanceBeforePayout + 0.4 ether);
        assert(core.subnetEmissionPool(netuid) == 0.6 ether);
    }

    function testGovernanceCanPayoutDefaultEmissionSplit() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        StakeActor governance = new StakeActor();
        StakeActor validatorRecipient = new StakeActor();
        StakeActor minerRecipient = new StakeActor();
        StakeActor ownerRecipient = new StakeActor();
        core.configureSubnetGovernance(netuid, address(governance), 2);
        core.fundSubnetEmission{value: 1 ether}(netuid);

        governance.queueSubnetEmissionSplitPayout(
            core, netuid, address(validatorRecipient), address(minerRecipient), address(ownerRecipient), 1 ether
        );

        vm.roll(block.number + 2);
        uint256 validatorBefore = address(validatorRecipient).balance;
        uint256 minerBefore = address(minerRecipient).balance;
        uint256 ownerBefore = address(ownerRecipient).balance;

        governance.payoutSubnetEmissionSplit(
            core,
            netuid,
            payable(address(validatorRecipient)),
            payable(address(minerRecipient)),
            payable(address(ownerRecipient)),
            1 ether
        );

        (uint256 validatorAmount, uint256 minerAmount, uint256 ownerAmount) = core.quoteDefaultEmissionSplit(1 ether);
        assert(validatorAmount == 0.41 ether);
        assert(minerAmount == 0.41 ether);
        assert(ownerAmount == 0.18 ether);
        assert(address(validatorRecipient).balance == validatorBefore + validatorAmount);
        assert(address(minerRecipient).balance == minerBefore + minerAmount);
        assert(address(ownerRecipient).balance == ownerBefore + ownerAmount);
        assert(core.subnetEmissionPool(netuid) == 0);
    }

    function testInvalidMechanismIdRevertsOnFunding() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        uint16 invalidMechid = uint16(core.MAX_MECHANISM_ID() + 1);

        bool reverted = false;
        try core.fundMechanismEmission{value: 1 ether}(netuid, invalidMechid) {}
        catch {
            reverted = true;
        }
        assert(reverted);
    }

    function testOnlyGovernanceCanQueueMechanismEmissionPayout() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        StakeActor governance = new StakeActor();
        StakeActor actor = new StakeActor();
        core.configureSubnetGovernance(netuid, address(governance), 2);

        bool reverted = false;
        try actor.queueMechanismEmissionPayout(core, netuid, 1, address(actor), 1 ether) {}
        catch {
            reverted = true;
        }
        assert(reverted);
    }

    function testGovernanceCanPayoutMechanismEmissionAfterDelay() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        StakeActor governance = new StakeActor();
        StakeActor recipient = new StakeActor();
        core.configureSubnetGovernance(netuid, address(governance), 2);
        core.fundMechanismEmission{value: 1 ether}(netuid, 1);
        core.fundMechanismEmission{value: 0.5 ether}(netuid, 2);

        governance.queueMechanismEmissionPayout(core, netuid, 1, address(recipient), 0.4 ether);
        bool earlyReverted = false;
        try governance.payoutMechanismEmission(core, netuid, 1, payable(address(recipient)), 0.4 ether) {}
        catch {
            earlyReverted = true;
        }
        assert(earlyReverted);

        vm.roll(block.number + 2);
        uint256 balanceBeforePayout = address(recipient).balance;
        governance.payoutMechanismEmission(core, netuid, 1, payable(address(recipient)), 0.4 ether);
        assert(address(recipient).balance == balanceBeforePayout + 0.4 ether);
        assert(core.mechanismEmissionPool(netuid, 1) == 0.6 ether);
        assert(core.mechanismEmissionPool(netuid, 2) == 0.5 ether);
        assert(core.subnetEmissionPool(netuid) == 0);
    }

    function testGovernanceCanPayoutMechanismEmissionSplit() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        StakeActor governance = new StakeActor();
        StakeActor validatorRecipient = new StakeActor();
        StakeActor minerRecipient = new StakeActor();
        StakeActor ownerRecipient = new StakeActor();
        core.configureSubnetGovernance(netuid, address(governance), 2);
        core.fundMechanismEmission{value: 1 ether}(netuid, 7);

        governance.queueMechanismEmissionSplitPayout(
            core, netuid, 7, address(validatorRecipient), address(minerRecipient), address(ownerRecipient), 1 ether
        );

        vm.roll(block.number + 2);
        uint256 validatorBefore = address(validatorRecipient).balance;
        uint256 minerBefore = address(minerRecipient).balance;
        uint256 ownerBefore = address(ownerRecipient).balance;

        governance.payoutMechanismEmissionSplit(
            core,
            netuid,
            7,
            payable(address(validatorRecipient)),
            payable(address(minerRecipient)),
            payable(address(ownerRecipient)),
            1 ether
        );

        (uint256 validatorAmount, uint256 minerAmount, uint256 ownerAmount) = core.quoteDefaultEmissionSplit(1 ether);
        assert(address(validatorRecipient).balance == validatorBefore + validatorAmount);
        assert(address(minerRecipient).balance == minerBefore + minerAmount);
        assert(address(ownerRecipient).balance == ownerBefore + ownerAmount);
        assert(core.mechanismEmissionPool(netuid, 7) == 0);
        assert(core.subnetEmissionPool(netuid) == 0);
    }

    function testOnlyGovernanceCanQueueEmissionScheduleUpdate() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        StakeActor governance = new StakeActor();
        StakeActor actor = new StakeActor();
        core.configureSubnetGovernance(netuid, address(governance), 2);

        bool reverted = false;
        try actor.queueSubnetEmissionScheduleUpdate(core, netuid, 1 ether, 0.2 ether, 2, 0) {}
        catch {
            reverted = true;
        }
        assert(reverted);
    }

    function testOnlyGovernanceCanQueueMechanismEmissionScheduleUpdate() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        StakeActor governance = new StakeActor();
        StakeActor actor = new StakeActor();
        core.configureSubnetGovernance(netuid, address(governance), 2);

        bool reverted = false;
        try actor.queueMechanismEmissionScheduleUpdate(core, netuid, 3, 1 ether, 0.2 ether, 2, 0) {}
        catch {
            reverted = true;
        }
        assert(reverted);
    }

    function testGovernanceCanConfigureEmissionScheduleAfterDelay() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        StakeActor governance = new StakeActor();
        core.configureSubnetGovernance(netuid, address(governance), 2);

        governance.queueSubnetEmissionScheduleUpdate(core, netuid, 1 ether, 0.125 ether, 2, 0);
        bool earlyReverted = false;
        try governance.configureSubnetEmissionSchedule(core, netuid, 1 ether, 0.125 ether, 2, 0) {}
        catch {
            earlyReverted = true;
        }
        assert(earlyReverted);

        vm.roll(block.number + 2);
        governance.configureSubnetEmissionSchedule(core, netuid, 1 ether, 0.125 ether, 2, 0);

        assert(core.subnetEpochEmissionBase(netuid) == 1 ether);
        assert(core.subnetEpochEmissionFloor(netuid) == 0.125 ether);
        assert(core.subnetEpochEmissionHalvingPeriod(netuid) == 2);
        assert(core.subnetEpochEmissionStart(netuid) == 0);
        assert(core.quoteSubnetEpochEmission(netuid, 0) == 1 ether);
        assert(core.quoteSubnetEpochEmission(netuid, 1) == 1 ether);
        assert(core.quoteSubnetEpochEmission(netuid, 2) == 0.5 ether);
        assert(core.quoteSubnetEpochEmission(netuid, 4) == 0.25 ether);
        assert(core.quoteSubnetEpochEmission(netuid, 8) == 0.125 ether);
    }

    function testInvalidEmissionScheduleReverts() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        StakeActor governance = new StakeActor();
        core.configureSubnetGovernance(netuid, address(governance), 2);

        bool floorAboveBaseReverted = false;
        try governance.queueSubnetEmissionScheduleUpdate(core, netuid, 0.5 ether, 1 ether, 2, 0) {}
        catch {
            floorAboveBaseReverted = true;
        }
        assert(floorAboveBaseReverted);

        bool zeroHalvingPeriodReverted = false;
        try governance.queueSubnetEmissionScheduleUpdate(core, netuid, 1 ether, 0.5 ether, 0, 0) {}
        catch {
            zeroHalvingPeriodReverted = true;
        }
        assert(zeroHalvingPeriodReverted);
    }

    function testGovernanceCanConfigureMechanismEmissionScheduleAfterDelay() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        uint16 mechid = 5;
        StakeActor governance = new StakeActor();
        core.configureSubnetGovernance(netuid, address(governance), 2);

        governance.queueMechanismEmissionScheduleUpdate(core, netuid, mechid, 1 ether, 0.125 ether, 2, 0);
        bool earlyReverted = false;
        try governance.configureMechanismEmissionSchedule(core, netuid, mechid, 1 ether, 0.125 ether, 2, 0) {}
        catch {
            earlyReverted = true;
        }
        assert(earlyReverted);

        vm.roll(block.number + 2);
        governance.configureMechanismEmissionSchedule(core, netuid, mechid, 1 ether, 0.125 ether, 2, 0);

        assert(core.mechanismEpochEmissionBase(netuid, mechid) == 1 ether);
        assert(core.mechanismEpochEmissionFloor(netuid, mechid) == 0.125 ether);
        assert(core.mechanismEpochEmissionHalvingPeriod(netuid, mechid) == 2);
        assert(core.mechanismEpochEmissionStart(netuid, mechid) == 0);
        assert(core.quoteMechanismEpochEmission(netuid, mechid, 0) == 1 ether);
        assert(core.quoteMechanismEpochEmission(netuid, mechid, 1) == 1 ether);
        assert(core.quoteMechanismEpochEmission(netuid, mechid, 2) == 0.5 ether);
        assert(core.quoteMechanismEpochEmission(netuid, mechid, 4) == 0.25 ether);
        assert(core.quoteMechanismEpochEmission(netuid, mechid, 8) == 0.125 ether);
    }

    function testInvalidMechanismEmissionScheduleReverts() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        uint16 mechid = 8;
        StakeActor governance = new StakeActor();
        core.configureSubnetGovernance(netuid, address(governance), 2);

        bool floorAboveBaseReverted = false;
        try governance.queueMechanismEmissionScheduleUpdate(core, netuid, mechid, 0.5 ether, 1 ether, 2, 0) {}
        catch {
            floorAboveBaseReverted = true;
        }
        assert(floorAboveBaseReverted);

        bool zeroHalvingPeriodReverted = false;
        try governance.queueMechanismEmissionScheduleUpdate(core, netuid, mechid, 1 ether, 0.5 ether, 0, 0) {}
        catch {
            zeroHalvingPeriodReverted = true;
        }
        assert(zeroHalvingPeriodReverted);
    }

    function testGovernanceCanPayoutEpochEmissionAfterDelay() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 4);
        StakeActor governance = new StakeActor();
        StakeActor validatorRecipient = new StakeActor();
        StakeActor minerRecipient = new StakeActor();
        StakeActor ownerRecipient = new StakeActor();
        core.configureSubnetGovernance(netuid, address(governance), 2);
        core.fundSubnetEmission{value: 5 ether}(netuid);

        governance.queueSubnetEmissionScheduleUpdate(core, netuid, 1 ether, 0.25 ether, 1, 0);
        vm.roll(block.number + 2);
        governance.configureSubnetEmissionSchedule(core, netuid, 1 ether, 0.25 ether, 1, 0);

        vm.roll(block.number + 8);
        uint64 current = core.currentEpoch(netuid);
        assert(current > 0);
        uint64 epochToPay = current - 1;
        uint256 totalAmount = core.quoteSubnetEpochEmission(netuid, epochToPay);
        assert(totalAmount > 0);

        (, uint64 readyAtBlock) = governance.queueSubnetEpochEmissionPayout(
            core, netuid, epochToPay, address(validatorRecipient), address(minerRecipient), address(ownerRecipient)
        );

        bool earlyReverted = false;
        try governance.payoutSubnetEpochEmission(
            core,
            netuid,
            epochToPay,
            payable(address(validatorRecipient)),
            payable(address(minerRecipient)),
            payable(address(ownerRecipient))
        ) {} catch {
            earlyReverted = true;
        }
        assert(earlyReverted);

        vm.roll(readyAtBlock);
        uint256 validatorBefore = address(validatorRecipient).balance;
        uint256 minerBefore = address(minerRecipient).balance;
        uint256 ownerBefore = address(ownerRecipient).balance;

        governance.payoutSubnetEpochEmission(
            core,
            netuid,
            epochToPay,
            payable(address(validatorRecipient)),
            payable(address(minerRecipient)),
            payable(address(ownerRecipient))
        );

        (uint256 validatorAmount, uint256 minerAmount, uint256 ownerAmount) =
            core.quoteDefaultEmissionSplit(totalAmount);
        assert(address(validatorRecipient).balance == validatorBefore + validatorAmount);
        assert(address(minerRecipient).balance == minerBefore + minerAmount);
        assert(address(ownerRecipient).balance == ownerBefore + ownerAmount);
        assert(core.subnetEpochEmissionPaid(netuid, epochToPay));

        bool doublePayReverted = false;
        try governance.payoutSubnetEpochEmission(
            core,
            netuid,
            epochToPay,
            payable(address(validatorRecipient)),
            payable(address(minerRecipient)),
            payable(address(ownerRecipient))
        ) {} catch {
            doublePayReverted = true;
        }
        assert(doublePayReverted);
    }

    function testEpochEmissionPayoutRequiresFinalizedEpoch() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 32);
        StakeActor governance = new StakeActor();
        StakeActor validatorRecipient = new StakeActor();
        StakeActor minerRecipient = new StakeActor();
        StakeActor ownerRecipient = new StakeActor();
        core.configureSubnetGovernance(netuid, address(governance), 2);
        core.fundSubnetEmission{value: 2 ether}(netuid);

        governance.queueSubnetEmissionScheduleUpdate(core, netuid, 1 ether, 0.25 ether, 2, 0);
        vm.roll(block.number + 2);
        governance.configureSubnetEmissionSchedule(core, netuid, 1 ether, 0.25 ether, 2, 0);

        uint64 current = core.currentEpoch(netuid);
        (, uint64 readyAtBlock) = governance.queueSubnetEpochEmissionPayout(
            core, netuid, current, address(validatorRecipient), address(minerRecipient), address(ownerRecipient)
        );
        vm.roll(readyAtBlock);

        bool reverted = false;
        try governance.payoutSubnetEpochEmission(
            core,
            netuid,
            current,
            payable(address(validatorRecipient)),
            payable(address(minerRecipient)),
            payable(address(ownerRecipient))
        ) {} catch {
            reverted = true;
        }
        assert(reverted);
    }

    function testGovernanceCanPayoutMechanismEpochEmissionAfterDelay() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 4);
        uint16 mechid = 9;
        StakeActor governance = new StakeActor();
        StakeActor validatorRecipient = new StakeActor();
        StakeActor minerRecipient = new StakeActor();
        StakeActor ownerRecipient = new StakeActor();
        core.configureSubnetGovernance(netuid, address(governance), 2);
        core.fundMechanismEmission{value: 5 ether}(netuid, mechid);
        core.fundMechanismEmission{value: 0.75 ether}(netuid, mechid + 1);

        governance.queueMechanismEmissionScheduleUpdate(core, netuid, mechid, 1 ether, 0.25 ether, 1, 0);
        vm.roll(block.number + 2);
        governance.configureMechanismEmissionSchedule(core, netuid, mechid, 1 ether, 0.25 ether, 1, 0);

        vm.roll(block.number + 8);
        uint64 current = core.currentEpoch(netuid);
        assert(current > 0);
        uint64 epochToPay = current - 1;
        uint256 totalAmount = core.quoteMechanismEpochEmission(netuid, mechid, epochToPay);
        assert(totalAmount > 0);

        (, uint64 readyAtBlock) = governance.queueMechanismEpochEmissionPayout(
            core,
            netuid,
            mechid,
            epochToPay,
            address(validatorRecipient),
            address(minerRecipient),
            address(ownerRecipient)
        );

        bool earlyReverted = false;
        try governance.payoutMechanismEpochEmission(
            core,
            netuid,
            mechid,
            epochToPay,
            payable(address(validatorRecipient)),
            payable(address(minerRecipient)),
            payable(address(ownerRecipient))
        ) {} catch {
            earlyReverted = true;
        }
        assert(earlyReverted);

        vm.roll(readyAtBlock);
        uint256 validatorBefore = address(validatorRecipient).balance;
        uint256 minerBefore = address(minerRecipient).balance;
        uint256 ownerBefore = address(ownerRecipient).balance;

        governance.payoutMechanismEpochEmission(
            core,
            netuid,
            mechid,
            epochToPay,
            payable(address(validatorRecipient)),
            payable(address(minerRecipient)),
            payable(address(ownerRecipient))
        );

        (uint256 validatorAmount, uint256 minerAmount, uint256 ownerAmount) =
            core.quoteDefaultEmissionSplit(totalAmount);
        assert(address(validatorRecipient).balance == validatorBefore + validatorAmount);
        assert(address(minerRecipient).balance == minerBefore + minerAmount);
        assert(address(ownerRecipient).balance == ownerBefore + ownerAmount);
        assert(core.mechanismEpochEmissionPaid(netuid, mechid, epochToPay));
        assert(core.mechanismEmissionPool(netuid, mechid) == 5 ether - totalAmount);
        assert(core.mechanismEmissionPool(netuid, mechid + 1) == 0.75 ether);
        assert(core.subnetEmissionPool(netuid) == 0);

        bool doublePayReverted = false;
        try governance.payoutMechanismEpochEmission(
            core,
            netuid,
            mechid,
            epochToPay,
            payable(address(validatorRecipient)),
            payable(address(minerRecipient)),
            payable(address(ownerRecipient))
        ) {} catch {
            doublePayReverted = true;
        }
        assert(doublePayReverted);
    }

    function testMechanismEpochEmissionPayoutRequiresFinalizedEpoch() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 32);
        uint16 mechid = 6;
        StakeActor governance = new StakeActor();
        StakeActor validatorRecipient = new StakeActor();
        StakeActor minerRecipient = new StakeActor();
        StakeActor ownerRecipient = new StakeActor();
        core.configureSubnetGovernance(netuid, address(governance), 2);
        core.fundMechanismEmission{value: 2 ether}(netuid, mechid);

        governance.queueMechanismEmissionScheduleUpdate(core, netuid, mechid, 1 ether, 0.25 ether, 2, 0);
        vm.roll(block.number + 2);
        governance.configureMechanismEmissionSchedule(core, netuid, mechid, 1 ether, 0.25 ether, 2, 0);

        uint64 current = core.currentEpoch(netuid);
        (, uint64 readyAtBlock) = governance.queueMechanismEpochEmissionPayout(
            core, netuid, mechid, current, address(validatorRecipient), address(minerRecipient), address(ownerRecipient)
        );
        vm.roll(readyAtBlock);

        bool reverted = false;
        try governance.payoutMechanismEpochEmission(
            core,
            netuid,
            mechid,
            current,
            payable(address(validatorRecipient)),
            payable(address(minerRecipient)),
            payable(address(ownerRecipient))
        ) {} catch {
            reverted = true;
        }
        assert(reverted);
    }

    function testReentrancyIsBlockedOnWithdraw() public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        ReentrantWithdrawActor attacker = new ReentrantWithdrawActor();
        vm.deal(address(attacker), 10 ether);
        attacker.addStake{value: 2 ether}(core, netuid);

        attacker.attackWithdraw(core, netuid, 1 ether);

        assert(attacker.reenterAttempted());
        assert(attacker.reenterBlocked());
        assert(core.stakeOf(netuid, address(attacker)) == 1 ether);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PulseTensorCore} from "../src/PulseTensorCore.sol";

contract EchidnaStakeActor {
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

    function commitWeights(PulseTensorCore core, uint16 netuid, bytes32 commitment) external {
        core.commitWeights(netuid, commitment);
    }

    function revealWeights(PulseTensorCore core, uint16 netuid, uint64 epoch, bytes32 weightsHash, bytes32 salt)
        external
    {
        core.revealWeights(netuid, epoch, weightsHash, salt);
    }

    function challengeExpiredCommit(PulseTensorCore core, uint16 netuid, uint64 epoch, address validator) external {
        core.challengeExpiredCommit(netuid, epoch, validator);
    }

    receive() external payable {}
}

contract PulseTensorCoreEchidna {
    PulseTensorCore internal core;
    EchidnaStakeActor internal actorA;
    EchidnaStakeActor internal actorB;
    uint16 internal netuid;

    struct RevealPlan {
        uint64 epoch;
        bytes32 weightsHash;
        bytes32 salt;
        bool exists;
    }

    RevealPlan internal revealPlanA;
    RevealPlan internal revealPlanB;

    constructor() payable {
        core = new PulseTensorCore();
        netuid = core.createSubnet(8, 1 ether, 500, 2, 16);
        actorA = new EchidnaStakeActor();
        actorB = new EchidnaStakeActor();
    }

    function act_addStakeA(uint96 amountRaw) external {
        _actAddStake(actorA, amountRaw);
    }

    function act_addStakeB(uint96 amountRaw) external {
        _actAddStake(actorB, amountRaw);
    }

    function _actAddStake(EchidnaStakeActor actor, uint96 amountRaw) internal {
        uint256 amount = uint256(amountRaw) % 1 ether + 1;
        if (address(this).balance < amount) {
            return;
        }

        try actor.addStake{value: amount}(core, netuid) {} catch {}
    }

    function act_removeStakeA(uint96 amountRaw) external {
        _actRemoveStake(actorA, amountRaw);
    }

    function act_removeStakeB(uint96 amountRaw) external {
        _actRemoveStake(actorB, amountRaw);
    }

    function _actRemoveStake(EchidnaStakeActor actor, uint96 amountRaw) internal {
        uint256 currentStake = core.stakeOf(netuid, address(actor));
        uint256 lockedStake;
        if (core.isValidator(netuid, address(actor))) {
            (,,,,, lockedStake,) = core.subnets(netuid);
        }
        if (currentStake <= lockedStake) {
            return;
        }

        uint256 amount = uint256(amountRaw) % (currentStake - lockedStake) + 1;
        try actor.removeStake(core, netuid, amount) {} catch {}
    }

    function act_registerA() external {
        try actorA.registerValidator(core, netuid) {} catch {}
    }

    function act_registerB() external {
        try actorB.registerValidator(core, netuid) {} catch {}
    }

    function act_unregisterA() external {
        try actorA.unregisterValidator(core, netuid) {} catch {}
    }

    function act_unregisterB() external {
        try actorB.unregisterValidator(core, netuid) {} catch {}
    }

    function act_commitA(bytes32 seed) external {
        _actCommit(actorA, seed, true);
    }

    function act_commitB(bytes32 seed) external {
        _actCommit(actorB, seed, false);
    }

    function _actCommit(EchidnaStakeActor actor, bytes32 seed, bool isActorA) internal {
        if (!core.canValidate(netuid, address(actor)) || core.activeCommitEpoch(netuid, address(actor)) != 0) {
            return;
        }

        uint64 epoch = core.currentEpoch(netuid);
        bytes32 weightsHash = keccak256(abi.encode("echidna-weights", seed, address(actor), epoch));
        bytes32 salt = keccak256(abi.encode("echidna-salt", seed, address(actor), epoch));
        bytes32 commitment = keccak256(
            abi.encode(weightsHash, salt, address(actor), netuid, epoch, block.chainid, address(core), uint32(1))
        );

        try actor.commitWeights(core, netuid, commitment) {} catch {}

        if (core.activeCommitEpoch(netuid, address(actor)) == epoch + 1) {
            RevealPlan memory nextPlan = RevealPlan({epoch: epoch, weightsHash: weightsHash, salt: salt, exists: true});
            if (isActorA) {
                revealPlanA = nextPlan;
            } else {
                revealPlanB = nextPlan;
            }
        }
    }

    function act_revealA() external {
        _actReveal(actorA, true);
    }

    function act_revealB() external {
        _actReveal(actorB, false);
    }

    function _actReveal(EchidnaStakeActor actor, bool isActorA) internal {
        RevealPlan memory plan = isActorA ? revealPlanA : revealPlanB;
        if (!plan.exists) {
            return;
        }

        try actor.revealWeights(core, netuid, plan.epoch, plan.weightsHash, plan.salt) {
            if (isActorA) {
                delete revealPlanA;
            } else {
                delete revealPlanB;
            }
        } catch {}
    }

    function act_challengeA(bool targetActorA) external {
        _actChallenge(actorA, targetActorA);
    }

    function act_challengeB(bool targetActorA) external {
        _actChallenge(actorB, targetActorA);
    }

    function _actChallenge(EchidnaStakeActor challenger, bool targetActorA) internal {
        EchidnaStakeActor targetActor = targetActorA ? actorA : actorB;
        address target = address(targetActor);
        uint64 activeEpochPlusOne = core.activeCommitEpoch(netuid, target);
        if (activeEpochPlusOne == 0) {
            return;
        }

        uint64 epoch = activeEpochPlusOne - 1;
        try challenger.challengeExpiredCommit(core, netuid, epoch, target) {
            if (targetActorA) {
                delete revealPlanA;
            } else {
                delete revealPlanB;
            }
        } catch {}
    }

    function coreContract() external view returns (PulseTensorCore) {
        return core;
    }

    function actorAAddress() external view returns (address) {
        return address(actorA);
    }

    function actorBAddress() external view returns (address) {
        return address(actorB);
    }

    function subnetId() external view returns (uint16) {
        return netuid;
    }

    function plannedRevealA() external view returns (uint64 epoch, bytes32 weightsHash, bytes32 salt, bool exists) {
        RevealPlan memory plan = revealPlanA;
        return (plan.epoch, plan.weightsHash, plan.salt, plan.exists);
    }

    function plannedRevealB() external view returns (uint64 epoch, bytes32 weightsHash, bytes32 salt, bool exists) {
        RevealPlan memory plan = revealPlanB;
        return (plan.epoch, plan.weightsHash, plan.salt, plan.exists);
    }

    function echidna_total_stake_conserved() external view returns (bool) {
        (,,,,,, uint256 totalStake) = core.subnets(netuid);
        uint256 sumStake = core.stakeOf(netuid, address(actorA)) + core.stakeOf(netuid, address(actorB));
        return totalStake == sumStake;
    }

    function echidna_validator_count_within_bound() external view returns (bool) {
        (, uint16 maxValidators,,,,,) = core.subnets(netuid);
        return core.validatorCount(netuid) <= maxValidators;
    }

    function echidna_registered_validators_can_validate() external view returns (bool) {
        if (core.isValidator(netuid, address(actorA)) && !core.canValidate(netuid, address(actorA))) {
            return false;
        }
        if (core.isValidator(netuid, address(actorB)) && !core.canValidate(netuid, address(actorB))) {
            return false;
        }
        return true;
    }

    function echidna_pending_commitment_count_bounded() external view returns (bool) {
        if (core.pendingCommitmentCount(netuid, address(actorA)) > 1) {
            return false;
        }
        if (core.pendingCommitmentCount(netuid, address(actorB)) > 1) {
            return false;
        }
        return true;
    }

    function echidna_active_commit_epoch_consistent_with_pending_count() external view returns (bool) {
        uint64 activeA = core.activeCommitEpoch(netuid, address(actorA));
        uint64 activeB = core.activeCommitEpoch(netuid, address(actorB));
        uint256 pendingA = core.pendingCommitmentCount(netuid, address(actorA));
        uint256 pendingB = core.pendingCommitmentCount(netuid, address(actorB));

        if ((activeA == 0) != (pendingA == 0)) {
            return false;
        }
        if ((activeB == 0) != (pendingB == 0)) {
            return false;
        }
        return true;
    }

    receive() external payable {}
}

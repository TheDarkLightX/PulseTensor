// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PulseTensorCore} from "../../src/PulseTensorCore.sol";

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

    function revealWeights(PulseTensorCore core, uint16 netuid, uint64 epoch, bytes32 weightsHash, bytes32 salt) external {
        core.revealWeights(netuid, epoch, weightsHash, salt);
    }

    function challengeExpiredCommit(PulseTensorCore core, uint16 netuid, uint64 epoch, address validator) external {
        core.challengeExpiredCommit(netuid, epoch, validator);
    }
}

contract PulseTensorCoreEchidna {
    PulseTensorCore internal core;
    EchidnaStakeActor internal actorA;
    EchidnaStakeActor internal actorB;
    uint16 internal netuid;

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
        if (currentStake == 0) {
            return;
        }

        uint256 amount = uint256(amountRaw) % currentStake + 1;
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

    function act_commitA(bytes32 commitment) external {
        _actCommit(actorA, commitment);
    }

    function act_commitB(bytes32 commitment) external {
        _actCommit(actorB, commitment);
    }

    function _actCommit(EchidnaStakeActor actor, bytes32 commitment) internal {
        if (!core.canValidate(netuid, address(actor))) {
            return;
        }
        try actor.commitWeights(core, netuid, commitment) {} catch {}
    }

    function act_revealA(uint64 epoch, bytes32 weightsHash, bytes32 salt) external {
        _actReveal(actorA, epoch, weightsHash, salt);
    }

    function act_revealB(uint64 epoch, bytes32 weightsHash, bytes32 salt) external {
        _actReveal(actorB, epoch, weightsHash, salt);
    }

    function _actReveal(EchidnaStakeActor actor, uint64 epoch, bytes32 weightsHash, bytes32 salt) internal {
        try actor.revealWeights(core, netuid, epoch, weightsHash, salt) {} catch {}
    }

    function act_challengeA(uint64 epoch, bool targetActorA) external {
        address target = targetActorA ? address(actorA) : address(actorB);
        try actorA.challengeExpiredCommit(core, netuid, epoch, target) {} catch {}
    }

    function act_challengeB(uint64 epoch, bool targetActorA) external {
        address target = targetActorA ? address(actorA) : address(actorB);
        try actorB.challengeExpiredCommit(core, netuid, epoch, target) {} catch {}
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

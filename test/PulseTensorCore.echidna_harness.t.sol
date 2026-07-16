// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PulseTensorCore} from "../src/PulseTensorCore.sol";
import {PulseTensorCoreEchidna} from "../echidna/PulseTensorCoreEchidna.sol";

contract PulseTensorCoreEchidnaHarnessTest is Test {
    PulseTensorCoreEchidna internal harness;
    PulseTensorCore internal core;
    uint16 internal netuid;
    address internal actorA;
    address internal actorB;

    function setUp() public {
        vm.deal(address(this), 20 ether);
        harness = new PulseTensorCoreEchidna{value: 10 ether}();
        core = harness.coreContract();
        netuid = harness.subnetId();
        actorA = harness.actorAAddress();
        actorB = harness.actorBAddress();
    }

    function test_AddAndRemoveActionsReachStateChangesForBothActors() public {
        harness.act_addStakeA(uint96(1 ether - 1));
        harness.act_addStakeB(uint96(1 ether - 1));
        assertEq(core.stakeOf(netuid, actorA), 1 ether);
        assertEq(core.stakeOf(netuid, actorB), 1 ether);

        harness.act_removeStakeA(0);
        harness.act_removeStakeB(1);

        assertEq(core.stakeOf(netuid, actorA), 1 ether - 1);
        assertEq(core.stakeOf(netuid, actorB), 1 ether - 2);
        assertEq(actorA.balance, 1);
        assertEq(actorB.balance, 2);
        _assertHarnessProperties();
    }

    function test_RegisterAndUnregisterActionsReachStateChangesForBothActors() public {
        _stakeBothActors();

        harness.act_registerA();
        harness.act_registerB();
        assertTrue(core.isValidator(netuid, actorA));
        assertTrue(core.isValidator(netuid, actorB));

        harness.act_unregisterA();
        harness.act_unregisterB();
        assertFalse(core.isValidator(netuid, actorA));
        assertFalse(core.isValidator(netuid, actorB));
        _assertHarnessProperties();
    }

    function test_CommitAndRevealActionsReachValidStateChangesForBothActors() public {
        _stakeAndRegisterBothActors();

        harness.act_commitA(keccak256("actor-a-seed"));
        harness.act_commitB(keccak256("actor-b-seed"));

        (uint64 epochA, bytes32 weightsHashA,, bool planAExists) = harness.plannedRevealA();
        (uint64 epochB, bytes32 weightsHashB,, bool planBExists) = harness.plannedRevealB();
        assertTrue(planAExists);
        assertTrue(planBExists);
        assertEq(core.activeCommitEpoch(netuid, actorA), epochA + 1);
        assertEq(core.activeCommitEpoch(netuid, actorB), epochB + 1);

        (, uint64 revealAtA,) = core.epochCommitments(netuid, epochA, actorA);
        (, uint64 revealAtB,) = core.epochCommitments(netuid, epochB, actorB);
        vm.roll(revealAtA > revealAtB ? revealAtA : revealAtB);

        harness.act_revealA();
        harness.act_revealB();

        assertTrue(core.epochRevealed(netuid, epochA, actorA));
        assertTrue(core.epochRevealed(netuid, epochB, actorB));
        assertEq(core.epochRevealedWeightsHash(netuid, epochA, actorA), weightsHashA);
        assertEq(core.epochRevealedWeightsHash(netuid, epochB, actorB), weightsHashB);
        assertEq(core.pendingCommitmentCount(netuid, actorA), 0);
        assertEq(core.pendingCommitmentCount(netuid, actorB), 0);
        _assertHarnessProperties();
    }

    function test_ChallengeActionsReachExpiredCommitStateChangesForBothActors() public {
        _stakeAndRegisterBothActors();
        harness.act_commitA(keccak256("expired-a"));
        harness.act_commitB(keccak256("expired-b"));

        (uint64 epochA,,, bool planAExists) = harness.plannedRevealA();
        (uint64 epochB,,, bool planBExists) = harness.plannedRevealB();
        assertTrue(planAExists);
        assertTrue(planBExists);
        (,, uint64 expireAtA) = core.epochCommitments(netuid, epochA, actorA);
        (,, uint64 expireAtB) = core.epochCommitments(netuid, epochB, actorB);
        uint64 latestExpiry = expireAtA > expireAtB ? expireAtA : expireAtB;
        vm.roll(uint256(latestExpiry) + 1);

        harness.act_challengeA(false);
        harness.act_challengeB(true);

        assertEq(core.activeCommitEpoch(netuid, actorA), 0);
        assertEq(core.activeCommitEpoch(netuid, actorB), 0);
        assertEq(core.pendingCommitmentCount(netuid, actorA), 0);
        assertEq(core.pendingCommitmentCount(netuid, actorB), 0);
        assertGt(core.challengeRewardOf(netuid, actorA), 0);
        assertGt(core.challengeRewardOf(netuid, actorB), 0);
        _assertHarnessProperties();
    }

    function _stakeBothActors() internal {
        harness.act_addStakeA(uint96(1 ether - 1));
        harness.act_addStakeB(uint96(1 ether - 1));
    }

    function _stakeAndRegisterBothActors() internal {
        _stakeBothActors();
        harness.act_registerA();
        harness.act_registerB();
        assertTrue(core.canValidate(netuid, actorA));
        assertTrue(core.canValidate(netuid, actorB));
    }

    function _assertHarnessProperties() internal view {
        assertTrue(harness.echidna_stake_and_native_liabilities_conserved());
        assertTrue(harness.echidna_validator_count_exact_and_bounded());
        assertTrue(harness.echidna_registered_validators_can_validate());
        assertTrue(harness.echidna_pending_commitment_count_bounded());
        assertTrue(harness.echidna_active_commit_epoch_consistent_with_pending_count());
    }
}

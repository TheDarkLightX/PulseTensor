// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PulseTensorCore} from "../src/PulseTensorCore.sol";
import {PulseTensorDomain} from "../src/core/PulseTensorDomain.sol";

contract PulseTensorCoreFuzzTest is Test {
    PulseTensorCore internal core;
    address internal constant VALIDATOR = address(0xBEEF);

    function setUp() public {
        core = new PulseTensorCore();
        vm.deal(address(this), 1_000 ether);
    }

    function _computeCommitment(bytes32 weightsHash, bytes32 salt, address validator, uint16 netuid, uint64 epoch)
        internal
        view
        returns (bytes32)
    {
        return keccak256(abi.encode(weightsHash, salt, validator, netuid, epoch, block.chainid, address(core), 1));
    }

    function _computeMechanismCommitment(
        bytes32 weightsHash,
        bytes32 salt,
        address validator,
        uint16 netuid,
        uint16 mechid,
        uint64 epoch
    ) internal view returns (bytes32) {
        return keccak256(
            abi.encode(weightsHash, salt, validator, netuid, mechid, epoch, block.chainid, address(core), 1)
        );
    }

    function _quoteDefaultEmissionSplit(uint256 totalAmount)
        internal
        pure
        returns (uint256 validatorAmount, uint256 minerAmount, uint256 ownerAmount)
    {
        validatorAmount = (totalAmount * 4_100) / 10_000;
        minerAmount = (totalAmount * 4_100) / 10_000;
        ownerAmount = totalAmount - validatorAmount - minerAmount;
    }

    function testFuzz_StakeAccountingRemainsConservative(uint96 addAmountRaw, uint96 removeAmountRaw) public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        vm.deal(VALIDATOR, 1_000 ether);

        uint256 addAmount = bound(uint256(addAmountRaw), 1, 100 ether);
        vm.prank(VALIDATOR);
        core.addStake{value: addAmount}(netuid);

        (,,,,,, uint256 totalAfterAdd) = core.subnets(netuid);
        assertEq(totalAfterAdd, addAmount);
        assertEq(core.stakeOf(netuid, VALIDATOR), addAmount);

        uint256 removeAmount = bound(uint256(removeAmountRaw), 1, addAmount);
        vm.prank(VALIDATOR);
        core.removeStake(netuid, removeAmount);

        (,,,,,, uint256 totalAfterRemove) = core.subnets(netuid);
        assertEq(totalAfterRemove, addAmount - removeAmount);
        assertEq(core.stakeOf(netuid, VALIDATOR), addAmount - removeAmount);
    }

    function testFuzz_ValidatorWithdrawEnforcesMinimumStake(
        uint96 minStakeRaw,
        uint96 extraStakeRaw,
        uint96 withdrawalRaw
    ) public {
        uint256 minStake = bound(uint256(minStakeRaw), 1 ether, 10 ether);
        uint16 netuid = core.createSubnet(64, minStake, 500, 2, 16);
        vm.deal(VALIDATOR, 1_000 ether);

        uint256 extraStake = bound(uint256(extraStakeRaw), 0, 10 ether);
        uint256 initialStake = minStake + extraStake;
        vm.prank(VALIDATOR);
        core.addStake{value: initialStake}(netuid);
        vm.prank(VALIDATOR);
        core.registerValidator(netuid);

        uint256 withdrawal = bound(uint256(withdrawalRaw), 1, initialStake);
        bool shouldRevert = initialStake - withdrawal < minStake;

        vm.prank(VALIDATOR);
        if (shouldRevert) {
            vm.expectRevert(PulseTensorCore.StakeBelowValidatorMinimum.selector);
            core.removeStake(netuid, withdrawal);
            assertEq(core.stakeOf(netuid, VALIDATOR), initialStake);
        } else {
            core.removeStake(netuid, withdrawal);
            assertEq(core.stakeOf(netuid, VALIDATOR), initialStake - withdrawal);
        }
    }

    function testFuzz_CommitRevealIsBoundToEpochSaltAndValidator(
        bytes32 weightsHash,
        bytes32 salt,
        bytes32 wrongSalt,
        uint64 revealDelayRaw
    ) public {
        vm.assume(wrongSalt != salt);
        uint64 revealDelayBlocks = uint64(bound(uint256(revealDelayRaw), 1, 10));
        uint64 epochLengthBlocks = revealDelayBlocks + 12;
        uint16 netuid = core.createSubnet(64, 1 ether, 500, revealDelayBlocks, epochLengthBlocks);
        vm.deal(VALIDATOR, 1_000 ether);

        vm.prank(VALIDATOR);
        core.addStake{value: 1 ether}(netuid);
        vm.prank(VALIDATOR);
        core.registerValidator(netuid);

        uint64 epoch = core.currentEpoch(netuid);
        bytes32 commitment = _computeCommitment(weightsHash, salt, VALIDATOR, netuid, epoch);
        vm.prank(VALIDATOR);
        core.commitWeights(netuid, commitment);

        vm.roll(block.number + revealDelayBlocks - 1);
        vm.prank(VALIDATOR);
        vm.expectRevert(PulseTensorDomain.RevealTooEarly.selector);
        core.revealWeights(netuid, epoch, weightsHash, salt);

        vm.roll(block.number + 1);
        vm.prank(VALIDATOR);
        vm.expectRevert(PulseTensorDomain.CommitmentMismatch.selector);
        core.revealWeights(netuid, epoch, weightsHash, wrongSalt);

        vm.prank(VALIDATOR);
        core.revealWeights(netuid, epoch, weightsHash, salt);
        assertTrue(core.epochRevealed(netuid, epoch, VALIDATOR));
    }

    function testFuzz_MechanismCommitRevealIsBoundToEpochSaltValidatorAndMechid(
        bytes32 weightsHash,
        bytes32 salt,
        bytes32 wrongSalt,
        uint16 mechidRaw,
        uint64 revealDelayRaw
    ) public {
        vm.assume(wrongSalt != salt);
        uint16 mechid = uint16(bound(uint256(mechidRaw), 0, core.MAX_MECHANISM_ID()));
        uint64 revealDelayBlocks = uint64(bound(uint256(revealDelayRaw), 1, 10));
        uint64 epochLengthBlocks = revealDelayBlocks + 12;
        uint16 netuid = core.createSubnet(64, 1 ether, 500, revealDelayBlocks, epochLengthBlocks);
        vm.deal(VALIDATOR, 1_000 ether);

        vm.prank(VALIDATOR);
        core.addStake{value: 1 ether}(netuid);
        vm.prank(VALIDATOR);
        core.registerValidator(netuid);

        uint64 epoch = core.currentEpoch(netuid);
        bytes32 commitment = _computeMechanismCommitment(weightsHash, salt, VALIDATOR, netuid, mechid, epoch);
        vm.prank(VALIDATOR);
        core.commitMechanismWeights(netuid, mechid, commitment);

        vm.roll(block.number + revealDelayBlocks - 1);
        vm.prank(VALIDATOR);
        vm.expectRevert(PulseTensorDomain.RevealTooEarly.selector);
        core.revealMechanismWeights(netuid, mechid, epoch, weightsHash, salt);

        vm.roll(block.number + 1);
        vm.prank(VALIDATOR);
        vm.expectRevert(PulseTensorDomain.CommitmentMismatch.selector);
        core.revealMechanismWeights(netuid, mechid, epoch, weightsHash, wrongSalt);

        vm.prank(VALIDATOR);
        core.revealMechanismWeights(netuid, mechid, epoch, weightsHash, salt);
        assertTrue(core.mechanismEpochRevealed(netuid, mechid, epoch, VALIDATOR));
    }

    function testFuzz_PendingCommitmentLocksStakeUntilReveal(
        bytes32 weightsHash,
        bytes32 salt,
        uint64 revealDelayRaw,
        uint96 stakeRaw,
        uint96 withdrawalRaw
    ) public {
        uint64 revealDelayBlocks = uint64(bound(uint256(revealDelayRaw), 1, 10));
        uint64 epochLengthBlocks = revealDelayBlocks + 12;
        uint16 netuid = core.createSubnet(64, 1 ether, 500, revealDelayBlocks, epochLengthBlocks);
        vm.deal(VALIDATOR, 1_000 ether);

        uint256 initialStake = bound(uint256(stakeRaw), 2 ether, 100 ether);
        vm.prank(VALIDATOR);
        core.addStake{value: initialStake}(netuid);
        vm.prank(VALIDATOR);
        core.registerValidator(netuid);

        uint64 epoch = core.currentEpoch(netuid);
        bytes32 commitment = _computeCommitment(weightsHash, salt, VALIDATOR, netuid, epoch);
        vm.prank(VALIDATOR);
        core.commitWeights(netuid, commitment);

        uint256 withdrawal = bound(uint256(withdrawalRaw), 1, initialStake - 1 ether);
        vm.prank(VALIDATOR);
        vm.expectRevert(PulseTensorCore.PendingCommitmentExists.selector);
        core.removeStake(netuid, withdrawal);
        assertEq(core.stakeOf(netuid, VALIDATOR), initialStake);

        vm.roll(block.number + revealDelayBlocks);
        vm.prank(VALIDATOR);
        core.revealWeights(netuid, epoch, weightsHash, salt);

        vm.prank(VALIDATOR);
        core.removeStake(netuid, withdrawal);
        assertEq(core.stakeOf(netuid, VALIDATOR), initialStake - withdrawal);
    }

    function testFuzz_CommitLifecycleMaintainsActiveEpochAndPendingCount(
        bytes32 weightsHash,
        bytes32 salt,
        uint64 revealDelayRaw,
        bool resolveByChallenge
    ) public {
        uint64 revealDelayBlocks = uint64(bound(uint256(revealDelayRaw), 1, 10));
        uint64 epochLengthBlocks = revealDelayBlocks + 12;
        uint16 netuid = core.createSubnet(64, 1 ether, 500, revealDelayBlocks, epochLengthBlocks);
        vm.deal(VALIDATOR, 1_000 ether);

        vm.prank(VALIDATOR);
        core.addStake{value: 1 ether}(netuid);
        vm.prank(VALIDATOR);
        core.registerValidator(netuid);

        uint64 epoch = core.currentEpoch(netuid);
        bytes32 commitment = _computeCommitment(weightsHash, salt, VALIDATOR, netuid, epoch);
        if (commitment == bytes32(0)) {
            return;
        }

        vm.prank(VALIDATOR);
        core.commitWeights(netuid, commitment);
        assertEq(core.activeCommitEpoch(netuid, VALIDATOR), epoch + 1);
        assertEq(core.pendingCommitmentCount(netuid, VALIDATOR), 1);

        if (resolveByChallenge) {
            vm.roll(block.number + revealDelayBlocks + 12);
            core.challengeExpiredCommit(netuid, epoch, VALIDATOR);
        } else {
            vm.roll(block.number + revealDelayBlocks);
            vm.prank(VALIDATOR);
            core.revealWeights(netuid, epoch, weightsHash, salt);
        }

        assertEq(core.activeCommitEpoch(netuid, VALIDATOR), 0);
        assertEq(core.pendingCommitmentCount(netuid, VALIDATOR), 0);
    }

    function testFuzz_ChallengeExpiredCommitSlashesBoundedAmount(uint96 initialStakeRaw) public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 4);
        uint256 initialStake = bound(uint256(initialStakeRaw), 1 ether, 100 ether);
        vm.deal(VALIDATOR, 1_000 ether);

        vm.prank(VALIDATOR);
        core.addStake{value: initialStake}(netuid);
        vm.prank(VALIDATOR);
        core.registerValidator(netuid);

        uint64 epoch = core.currentEpoch(netuid);
        bytes32 weightsHash = keccak256(abi.encodePacked("challenge-fuzz"));
        bytes32 salt = bytes32(uint256(7));
        bytes32 commitment = _computeCommitment(weightsHash, salt, VALIDATOR, netuid, epoch);
        vm.prank(VALIDATOR);
        core.commitWeights(netuid, commitment);

        vm.roll(block.number + 5);
        (uint256 slashedAmount,) = core.challengeExpiredCommit(netuid, epoch, VALIDATOR);

        assertGt(slashedAmount, 0);
        assertLe(slashedAmount, initialStake);
        assertEq(core.stakeOf(netuid, VALIDATOR), initialStake - slashedAmount);
        assertEq(core.challengeRewardOf(netuid, address(this)) + core.subnetEmissionPool(netuid), slashedAmount);
    }

    function testFuzz_SelfChallengeRoutesFullSlashToPool(uint96 initialStakeRaw) public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 4);
        uint256 initialStake = bound(uint256(initialStakeRaw), 1 ether, 100 ether);
        vm.deal(VALIDATOR, 1_000 ether);

        vm.prank(VALIDATOR);
        core.addStake{value: initialStake}(netuid);
        vm.prank(VALIDATOR);
        core.registerValidator(netuid);

        uint64 epoch = core.currentEpoch(netuid);
        bytes32 weightsHash = keccak256(abi.encodePacked("self-challenge-fuzz"));
        bytes32 salt = bytes32(uint256(7));
        bytes32 commitment = _computeCommitment(weightsHash, salt, VALIDATOR, netuid, epoch);
        vm.prank(VALIDATOR);
        core.commitWeights(netuid, commitment);

        vm.roll(block.number + 5);
        vm.prank(VALIDATOR);
        (uint256 slashedAmount,) = core.challengeExpiredCommit(netuid, epoch, VALIDATOR);

        assertGt(slashedAmount, 0);
        assertEq(core.challengeRewardOf(netuid, VALIDATOR), 0);
        assertEq(core.subnetEmissionPool(netuid), slashedAmount);
    }

    function testFuzz_DefaultEmissionSplitConservesTotal(uint96 totalRaw) public pure {
        uint256 totalAmount = bound(uint256(totalRaw), 1, 1_000 ether);
        (uint256 validatorAmount, uint256 minerAmount, uint256 ownerAmount) =
            _quoteDefaultEmissionSplit(totalAmount);
        assertEq(validatorAmount + minerAmount + ownerAmount, totalAmount);
    }

    function testFuzz_MechanismEmissionPoolAccounting(uint16 mechidRaw, uint96 fundRaw, uint96 payoutRaw) public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        core.configureSubnetGovernance(netuid, address(this), 2);

        uint16 mechid = uint16(bound(uint256(mechidRaw), 0, core.MAX_MECHANISM_ID()));
        uint256 fundAmount = bound(uint256(fundRaw), 1, 100 ether);
        uint256 payoutAmount = bound(uint256(payoutRaw), 1, fundAmount);

        core.fundMechanismEmission{value: fundAmount}(netuid, mechid);
        core.queueMechanismEmissionPayout(netuid, mechid, VALIDATOR, payoutAmount);

        vm.roll(block.number + 2);
        core.payoutMechanismEmission(netuid, mechid, payable(VALIDATOR), payoutAmount);

        assertEq(core.mechanismEmissionPool(netuid, mechid), fundAmount - payoutAmount);
    }

    function testFuzz_MechanismEpochEmissionQuoteRespectsBounds(
        uint16 mechidRaw,
        uint96 baseRaw,
        uint96 floorRaw,
        uint64 halvingRaw,
        uint64 startRaw,
        uint64 epochRaw
    ) public {
        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        core.configureSubnetGovernance(netuid, address(this), 2);

        uint16 mechid = uint16(bound(uint256(mechidRaw), 0, core.MAX_MECHANISM_ID()));
        uint256 baseAmount = bound(uint256(baseRaw), 1, 50 ether);
        uint256 floorAmount = bound(uint256(floorRaw), 0, baseAmount);
        uint64 halvingPeriod = uint64(bound(uint256(halvingRaw), 1, 32));
        uint64 startEpoch = uint64(bound(uint256(startRaw), 0, 100));
        uint64 epoch = uint64(bound(uint256(epochRaw), 0, 200));

        core.queueMechanismEmissionScheduleUpdate(netuid, mechid, baseAmount, floorAmount, halvingPeriod, startEpoch);
        vm.roll(block.number + 2);
        core.configureMechanismEmissionSchedule(netuid, mechid, baseAmount, floorAmount, halvingPeriod, startEpoch);

        uint256 quoteAmount = core.quoteMechanismEpochEmission(netuid, mechid, epoch);
        if (epoch < startEpoch) {
            assertEq(quoteAmount, 0);
        } else {
            assertLe(quoteAmount, baseAmount);
            assertGe(quoteAmount, floorAmount);
        }
    }
}

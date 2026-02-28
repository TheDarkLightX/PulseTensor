// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PulseTensorDomain} from "../src/core/PulseTensorDomain.sol";

contract PulseTensorDomainHarness {
    function validateSubnetConfig(
        uint16 maxValidators,
        uint16 ownerFeeBps,
        uint64 revealDelayBlocks,
        uint64 epochLengthBlocks
    ) external pure {
        PulseTensorDomain.validateSubnetConfig(maxValidators, ownerFeeBps, revealDelayBlocks, epochLengthBlocks);
    }

    function addStake(uint256 currentStake, uint256 totalStake, uint256 amount)
        external
        pure
        returns (uint256 newStake, uint256 newTotalStake)
    {
        return PulseTensorDomain.addStake(currentStake, totalStake, amount);
    }

    function removeStake(uint256 currentStake, uint256 totalStake, uint256 amount)
        external
        pure
        returns (uint256 newStake, uint256 newTotalStake)
    {
        return PulseTensorDomain.removeStake(currentStake, totalStake, amount);
    }

    function scheduleCommit(
        PulseTensorDomain.PendingCommitment memory pending,
        bytes32 commitment,
        uint256 currentBlock,
        uint64 revealDelayBlocks,
        uint64 expireAtBlock
    ) external pure returns (PulseTensorDomain.PendingCommitment memory nextPending) {
        return PulseTensorDomain.scheduleCommit(pending, commitment, currentBlock, revealDelayBlocks, expireAtBlock);
    }

    function verifyReveal(
        PulseTensorDomain.PendingCommitment memory pending,
        uint256 currentBlock,
        bytes32 weightsHash,
        bytes32 salt,
        address validator,
        uint16 netuid,
        uint64 epoch,
        uint256 domainChainId,
        address domainContract,
        uint32 domainVersion
    ) external pure {
        PulseTensorDomain.verifyReveal(
            pending,
            currentBlock,
            weightsHash,
            salt,
            validator,
            netuid,
            epoch,
            domainChainId,
            domainContract,
            domainVersion
        );
    }

    function computeCommitment(
        bytes32 weightsHash,
        bytes32 salt,
        address validator,
        uint16 netuid,
        uint64 epoch,
        uint256 domainChainId,
        address domainContract,
        uint32 domainVersion
    ) external pure returns (bytes32) {
        return PulseTensorDomain.computeCommitment(
            weightsHash, salt, validator, netuid, epoch, domainChainId, domainContract, domainVersion
        );
    }

    function verifyExpiredCommitment(PulseTensorDomain.PendingCommitment memory pending, uint256 currentBlock)
        external
        pure
    {
        PulseTensorDomain.verifyExpiredCommitment(pending, currentBlock);
    }

    function slashStakeByBps(uint256 currentStake, uint256 totalStake, uint16 slashBps)
        external
        pure
        returns (uint256 newStake, uint256 newTotalStake, uint256 slashedAmount)
    {
        return PulseTensorDomain.slashStakeByBps(currentStake, totalStake, slashBps);
    }
}

contract PulseTensorDomainTest {
    PulseTensorDomainHarness internal harness;

    function setUp() public {
        harness = new PulseTensorDomainHarness();
    }

    function testValidateSubnetConfigRejectsInvalidValues() public view {
        bool reverted = false;
        try harness.validateSubnetConfig(0, 100, 2, 16) {}
        catch {
            reverted = true;
        }
        assert(reverted);

        reverted = false;
        try harness.validateSubnetConfig(32, 2501, 2, 16) {}
        catch {
            reverted = true;
        }
        assert(reverted);

        reverted = false;
        try harness.validateSubnetConfig(32, 100, 0, 16) {}
        catch {
            reverted = true;
        }
        assert(reverted);

        reverted = false;
        try harness.validateSubnetConfig(32, 100, 2, 2) {}
        catch {
            reverted = true;
        }
        assert(reverted);
    }

    function testValidateSubnetConfigAcceptsBoundaryValues() public view {
        harness.validateSubnetConfig(1024, 2000, 20_000, 120_000);
        harness.validateSubnetConfig(1, 0, 1, 2);
    }

    function testAddAndRemoveStakeTransitions() public view {
        (uint256 stakeAfterAdd, uint256 totalAfterAdd) = harness.addStake(2 ether, 10 ether, 3 ether);
        assert(stakeAfterAdd == 5 ether);
        assert(totalAfterAdd == 13 ether);

        (uint256 stakeAfterRemove, uint256 totalAfterRemove) = harness.removeStake(5 ether, 13 ether, 2 ether);
        assert(stakeAfterRemove == 3 ether);
        assert(totalAfterRemove == 11 ether);
    }

    function testRemoveStakeRejectsOverdraw() public view {
        bool reverted = false;
        try harness.removeStake(1 ether, 1 ether, 2 ether) returns (uint256, uint256) {}
        catch {
            reverted = true;
        }
        assert(reverted);
    }

    function testCommitRevealChecks() public view {
        bytes32 weightsHash = keccak256(abi.encodePacked("weights-v2"));
        bytes32 salt = bytes32(uint256(5678));
        bytes32 commitment =
            harness.computeCommitment(weightsHash, salt, address(this), 1, 5, block.chainid, address(this), 1);

        PulseTensorDomain.PendingCommitment memory empty;
        PulseTensorDomain.PendingCommitment memory pending = harness.scheduleCommit(empty, commitment, 100, 2, 120);
        assert(pending.commitment == commitment);
        assert(pending.revealAtBlock == 102);
        assert(pending.expireAtBlock == 120);

        bool earlyReverted = false;
        try harness.verifyReveal(pending, 101, weightsHash, salt, address(this), 1, 5, block.chainid, address(this), 1)
        {} catch {
            earlyReverted = true;
        }
        assert(earlyReverted);

        harness.verifyReveal(pending, 102, weightsHash, salt, address(this), 1, 5, block.chainid, address(this), 1);

        bool expiredReverted = false;
        try harness.verifyReveal(pending, 121, weightsHash, salt, address(this), 1, 5, block.chainid, address(this), 1)
        {} catch {
            expiredReverted = true;
        }
        assert(expiredReverted);

        bool windowClosedReverted = false;
        try harness.scheduleCommit(empty, commitment, 100, 30, 120) returns (PulseTensorDomain.PendingCommitment memory)
        {} catch {
            windowClosedReverted = true;
        }
        assert(windowClosedReverted);
    }

    function testExpiredCommitAndSlashChecks() public view {
        PulseTensorDomain.PendingCommitment memory pending =
            PulseTensorDomain.PendingCommitment({commitment: bytes32(uint256(1)), revealAtBlock: 10, expireAtBlock: 20});

        bool notExpiredReverted = false;
        try harness.verifyExpiredCommitment(pending, 20) {}
        catch {
            notExpiredReverted = true;
        }
        assert(notExpiredReverted);

        harness.verifyExpiredCommitment(pending, 21);

        (uint256 newStake, uint256 newTotalStake, uint256 slashedAmount) =
            harness.slashStakeByBps(2 ether, 2 ether, 500);
        assert(slashedAmount == 0.1 ether);
        assert(newStake == 1.9 ether);
        assert(newTotalStake == 1.9 ether);
    }

    function testSlashStakeByBpsBoundaryValues() public view {
        bool reverted = false;
        try harness.slashStakeByBps(1 ether, 1 ether, 0) returns (uint256, uint256, uint256) {}
        catch {
            reverted = true;
        }
        assert(reverted);

        reverted = false;
        try harness.slashStakeByBps(1 ether, 1 ether, 10_001) returns (uint256, uint256, uint256) {}
        catch {
            reverted = true;
        }
        assert(reverted);

        (uint256 newStake, uint256 newTotalStake, uint256 slashedAmount) =
            harness.slashStakeByBps(1 ether, 1 ether, 10_000);
        assert(slashedAmount == 1 ether);
        assert(newStake == 0);
        assert(newTotalStake == 0);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library PulseTensorDomain {
    uint16 internal constant BPS_DENOMINATOR = 10_000;
    uint16 internal constant MAX_VALIDATORS_LIMIT = 1024;
    uint16 internal constant MAX_OWNER_FEE_BPS = 2_000;
    uint64 internal constant MAX_REVEAL_DELAY_BLOCKS = 20_000;
    uint64 internal constant MAX_EPOCH_LENGTH_BLOCKS = 120_000;

    error InvalidConfig();
    error ZeroAmount();
    error InsufficientStake();
    error InvalidCommitment();
    error CommitmentExists();
    error CommitmentMissing();
    error RevealTooEarly();
    error RevealExpired();
    error CommitmentMismatch();
    error CommitmentWindowClosed();
    error CommitmentExpiredNeedsChallenge();
    error CommitmentNotExpired();
    error InvalidSlashBps();

    struct SubnetConfig {
        bool exists;
        uint16 maxValidators;
        uint16 ownerFeeBps;
        uint64 revealDelayBlocks;
        uint64 epochLengthBlocks;
        uint256 minValidatorStake;
        uint256 totalStake;
    }

    struct PendingCommitment {
        bytes32 commitment;
        uint64 revealAtBlock;
        uint64 expireAtBlock;
    }

    function validateSubnetConfig(
        uint16 maxValidators,
        uint16 ownerFeeBps,
        uint64 revealDelayBlocks,
        uint64 epochLengthBlocks
    ) internal pure {
        if (
            maxValidators == 0 || maxValidators > MAX_VALIDATORS_LIMIT || ownerFeeBps > MAX_OWNER_FEE_BPS
                || revealDelayBlocks == 0 || revealDelayBlocks > MAX_REVEAL_DELAY_BLOCKS || epochLengthBlocks == 0
                || epochLengthBlocks > MAX_EPOCH_LENGTH_BLOCKS || revealDelayBlocks >= epochLengthBlocks
        ) {
            revert InvalidConfig();
        }
    }

    function incrementNetuid(uint16 currentNetuid) internal pure returns (uint16) {
        if (currentNetuid == type(uint16).max) {
            revert InvalidConfig();
        }
        return currentNetuid + 1;
    }

    function initializeSubnetConfig(
        uint16 maxValidators,
        uint256 minValidatorStake,
        uint16 ownerFeeBps,
        uint64 revealDelayBlocks,
        uint64 epochLengthBlocks
    ) internal pure returns (SubnetConfig memory config) {
        config.exists = true;
        config.maxValidators = maxValidators;
        config.ownerFeeBps = ownerFeeBps;
        config.revealDelayBlocks = revealDelayBlocks;
        config.epochLengthBlocks = epochLengthBlocks;
        config.minValidatorStake = minValidatorStake;
        config.totalStake = 0;
    }

    function canValidate(SubnetConfig memory subnet, uint256 validatorStake) internal pure returns (bool) {
        return subnet.exists && validatorStake >= subnet.minValidatorStake;
    }

    function addStake(uint256 currentStake, uint256 totalStake, uint256 amount)
        internal
        pure
        returns (uint256 newStake, uint256 newTotalStake)
    {
        if (amount == 0) revert ZeroAmount();
        newStake = currentStake + amount;
        newTotalStake = totalStake + amount;
    }

    function removeStake(uint256 currentStake, uint256 totalStake, uint256 amount)
        internal
        pure
        returns (uint256 newStake, uint256 newTotalStake)
    {
        if (amount == 0) revert ZeroAmount();
        if (amount > currentStake || amount > totalStake) revert InsufficientStake();
        unchecked {
            newStake = currentStake - amount;
            newTotalStake = totalStake - amount;
        }
    }

    function scheduleCommit(
        PendingCommitment memory pending,
        bytes32 commitment,
        uint256 currentBlock,
        uint64 revealDelayBlocks,
        uint64 expireAtBlock
    ) internal pure returns (PendingCommitment memory nextPending) {
        if (commitment == bytes32(0)) revert InvalidCommitment();
        if (pending.commitment != bytes32(0)) revert CommitmentExists();

        uint256 revealAt = currentBlock + revealDelayBlocks;
        if (revealAt > type(uint64).max) revert InvalidConfig();
        if (expireAtBlock < revealAt) revert CommitmentWindowClosed();

        nextPending.commitment = commitment;
        nextPending.revealAtBlock = uint64(revealAt);
        nextPending.expireAtBlock = expireAtBlock;
    }

    function verifyReveal(
        PendingCommitment memory pending,
        uint256 currentBlock,
        bytes32 weightsHash,
        bytes32 salt,
        address validator,
        uint16 netuid,
        uint64 epoch,
        uint256 domainChainId,
        address domainContract,
        uint32 domainVersion
    ) internal pure {
        if (pending.commitment == bytes32(0)) revert CommitmentMissing();
        if (currentBlock < pending.revealAtBlock) revert RevealTooEarly();
        if (currentBlock > pending.expireAtBlock) revert RevealExpired();

        bytes32 expectedCommitment =
            computeCommitment(weightsHash, salt, validator, netuid, epoch, domainChainId, domainContract, domainVersion);
        if (expectedCommitment != pending.commitment) revert CommitmentMismatch();
    }

    function verifyExpiredCommitment(PendingCommitment memory pending, uint256 currentBlock) internal pure {
        if (pending.commitment == bytes32(0)) revert CommitmentMissing();
        if (currentBlock <= pending.expireAtBlock) revert CommitmentNotExpired();
    }

    function slashStakeByBps(uint256 currentStake, uint256 totalStake, uint16 slashBps)
        internal
        pure
        returns (uint256 newStake, uint256 newTotalStake, uint256 slashedAmount)
    {
        if (slashBps == 0 || slashBps > BPS_DENOMINATOR) revert InvalidSlashBps();
        if (currentStake == 0) return (0, totalStake, 0);

        slashedAmount = (currentStake * slashBps) / BPS_DENOMINATOR;
        if (slashedAmount == 0) slashedAmount = 1;
        if (slashedAmount > currentStake) slashedAmount = currentStake;
        if (slashedAmount > totalStake) slashedAmount = totalStake;

        (newStake, newTotalStake) = removeStake(currentStake, totalStake, slashedAmount);
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
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(weightsHash, salt, validator, netuid, epoch, domainChainId, domainContract, domainVersion)
        );
    }

    function currentEpoch(uint256 currentBlock, uint64 epochLengthBlocks) internal pure returns (uint64) {
        if (epochLengthBlocks == 0) revert InvalidConfig();
        uint256 epoch = currentBlock / epochLengthBlocks;
        if (epoch > type(uint64).max) revert InvalidConfig();
        return uint64(epoch);
    }

    function epochEndBlock(uint64 epoch, uint64 epochLengthBlocks) internal pure returns (uint64) {
        if (epochLengthBlocks == 0) revert InvalidConfig();
        uint256 end = (uint256(epoch) + 1) * epochLengthBlocks - 1;
        if (end > type(uint64).max) revert InvalidConfig();
        return uint64(end);
    }
}

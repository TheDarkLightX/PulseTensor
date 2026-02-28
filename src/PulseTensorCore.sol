// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PulseTensorDomain} from "./core/PulseTensorDomain.sol";

contract PulseTensorCore {
    bytes32 private constant OWNER_ACTION_PAUSE_TAG = keccak256("OWNER_ACTION_PAUSE");
    bytes32 private constant OWNER_ACTION_CONFIG_TAG = keccak256("OWNER_ACTION_CONFIG");
    bytes32 private constant OWNER_ACTION_EMISSION_PAYOUT_TAG = keccak256("OWNER_ACTION_EMISSION_PAYOUT");
    bytes32 private constant OWNER_ACTION_EMISSION_SPLIT_TAG = keccak256("OWNER_ACTION_EMISSION_SPLIT");
    bytes32 private constant OWNER_ACTION_MECHANISM_EMISSION_PAYOUT_TAG =
        keccak256("OWNER_ACTION_MECHANISM_EMISSION_PAYOUT");
    bytes32 private constant OWNER_ACTION_MECHANISM_EMISSION_SPLIT_TAG =
        keccak256("OWNER_ACTION_MECHANISM_EMISSION_SPLIT");
    bytes32 private constant OWNER_ACTION_EMISSION_SCHEDULE_TAG = keccak256("OWNER_ACTION_EMISSION_SCHEDULE");
    bytes32 private constant OWNER_ACTION_EPOCH_EMISSION_PAYOUT_TAG = keccak256("OWNER_ACTION_EPOCH_EMISSION_PAYOUT");
    bytes32 private constant OWNER_ACTION_MECHANISM_EMISSION_SCHEDULE_TAG =
        keccak256("OWNER_ACTION_MECHANISM_EMISSION_SCHEDULE");
    bytes32 private constant OWNER_ACTION_MECHANISM_EPOCH_EMISSION_PAYOUT_TAG =
        keccak256("OWNER_ACTION_MECHANISM_EPOCH_EMISSION_PAYOUT");
    bytes32 private constant OWNER_ACTION_EMISSION_SMOOTHING_TAG = keccak256("OWNER_ACTION_EMISSION_SMOOTHING");
    bytes32 private constant OWNER_ACTION_MECHANISM_EMISSION_SMOOTHING_TAG =
        keccak256("OWNER_ACTION_MECHANISM_EMISSION_SMOOTHING");
    uint32 private constant COMMITMENT_DOMAIN_VERSION = 1;

    uint16 public constant BPS_DENOMINATOR = 10_000;
    uint16 public constant MAX_VALIDATORS_LIMIT = 1024;
    uint16 public constant MAX_OWNER_FEE_BPS = 2_000;
    uint16 public constant MAX_MECHANISM_ID = 1023;
    uint16 public constant MISSING_REVEAL_SLASH_BPS = 500;
    uint16 public constant CHALLENGE_BOUNTY_BPS = 2_000;
    uint16 public constant VALIDATOR_EMISSION_BPS = 4_100;
    uint16 public constant MINER_EMISSION_BPS = 4_100;
    uint16 public constant OWNER_EMISSION_BPS = 1_800;
    uint64 public constant MAX_REVEAL_DELAY_BLOCKS = 20_000;
    uint64 public constant MAX_EPOCH_LENGTH_BLOCKS = 120_000;
    uint64 public constant MIN_OWNER_ACTION_DELAY_BLOCKS = 2;
    uint64 public constant MAX_OWNER_ACTION_DELAY_BLOCKS = 200_000;
    uint64 public constant OWNER_ACTION_EXPIRY_BLOCKS = 200_000;

    error SubnetNotFound();
    error Unauthorized();
    error Reentrancy();
    error TransferFailed();
    error NotValidator();
    error ValidatorAlreadyRegistered();
    error ValidatorNotRegistered();
    error MinerAlreadyRegistered();
    error MinerNotRegistered();
    error ValidatorCapacityReached();
    error StakeBelowValidatorMinimum();
    error SubnetPaused();
    error InvalidAddress();
    error GovernanceContractRequired();
    error GovernanceNotConfigured();
    error NotSubnetGovernance();
    error InvalidOwnerActionDelay();
    error OwnerActionAlreadyQueued();
    error OwnerActionNotQueued();
    error OwnerActionNotReady();
    error OwnerActionExpired();
    error OwnerActionQueuedByMismatch();
    error PendingOwnerMismatch();
    error PendingCommitmentExists();
    error InvalidMechanismId();
    error InsufficientEmissionPool();
    error InsufficientMechanismEmissionPool();
    error InsufficientChallengeReward();
    error InvalidEmissionSchedule();
    error EmissionScheduleNotConfigured();
    error EpochEmissionNotFinalized();
    error EpochEmissionAlreadyPaid();
    error EpochEmissionUnavailable();

    uint16 public nextNetuid = 1;
    uint256 private lockState = 1;

    mapping(uint16 => PulseTensorDomain.SubnetConfig) public subnets;
    mapping(uint16 => address) public subnetOwner;
    mapping(uint16 => address) public pendingSubnetOwner;
    mapping(uint16 => address) public subnetGovernance;
    mapping(uint16 => uint64) public subnetOwnerActionDelayBlocks;
    mapping(uint16 => mapping(bytes32 => uint64)) public subnetOwnerActionReadyAtBlock;
    mapping(uint16 => mapping(bytes32 => address)) public subnetOwnerActionQueuedBy;
    mapping(uint16 => bool) public subnetPaused;
    mapping(uint16 => uint16) public validatorCount;
    mapping(uint16 => mapping(address => uint256)) public stakeOf;
    mapping(uint16 => mapping(address => bool)) public isValidator;
    mapping(uint16 => mapping(address => bool)) public isMiner;
    mapping(uint16 => mapping(uint64 => mapping(address => PulseTensorDomain.PendingCommitment))) public
        epochCommitments;
    mapping(uint16 => mapping(address => uint64)) public activeCommitEpoch;
    mapping(uint16 => mapping(uint16 => mapping(uint64 => mapping(address => PulseTensorDomain.PendingCommitment))))
        public mechanismEpochCommitments;
    mapping(uint16 => mapping(uint16 => mapping(address => uint64))) public mechanismActiveCommitEpoch;
    mapping(uint16 => mapping(address => uint256)) public pendingCommitmentCount;
    mapping(uint16 => mapping(uint64 => mapping(address => bool))) public epochRevealed;
    mapping(uint16 => mapping(uint64 => mapping(address => bytes32))) public epochRevealedWeightsHash;
    mapping(uint16 => mapping(uint16 => mapping(uint64 => mapping(address => bool)))) public mechanismEpochRevealed;
    mapping(uint16 => mapping(uint16 => mapping(uint64 => mapping(address => bytes32)))) public
        mechanismEpochRevealedWeightsHash;
    mapping(uint16 => uint256) public subnetEmissionPool;
    mapping(uint16 => mapping(uint16 => uint256)) public mechanismEmissionPool;
    mapping(uint16 => mapping(address => uint256)) public challengeRewardOf;
    mapping(uint16 => uint256) public subnetEpochEmissionBase;
    mapping(uint16 => uint256) public subnetEpochEmissionFloor;
    mapping(uint16 => uint64) public subnetEpochEmissionHalvingPeriod;
    mapping(uint16 => uint64) public subnetEpochEmissionStart;
    mapping(uint16 => mapping(uint64 => bool)) public subnetEpochEmissionPaid;
    mapping(uint16 => mapping(uint16 => uint256)) public mechanismEpochEmissionBase;
    mapping(uint16 => mapping(uint16 => uint256)) public mechanismEpochEmissionFloor;
    mapping(uint16 => mapping(uint16 => uint64)) public mechanismEpochEmissionHalvingPeriod;
    mapping(uint16 => mapping(uint16 => uint64)) public mechanismEpochEmissionStart;
    mapping(uint16 => mapping(uint16 => mapping(uint64 => bool))) public mechanismEpochEmissionPaid;
    mapping(uint16 => bool) public subnetEmissionSmoothDecayEnabled;
    mapping(uint16 => mapping(uint16 => bool)) public mechanismEmissionSmoothDecayEnabled;

    event SubnetCreated(
        uint16 indexed netuid,
        address indexed owner,
        uint16 maxValidators,
        uint256 minValidatorStake,
        uint16 ownerFeeBps,
        uint64 revealDelayBlocks,
        uint64 epochLengthBlocks
    );
    event SubnetConfigUpdated(
        uint16 indexed netuid,
        uint256 minValidatorStake,
        uint16 ownerFeeBps,
        uint64 revealDelayBlocks,
        uint64 epochLengthBlocks
    );
    event SubnetOwnerTransferStarted(uint16 indexed netuid, address indexed currentOwner, address indexed pendingOwner);
    event SubnetOwnerTransferred(uint16 indexed netuid, address indexed previousOwner, address indexed newOwner);
    event SubnetGovernanceConfigured(uint16 indexed netuid, address indexed governance, uint64 ownerActionDelayBlocks);
    event SubnetOwnerActionQueued(
        uint16 indexed netuid, bytes32 indexed actionId, uint64 readyAtBlock, address indexed governance
    );
    event SubnetOwnerActionCancelled(uint16 indexed netuid, bytes32 indexed actionId, address indexed governance);
    event SubnetOwnerActionExecuted(uint16 indexed netuid, bytes32 indexed actionId, address indexed governance);
    event SubnetPausedSet(uint16 indexed netuid, bool paused);
    event StakeAdded(uint16 indexed netuid, address indexed staker, uint256 amount, uint256 newStake);
    event StakeRemoved(uint16 indexed netuid, address indexed staker, uint256 amount, uint256 newStake);
    event SubnetEmissionFunded(uint16 indexed netuid, address indexed funder, uint256 amount, uint256 newPoolBalance);
    event SubnetEmissionPaid(uint16 indexed netuid, address indexed recipient, uint256 amount, uint256 newPoolBalance);
    event MechanismEmissionFunded(
        uint16 indexed netuid, uint16 indexed mechid, address indexed funder, uint256 amount, uint256 newPoolBalance
    );
    event MechanismEmissionPaid(
        uint16 indexed netuid, uint16 indexed mechid, address indexed recipient, uint256 amount, uint256 newPoolBalance
    );
    event MechanismEmissionSplitPaid(
        uint16 indexed netuid,
        uint16 indexed mechid,
        address indexed validatorRecipient,
        address minerRecipient,
        address ownerRecipient,
        uint256 validatorAmount,
        uint256 minerAmount,
        uint256 ownerAmount,
        uint256 newPoolBalance
    );
    event MechanismEmissionScheduleConfigured(
        uint16 indexed netuid,
        uint16 indexed mechid,
        uint256 baseEmissionPerEpoch,
        uint256 floorEmissionPerEpoch,
        uint64 halvingPeriodEpochs,
        uint64 startEpoch
    );
    event SubnetEmissionScheduleConfigured(
        uint16 indexed netuid,
        uint256 baseEmissionPerEpoch,
        uint256 floorEmissionPerEpoch,
        uint64 halvingPeriodEpochs,
        uint64 startEpoch
    );
    event SubnetEmissionSmoothingConfigured(uint16 indexed netuid, bool smoothDecayEnabled);
    event MechanismEmissionSmoothingConfigured(uint16 indexed netuid, uint16 indexed mechid, bool smoothDecayEnabled);
    event SubnetEmissionSplitPaid(
        uint16 indexed netuid,
        address indexed validatorRecipient,
        address indexed minerRecipient,
        address ownerRecipient,
        uint256 validatorAmount,
        uint256 minerAmount,
        uint256 ownerAmount,
        uint256 newPoolBalance
    );
    event MechanismEpochEmissionPaid(
        uint16 indexed netuid,
        uint16 indexed mechid,
        uint64 indexed epoch,
        address validatorRecipient,
        address minerRecipient,
        address ownerRecipient,
        uint256 totalAmount,
        uint256 validatorAmount,
        uint256 minerAmount,
        uint256 ownerAmount,
        uint256 newPoolBalance
    );
    event SubnetEpochEmissionPaid(
        uint16 indexed netuid,
        uint64 indexed epoch,
        address indexed validatorRecipient,
        address minerRecipient,
        address ownerRecipient,
        uint256 totalAmount,
        uint256 validatorAmount,
        uint256 minerAmount,
        uint256 ownerAmount,
        uint256 newPoolBalance
    );
    event ValidatorRegistered(uint16 indexed netuid, address indexed validator);
    event ValidatorUnregistered(uint16 indexed netuid, address indexed validator);
    event MinerRegistered(uint16 indexed netuid, address indexed miner);
    event MinerUnregistered(uint16 indexed netuid, address indexed miner);
    event ChallengeRewardAccrued(
        uint16 indexed netuid, address indexed challenger, uint256 amount, uint256 newClaimableBalance
    );
    event ChallengeRewardClaimed(
        uint16 indexed netuid, address indexed challenger, uint256 amount, uint256 remainingClaimableBalance
    );
    event ValidatorSlashed(
        uint16 indexed netuid,
        uint64 indexed epoch,
        address indexed validator,
        address challenger,
        uint256 slashedAmount,
        bool validatorUnregistered,
        uint256 challengerRewardAmount,
        uint256 emissionPoolAmount
    );
    event MechanismValidatorSlashed(
        uint16 indexed netuid,
        uint16 indexed mechid,
        uint64 indexed epoch,
        address validator,
        address challenger,
        uint256 slashedAmount,
        bool validatorUnregistered,
        uint256 challengerRewardAmount,
        uint256 emissionPoolAmount
    );
    event WeightsCommitted(
        uint16 indexed netuid,
        uint64 indexed epoch,
        address indexed validator,
        bytes32 commitment,
        uint64 revealAtBlock,
        uint64 expireAtBlock
    );
    event WeightsRevealed(uint16 indexed netuid, uint64 indexed epoch, address indexed validator, bytes32 weightsHash);
    event MechanismWeightsCommitted(
        uint16 indexed netuid,
        uint16 indexed mechid,
        uint64 indexed epoch,
        address validator,
        bytes32 commitment,
        uint64 revealAtBlock,
        uint64 expireAtBlock
    );
    event MechanismWeightsRevealed(
        uint16 indexed netuid, uint16 indexed mechid, uint64 indexed epoch, address validator, bytes32 weightsHash
    );

    modifier nonReentrant() {
        if (lockState != 1) revert Reentrancy();
        lockState = 2;
        _;
        lockState = 1;
    }

    modifier onlySubnetOwner(uint16 netuid) {
        if (subnetOwner[netuid] != msg.sender) revert Unauthorized();
        _;
    }

    modifier onlySubnetGovernance(uint16 netuid) {
        address governance = subnetGovernance[netuid];
        if (governance == address(0)) revert GovernanceNotConfigured();
        if (governance != msg.sender) revert NotSubnetGovernance();
        _;
    }

    modifier subnetExists(uint16 netuid) {
        if (!subnets[netuid].exists) revert SubnetNotFound();
        _;
    }

    modifier whenSubnetActive(uint16 netuid) {
        if (!subnets[netuid].exists) revert SubnetNotFound();
        if (subnetPaused[netuid]) revert SubnetPaused();
        _;
    }

    function createSubnet(
        uint16 maxValidators,
        uint256 minValidatorStake,
        uint16 ownerFeeBps,
        uint64 revealDelayBlocks,
        uint64 epochLengthBlocks
    ) external returns (uint16 netuid) {
        if (
            maxValidators > MAX_VALIDATORS_LIMIT || ownerFeeBps > MAX_OWNER_FEE_BPS
                || revealDelayBlocks > MAX_REVEAL_DELAY_BLOCKS || epochLengthBlocks > MAX_EPOCH_LENGTH_BLOCKS
        ) revert PulseTensorDomain.InvalidConfig();
        PulseTensorDomain.validateSubnetConfig(maxValidators, ownerFeeBps, revealDelayBlocks, epochLengthBlocks);

        netuid = nextNetuid;
        nextNetuid = PulseTensorDomain.incrementNetuid(netuid);

        subnets[netuid] = PulseTensorDomain.initializeSubnetConfig(
            maxValidators, minValidatorStake, ownerFeeBps, revealDelayBlocks, epochLengthBlocks
        );
        subnetOwner[netuid] = msg.sender;

        emit SubnetCreated(
            netuid, msg.sender, maxValidators, minValidatorStake, ownerFeeBps, revealDelayBlocks, epochLengthBlocks
        );
    }

    function initiateSubnetOwnerTransfer(uint16 netuid, address newOwner)
        external
        subnetExists(netuid)
        onlySubnetOwner(netuid)
    {
        if (newOwner == address(0) || newOwner == subnetOwner[netuid]) revert InvalidAddress();
        pendingSubnetOwner[netuid] = newOwner;
        emit SubnetOwnerTransferStarted(netuid, msg.sender, newOwner);
    }

    function acceptSubnetOwnerTransfer(uint16 netuid) external subnetExists(netuid) {
        if (pendingSubnetOwner[netuid] != msg.sender) revert PendingOwnerMismatch();
        address previousOwner = subnetOwner[netuid];
        subnetOwner[netuid] = msg.sender;
        pendingSubnetOwner[netuid] = address(0);
        emit SubnetOwnerTransferred(netuid, previousOwner, msg.sender);
    }

    function configureSubnetGovernance(uint16 netuid, address governance, uint64 ownerActionDelayBlocks)
        external
        subnetExists(netuid)
        onlySubnetOwner(netuid)
    {
        if (governance == address(0)) revert InvalidAddress();
        if (governance.code.length == 0) revert GovernanceContractRequired();
        if (
            ownerActionDelayBlocks < MIN_OWNER_ACTION_DELAY_BLOCKS
                || ownerActionDelayBlocks > MAX_OWNER_ACTION_DELAY_BLOCKS
        ) revert InvalidOwnerActionDelay();

        subnetGovernance[netuid] = governance;
        subnetOwnerActionDelayBlocks[netuid] = ownerActionDelayBlocks;
        emit SubnetGovernanceConfigured(netuid, governance, ownerActionDelayBlocks);
    }

    function queueSubnetPause(uint16 netuid, bool paused)
        external
        subnetExists(netuid)
        onlySubnetGovernance(netuid)
        returns (bytes32 actionId, uint64 readyAtBlock)
    {
        actionId = _pauseActionId(netuid, paused);
        readyAtBlock = _queueOwnerAction(netuid, actionId);
    }

    function queueSubnetConfigUpdate(
        uint16 netuid,
        uint256 minValidatorStake,
        uint16 ownerFeeBps,
        uint64 revealDelayBlocks,
        uint64 epochLengthBlocks
    ) external subnetExists(netuid) onlySubnetGovernance(netuid) returns (bytes32 actionId, uint64 readyAtBlock) {
        actionId = _configActionId(netuid, minValidatorStake, ownerFeeBps, revealDelayBlocks, epochLengthBlocks);
        readyAtBlock = _queueOwnerAction(netuid, actionId);
    }

    function queueSubnetEmissionPayout(uint16 netuid, address recipient, uint256 amount)
        external
        subnetExists(netuid)
        onlySubnetGovernance(netuid)
        returns (bytes32 actionId, uint64 readyAtBlock)
    {
        if (recipient == address(0)) revert InvalidAddress();
        if (amount == 0) revert PulseTensorDomain.ZeroAmount();
        actionId = _emissionPayoutActionId(netuid, recipient, amount);
        readyAtBlock = _queueOwnerAction(netuid, actionId);
    }

    function queueSubnetEmissionSplitPayout(
        uint16 netuid,
        address validatorRecipient,
        address minerRecipient,
        address ownerRecipient,
        uint256 totalAmount
    ) external subnetExists(netuid) onlySubnetGovernance(netuid) returns (bytes32 actionId, uint64 readyAtBlock) {
        if (validatorRecipient == address(0) || minerRecipient == address(0) || ownerRecipient == address(0)) {
            revert InvalidAddress();
        }
        if (totalAmount == 0) revert PulseTensorDomain.ZeroAmount();
        actionId = _emissionSplitActionId(netuid, validatorRecipient, minerRecipient, ownerRecipient, totalAmount);
        readyAtBlock = _queueOwnerAction(netuid, actionId);
    }

    function queueMechanismEmissionPayout(uint16 netuid, uint16 mechid, address recipient, uint256 amount)
        external
        subnetExists(netuid)
        onlySubnetGovernance(netuid)
        returns (bytes32 actionId, uint64 readyAtBlock)
    {
        _validateMechanismId(mechid);
        if (recipient == address(0)) revert InvalidAddress();
        if (amount == 0) revert PulseTensorDomain.ZeroAmount();
        actionId = _mechanismEmissionPayoutActionId(netuid, mechid, recipient, amount);
        readyAtBlock = _queueOwnerAction(netuid, actionId);
    }

    function queueMechanismEmissionSplitPayout(
        uint16 netuid,
        uint16 mechid,
        address validatorRecipient,
        address minerRecipient,
        address ownerRecipient,
        uint256 totalAmount
    ) external subnetExists(netuid) onlySubnetGovernance(netuid) returns (bytes32 actionId, uint64 readyAtBlock) {
        _validateMechanismId(mechid);
        if (validatorRecipient == address(0) || minerRecipient == address(0) || ownerRecipient == address(0)) {
            revert InvalidAddress();
        }
        if (totalAmount == 0) revert PulseTensorDomain.ZeroAmount();
        actionId = _mechanismEmissionSplitActionId(
            netuid, mechid, validatorRecipient, minerRecipient, ownerRecipient, totalAmount
        );
        readyAtBlock = _queueOwnerAction(netuid, actionId);
    }

    function queueSubnetEmissionScheduleUpdate(
        uint16 netuid,
        uint256 baseEmissionPerEpoch,
        uint256 floorEmissionPerEpoch,
        uint64 halvingPeriodEpochs,
        uint64 startEpoch
    ) external subnetExists(netuid) onlySubnetGovernance(netuid) returns (bytes32 actionId, uint64 readyAtBlock) {
        _validateEmissionSchedule(baseEmissionPerEpoch, floorEmissionPerEpoch, halvingPeriodEpochs);
        actionId = _emissionScheduleActionId(
            netuid, baseEmissionPerEpoch, floorEmissionPerEpoch, halvingPeriodEpochs, startEpoch
        );
        readyAtBlock = _queueOwnerAction(netuid, actionId);
    }

    function queueSubnetEmissionSmoothingUpdate(uint16 netuid, bool smoothDecayEnabled)
        external
        subnetExists(netuid)
        onlySubnetGovernance(netuid)
        returns (bytes32 actionId, uint64 readyAtBlock)
    {
        actionId = _emissionSmoothingActionId(netuid, smoothDecayEnabled);
        readyAtBlock = _queueOwnerAction(netuid, actionId);
    }

    function queueSubnetEpochEmissionPayout(
        uint16 netuid,
        uint64 epoch,
        address validatorRecipient,
        address minerRecipient,
        address ownerRecipient
    ) external subnetExists(netuid) onlySubnetGovernance(netuid) returns (bytes32 actionId, uint64 readyAtBlock) {
        if (validatorRecipient == address(0) || minerRecipient == address(0) || ownerRecipient == address(0)) {
            revert InvalidAddress();
        }
        actionId = _epochEmissionPayoutActionId(netuid, epoch, validatorRecipient, minerRecipient, ownerRecipient);
        readyAtBlock = _queueOwnerAction(netuid, actionId);
    }

    function queueMechanismEmissionScheduleUpdate(
        uint16 netuid,
        uint16 mechid,
        uint256 baseEmissionPerEpoch,
        uint256 floorEmissionPerEpoch,
        uint64 halvingPeriodEpochs,
        uint64 startEpoch
    ) external subnetExists(netuid) onlySubnetGovernance(netuid) returns (bytes32 actionId, uint64 readyAtBlock) {
        _validateMechanismId(mechid);
        _validateEmissionSchedule(baseEmissionPerEpoch, floorEmissionPerEpoch, halvingPeriodEpochs);
        actionId = _mechanismEmissionScheduleActionId(
            netuid, mechid, baseEmissionPerEpoch, floorEmissionPerEpoch, halvingPeriodEpochs, startEpoch
        );
        readyAtBlock = _queueOwnerAction(netuid, actionId);
    }

    function queueMechanismEmissionSmoothingUpdate(uint16 netuid, uint16 mechid, bool smoothDecayEnabled)
        external
        subnetExists(netuid)
        onlySubnetGovernance(netuid)
        returns (bytes32 actionId, uint64 readyAtBlock)
    {
        _validateMechanismId(mechid);
        actionId = _mechanismEmissionSmoothingActionId(netuid, mechid, smoothDecayEnabled);
        readyAtBlock = _queueOwnerAction(netuid, actionId);
    }

    function queueMechanismEpochEmissionPayout(
        uint16 netuid,
        uint16 mechid,
        uint64 epoch,
        address validatorRecipient,
        address minerRecipient,
        address ownerRecipient
    ) external subnetExists(netuid) onlySubnetGovernance(netuid) returns (bytes32 actionId, uint64 readyAtBlock) {
        _validateMechanismId(mechid);
        if (validatorRecipient == address(0) || minerRecipient == address(0) || ownerRecipient == address(0)) {
            revert InvalidAddress();
        }
        actionId = _mechanismEpochEmissionPayoutActionId(
            netuid, mechid, epoch, validatorRecipient, minerRecipient, ownerRecipient
        );
        readyAtBlock = _queueOwnerAction(netuid, actionId);
    }

    function cancelSubnetOwnerAction(uint16 netuid, bytes32 actionId)
        external
        subnetExists(netuid)
        onlySubnetGovernance(netuid)
    {
        if (subnetOwnerActionReadyAtBlock[netuid][actionId] == 0) revert OwnerActionNotQueued();
        delete subnetOwnerActionReadyAtBlock[netuid][actionId];
        delete subnetOwnerActionQueuedBy[netuid][actionId];
        emit SubnetOwnerActionCancelled(netuid, actionId, msg.sender);
    }

    function updateSubnetConfig(
        uint16 netuid,
        uint256 minValidatorStake,
        uint16 ownerFeeBps,
        uint64 revealDelayBlocks,
        uint64 epochLengthBlocks
    ) external subnetExists(netuid) onlySubnetGovernance(netuid) {
        bytes32 actionId = _configActionId(netuid, minValidatorStake, ownerFeeBps, revealDelayBlocks, epochLengthBlocks);
        _consumeOwnerAction(netuid, actionId);

        PulseTensorDomain.SubnetConfig storage subnet = subnets[netuid];
        if (
            subnet.maxValidators > MAX_VALIDATORS_LIMIT || ownerFeeBps > MAX_OWNER_FEE_BPS
                || revealDelayBlocks > MAX_REVEAL_DELAY_BLOCKS || epochLengthBlocks > MAX_EPOCH_LENGTH_BLOCKS
        ) revert PulseTensorDomain.InvalidConfig();

        PulseTensorDomain.validateSubnetConfig(subnet.maxValidators, ownerFeeBps, revealDelayBlocks, epochLengthBlocks);

        subnet.minValidatorStake = minValidatorStake;
        subnet.ownerFeeBps = ownerFeeBps;
        subnet.revealDelayBlocks = revealDelayBlocks;
        subnet.epochLengthBlocks = epochLengthBlocks;

        emit SubnetConfigUpdated(netuid, minValidatorStake, ownerFeeBps, revealDelayBlocks, epochLengthBlocks);
    }

    function configureSubnetEmissionSchedule(
        uint16 netuid,
        uint256 baseEmissionPerEpoch,
        uint256 floorEmissionPerEpoch,
        uint64 halvingPeriodEpochs,
        uint64 startEpoch
    ) external subnetExists(netuid) onlySubnetGovernance(netuid) {
        _validateEmissionSchedule(baseEmissionPerEpoch, floorEmissionPerEpoch, halvingPeriodEpochs);
        bytes32 actionId = _emissionScheduleActionId(
            netuid, baseEmissionPerEpoch, floorEmissionPerEpoch, halvingPeriodEpochs, startEpoch
        );
        _consumeOwnerAction(netuid, actionId);

        subnetEpochEmissionBase[netuid] = baseEmissionPerEpoch;
        subnetEpochEmissionFloor[netuid] = floorEmissionPerEpoch;
        subnetEpochEmissionHalvingPeriod[netuid] = halvingPeriodEpochs;
        subnetEpochEmissionStart[netuid] = startEpoch;

        emit SubnetEmissionScheduleConfigured(
            netuid, baseEmissionPerEpoch, floorEmissionPerEpoch, halvingPeriodEpochs, startEpoch
        );
    }

    function configureSubnetEmissionSmoothing(uint16 netuid, bool smoothDecayEnabled)
        external
        subnetExists(netuid)
        onlySubnetGovernance(netuid)
    {
        bytes32 actionId = _emissionSmoothingActionId(netuid, smoothDecayEnabled);
        _consumeOwnerAction(netuid, actionId);

        subnetEmissionSmoothDecayEnabled[netuid] = smoothDecayEnabled;
        emit SubnetEmissionSmoothingConfigured(netuid, smoothDecayEnabled);
    }

    function configureMechanismEmissionSchedule(
        uint16 netuid,
        uint16 mechid,
        uint256 baseEmissionPerEpoch,
        uint256 floorEmissionPerEpoch,
        uint64 halvingPeriodEpochs,
        uint64 startEpoch
    ) external subnetExists(netuid) onlySubnetGovernance(netuid) {
        _validateMechanismId(mechid);
        _validateEmissionSchedule(baseEmissionPerEpoch, floorEmissionPerEpoch, halvingPeriodEpochs);
        bytes32 actionId = _mechanismEmissionScheduleActionId(
            netuid, mechid, baseEmissionPerEpoch, floorEmissionPerEpoch, halvingPeriodEpochs, startEpoch
        );
        _consumeOwnerAction(netuid, actionId);

        mechanismEpochEmissionBase[netuid][mechid] = baseEmissionPerEpoch;
        mechanismEpochEmissionFloor[netuid][mechid] = floorEmissionPerEpoch;
        mechanismEpochEmissionHalvingPeriod[netuid][mechid] = halvingPeriodEpochs;
        mechanismEpochEmissionStart[netuid][mechid] = startEpoch;

        emit MechanismEmissionScheduleConfigured(
            netuid, mechid, baseEmissionPerEpoch, floorEmissionPerEpoch, halvingPeriodEpochs, startEpoch
        );
    }

    function configureMechanismEmissionSmoothing(uint16 netuid, uint16 mechid, bool smoothDecayEnabled)
        external
        subnetExists(netuid)
        onlySubnetGovernance(netuid)
    {
        _validateMechanismId(mechid);
        bytes32 actionId = _mechanismEmissionSmoothingActionId(netuid, mechid, smoothDecayEnabled);
        _consumeOwnerAction(netuid, actionId);

        mechanismEmissionSmoothDecayEnabled[netuid][mechid] = smoothDecayEnabled;
        emit MechanismEmissionSmoothingConfigured(netuid, mechid, smoothDecayEnabled);
    }

    function setSubnetPaused(uint16 netuid, bool paused) external subnetExists(netuid) onlySubnetGovernance(netuid) {
        bytes32 actionId = _pauseActionId(netuid, paused);
        _consumeOwnerAction(netuid, actionId);

        subnetPaused[netuid] = paused;
        emit SubnetPausedSet(netuid, paused);
    }

    function fundSubnetEmission(uint16 netuid) external payable subnetExists(netuid) {
        if (msg.value == 0) revert PulseTensorDomain.ZeroAmount();
        subnetEmissionPool[netuid] += msg.value;
        emit SubnetEmissionFunded(netuid, msg.sender, msg.value, subnetEmissionPool[netuid]);
    }

    function fundMechanismEmission(uint16 netuid, uint16 mechid) external payable subnetExists(netuid) {
        _validateMechanismId(mechid);
        if (msg.value == 0) revert PulseTensorDomain.ZeroAmount();
        mechanismEmissionPool[netuid][mechid] += msg.value;
        emit MechanismEmissionFunded(netuid, mechid, msg.sender, msg.value, mechanismEmissionPool[netuid][mechid]);
    }

    function payoutSubnetEmission(uint16 netuid, address payable recipient, uint256 amount)
        external
        nonReentrant
        subnetExists(netuid)
        onlySubnetGovernance(netuid)
    {
        if (recipient == address(0)) revert InvalidAddress();
        if (amount == 0) revert PulseTensorDomain.ZeroAmount();

        bytes32 actionId = _emissionPayoutActionId(netuid, recipient, amount);
        _consumeOwnerAction(netuid, actionId);
        uint256 newPoolBalance = _reduceEmissionPool(netuid, amount);
        _transferValue(recipient, amount);
        emit SubnetEmissionPaid(netuid, recipient, amount, newPoolBalance);
    }

    function payoutSubnetEmissionSplit(
        uint16 netuid,
        address payable validatorRecipient,
        address payable minerRecipient,
        address payable ownerRecipient,
        uint256 totalAmount
    ) external nonReentrant subnetExists(netuid) onlySubnetGovernance(netuid) {
        if (validatorRecipient == address(0) || minerRecipient == address(0) || ownerRecipient == address(0)) {
            revert InvalidAddress();
        }
        if (totalAmount == 0) revert PulseTensorDomain.ZeroAmount();

        bytes32 actionId =
            _emissionSplitActionId(netuid, validatorRecipient, minerRecipient, ownerRecipient, totalAmount);
        _consumeOwnerAction(netuid, actionId);

        (uint256 validatorAmount, uint256 minerAmount, uint256 ownerAmount) = _quoteDefaultEmissionSplit(totalAmount);
        uint256 newPoolBalance = _reduceEmissionPool(netuid, totalAmount);

        _transferValue(validatorRecipient, validatorAmount);
        _transferValue(minerRecipient, minerAmount);
        _transferValue(ownerRecipient, ownerAmount);

        emit SubnetEmissionSplitPaid(
            netuid,
            validatorRecipient,
            minerRecipient,
            ownerRecipient,
            validatorAmount,
            minerAmount,
            ownerAmount,
            newPoolBalance
        );
    }

    function payoutMechanismEmission(uint16 netuid, uint16 mechid, address payable recipient, uint256 amount)
        external
        nonReentrant
        subnetExists(netuid)
        onlySubnetGovernance(netuid)
    {
        _validateMechanismId(mechid);
        if (recipient == address(0)) revert InvalidAddress();
        if (amount == 0) revert PulseTensorDomain.ZeroAmount();

        bytes32 actionId = _mechanismEmissionPayoutActionId(netuid, mechid, recipient, amount);
        _consumeOwnerAction(netuid, actionId);
        uint256 newPoolBalance = _reduceMechanismEmissionPool(netuid, mechid, amount);
        _transferValue(recipient, amount);
        emit MechanismEmissionPaid(netuid, mechid, recipient, amount, newPoolBalance);
    }

    function payoutMechanismEmissionSplit(
        uint16 netuid,
        uint16 mechid,
        address payable validatorRecipient,
        address payable minerRecipient,
        address payable ownerRecipient,
        uint256 totalAmount
    ) external nonReentrant subnetExists(netuid) onlySubnetGovernance(netuid) {
        _validateMechanismId(mechid);
        if (validatorRecipient == address(0) || minerRecipient == address(0) || ownerRecipient == address(0)) {
            revert InvalidAddress();
        }
        if (totalAmount == 0) revert PulseTensorDomain.ZeroAmount();

        bytes32 actionId = _mechanismEmissionSplitActionId(
            netuid, mechid, validatorRecipient, minerRecipient, ownerRecipient, totalAmount
        );
        _consumeOwnerAction(netuid, actionId);

        (uint256 validatorAmount, uint256 minerAmount, uint256 ownerAmount) = _quoteDefaultEmissionSplit(totalAmount);
        uint256 newPoolBalance = _reduceMechanismEmissionPool(netuid, mechid, totalAmount);

        _transferValue(validatorRecipient, validatorAmount);
        _transferValue(minerRecipient, minerAmount);
        _transferValue(ownerRecipient, ownerAmount);

        emit MechanismEmissionSplitPaid(
            netuid,
            mechid,
            validatorRecipient,
            minerRecipient,
            ownerRecipient,
            validatorAmount,
            minerAmount,
            ownerAmount,
            newPoolBalance
        );
    }

    function payoutSubnetEpochEmission(
        uint16 netuid,
        uint64 epoch,
        address payable validatorRecipient,
        address payable minerRecipient,
        address payable ownerRecipient
    ) external nonReentrant subnetExists(netuid) onlySubnetGovernance(netuid) {
        if (validatorRecipient == address(0) || minerRecipient == address(0) || ownerRecipient == address(0)) {
            revert InvalidAddress();
        }
        if (subnetEpochEmissionHalvingPeriod[netuid] == 0) revert EmissionScheduleNotConfigured();
        if (epoch >= currentEpoch(netuid)) revert EpochEmissionNotFinalized();
        if (subnetEpochEmissionPaid[netuid][epoch]) revert EpochEmissionAlreadyPaid();

        bytes32 actionId =
            _epochEmissionPayoutActionId(netuid, epoch, validatorRecipient, minerRecipient, ownerRecipient);
        _consumeOwnerAction(netuid, actionId);

        uint256 totalAmount = _quoteSubnetEpochEmission(netuid, epoch);
        if (totalAmount == 0) revert EpochEmissionUnavailable();

        (uint256 validatorAmount, uint256 minerAmount, uint256 ownerAmount) = _quoteDefaultEmissionSplit(totalAmount);
        uint256 newPoolBalance = _reduceEmissionPool(netuid, totalAmount);

        subnetEpochEmissionPaid[netuid][epoch] = true;
        _transferValue(validatorRecipient, validatorAmount);
        _transferValue(minerRecipient, minerAmount);
        _transferValue(ownerRecipient, ownerAmount);

        emit SubnetEpochEmissionPaid(
            netuid,
            epoch,
            validatorRecipient,
            minerRecipient,
            ownerRecipient,
            totalAmount,
            validatorAmount,
            minerAmount,
            ownerAmount,
            newPoolBalance
        );
    }

    function payoutMechanismEpochEmission(
        uint16 netuid,
        uint16 mechid,
        uint64 epoch,
        address payable validatorRecipient,
        address payable minerRecipient,
        address payable ownerRecipient
    ) external nonReentrant subnetExists(netuid) onlySubnetGovernance(netuid) {
        _validateMechanismId(mechid);
        if (validatorRecipient == address(0) || minerRecipient == address(0) || ownerRecipient == address(0)) {
            revert InvalidAddress();
        }
        if (mechanismEpochEmissionHalvingPeriod[netuid][mechid] == 0) revert EmissionScheduleNotConfigured();
        if (epoch >= currentEpoch(netuid)) revert EpochEmissionNotFinalized();
        if (mechanismEpochEmissionPaid[netuid][mechid][epoch]) revert EpochEmissionAlreadyPaid();

        bytes32 actionId = _mechanismEpochEmissionPayoutActionId(
            netuid, mechid, epoch, validatorRecipient, minerRecipient, ownerRecipient
        );
        _consumeOwnerAction(netuid, actionId);

        uint256 totalAmount = _quoteMechanismEpochEmission(netuid, mechid, epoch);
        if (totalAmount == 0) revert EpochEmissionUnavailable();

        (uint256 validatorAmount, uint256 minerAmount, uint256 ownerAmount) = _quoteDefaultEmissionSplit(totalAmount);
        uint256 newPoolBalance = _reduceMechanismEmissionPool(netuid, mechid, totalAmount);

        mechanismEpochEmissionPaid[netuid][mechid][epoch] = true;
        _transferValue(validatorRecipient, validatorAmount);
        _transferValue(minerRecipient, minerAmount);
        _transferValue(ownerRecipient, ownerAmount);

        emit MechanismEpochEmissionPaid(
            netuid,
            mechid,
            epoch,
            validatorRecipient,
            minerRecipient,
            ownerRecipient,
            totalAmount,
            validatorAmount,
            minerAmount,
            ownerAmount,
            newPoolBalance
        );
    }

    function claimChallengeReward(uint16 netuid, uint256 amount) external nonReentrant subnetExists(netuid) {
        if (amount == 0) revert PulseTensorDomain.ZeroAmount();
        uint256 claimableAmount = challengeRewardOf[netuid][msg.sender];
        if (amount > claimableAmount) revert InsufficientChallengeReward();

        challengeRewardOf[netuid][msg.sender] = claimableAmount - amount;
        _transferValue(payable(msg.sender), amount);
        emit ChallengeRewardClaimed(netuid, msg.sender, amount, challengeRewardOf[netuid][msg.sender]);
    }

    function addStake(uint16 netuid) external payable nonReentrant whenSubnetActive(netuid) {
        PulseTensorDomain.SubnetConfig storage subnet = subnets[netuid];

        (uint256 newStake, uint256 newTotalStake) =
            PulseTensorDomain.addStake(stakeOf[netuid][msg.sender], subnet.totalStake, msg.value);
        stakeOf[netuid][msg.sender] = newStake;
        subnet.totalStake = newTotalStake;

        emit StakeAdded(netuid, msg.sender, msg.value, stakeOf[netuid][msg.sender]);
    }

    function removeStake(uint16 netuid, uint256 amount) external nonReentrant whenSubnetActive(netuid) {
        if (_hasActiveCommitment(netuid, msg.sender)) revert PendingCommitmentExists();
        PulseTensorDomain.SubnetConfig storage subnet = subnets[netuid];

        uint256 currentStake = stakeOf[netuid][msg.sender];
        (uint256 newStake, uint256 newTotalStake) =
            PulseTensorDomain.removeStake(currentStake, subnet.totalStake, amount);
        if (isValidator[netuid][msg.sender] && newStake < subnet.minValidatorStake) revert StakeBelowValidatorMinimum();

        stakeOf[netuid][msg.sender] = newStake;
        subnet.totalStake = newTotalStake;

        (bool sent,) = msg.sender.call{value: amount}("");
        if (!sent) revert TransferFailed();

        emit StakeRemoved(netuid, msg.sender, amount, stakeOf[netuid][msg.sender]);
    }

    function canValidate(uint16 netuid, address validator) public view returns (bool) {
        PulseTensorDomain.SubnetConfig memory subnet = subnets[netuid];
        return isValidator[netuid][validator] && PulseTensorDomain.canValidate(subnet, stakeOf[netuid][validator]);
    }

    function registerValidator(uint16 netuid) external whenSubnetActive(netuid) {
        PulseTensorDomain.SubnetConfig storage subnet = subnets[netuid];
        if (isValidator[netuid][msg.sender]) revert ValidatorAlreadyRegistered();
        if (validatorCount[netuid] >= subnet.maxValidators) revert ValidatorCapacityReached();
        if (stakeOf[netuid][msg.sender] < subnet.minValidatorStake) revert StakeBelowValidatorMinimum();

        isValidator[netuid][msg.sender] = true;
        validatorCount[netuid] += 1;

        emit ValidatorRegistered(netuid, msg.sender);
    }

    function unregisterValidator(uint16 netuid) external subnetExists(netuid) {
        if (!isValidator[netuid][msg.sender]) revert ValidatorNotRegistered();
        if (_hasActiveCommitment(netuid, msg.sender)) revert PendingCommitmentExists();
        isValidator[netuid][msg.sender] = false;
        unchecked {
            validatorCount[netuid] -= 1;
        }

        emit ValidatorUnregistered(netuid, msg.sender);
    }

    function registerMiner(uint16 netuid) external whenSubnetActive(netuid) {
        if (isMiner[netuid][msg.sender]) revert MinerAlreadyRegistered();
        isMiner[netuid][msg.sender] = true;
        emit MinerRegistered(netuid, msg.sender);
    }

    function unregisterMiner(uint16 netuid) external subnetExists(netuid) {
        if (!isMiner[netuid][msg.sender]) revert MinerNotRegistered();
        isMiner[netuid][msg.sender] = false;
        emit MinerUnregistered(netuid, msg.sender);
    }

    function currentEpoch(uint16 netuid) public view subnetExists(netuid) returns (uint64) {
        return PulseTensorDomain.currentEpoch(block.number, subnets[netuid].epochLengthBlocks);
    }

    function commitWeights(uint16 netuid, bytes32 commitment) external whenSubnetActive(netuid) {
        if (!canValidate(netuid, msg.sender)) revert NotValidator();

        uint64 activeEpochPlusOne = activeCommitEpoch[netuid][msg.sender];
        if (activeEpochPlusOne != 0) {
            uint64 activeEpoch = activeEpochPlusOne - 1;
            PulseTensorDomain.PendingCommitment memory activePending = epochCommitments[netuid][activeEpoch][msg.sender];
            if (activePending.commitment != bytes32(0)) {
                if (block.number <= activePending.expireAtBlock) revert PulseTensorDomain.CommitmentExists();
                revert PulseTensorDomain.CommitmentExpiredNeedsChallenge();
            }
            activeCommitEpoch[netuid][msg.sender] = 0;
        }

        uint64 epoch = currentEpoch(netuid);
        uint64 expireAt = PulseTensorDomain.epochEndBlock(epoch, subnets[netuid].epochLengthBlocks);
        PulseTensorDomain.PendingCommitment memory nextPending = PulseTensorDomain.scheduleCommit(
            epochCommitments[netuid][epoch][msg.sender],
            commitment,
            block.number,
            subnets[netuid].revealDelayBlocks,
            expireAt
        );
        epochCommitments[netuid][epoch][msg.sender] = nextPending;
        if (epoch == type(uint64).max) revert PulseTensorDomain.InvalidConfig();
        activeCommitEpoch[netuid][msg.sender] = epoch + 1;
        _increasePendingCommitmentCount(netuid, msg.sender);

        emit WeightsCommitted(
            netuid, epoch, msg.sender, commitment, nextPending.revealAtBlock, nextPending.expireAtBlock
        );
    }

    function commitMechanismWeights(uint16 netuid, uint16 mechid, bytes32 commitment)
        external
        whenSubnetActive(netuid)
    {
        _validateMechanismId(mechid);
        if (!canValidate(netuid, msg.sender)) revert NotValidator();

        uint64 activeEpochPlusOne = mechanismActiveCommitEpoch[netuid][mechid][msg.sender];
        if (activeEpochPlusOne != 0) {
            uint64 activeEpoch = activeEpochPlusOne - 1;
            PulseTensorDomain.PendingCommitment memory activePending =
                mechanismEpochCommitments[netuid][mechid][activeEpoch][msg.sender];
            if (activePending.commitment != bytes32(0)) {
                if (block.number <= activePending.expireAtBlock) revert PulseTensorDomain.CommitmentExists();
                revert PulseTensorDomain.CommitmentExpiredNeedsChallenge();
            }
            mechanismActiveCommitEpoch[netuid][mechid][msg.sender] = 0;
        }

        uint64 epoch = currentEpoch(netuid);
        uint64 expireAt = PulseTensorDomain.epochEndBlock(epoch, subnets[netuid].epochLengthBlocks);
        PulseTensorDomain.PendingCommitment memory nextPending = PulseTensorDomain.scheduleCommit(
            mechanismEpochCommitments[netuid][mechid][epoch][msg.sender],
            commitment,
            block.number,
            subnets[netuid].revealDelayBlocks,
            expireAt
        );
        mechanismEpochCommitments[netuid][mechid][epoch][msg.sender] = nextPending;
        if (epoch == type(uint64).max) revert PulseTensorDomain.InvalidConfig();
        mechanismActiveCommitEpoch[netuid][mechid][msg.sender] = epoch + 1;
        _increasePendingCommitmentCount(netuid, msg.sender);

        emit MechanismWeightsCommitted(
            netuid, mechid, epoch, msg.sender, commitment, nextPending.revealAtBlock, nextPending.expireAtBlock
        );
    }

    function revealWeights(uint16 netuid, uint64 epoch, bytes32 weightsHash, bytes32 salt)
        external
        subnetExists(netuid)
    {
        PulseTensorDomain.verifyReveal(
            epochCommitments[netuid][epoch][msg.sender],
            block.number,
            weightsHash,
            salt,
            msg.sender,
            netuid,
            epoch,
            block.chainid,
            address(this),
            COMMITMENT_DOMAIN_VERSION
        );
        if (epochRevealed[netuid][epoch][msg.sender]) revert PulseTensorDomain.CommitmentExists();

        epochRevealed[netuid][epoch][msg.sender] = true;
        epochRevealedWeightsHash[netuid][epoch][msg.sender] = weightsHash;
        delete epochCommitments[netuid][epoch][msg.sender];
        if (activeCommitEpoch[netuid][msg.sender] == epoch + 1) {
            activeCommitEpoch[netuid][msg.sender] = 0;
        }
        _decreasePendingCommitmentCount(netuid, msg.sender);
        _maybeUnregisterValidatorIfIneligible(netuid, msg.sender);

        emit WeightsRevealed(netuid, epoch, msg.sender, weightsHash);
    }

    function revealMechanismWeights(uint16 netuid, uint16 mechid, uint64 epoch, bytes32 weightsHash, bytes32 salt)
        external
        subnetExists(netuid)
    {
        _validateMechanismId(mechid);

        PulseTensorDomain.PendingCommitment memory pending =
            mechanismEpochCommitments[netuid][mechid][epoch][msg.sender];
        if (pending.commitment == bytes32(0)) revert PulseTensorDomain.CommitmentMissing();
        if (block.number < pending.revealAtBlock) revert PulseTensorDomain.RevealTooEarly();
        if (block.number > pending.expireAtBlock) revert PulseTensorDomain.RevealExpired();

        bytes32 expectedCommitment = _computeMechanismCommitment(weightsHash, salt, msg.sender, netuid, mechid, epoch);
        if (expectedCommitment != pending.commitment) revert PulseTensorDomain.CommitmentMismatch();
        if (mechanismEpochRevealed[netuid][mechid][epoch][msg.sender]) revert PulseTensorDomain.CommitmentExists();

        mechanismEpochRevealed[netuid][mechid][epoch][msg.sender] = true;
        mechanismEpochRevealedWeightsHash[netuid][mechid][epoch][msg.sender] = weightsHash;
        delete mechanismEpochCommitments[netuid][mechid][epoch][msg.sender];
        if (mechanismActiveCommitEpoch[netuid][mechid][msg.sender] == epoch + 1) {
            mechanismActiveCommitEpoch[netuid][mechid][msg.sender] = 0;
        }
        _decreasePendingCommitmentCount(netuid, msg.sender);
        _maybeUnregisterValidatorIfIneligible(netuid, msg.sender);

        emit MechanismWeightsRevealed(netuid, mechid, epoch, msg.sender, weightsHash);
    }

    function challengeExpiredCommit(uint16 netuid, uint64 epoch, address validator)
        external
        subnetExists(netuid)
        returns (uint256 slashedAmount, bool validatorUnregistered)
    {
        PulseTensorDomain.PendingCommitment memory pending = epochCommitments[netuid][epoch][validator];
        PulseTensorDomain.verifyExpiredCommitment(pending, block.number);

        delete epochCommitments[netuid][epoch][validator];
        if (epoch != type(uint64).max && activeCommitEpoch[netuid][validator] == epoch + 1) {
            activeCommitEpoch[netuid][validator] = 0;
        }
        _decreasePendingCommitmentCount(netuid, validator);

        PulseTensorDomain.SubnetConfig storage subnet = subnets[netuid];
        (uint256 newStake, uint256 newTotalStake, uint256 slashAmount) =
            PulseTensorDomain.slashStakeByBps(stakeOf[netuid][validator], subnet.totalStake, MISSING_REVEAL_SLASH_BPS);
        stakeOf[netuid][validator] = newStake;
        subnet.totalStake = newTotalStake;
        slashedAmount = slashAmount;

        (uint256 challengerRewardAmount, uint256 emissionPoolAmount) =
            _splitSlashedAmount(slashedAmount, msg.sender == validator);
        if (challengerRewardAmount != 0) {
            challengeRewardOf[netuid][msg.sender] += challengerRewardAmount;
            emit ChallengeRewardAccrued(
                netuid, msg.sender, challengerRewardAmount, challengeRewardOf[netuid][msg.sender]
            );
        }
        if (emissionPoolAmount != 0) {
            subnetEmissionPool[netuid] += emissionPoolAmount;
            emit SubnetEmissionFunded(netuid, address(this), emissionPoolAmount, subnetEmissionPool[netuid]);
        }

        validatorUnregistered = _maybeUnregisterValidatorIfIneligible(netuid, validator);

        emit ValidatorSlashed(
            netuid,
            epoch,
            validator,
            msg.sender,
            slashedAmount,
            validatorUnregistered,
            challengerRewardAmount,
            emissionPoolAmount
        );
    }

    function challengeExpiredMechanismCommit(uint16 netuid, uint16 mechid, uint64 epoch, address validator)
        external
        subnetExists(netuid)
        returns (uint256 slashedAmount, bool validatorUnregistered)
    {
        _validateMechanismId(mechid);
        PulseTensorDomain.PendingCommitment memory pending = mechanismEpochCommitments[netuid][mechid][epoch][validator];
        PulseTensorDomain.verifyExpiredCommitment(pending, block.number);

        delete mechanismEpochCommitments[netuid][mechid][epoch][validator];
        if (epoch != type(uint64).max && mechanismActiveCommitEpoch[netuid][mechid][validator] == epoch + 1) {
            mechanismActiveCommitEpoch[netuid][mechid][validator] = 0;
        }
        _decreasePendingCommitmentCount(netuid, validator);

        PulseTensorDomain.SubnetConfig storage subnet = subnets[netuid];
        (uint256 newStake, uint256 newTotalStake, uint256 slashAmount) =
            PulseTensorDomain.slashStakeByBps(stakeOf[netuid][validator], subnet.totalStake, MISSING_REVEAL_SLASH_BPS);
        stakeOf[netuid][validator] = newStake;
        subnet.totalStake = newTotalStake;
        slashedAmount = slashAmount;

        (uint256 challengerRewardAmount, uint256 emissionPoolAmount) =
            _splitSlashedAmount(slashedAmount, msg.sender == validator);
        if (challengerRewardAmount != 0) {
            challengeRewardOf[netuid][msg.sender] += challengerRewardAmount;
            emit ChallengeRewardAccrued(
                netuid, msg.sender, challengerRewardAmount, challengeRewardOf[netuid][msg.sender]
            );
        }
        if (emissionPoolAmount != 0) {
            subnetEmissionPool[netuid] += emissionPoolAmount;
            emit SubnetEmissionFunded(netuid, address(this), emissionPoolAmount, subnetEmissionPool[netuid]);
        }

        validatorUnregistered = _maybeUnregisterValidatorIfIneligible(netuid, validator);

        emit MechanismValidatorSlashed(
            netuid,
            mechid,
            epoch,
            validator,
            msg.sender,
            slashedAmount,
            validatorUnregistered,
            challengerRewardAmount,
            emissionPoolAmount
        );
    }

    function _queueOwnerAction(uint16 netuid, bytes32 actionId) internal returns (uint64 readyAtBlock) {
        uint64 existingReadyAtBlock = subnetOwnerActionReadyAtBlock[netuid][actionId];
        if (existingReadyAtBlock != 0) {
            if (!_isOwnerActionExpired(existingReadyAtBlock)) revert OwnerActionAlreadyQueued();
            delete subnetOwnerActionReadyAtBlock[netuid][actionId];
            delete subnetOwnerActionQueuedBy[netuid][actionId];
        }

        uint64 delay = subnetOwnerActionDelayBlocks[netuid];
        if (delay < MIN_OWNER_ACTION_DELAY_BLOCKS || delay > MAX_OWNER_ACTION_DELAY_BLOCKS) {
            revert InvalidOwnerActionDelay();
        }

        uint256 readyAt = block.number + delay;
        if (readyAt > type(uint64).max) revert PulseTensorDomain.InvalidConfig();
        readyAtBlock = uint64(readyAt);
        subnetOwnerActionReadyAtBlock[netuid][actionId] = readyAtBlock;
        subnetOwnerActionQueuedBy[netuid][actionId] = msg.sender;

        emit SubnetOwnerActionQueued(netuid, actionId, readyAtBlock, msg.sender);
    }

    function _consumeOwnerAction(uint16 netuid, bytes32 actionId) internal {
        uint64 readyAtBlock = subnetOwnerActionReadyAtBlock[netuid][actionId];
        if (readyAtBlock == 0) revert OwnerActionNotQueued();
        address queuedBy = subnetOwnerActionQueuedBy[netuid][actionId];
        if (queuedBy == address(0) || queuedBy != msg.sender) revert OwnerActionQueuedByMismatch();
        if (block.number < readyAtBlock) revert OwnerActionNotReady();
        if (_isOwnerActionExpired(readyAtBlock)) revert OwnerActionExpired();

        delete subnetOwnerActionReadyAtBlock[netuid][actionId];
        delete subnetOwnerActionQueuedBy[netuid][actionId];
        emit SubnetOwnerActionExecuted(netuid, actionId, msg.sender);
    }

    function _isOwnerActionExpired(uint64 readyAtBlock) internal view returns (bool) {
        return block.number > uint256(readyAtBlock) + OWNER_ACTION_EXPIRY_BLOCKS;
    }

    function _pauseActionId(uint16 netuid, bool paused) internal pure returns (bytes32) {
        return keccak256(abi.encode(OWNER_ACTION_PAUSE_TAG, netuid, paused));
    }

    function _configActionId(
        uint16 netuid,
        uint256 minValidatorStake,
        uint16 ownerFeeBps,
        uint64 revealDelayBlocks,
        uint64 epochLengthBlocks
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                OWNER_ACTION_CONFIG_TAG, netuid, minValidatorStake, ownerFeeBps, revealDelayBlocks, epochLengthBlocks
            )
        );
    }

    function _emissionPayoutActionId(uint16 netuid, address recipient, uint256 amount)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(OWNER_ACTION_EMISSION_PAYOUT_TAG, netuid, recipient, amount));
    }

    function _emissionSplitActionId(
        uint16 netuid,
        address validatorRecipient,
        address minerRecipient,
        address ownerRecipient,
        uint256 totalAmount
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                OWNER_ACTION_EMISSION_SPLIT_TAG, netuid, validatorRecipient, minerRecipient, ownerRecipient, totalAmount
            )
        );
    }

    function _mechanismEmissionPayoutActionId(uint16 netuid, uint16 mechid, address recipient, uint256 amount)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(OWNER_ACTION_MECHANISM_EMISSION_PAYOUT_TAG, netuid, mechid, recipient, amount));
    }

    function _mechanismEmissionSplitActionId(
        uint16 netuid,
        uint16 mechid,
        address validatorRecipient,
        address minerRecipient,
        address ownerRecipient,
        uint256 totalAmount
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                OWNER_ACTION_MECHANISM_EMISSION_SPLIT_TAG,
                netuid,
                mechid,
                validatorRecipient,
                minerRecipient,
                ownerRecipient,
                totalAmount
            )
        );
    }

    function _emissionScheduleActionId(
        uint16 netuid,
        uint256 baseEmissionPerEpoch,
        uint256 floorEmissionPerEpoch,
        uint64 halvingPeriodEpochs,
        uint64 startEpoch
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                OWNER_ACTION_EMISSION_SCHEDULE_TAG,
                netuid,
                baseEmissionPerEpoch,
                floorEmissionPerEpoch,
                halvingPeriodEpochs,
                startEpoch
            )
        );
    }

    function _mechanismEmissionScheduleActionId(
        uint16 netuid,
        uint16 mechid,
        uint256 baseEmissionPerEpoch,
        uint256 floorEmissionPerEpoch,
        uint64 halvingPeriodEpochs,
        uint64 startEpoch
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                OWNER_ACTION_MECHANISM_EMISSION_SCHEDULE_TAG,
                netuid,
                mechid,
                baseEmissionPerEpoch,
                floorEmissionPerEpoch,
                halvingPeriodEpochs,
                startEpoch
            )
        );
    }

    function _emissionSmoothingActionId(uint16 netuid, bool smoothDecayEnabled) internal pure returns (bytes32) {
        return keccak256(abi.encode(OWNER_ACTION_EMISSION_SMOOTHING_TAG, netuid, smoothDecayEnabled));
    }

    function _mechanismEmissionSmoothingActionId(uint16 netuid, uint16 mechid, bool smoothDecayEnabled)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(OWNER_ACTION_MECHANISM_EMISSION_SMOOTHING_TAG, netuid, mechid, smoothDecayEnabled));
    }

    function _epochEmissionPayoutActionId(
        uint16 netuid,
        uint64 epoch,
        address validatorRecipient,
        address minerRecipient,
        address ownerRecipient
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                OWNER_ACTION_EPOCH_EMISSION_PAYOUT_TAG,
                netuid,
                epoch,
                validatorRecipient,
                minerRecipient,
                ownerRecipient
            )
        );
    }

    function _mechanismEpochEmissionPayoutActionId(
        uint16 netuid,
        uint16 mechid,
        uint64 epoch,
        address validatorRecipient,
        address minerRecipient,
        address ownerRecipient
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                OWNER_ACTION_MECHANISM_EPOCH_EMISSION_PAYOUT_TAG,
                netuid,
                mechid,
                epoch,
                validatorRecipient,
                minerRecipient,
                ownerRecipient
            )
        );
    }

    function _reduceEmissionPool(uint16 netuid, uint256 amount) internal returns (uint256 newPoolBalance) {
        uint256 poolBalance = subnetEmissionPool[netuid];
        if (amount > poolBalance) revert InsufficientEmissionPool();
        newPoolBalance = poolBalance - amount;
        subnetEmissionPool[netuid] = newPoolBalance;
    }

    function _reduceMechanismEmissionPool(uint16 netuid, uint16 mechid, uint256 amount)
        internal
        returns (uint256 newPoolBalance)
    {
        uint256 poolBalance = mechanismEmissionPool[netuid][mechid];
        if (amount > poolBalance) revert InsufficientMechanismEmissionPool();
        newPoolBalance = poolBalance - amount;
        mechanismEmissionPool[netuid][mechid] = newPoolBalance;
    }

    function _transferValue(address payable recipient, uint256 amount) internal {
        (bool sent,) = recipient.call{value: amount}("");
        if (!sent) revert TransferFailed();
    }

    function _splitSlashedAmount(uint256 slashedAmount, bool selfChallenge)
        internal
        pure
        returns (uint256 challengerRewardAmount, uint256 emissionPoolAmount)
    {
        if (slashedAmount == 0) {
            return (0, 0);
        }
        if (selfChallenge) {
            return (0, slashedAmount);
        }
        if (CHALLENGE_BOUNTY_BPS > BPS_DENOMINATOR) {
            revert PulseTensorDomain.InvalidConfig();
        }

        challengerRewardAmount = (slashedAmount * CHALLENGE_BOUNTY_BPS) / BPS_DENOMINATOR;
        if (challengerRewardAmount == 0) {
            challengerRewardAmount = 1;
        }
        if (challengerRewardAmount > slashedAmount) {
            challengerRewardAmount = slashedAmount;
        }

        emissionPoolAmount = slashedAmount - challengerRewardAmount;
    }

    function _validateEmissionSchedule(
        uint256 baseEmissionPerEpoch,
        uint256 floorEmissionPerEpoch,
        uint64 halvingPeriodEpochs
    ) internal pure {
        if (baseEmissionPerEpoch == 0) revert InvalidEmissionSchedule();
        if (floorEmissionPerEpoch > baseEmissionPerEpoch) revert InvalidEmissionSchedule();
        if (halvingPeriodEpochs == 0) revert InvalidEmissionSchedule();
    }

    function _validateMechanismId(uint16 mechid) internal pure {
        if (mechid > MAX_MECHANISM_ID) revert InvalidMechanismId();
    }

    function _increasePendingCommitmentCount(uint16 netuid, address validator) internal {
        pendingCommitmentCount[netuid][validator] += 1;
    }

    function _decreasePendingCommitmentCount(uint16 netuid, address validator) internal {
        uint256 currentCount = pendingCommitmentCount[netuid][validator];
        if (currentCount == 0) revert PulseTensorDomain.InvalidConfig();
        unchecked {
            pendingCommitmentCount[netuid][validator] = currentCount - 1;
        }
    }

    function _hasActiveCommitment(uint16 netuid, address validator) internal view returns (bool) {
        return pendingCommitmentCount[netuid][validator] != 0;
    }

    function _maybeUnregisterValidatorIfIneligible(uint16 netuid, address validator)
        internal
        returns (bool unregistered)
    {
        if (!isValidator[netuid][validator]) return false;
        if (_hasActiveCommitment(netuid, validator)) return false;
        if (stakeOf[netuid][validator] >= subnets[netuid].minValidatorStake) return false;

        isValidator[netuid][validator] = false;
        uint16 currentValidatorCount = validatorCount[netuid];
        if (currentValidatorCount == 0) revert PulseTensorDomain.InvalidConfig();
        unchecked {
            validatorCount[netuid] = currentValidatorCount - 1;
        }
        emit ValidatorUnregistered(netuid, validator);
        return true;
    }

    function quoteSubnetEpochEmission(uint16 netuid, uint64 epoch) external view returns (uint256 emissionAmount) {
        return _quoteSubnetEpochEmission(netuid, epoch);
    }

    function _quoteSubnetEpochEmission(uint16 netuid, uint64 epoch) internal view returns (uint256 emissionAmount) {
        uint64 halvingPeriodEpochs = subnetEpochEmissionHalvingPeriod[netuid];
        if (halvingPeriodEpochs == 0) return 0;

        uint64 startEpoch = subnetEpochEmissionStart[netuid];
        if (epoch < startEpoch) return 0;

        uint256 baseEmissionPerEpoch = subnetEpochEmissionBase[netuid];
        uint256 floorEmissionPerEpoch = subnetEpochEmissionFloor[netuid];
        bool smoothDecayEnabled = subnetEmissionSmoothDecayEnabled[netuid];
        emissionAmount = _quoteEpochEmission(
            baseEmissionPerEpoch, floorEmissionPerEpoch, halvingPeriodEpochs, startEpoch, epoch, smoothDecayEnabled
        );
    }

    function quoteMechanismEpochEmission(uint16 netuid, uint16 mechid, uint64 epoch) external view returns (uint256) {
        return _quoteMechanismEpochEmission(netuid, mechid, epoch);
    }

    function _quoteMechanismEpochEmission(uint16 netuid, uint16 mechid, uint64 epoch)
        internal
        view
        returns (uint256 emissionAmount)
    {
        _validateMechanismId(mechid);
        uint64 halvingPeriodEpochs = mechanismEpochEmissionHalvingPeriod[netuid][mechid];
        if (halvingPeriodEpochs == 0) return 0;

        uint64 startEpoch = mechanismEpochEmissionStart[netuid][mechid];
        if (epoch < startEpoch) return 0;

        uint256 baseEmissionPerEpoch = mechanismEpochEmissionBase[netuid][mechid];
        uint256 floorEmissionPerEpoch = mechanismEpochEmissionFloor[netuid][mechid];
        bool smoothDecayEnabled = mechanismEmissionSmoothDecayEnabled[netuid][mechid];
        emissionAmount = _quoteEpochEmission(
            baseEmissionPerEpoch, floorEmissionPerEpoch, halvingPeriodEpochs, startEpoch, epoch, smoothDecayEnabled
        );
    }

    function _quoteEpochEmission(
        uint256 baseEmissionPerEpoch,
        uint256 floorEmissionPerEpoch,
        uint64 halvingPeriodEpochs,
        uint64 startEpoch,
        uint64 epoch,
        bool smoothDecayEnabled
    ) internal pure returns (uint256 emissionAmount) {
        uint64 elapsedEpochs = epoch - startEpoch;
        uint64 halvings = elapsedEpochs / halvingPeriodEpochs;

        if (halvings >= 256) {
            return floorEmissionPerEpoch;
        }

        uint256 currentStepEmission = baseEmissionPerEpoch >> halvings;
        if (currentStepEmission < floorEmissionPerEpoch) {
            return floorEmissionPerEpoch;
        }
        if (!smoothDecayEnabled) {
            return currentStepEmission;
        }

        uint64 remainder = elapsedEpochs % halvingPeriodEpochs;
        if (remainder == 0) {
            return currentStepEmission;
        }

        uint256 nextStepEmission = currentStepEmission >> 1;
        if (nextStepEmission < floorEmissionPerEpoch) {
            nextStepEmission = floorEmissionPerEpoch;
        }
        if (nextStepEmission >= currentStepEmission) {
            return currentStepEmission;
        }

        uint256 stepDelta = currentStepEmission - nextStepEmission;
        emissionAmount = currentStepEmission - ((stepDelta * remainder) / halvingPeriodEpochs);
        if (emissionAmount < floorEmissionPerEpoch) {
            emissionAmount = floorEmissionPerEpoch;
        }
    }

    function _quoteDefaultEmissionSplit(uint256 totalAmount)
        internal
        pure
        returns (uint256 validatorAmount, uint256 minerAmount, uint256 ownerAmount)
    {
        if (totalAmount == 0) revert PulseTensorDomain.ZeroAmount();
        if (VALIDATOR_EMISSION_BPS + MINER_EMISSION_BPS + OWNER_EMISSION_BPS > BPS_DENOMINATOR) {
            revert PulseTensorDomain.InvalidConfig();
        }
        validatorAmount = (totalAmount * VALIDATOR_EMISSION_BPS) / BPS_DENOMINATOR;
        minerAmount = (totalAmount * MINER_EMISSION_BPS) / BPS_DENOMINATOR;
        ownerAmount = (totalAmount * OWNER_EMISSION_BPS) / BPS_DENOMINATOR;
        uint256 distributedAmount = validatorAmount + minerAmount + ownerAmount;
        if (distributedAmount < totalAmount) {
            ownerAmount += totalAmount - distributedAmount;
        }
    }

    function _computeMechanismCommitment(
        bytes32 weightsHash,
        bytes32 salt,
        address validator,
        uint16 netuid,
        uint16 mechid,
        uint64 epoch
    ) internal view returns (bytes32) {
        _validateMechanismId(mechid);
        return keccak256(
            abi.encode(
                weightsHash,
                salt,
                validator,
                netuid,
                mechid,
                epoch,
                block.chainid,
                address(this),
                COMMITMENT_DOMAIN_VERSION
            )
        );
    }
}

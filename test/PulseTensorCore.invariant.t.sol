// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";
import {PulseTensorCore} from "../src/PulseTensorCore.sol";

contract PulseTensorCoreInvariantHandler is Test {
    PulseTensorCore internal immutable core;
    uint16 internal immutable netuid;
    address internal immutable owner;
    address[] internal actors;

    uint256 internal trackedTotalStakeValue;
    uint16 internal trackedValidatorCountValue;
    mapping(address => uint256) internal trackedStake;
    mapping(address => bool) internal trackedValidator;

    constructor(PulseTensorCore _core, uint16 _netuid, address _owner, address[] memory _actors) {
        core = _core;
        netuid = _netuid;
        owner = _owner;
        for (uint256 index = 0; index < _actors.length; index++) {
            actors.push(_actors[index]);
        }
    }

    function _pickActor(uint256 actorSeed) internal view returns (address) {
        return actors[actorSeed % actors.length];
    }

    function addStake(uint256 actorSeed, uint256 amountSeed) external {
        address actor = _pickActor(actorSeed);
        uint256 balance = actor.balance;
        if (balance == 0) return;

        uint256 maxAmount = balance > 20 ether ? 20 ether : balance;
        uint256 amount = bound(amountSeed, 1, maxAmount);

        vm.prank(actor);
        try core.addStake{value: amount}(netuid) {
            trackedStake[actor] += amount;
            trackedTotalStakeValue += amount;
        } catch {}
    }

    function removeStake(uint256 actorSeed, uint256 amountSeed) external {
        address actor = _pickActor(actorSeed);
        uint256 currentStake = trackedStake[actor];
        if (currentStake == 0) return;

        uint256 amount = bound(amountSeed, 1, currentStake);
        vm.prank(actor);
        try core.removeStake(netuid, amount) {
            trackedStake[actor] -= amount;
            trackedTotalStakeValue -= amount;
        } catch {}
    }

    function registerValidator(uint256 actorSeed) external {
        address actor = _pickActor(actorSeed);
        if (trackedValidator[actor]) return;

        vm.prank(actor);
        try core.registerValidator(netuid) {
            trackedValidator[actor] = true;
            trackedValidatorCountValue += 1;
        } catch {}
    }

    function unregisterValidator(uint256 actorSeed) external {
        address actor = _pickActor(actorSeed);
        if (!trackedValidator[actor]) return;

        vm.prank(actor);
        try core.unregisterValidator(netuid) {
            trackedValidator[actor] = false;
            trackedValidatorCountValue -= 1;
        } catch {}
    }

    function togglePause(bool paused) external {
        uint64 readyAtBlock;
        try core.queueSubnetPause(netuid, paused) returns (bytes32, uint64 readyAt) {
            readyAtBlock = readyAt;
        } catch {
            return;
        }

        if (block.number < readyAtBlock) {
            vm.roll(readyAtBlock);
        }

        try core.setSubnetPaused(netuid, paused) {} catch {}
    }

    function rollBlocks(uint64 blocksRaw) external {
        uint64 blocks = uint64(bound(uint256(blocksRaw), 1, 20));
        vm.roll(block.number + blocks);
    }

    function trackedTotalStake() external view returns (uint256) {
        return trackedTotalStakeValue;
    }

    function trackedValidatorCount() external view returns (uint16) {
        return trackedValidatorCountValue;
    }

    function isTrackedValidator(address actor) external view returns (bool) {
        return trackedValidator[actor];
    }

    function trackedStakeOf(address actor) external view returns (uint256) {
        return trackedStake[actor];
    }
}

contract PulseTensorCoreInvariantTest is StdInvariant, Test {
    PulseTensorCore internal core;
    PulseTensorCoreInvariantHandler internal handler;
    uint16 internal netuid;
    address internal owner = makeAddr("owner");
    address[] internal actors;

    function setUp() public {
        vm.prank(owner);
        core = new PulseTensorCore();

        vm.prank(owner);
        netuid = core.createSubnet(4, 1 ether, 500, 2, 16);

        actors = new address[](5);
        for (uint256 index = 0; index < actors.length; index++) {
            actors[index] = makeAddr(string.concat("actor-", vm.toString(index)));
            vm.deal(actors[index], 2_000 ether);
        }

        handler = new PulseTensorCoreInvariantHandler(core, netuid, owner, actors);
        vm.prank(owner);
        core.configureSubnetGovernance(netuid, address(handler), 2);
        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = handler.addStake.selector;
        selectors[1] = handler.removeStake.selector;
        selectors[2] = handler.registerValidator.selector;
        selectors[3] = handler.unregisterValidator.selector;
        selectors[4] = handler.togglePause.selector;
        selectors[5] = handler.rollBlocks.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_TotalStakeMatchesTrackedActors() external view {
        (,,,,,, uint256 subnetTotalStake) = core.subnets(netuid);
        assertEq(subnetTotalStake, handler.trackedTotalStake());
    }

    function invariant_ValidatorCountMatchesTrackedActors() external view {
        assertEq(core.validatorCount(netuid), handler.trackedValidatorCount());
    }

    function invariant_RegisteredValidatorsRespectBounds() external view {
        (, uint16 maxValidators,,,,,) = core.subnets(netuid);
        assertLe(core.validatorCount(netuid), maxValidators);
    }

    function invariant_TrackedValidatorsCanValidate() external view {
        (, uint16 maxValidators,,,, uint256 minStake,) = core.subnets(netuid);
        assertLe(core.validatorCount(netuid), maxValidators);

        for (uint256 index = 0; index < actors.length; index++) {
            address actor = actors[index];
            if (handler.isTrackedValidator(actor)) {
                assertTrue(core.canValidate(netuid, actor));
                assertGe(core.stakeOf(netuid, actor), minStake);
                assertTrue(core.isValidator(netuid, actor));
            }
        }
    }
}

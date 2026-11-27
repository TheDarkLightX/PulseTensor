// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ControlID} from "risc0/groth16/ControlID.sol";
import {RiscZeroGroth16Verifier} from "risc0/groth16/RiscZeroGroth16Verifier.sol";
import {PulseTensorCore} from "../src/PulseTensorCore.sol";
import {PulseTensorExactInferenceSettlementV1} from "../src/PulseTensorExactInferenceSettlementV1.sol";
import {RiscZeroVerifierAdapter} from "../src/adapters/RiscZeroVerifierAdapter.sol";

contract ReplayGovernance {}

contract FundedTaskTest is Test {
    uint256 private constant ESCROW = 10_001;
    uint16 private constant FEE_BPS = 1_200;
    address private constant REQUESTER = address(0x1001);
    address private constant PROVIDER = address(0x2001);
    address private constant BENEFICIARY = address(0x3001);
    address private constant TREASURY = address(0x4001);

    PulseTensorExactInferenceSettlementV1 private settlement;
    RiscZeroGroth16Verifier private directVerifier;
    bytes private journal;
    uint256 private taskId;
    int64[4] private scores;
    uint8 private classIndex;

    function setUp() public {
        vm.chainId(31337);
        vm.roll(1000);
        PulseTensorCore core = new PulseTensorCore();
        settlement = new PulseTensorExactInferenceSettlementV1(address(core));
        directVerifier = new RiscZeroGroth16Verifier(ControlID.CONTROL_ROOT, ControlID.BN254_CONTROL_ID);
        RiscZeroVerifierAdapter adapter =
            new RiscZeroVerifierAdapter(address(directVerifier), 0xe71e6620, address(directVerifier).codehash);

        uint16 netuid = core.createSubnet(64, 1 ether, 500, 2, 16);
        address governance = address(new ReplayGovernance());
        core.configureSubnetGovernance(netuid, governance, 2);
        bytes memory fixtureJournal = vm.parseBytes(string.concat("0x", vm.trim(vm.readFile("fixtures/journal.hex"))));
        PulseTensorExactInferenceSettlementV1.ExactInferencePublicValuesV1 memory fixture =
            abi.decode(fixtureJournal, (PulseTensorExactInferenceSettlementV1.ExactInferencePublicValuesV1));

        PulseTensorExactInferenceSettlementV1.VerifierConfigInput memory config = PulseTensorExactInferenceSettlementV1
            .VerifierConfigInput({
            netuid: netuid,
            adapter: address(adapter),
            adapterRuntimeCodeHash: address(adapter).codehash,
            verifierRuntimeCodeHash: address(directVerifier).codehash,
            programId: vm.parseBytes32(string.concat("0x", vm.trim(vm.readFile("fixtures/image_id.txt")))),
            relationId: fixture.relationId,
            proofSystemId: adapter.proofSystemId(),
            proofSelector: adapter.proofSelector(),
            protocolFeeBps: FEE_BPS,
            treasury: TREASURY
        });
        vm.prank(governance);
        (bytes32 actionId, uint64 readyAt) = settlement.queueVerifierConfig(config);
        vm.roll(readyAt);
        vm.prank(governance);
        uint64 configId = settlement.executeVerifierConfig(config, actionId);

        vm.deal(REQUESTER, ESCROW);
        vm.prank(REQUESTER);
        taskId = settlement.createExactInferenceTask{value: ESCROW}(
            netuid,
            1,
            configId,
            fixture.inputCommitment,
            fixture.modelCommitment,
            7,
            uint64(block.number + 100),
            REQUESTER
        );
        classIndex = fixture.classIndex;
        scores = fixture.scores;
        journal = settlement.encodeExactInferencePublicValues(taskId, PROVIDER, BENEFICIARY, classIndex, scores);
    }

    function testWriteRealTaskJournal() public {
        vm.writeFileBinary("fixtures/funded_task_journal.bin", journal);
    }

    function testSettleFundedTaskWithRealProof() public {
        bytes memory seal = vm.parseBytes(vm.trim(vm.readFile("fixtures/funded_task_seal.hex")));
        assertEq(seal.length, 260);
        assertEq(journal, vm.readFileBinary("fixtures/funded_task_journal.bin"));

        uint256 gasBefore = gasleft();
        settlement.submitExactInferenceProof(taskId, PROVIDER, BENEFICIARY, classIndex, scores, seal);
        emit log_named_uint("local exact settlement gas (before calldata charge)", gasBefore - gasleft());
        emit log_named_bytes32("direct verifier runtime hash", address(directVerifier).codehash);
        assertEq(
            uint256(settlement.exactInferenceTasks(taskId).status),
            uint256(PulseTensorExactInferenceSettlementV1.TaskStatus.ProofSettled)
        );
        assertEq(settlement.totalOpenEscrowWei(), 0);
        assertEq(settlement.claimableWei(BENEFICIARY), 8_801);
        assertEq(settlement.claimableWei(TREASURY), 1_200);
        assertTrue(settlement.accountingInvariantHolds());

        vm.prank(BENEFICIARY);
        settlement.claim(payable(BENEFICIARY), 8_801);
        vm.prank(TREASURY);
        settlement.claim(payable(TREASURY), 1_200);
        assertEq(BENEFICIARY.balance, 8_801);
        assertEq(TREASURY.balance, 1_200);
        assertEq(address(settlement).balance, 0);
        assertTrue(settlement.accountingInvariantHolds());
    }
}

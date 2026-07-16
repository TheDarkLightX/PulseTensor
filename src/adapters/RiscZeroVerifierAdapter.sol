// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {
    IPulseTensorProofVerifier, IPulseTensorProofVerifierMetadata
} from "../interfaces/IPulseTensorProofVerifier.sol";
import {IRiscZeroVerifierWithSelector} from "../interfaces/IRiscZeroVerifier.sol";

/// @notice Non-upgradeable RISC Zero Groth16 adapter for PulseTensor public-value journals.
/// @dev This contract intentionally targets a direct verifier exposing `SELECTOR()`. It does
///      not trust a mutable router or proxy. `programId` is the public RISC Zero image ID; it
///      is a program commitment, not a secret or signing key.
contract RiscZeroVerifierAdapter is IPulseTensorProofVerifier, IPulseTensorProofVerifierMetadata {
    bytes32 public constant RISC_ZERO_GROTH16_V3_PROOF_SYSTEM_ID = keccak256("PULSETENSOR_RISC_ZERO_GROTH16_V3");
    bytes32 public constant RISC_ZERO_VERSION_HASH = keccak256("3.0.0");
    uint256 public constant RISC_ZERO_GROTH16_V3_SEAL_BYTES = 4 + 8 * 32;

    error InvalidVerifier();
    error InvalidProgramId();
    error InvalidProofSelector();
    error VerifierSelectorMismatch(bytes4 expected, bytes4 actual);
    error VerifierVersionMismatch();
    error VerifierRuntimeCodeHashMismatch(bytes32 expected, bytes32 actual);

    address public immutable RISC_ZERO_VERIFIER;
    bytes4 public immutable PROOF_SELECTOR;
    bytes32 public immutable VERIFIER_RUNTIME_CODE_HASH;

    constructor(address verifierAddress, bytes4 expectedSelector, bytes32 expectedRuntimeCodeHash) {
        if (
            verifierAddress == address(0) || verifierAddress.code.length == 0 || expectedSelector == bytes4(0)
                || expectedRuntimeCodeHash == bytes32(0)
        ) revert InvalidVerifier();

        bytes32 actualRuntimeCodeHash = verifierAddress.codehash;
        if (actualRuntimeCodeHash != expectedRuntimeCodeHash) {
            revert VerifierRuntimeCodeHashMismatch(expectedRuntimeCodeHash, actualRuntimeCodeHash);
        }

        bytes4 actualSelector = IRiscZeroVerifierWithSelector(verifierAddress).SELECTOR();
        if (actualSelector != expectedSelector) revert VerifierSelectorMismatch(expectedSelector, actualSelector);
        if (keccak256(bytes(IRiscZeroVerifierWithSelector(verifierAddress).VERSION())) != RISC_ZERO_VERSION_HASH) {
            revert VerifierVersionMismatch();
        }

        RISC_ZERO_VERIFIER = verifierAddress;
        PROOF_SELECTOR = expectedSelector;
        VERIFIER_RUNTIME_CODE_HASH = expectedRuntimeCodeHash;
    }

    function proofSystemId() external pure override returns (bytes32) {
        return RISC_ZERO_GROTH16_V3_PROOF_SYSTEM_ID;
    }

    function proofSelector() external view override returns (bytes4) {
        return PROOF_SELECTOR;
    }

    function verifierRuntimeCodeHash() external view override returns (bytes32) {
        return VERIFIER_RUNTIME_CODE_HASH;
    }

    function verify(bytes32 programId, bytes calldata publicValues, bytes calldata proof) external view override {
        if (programId == bytes32(0)) revert InvalidProgramId();
        if (proof.length != RISC_ZERO_GROTH16_V3_SEAL_BYTES || bytes4(proof[:4]) != PROOF_SELECTOR) {
            revert InvalidProofSelector();
        }

        bytes32 actualRuntimeCodeHash = RISC_ZERO_VERIFIER.codehash;
        if (actualRuntimeCodeHash != VERIFIER_RUNTIME_CODE_HASH) {
            revert VerifierRuntimeCodeHashMismatch(VERIFIER_RUNTIME_CODE_HASH, actualRuntimeCodeHash);
        }

        IRiscZeroVerifierWithSelector(RISC_ZERO_VERIFIER).verify(proof, programId, sha256(publicValues));
    }

    function verifierRuntimeCodeHashMatches() external view override returns (bool) {
        return RISC_ZERO_VERIFIER.codehash == VERIFIER_RUNTIME_CODE_HASH;
    }
}

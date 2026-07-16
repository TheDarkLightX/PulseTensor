// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Proof-system-neutral verifier boundary used by exact PulseTensor settlements.
/// @dev Implementations MUST revert unless `proof` establishes execution of `programId`
///      with exactly `publicValues` as its public output.
interface IPulseTensorProofVerifier {
    function verify(bytes32 programId, bytes calldata publicValues, bytes calldata proof) external view;

    function proofSystemId() external view returns (bytes32);
}

/// @notice Verifier metadata committed by a PulseTensor verifier configuration.
/// @dev Production implementations MUST return deployment-immutable metadata; this interface cannot enforce
///      immutability. The runtime hash is for the underlying proof verifier, not this adapter. The settlement
///      separately snapshots and checks the adapter's runtime code hash.
interface IPulseTensorProofVerifierMetadata {
    function proofSelector() external view returns (bytes4);

    function verifierRuntimeCodeHash() external view returns (bytes32);

    /// @notice True only while the adapter's pinned underlying verifier still has the committed runtime code.
    /// @dev Implementations MUST be side-effect-free, complete within 50,000 gas, and return one canonical
    ///      32-byte ABI boolean. The settlement treats every failure or malformed response as unavailable.
    function verifierRuntimeCodeHashMatches() external view returns (bool);
}

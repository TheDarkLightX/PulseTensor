// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Minimal Apache-compatible RISC Zero verifier ABI used by the adapter.
interface IRiscZeroVerifier {
    function verify(bytes calldata seal, bytes32 imageId, bytes32 journalDigest) external view;
}

/// @notice Direct RISC Zero verifier metadata. Routers and proxies are intentionally unsupported.
interface IRiscZeroVerifierWithSelector is IRiscZeroVerifier {
    function SELECTOR() external view returns (bytes4);

    function VERSION() external view returns (string memory);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// Compiled only by the harness-checker mutation test. Echidna must reject this
// parameterized, non-Boolean function as a property.
contract InvalidEchidnaHarness {
    function echidna_invalid(uint256 value) external pure returns (bytes32) {
        return bytes32(value);
    }
}

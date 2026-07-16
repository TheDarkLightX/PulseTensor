// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PulseTensorCoreEchidna} from "../PulseTensorCoreEchidna.sol";

/// @dev Negative control for the release gate. Production verification must
///      demonstrate that the selected Echidna image exits with failure here.
contract PulseTensorCoreEchidnaKnownFailure is PulseTensorCoreEchidna {
    constructor() payable PulseTensorCoreEchidna() {}

    function echidna_gate_known_failure() external pure returns (bool) {
        return false;
    }
}

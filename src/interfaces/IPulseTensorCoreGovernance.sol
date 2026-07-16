// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Read-only Core surface required by the exact-inference companion settlement.
interface IPulseTensorCoreGovernance {
    function subnetGovernance(uint16 netuid) external view returns (address);

    function subnetGovernanceGeneration(uint16 netuid) external view returns (uint64);

    function subnetOwnerActionDelayBlocks(uint16 netuid) external view returns (uint64);

    function subnetPaused(uint16 netuid) external view returns (bool);
}

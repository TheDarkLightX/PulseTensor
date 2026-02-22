# Bittensor -> PulseTensor Delta

This is the baseline design transfer for PulseTensor.

## What We Keep

- Subnet abstraction for specialized AI markets.
- Miner/validator role split for quality competition.
- Commit/reveal weight flow to reduce direct copying.
- Stake-based eligibility for validator influence.
- Epoch-gated operations and delayed reveal semantics (same anti-front-running class used across Bittensor flows).
- Explicit validator capacity and minimum-stake admission constraints.

## What We Improve

1. **EVM-native settlement on Pulsechain**
   - Core incentive and staking logic lives in audit-ready smart contracts with formal and test gates.
   - Lower operational friction for integrations with Pulsechain DeFi and wallets.

2. **Formal-first protocol evolution**
   - Every contract-level transition has a corresponding ESSO model.
   - Promotion requires `validate` + `verify-multi` gates before implementation merge.

3. **Stronger anti-collusion and anti-copying controls**
   - Commit/reveal tied to explicit timing windows and validator-bound commitments.
   - Mechanism-scoped commit/reveal lanes (`mechid`) for independent incentive channels within a subnet.
   - Permissionless dispute hook to challenge expired unrevealed commits with automatic stake slashing.
   - Morph stress campaigns used to search adversarial strategies before release.

4. **Research-to-production bridge**
   - ZAG/Lean used for theorem-backed algorithmic components.
   - Morph used as an untrusted idea generator; only verified candidates can graduate.

5. **Contract modularity for correctness**
   - Separate modules for registry, stake ledger, emissions, and disputes.
   - Smaller modules mean smaller state spaces and easier formal checking.

## Source Snapshot Used

- Bittensor SDK repo (`external/bittensor`, commit `c3751f0c1`)
- Bittensor docs:
  - https://docs.learnbittensor.org/subnets/understanding-subnets
  - https://docs.learnbittensor.org/validators
  - https://docs.learnbittensor.org/learn/yuma-consensus
- Pulsechain execution client (`external/go-pulse`) for network constraints and chain config.

## Bittensor-Derived Controls Implemented in PulseTensor

1. **Stake precondition enforcement**
   - Rejects registration without minimum stake.
   - Rejects validator withdrawals that would violate minimum stake.
   - Covered by:
     - `test/PulseTensorCore.t.sol` (`testRegisterValidatorRequiresMinStake`, `testValidatorCannotWithdrawBelowMinimumStake`)
     - `test/PulseTensorCore.fuzz.t.sol` (`testFuzz_ValidatorWithdrawEnforcesMinimumStake`)

2. **Subnet capacity and role consistency**
   - Enforces validator cap.
   - Prevents duplicate register/unregister misuse patterns.
   - Covered by:
     - `test/PulseTensorCore.t.sol` (`testValidatorCapacityEnforced`, `testMinerRegisterAndUnregister`)
     - `test/PulseTensorCore.invariant.t.sol` (`invariant_ValidatorCountMatchesTrackedActors`, `invariant_RegisteredValidatorsRespectBounds`)

3. **Commit/reveal anti-copying discipline**
   - Validator-only commit.
   - Binding to `{weightsHash, salt, validator, subnet, epoch, chainId, contractAddress, protocolVersion}`.
   - Boundary semantics are explicit:
     - Reveal valid iff `currentBlock >= revealAtBlock && currentBlock <= expireAtBlock`.
     - Challenge valid iff `currentBlock > expireAtBlock`.
   - Duplicate commit, wrong salt, early reveal, future-epoch reveal, and double reveal rejection.
   - Unrevealed commitments expire at epoch end but remain unresolved until challenged.
   - Validators cannot recommit while an expired unresolved commitment exists; permissionless challenge is required (including self-challenge by the validator).
   - Self-challenge is allowed for liveness but does not pay bounty to the challenged validator (full slash is routed to emission pool on self-challenge).
   - Slash collateral is now enforced while a commitment is unresolved:
     - Validators cannot withdraw stake while a pending commitment exists.
     - Validators cannot unregister while a pending commitment exists.
     - Automatic validator-unregister on under-minimum stake is deferred until all pending commitments are resolved; final reveal/challenge performs cleanup.
     - This closes the "commit then withdraw/unregister before challenge" escape hatch and keeps slashing enforceable.
   - Reveal acceptance is bound to commitment timing windows (`revealAtBlock`/`expireAtBlock`) and remains valid even if governance later changes subnet epoch length.
   - Expired unrevealed commitments are challenged and slashed to reduce griefing and stale-state risk (`slash = max(1, stake * 500 / 10000)` bounded by available stake).
   - Slash accounting is explicit and non-lossy:
     - Non-self challenge reward = `max(1, slash * 2000 / 10000)`, bounded by slash amount.
     - Self-challenge reward = `0`; full slash is routed to subnet emission pool.
     - Remaining slash (or full slash for self-challenge) is routed to subnet emission pool.
   - Covered by:
     - `test/PulseTensorCore.t.sol` (`testCommitRevealFlow`, `testMechanismCommitRevealFlow`, `testMechanismCommitmentIncludesMechanismId`, `testDuplicateCommitInSameEpochReverts`, `testRevealWrongSaltReverts`, `testRevealFutureEpochReverts`, `testDoubleRevealReverts`, `testCommitCanResumeAfterExpiredPendingCommitment`, `testCommitTooLateInEpochReverts`, `testChallengeExpiredCommitSlashesStakeAndClearsPending`, `testChallengeExpiredMechanismCommitSlashesStakeAndClearsPending`, `testChallengeExpiredCommitBeforeExpiryReverts`, `testChallengeExpiredCommitCanUnregisterValidator`, `testChallengeExpiredCommitCannotBeAppliedTwice`, `testChallengeExpiredCommitWorksWhileSubnetPaused`, `testValidatorCannotWithdrawWithPendingCommitment`, `testValidatorCannotWithdrawWithPendingMechanismCommitment`, `testValidatorCannotUnregisterWithPendingCommitment`, `testSelfChallengeRoutesFullSlashToEmissionPool`, `testSelfChallengeMechanismRoutesFullSlashToEmissionPool`, `testRevealStillWorksAfterEpochLengthIncrease`, `testMechanismRevealStillWorksAfterEpochLengthIncrease`, `testRevealStillWorksAfterEpochLengthDecrease`, `testMechanismRevealStillWorksAfterEpochLengthDecrease`, `testChallengerCanClaimAccruedReward`, `testCannotClaimChallengeRewardAboveBalance`)
     - `test/PulseTensorCore.fuzz.t.sol` (`testFuzz_CommitRevealIsBoundToEpochSaltAndValidator`, `testFuzz_MechanismCommitRevealIsBoundToEpochSaltValidatorAndMechid`, `testFuzz_ChallengeExpiredCommitSlashesBoundedAmount`, `testFuzz_SelfChallengeRoutesFullSlashToPool`, `testFuzz_PendingCommitmentLocksStakeUntilReveal`)

4. **Reentrancy defenses on critical value paths**
   - Reentrancy guard enforced on `removeStake` and `claimChallengeReward`.
   - External value transfers use explicit return-value checks and revert on failure.
   - Covered by:
     - `test/PulseTensorCore.t.sol` (`testReentrancyIsBlockedOnWithdraw`)

5. **Pause authority and governance bounds**
   - Privileged subnet controls are routed through governance contract + on-chain timelock queue/execute.
   - Subnet ownership transfer is explicit two-step (`initiate`/`accept`) to reduce key-loss and handover risk.
   - Covered by:
     - `test/PulseTensorCore.t.sol` (`testOnlyOwnerCanConfigureSubnetGovernance`, `testGovernanceCanPauseSubnetAfterDelay`, `testOnlyGovernanceCanQueuePause`, `testOnlyGovernanceCanQueueSubnetConfigUpdate`, `testGovernanceCanUpdateSubnetConfigAfterDelay`, `testSubnetOwnerTransferIsTwoStep`)

6. **Emission accounting and low-risk payout defaults**
   - Emissions are explicit contract liabilities (`subnetEmissionPool`) and can be funded directly or via slash routing.
   - Governance-controlled emission payouts use the same timelock queue/execute path as other privileged actions.
   - Default split payout mirrors Bittensor-style role proportions:
     - Validator sink: 41%
     - Miner sink: 41%
     - Owner sink: 18%
   - Covered by:
     - `test/PulseTensorCore.t.sol` (`testOnlyGovernanceCanQueueEmissionPayout`, `testGovernanceCanPayoutEmissionAfterDelay`, `testGovernanceCanPayoutDefaultEmissionSplit`)
     - `test/PulseTensorCore.fuzz.t.sol` (`testFuzz_DefaultEmissionSplitConservesTotal`)

7. **Multi-mechanism emission isolation (Bittensor-aligned improvement)**
   - Added per-mechanism emission pools (`mechanismEmissionPool[netuid][mechid]`) to support independent incentive tracks inside a single subnet.
   - Added per-mechanism epoch schedules and payout tracking (`mechanismEpochEmissionBase/Floor/HalvingPeriod/Start/Paid`) so each mechanism can run an independent halving curve.
   - Mechanism payouts are governance-timelocked (queue/execute), matching the existing fail-closed privileged action pattern.
   - Emission isolation is explicit:
     - Payout from one mechanism pool cannot drain another mechanism pool.
     - Mechanism payouts do not mutate `subnetEmissionPool`.
     - Mechanism epoch payouts are finalized-epoch only and one-time per `(netuid, mechid, epoch)`.
   - Covered by:
     - `test/PulseTensorCore.t.sol` (`testInvalidMechanismIdRevertsOnFunding`, `testOnlyGovernanceCanQueueMechanismEmissionPayout`, `testGovernanceCanPayoutMechanismEmissionAfterDelay`, `testGovernanceCanPayoutMechanismEmissionSplit`, `testOnlyGovernanceCanQueueMechanismEmissionScheduleUpdate`, `testGovernanceCanConfigureMechanismEmissionScheduleAfterDelay`, `testInvalidMechanismEmissionScheduleReverts`, `testGovernanceCanPayoutMechanismEpochEmissionAfterDelay`, `testMechanismEpochEmissionPayoutRequiresFinalizedEpoch`)
     - `test/PulseTensorCore.fuzz.t.sol` (`testFuzz_MechanismEmissionPoolAccounting`, `testFuzz_MechanismEpochEmissionQuoteRespectsBounds`)

8. **Smooth-decay emission mode (timelocked, opt-in)**
   - Added governance-queued toggles for subnet and mechanism emission smoothing (`queue/configure ...EmissionSmoothing...`).
   - Default behavior remains the existing step-halving quote path unless smoothing is explicitly enabled.
   - Smooth mode linearly interpolates between halving steps, preserving configured floor bounds while reducing per-epoch emission shocks.
   - Covered by:
     - `test/PulseTensorCore.inference_emission.t.sol` (`testSubnetEmissionSmoothingCanBeGovernedAndQuotesSmoothly`, `testMechanismEmissionSmoothingCanBeGoverned`)

9. **Optimistic inference batch-root settlement module**
   - Added `PulseTensorInferenceSettlement` as a separate settlement shell to avoid expanding core runtime size.
   - Governance policy updates are queued and timelocked (`queueBatchPolicyUpdate` -> `configureBatchPolicy`) to reduce instant-parameter-change risk.
   - Validators can commit batch roots with bonds only for the current core epoch, reducing epoch-squatting spam.
   - Settlement/challenge leaf indices are bounded by `itemCount`, reducing malformed-proof attack surface.
   - Anyone can finalize after challenge window.
   - Fraud paths:
     - replay challenge: prove committed leaf already settled in a prior finalized batch,
     - duplicate challenge: prove the same leaf appears at multiple indices in a batch.
   - Successful challenge slashes proposer bond and accrues challenger reward; finalized batches can permissionlessly settle leaves into replay protection state.
   - Covered by:
     - `test/PulseTensorCore.inference_emission.t.sol` (`testInferenceBatchCommitFinalizeAndLeafSettlement`, `testInferenceBatchReplayChallengeSlashesBond`, `testInferenceBatchDuplicateLeafChallengeSlashesBond`, `testInferenceBatchPolicyRequiresQueuedGovernanceAction`, `testInferenceBatchCommitRequiresCurrentEpoch`, `testInferenceSettlementRejectsOutOfRangeLeafIndex`, `testInferenceDuplicateChallengeRejectsOutOfRangeIndex`)

10. **Standards-driven hardening gates**
   - Security process is mapped to OWASP SCSVS/Top10 + EthTrust levels, with evidence tracked in `docs/security/control_matrix.json`.
   - Compiler risk is fail-closed against Solidity known bug feeds; configured compiler must satisfy policy and active-bug checks.
   - Slither detector exclusions are allowlisted + hash-locked to prevent silent drift.
   - Mythril SWC ignores are allowlisted + hash-locked to prevent silent drift.
   - Verification artifacts are freshness-gated against explicit manifests for each run.
   - Covered by:
     - `scripts/check_compiler_known_bugs.sh`
     - `scripts/check_security_controls.sh`
     - `scripts/check_security_antipatterns.sh`
     - `scripts/check_slither_exclusions.sh`
     - `scripts/check_mythril_allowlist.sh`
     - `scripts/check_mythril.sh`
     - `scripts/check_artifact_freshness.sh`

## Deterministic Evidence Artifacts

- Security manifest: `docs/security/artifact_manifest.security.txt`
- ESSO-only manifest: `docs/security/artifact_manifest.esso.txt`
- Release manifest: `docs/security/artifact_manifest.release.txt`
- `runs/security/compiler_bug_report.json`
- `runs/security/control_matrix_report.json`
- `runs/slither/slither_report.json`
- `runs/slither/slither_inference_settlement_report.json`
- `runs/security/mythril_core_findings.json`
- `runs/security/mythril_settlement_findings.json`
- `runs/security/mythril_summary.json`
- `runs/esso_verify/pulsetensor_core/verification_report.json`
- `runs/esso_verify/pulsetensor_inference_settlement/verification_report.json`

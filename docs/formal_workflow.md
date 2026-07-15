# Formal Workflow (Correct by Construction)

This workflow is mandatory for protocol-changing smart-contract work in PulseTensor.

## Gate 1: Contract Build + Tests

- Run:
  - `make build`
  - `make test`
  - `bash scripts/check_deploy_code_size.sh` (deploy profile code-size viability)

Required outcome:

- No failing compilation or tests in Foundry.

## Gate 2: Security Static + Adversarial Checks

- Run:
  - `bash scripts/check_security.sh`

Required outcome:

- Solidity compiler known-bug gate passes (`check_compiler_known_bugs.sh`).
- Security control matrix coverage gate passes (`check_security_controls.sh`).
- Requirements traceability + BVA coverage gate passes (`check_requirements_traceability.sh`).
- Security anti-pattern gate passes (`check_security_antipatterns.sh`).
- Security readiness docs exist and pass structural gate (`scripts/check_security_readiness_docs.sh`).
  - Includes committee charter, signer checklist, and multisig operations standard.
- Solhint policy passes (`scripts/solhint.security.json`).
- Slither exclusion allowlist lock passes (`check_slither_exclusions.sh`).
- Slither pass with only locked detector exclusions.
- Mythril bytecode-analysis gate passes with hash-locked SWC allowlist (`check_mythril.sh` + `check_mythril_allowlist.sh`).
- Foundry fuzz + invariant suites pass.
- Security artifacts are freshly regenerated for the current run (`docs/security/artifact_manifest.security.txt`).
- Optional: set `RUN_ECHIDNA=1` to include Echidna campaign.

## Gate 3: Formalized Specification Consistency

- Maintain bounded protocol-state specifications in `specs/formal/`.
- Keep implementation and tests aligned with these specifications.
- Any specification change must be accompanied by matching contract/test updates.
- Keep still-unimplemented target designs under `specs/protocol/`, with explicit implementation status, rather than presenting them as current contract specifications.

Required outcome:

- No spec-to-implementation drift for promoted protocol behavior.

## Gate 3A: Target Protocol Design Consistency

- Run:
  - `make verify-protocol-spec`
  - `make verify-protocol-spec-checker`

Required outcome:

- The target manifest, canonical schema digests, fixtures, versioned economics, lifecycle, assurance modes, ordered typed domains, and theorem inventory pass structural checks.
- The invalid-mutation suite proves the checker rejects broken allocation sums, cross-asset netting, oracle-dependent settlement, mixed-asset bonds, missing refund paths, sponsor-refund redirection, governance seizure, relaxed required fields, weakened signed domains, forged asset IDs, uint256 overflow, incorrect bond principals or confiscation, missing submission/challenge timeouts, inconsistent decision records, signature-derived nullifiers, unsupported implementation claims, duplicate IDs, and invalid funding quantum.
- Planned modules remain `target_unimplemented` until source, test, and requirement evidence is added.

This gate is checked target-design consistency. It is not a state-space model check, Solidity implementation test, economic-demand proof, or refinement theorem.

## Gate 4: Requirements Traceability + BVA Coverage

- Run:
  - `make verify-requirements-traceability`

Required outcome:

- `specs/formal/requirements_traceability.json` passes strict schema + coverage checks.
- Every listed critical function has at least one mapped requirement and test evidence.
- Boundary-value-analysis (BVA) coverage targets are met per contract.

## Gate 5 (Recommended): Multi-Goal Frontier Synthesis

- Run:
  - `make synth-goal-frontier`
  - `make verify-goal-frontier`
  - `make synth-tokenomics-frontier`
  - `make verify-tokenomics-frontier`
  - `make synth-participant-regret-frontier`
  - `make verify-participant-regret-frontier`

Required outcome:

- Goal-frontier report is generated under `runs/formal/`.
- Maximal realizable goal sets and minimal relaxations are reviewed for the change.
- Example frontier regression check passes for the emergency-mode reference model.

## Gate 6 (Recommended): Local Live-Chain E2E Replay

- Run:
  - `make verify-local-e2e`

Required outcome:

- Deterministic local Anvil replay passes for deployed contracts and writes `runs/local_e2e/local_e2e_report.json`.
- Governance delay queue/execute, commit/reveal, inference batch commit/finalize/settle, and claim drains are all validated.

## Determinism and Privacy Controls

- Keep private dependency directories untracked and out of release artifacts.
- Run `bash scripts/check_private_boundaries.sh` before release gates to fail closed on accidental private-tool leakage.
- Record deterministic run artifacts under `runs/`.
- Run `bash scripts/verify_toolchain.sh` before release verification to fail closed on environment drift.
- Treat missing tools, timeouts, or non-zero exit codes as release-blocking failures.

## Combined Pipeline

- Required release/merge gate:
  - `make verify-release`
  - Runs exact pinned-component checks, build/tests, security suite, mandatory Echidna, deploy-size validation, local live-chain E2E, all frontier checks, and a commit-bound evidence manifest.
- Compatibility alias:
  - `make verify-complete`
  - Delegates to the one canonical `make verify-release` pipeline.
- Fast local iteration (not release/merge gate):
  - `make verify-dev`
  - Runs boundary checks + build/tests.
- Requirements/BVA mapping gate:
  - `make verify-requirements-traceability`
  - Validates requirement-to-function/test mapping and per-contract BVA minimums.
- Target protocol design gate:
  - `make verify-protocol-spec`
  - Validates the target manifest and writes `runs/formal/pulsetensor_target_v1.report.json`.
- Target checker mutation gate:
  - `make verify-protocol-spec-checker`
  - Rejects named invalid target mutations and writes no promoted implementation claim.
- Design-space exploration check (recommended pre-promotion for mechanism/policy changes):
  - `make verify-goal-frontier`
  - Verifies deterministic frontier synthesis behavior on the reference model.
- Local live-chain integration replay (recommended pre-promotion for protocol/runtime changes):
  - `make verify-local-e2e`
  - Validates end-to-end deployed flow locally and emits a deterministic run artifact.
- Extended release entrypoint:
  - `make verify-release-full`
  - Compatibility alias that delegates to `make verify-release`.

## CLI Contract

- `scripts/verify_toolchain.sh`
  - Exit `0`: required commands are present and pinned component versions and binary/content hashes match the lock file.
  - Exit non-zero: missing command or version mismatch.
- `scripts/check_private_boundaries.sh`
  - Exit `0`: private dependency directories remain untracked, no SSH-style repo URLs are present in tracked files, and public documentation does not depend on local private dependency paths.
  - Exit non-zero: any privacy-boundary violation.
- `scripts/check_security.sh`
  - Exit `0`: compiler known-bug gate + control matrix + requirements traceability/BVA + anti-pattern + readiness docs + Solhint + Slither allowlist lock + Slither + Mythril + deterministic fuzz/invariant checks pass (and Echidna when `RUN_ECHIDNA=1`), and security artifact freshness manifest passes.
  - Exit non-zero: any security gate fails.
- `scripts/check_deploy_code_size.sh`
  - Exit `0`: deployment-optimizer build (`FOUNDRY_OPTIMIZER_RUNS` default `1`) keeps `PulseTensorCore` and `PulseTensorInferenceSettlement` within EVM runtime/initcode limits.
  - Exit non-zero: deploy profile exceeds code-size limits or size report parsing fails.
- `scripts/check_requirements_traceability.sh`
  - Exit `0`: requirements matrix schema, function coverage, test linkage, and BVA minimums pass; report written to `runs/security/requirements_traceability_report.json`.
  - Exit non-zero: malformed matrix, missing paths/tests/functions, uncovered required function, or insufficient BVA coverage.
- `scripts/check_protocol_spec.py`
  - Exit `0`: target manifest, schemas/examples, asset isolation, payout sums, lifecycle/refunds, typed domains, governance bounds, and proof-obligation recipes pass; deterministic report written unless disabled.
  - Exit non-zero: malformed target, missing references, inconsistent schema/example, unsafe asset/economic policy, lifecycle defect, weakened domain, unsupported implementation claim, or invalid proof inventory.
- `scripts/test_protocol_spec_checker.sh`
  - Exit `0`: every named invalid mutation is rejected and two baseline reports are byte-identical.
  - Exit non-zero: baseline invalid, nondeterministic report, or any invalid mutation accepted.
- `scripts/check_local_e2e.sh`
  - Exit `0`: fresh local Anvil deployment + deterministic E2E flow passes, and `runs/local_e2e/local_e2e_report.json` is produced.
  - Exit non-zero: any local integration assertion or deployment/runtime step fails.
- `scripts/synthesize_goal_frontier.py`
  - Exit `0`: valid model is parsed, all goal subsets are evaluated deterministically, and frontier report is produced.
  - Exit non-zero: malformed model, inconsistent transitions, or synthesis failure.
- `scripts/check_goal_frontier_example.sh`
  - Exit `0`: reference emergency-mode model yields expected maximal frontier and minimal relaxations.
  - Exit non-zero: synthesized frontier deviates from expected deterministic result.
- `scripts/check_tokenomics_goal_frontier.sh`
  - Exit `0`: tokenomics model yields expected deterministic maximal frontier and minimal relaxations.
  - Exit non-zero: synthesized frontier deviates from expected deterministic result.
- `scripts/check_participant_regret_frontier.sh`
  - Exit `0`: participant-regret model yields expected deterministic maximal frontier and minimal relaxations.
  - Exit non-zero: synthesized frontier deviates from expected deterministic result.
- `scripts/verify_release.sh`
  - Exit `0`: the canonical release pipeline passes: exact toolchain, non-vacuous Echidna harness checks and campaign, deployment-profile size/tests, analyzers, local lifecycle, formal-frontier regressions, and commit-bound evidence.
  - Exit non-zero: any upstream gate failure.
- `scripts/verify_release_full.sh`
  - Exit `0`: the canonical `verify_release.sh` pipeline passes through this compatibility alias.
  - Exit non-zero: any upstream gate failure.
- `scripts/verify_complete.sh`
  - Exit `0`: the canonical `verify_release.sh` pipeline passes through this compatibility alias.
  - Exit non-zero: any upstream gate failure.

## Definition of Done (Protocol Change)

A protocol change is complete only if:

1. Specification updates are reflected in contracts and tests.
2. Solidity implementation matches intended behavior.
3. Foundry tests cover happy-path and adversarial-path behavior.
4. For mechanism/policy changes, deterministic goal-frontier exploration artifacts are reviewed (`runs/formal/*goal_frontier*.report.json`).
5. Privileged subnet actions use on-chain governance-contract + timelock queue/execute controls.
6. Commit/reveal dispute and slashing paths are covered by regression tests.
7. Slash and emission accounting remain explicit liabilities (`totalStake`, `challengeRewardOf`, `subnetEmissionPool`, `mechanismEmissionPool`) with payout tests.
8. Pending commitments keep slash collateral enforceable (no stake withdrawal or validator unregister until reveal/challenge resolution).
9. Epoch emission schedules (subnet + mechanism) are governance-timelocked and payout only finalized epochs once.
10. Mechanism-scoped commit/reveal lanes preserve validator accountability and challengeability (`mechid`-scoped commitments).
11. Self-challenge cannot capture challenge bounty; if validator self-challenges, full slash routes to emission pool.
12. Commit revealability is preserved under governance config drift (e.g., epoch-length updates cannot invalidate an otherwise valid reveal window).
13. Validator auto-unregister on under-min stake only happens when pending commitment count is zero; unresolved commitments keep accountability live until final resolution.
14. Emergency pause must not deadlock pending commitment resolution; reveal/challenge flows remain callable while paused.
15. Settlement policy governance queues have explicit lifecycle controls (queue, cancel, ready check, bounded expiry, requeue after expiry) and queue-origin binding (`queuedBy == executor`) to prevent governance-rotation execution drift.
16. Subnet owner-action queues enforce the same bounded-expiry and queue-origin-binding invariants while still allowing current governance to cancel stale queued actions after rotation.
17. Queue-state observability exists for operator monitoring (`readyAt`, `queuedBy`, readiness/expiry status) without event replay.
18. Inference leaf construction is domain-separated by `(netuid, mechid, epoch, requestId, resultHash)` (or an equivalent collision-resistant encoding).
19. External audit packet and scope are current (`docs/security/external_audit_plan.md`).
20. Governance queue incident runbook, staged launch controls, committee charter, signer checklist, and multisig operations standard are current (`docs/security/governance_queue_runbook.md`, `docs/security/launch_controls.md`, `docs/security/governance_committee_charter.md`, `docs/security/signer_selection_checklist.md`, `docs/security/multisig_operations.md`).
21. Requirements traceability matrix is current and passes coverage checks (`specs/formal/requirements_traceability.json`, `scripts/check_requirements_traceability.sh`).
22. Any affected unimplemented target design is updated under `specs/protocol/`, remains accurately status-labeled, and passes both target-spec gates.

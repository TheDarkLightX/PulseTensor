# Formal Workflow (Correct by Construction)

This workflow is mandatory for protocol-changing smart-contract work in PulseTensor.

## Gate 1: ESSO Model Validity

- Keep a bounded ESSO model for each protocol module in `specs/esso/`.
- Run:
  - `bash scripts/check_esso.sh`

Required outcome:

- `python3 -m ESSO validate` passes.
- `python3 -m ESSO verify-multi --solvers z3,cvc5 --timeout-ms 10000 --determinism-trials 2` passes.

## Gate 2: Contract Build + Tests

- Run:
  - `make build`
  - `make test`

Required outcome:

- No failing compilation or tests in Foundry.

## Gate 2.5: Security Static + Adversarial Checks

- Run:
  - `bash scripts/check_security.sh`

Required outcome:

- Solidity compiler known-bug gate passes (`check_compiler_known_bugs.sh`).
- Security control matrix coverage gate passes (`check_security_controls.sh`).
- Security anti-pattern gate passes (`check_security_antipatterns.sh`).
- Solhint policy passes (`scripts/solhint.security.json`).
- Slither exclusion allowlist lock passes (`check_slither_exclusions.sh`).
- Slither pass with only locked detector exclusions.
- Mythril bytecode-analysis gate passes with hash-locked SWC allowlist (`check_mythril.sh` + `check_mythril_allowlist.sh`).
- Foundry fuzz + invariant suites pass.
- Security artifacts are freshly regenerated for the current run (`docs/security/artifact_manifest.security.txt`).
- Optional: set `RUN_ECHIDNA=1` to include Echidna campaign.

## Gate 3: Morph Adversarial Search

- Run:
  - `bash scripts/check_morph.sh`

Required outcome:

- No promoted candidate violates required invariants.
- Any discovered attack pattern creates a regression test or model refinement.

## Gate 4: ZAG/Lean Algorithmic Assurance

- Run:
  - `bash scripts/check_zag.sh` (quick mode)
  - `bash scripts/check_zag.sh full` (full mode)

Required outcome:

- Lean build/test checks pass for algorithmic components promoted into protocol logic.

## Gate 5: Orchestration-Unit Determinism

- Run:
  - `bash scripts/check_orch_unit.sh`

Required outcome:

- `orch_unit` CLI is callable from `external/Orchestration-Unit`.
- Deterministic `kernels` listing is stable across repeated runs.

## Determinism Controls

- Keep `external/ESSO`, `external/Morph`, `external/ZAG`, `external/bittensor`, `external/go-pulse`, and `external/Orchestration-Unit` on pinned commits from `scripts/toolchain.lock`.
- Treat `external/ESSO`, `external/Morph`, `external/ZAG`, and `external/Orchestration-Unit` as private internal tooling and keep them outside public redistribution paths.
- Treat `external/Orchestration-Unit` as orchestration/infrastructure tooling only (not protocol runtime dependency).
- Run `bash scripts/check_private_boundaries.sh` before build/test gates to fail closed on accidental private-tool leakage.
- Record solver/tool versions (`z3`, `cvc5`, `python3`, `forge`, `lake`) in CI artifacts alongside verification output.
- Run `bash scripts/verify_toolchain.sh` before release verification to fail closed on drift.
- Treat solver `unknown`, missing tools, or timeout as a release-blocking failure.
- Treat any non-zero exit code from `check_esso.sh`, `check_morph.sh`, and `check_zag.sh` as release-blocking failure.

## Combined Pipeline

- Required release/merge gate:
  - `make verify-release`
  - Enforces pinned toolchain + pinned upstream commits and always runs `forge`, ESSO, Morph, ZAG (quick mode), mandatory Echidna, and Orchestration-Unit checks in fail-closed mode.
- Fast local iteration (not release/merge gate):
  - `make verify-dev`
  - Runs ESSO-only artifact freshness (`docs/security/artifact_manifest.esso.txt`).
- Full research gate:
  - `make verify-release-full`
  - Runs ZAG in full mode with mandatory Echidna.

## CLI Contract

- `scripts/verify_toolchain.sh`
  - Exit `0`: all pinned commits, clean external repos, and pinned tool versions match lock file.
  - Exit non-zero: any mismatch or dirty external repo.
- `scripts/check_private_boundaries.sh`
  - Exit `0`: `external/` remains untracked, no private/upstream repo URLs are present in public-tree files, and private tool remotes use SSH.
  - Exit non-zero: any privacy-boundary violation.
- `scripts/check_esso.sh`
  - Exit `0`: `validate` succeeds, `verify-multi` succeeds with `--timeout-ms 10000 --determinism-trials 2`, and `verification_report.json` confirms `verdict=VERIFIED`, `failed_queries=0`, `inconclusive_queries=0`, and solver agreement.
  - Exit non-zero: validation failure, solver disagreement/timeout/unknown, missing solver binaries, or report-level fail-closed checks failing.
- `scripts/check_security.sh`
  - Exit `0`: compiler known-bug gate + control matrix + anti-pattern + Solhint + Slither allowlist lock + Slither + Mythril + deterministic fuzz/invariant checks pass (and Echidna when `RUN_ECHIDNA=1`), and security artifact freshness manifest passes.
  - Exit non-zero: any security gate fails.
- `scripts/check_morph.sh` and `scripts/check_zag.sh`
  - Exit `0`: required command suite succeeds.
  - Exit non-zero: any command failure or missing dependency.
  - Reproducibility policy: fixed seed, fixed round/budget settings, and fixed timeout policy in script defaults.
- `scripts/check_orch_unit.sh`
  - Exit `0`: `orch_unit` CLI responds and deterministic `kernels` listing is stable with non-empty output.
  - Exit non-zero: missing repo/tooling, unstable deterministic output, or malformed command output.
- `scripts/verify_release.sh`
  - Exit `0`: toolchain lock + release gate pass in canonical quick mode (`ZAG_MODE=quick`) with `RUN_ECHIDNA=1`.
  - Exit non-zero: any upstream gate failure or non-quick `ZAG_MODE` override.
- `scripts/verify_release_full.sh`
  - Exit `0`: toolchain lock + full release gate pass in full mode (`ZAG_MODE=full`) with `RUN_ECHIDNA=1`.
  - Exit non-zero: any upstream gate failure or non-full `ZAG_MODE` override.

## Definition of Done (Protocol Change)

A protocol change is complete only if:

1. ESSO model is updated and verified.
2. Solidity implementation matches model intent.
3. Foundry tests cover happy-path and adversarial-path behavior.
4. Morph/ZAG outputs are recorded for the change where applicable.
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
16. Subnet owner-action queues keep the same queue-origin binding invariant, while still allowing current governance to cancel stale queued actions after rotation.
17. Queue-state observability exists for operator monitoring (`readyAt`, `queuedBy`, readiness/expiry status) without event replay.
18. Inference leaf construction is domain-separated by `(netuid, mechid, epoch, requestId, resultHash)` (or an equivalent collision-resistant encoding).

# External Audit Plan

Last updated: 2026-02-23

## Scope

- `src/PulseTensorCore.sol`
- `src/PulseTensorInferenceSettlement.sol`
- `src/core/PulseTensorDomain.sol`
- Release-gate scripts under `scripts/` that enforce fail-closed promotion.

## Security Objectives

- Validate privileged action controls (queue delay, queue origin binding, bounded expiry, cancel/requeue behavior).
- Validate economic safety/liveness (slashing, challenge rewards, emission accounting, settlement escrow/finalization).
- Validate commit/reveal accountability (including paused-mode reveal/challenge safety).
- Validate upgrade/parameter governance assumptions and operational risk boundaries.

## Deliverables

- Critical/high/medium findings with proof-of-concept or trace.
- Explicit non-findings list for scoped high-risk classes.
- Patch verification memo after remediation.
- Final sign-off report with residual risk summary.

## Selection Criteria

- Demonstrated EVM formal + adversarial testing capability.
- Prior work on governance timelocks and DeFi settlement systems.
- Ability to replay deterministic evidence from project gates.
- Clear SLA for triage and retest.

## Audit Packet Inputs

- Latest commit hash and release candidate tag.
- `docs/formal_workflow.md` and `docs/security/security_standards.md`.
- `docs/security/control_matrix.json`.
- Deterministic run artifacts under `runs/` from:
  - `forge test`
  - `bash scripts/check_security.sh`
  - `bash scripts/verify_release.sh`

## Timeline

1. Freeze candidate scope.
2. Run internal full gate and produce packet.
3. External audit execution.
4. Remediation patch set.
5. Retest and final sign-off.

## Out of Scope

- Private tooling repositories as protocol runtime components.
- Non-protocol website/branding assets.

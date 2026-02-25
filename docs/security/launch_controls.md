# Launch Controls

Last updated: 2026-02-25

## Phase 0: Pre-Launch Gate

- Require clean pass of:
  - `make verify-release` (or equivalent explicit checks).
- Freeze privileged governance parameter set and publish initial values.
- Finalize governance committee and signer readiness:
  - `docs/security/governance_committee_charter.md`,
  - `docs/security/signer_selection_checklist.md`,
  - `docs/security/multisig_operations.md`.
- Prepare incident contacts and queue operations runbook.

## Phase 1: Guarded Launch

- Start with conservative limits:
  - lower per-subnet emission/funding ceilings,
  - constrained governance action frequency,
  - narrower participation set while monitoring stabilizes.
- Enable continuous queue-state and failure telemetry.
- Review daily for first 7 days.

## Phase 2: Controlled Expansion

- Expand limits only after:
  - no unresolved critical/high findings,
  - stable queue operations,
  - stable dispute/finalization paths under production load.
- Each expansion requires a rollback condition and owner.

## Bug Bounty

- Launch bounty before broad expansion.
- Minimum scope:
  - privileged action bypass,
  - queue-origin/expiry bypass,
  - fund loss/freeze paths,
  - challenge/slashing bypass,
  - settlement replay/duplication bypass.
- Require reproducible report and impact classification.

## Rollback and Pause Policy

- If a critical vulnerability is confirmed:
  1. Pause affected subnet(s) via governed queue.
  2. Freeze further parameter expansion.
  3. Publish incident status and mitigation ETA.
  4. Resume only after patch + retest + reviewer sign-off.

## Governance Activation Gate

- Do not activate public mainnet governance until:
  - 7 signer committee is seated,
  - 4-of-7 threshold is live on multisig governance account,
  - signer key compromise drill and replacement drill have completed successfully,
  - multisig transaction simulation flow is operational.

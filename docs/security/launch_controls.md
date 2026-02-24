# Launch Controls

Last updated: 2026-02-23

## Phase 0: Pre-Launch Gate

- Require clean pass of:
  - `make verify-release` (or equivalent explicit checks).
- Freeze privileged governance parameter set and publish initial values.
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

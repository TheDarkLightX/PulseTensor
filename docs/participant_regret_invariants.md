# Participant-Regret Invariants

This document pins the safety invariants that minimize likely participant regret in PulseTensor's current launch posture.

Selection method:

1. Model tradeoffs in `configs/formal/pulsetensor_participant_regret_goal_frontier.json`.
2. Compute maximal realizable goal sets with `scripts/synthesize_goal_frontier.py`.
3. Enforce deterministic expected results with `scripts/check_participant_regret_frontier.sh`.
4. Choose the safety-oriented maximal set and map each goal to requirement evidence.

## Recommended Invariant Set

Selected frontier goals:

- `G1_SOLVENCY_SAFETY`
- `G2_ACCOUNTING_CONSERVATION`
- `G3_NO_RETROACTIVE_FEE_EXTRACTION`
- `G4_PREFINALIZE_ESCROW_EXIT`
- `G5_CHALLENGE_FAIRNESS`
- `G6_BOUNDED_SLASHING`
- `G7_FEE_CAP_CREDIBILITY`
- `G8_TIMELOCKED_GOVERNANCE_PATH`

`G9_AGGRESSIVE_TREASURY_GROWTH` is intentionally excluded by default because it conflicts with the above set in the current model.

## Goal-to-Requirement Mapping

### `G1_SOLVENCY_SAFETY`

- `CORE-REQ-005`: conservative stake accounting and eligibility.
- `DOMAIN-REQ-002`: overdraw-resistant stake transition math.

### `G2_ACCOUNTING_CONSERVATION`

- `CORE-REQ-009`: finalized-epoch-only subnet emission payout.
- `CORE-REQ-010`: mechanism-lane payout bounded to finalized epochs.
- `SETTLEMENT-REQ-005`: deterministic fee split + proposer bond refund accounting.

### `G3_NO_RETROACTIVE_FEE_EXTRACTION`

- `SETTLEMENT-REQ-005`: fee policy snapshotted at commit.

### `G4_PREFINALIZE_ESCROW_EXIT`

- `SETTLEMENT-REQ-004`: pre-finalization escrow withdrawal remains available and bounded.

### `G5_CHALLENGE_FAIRNESS`

- `CORE-REQ-004`: pause mode preserves reveal/challenge liveness.
- `SETTLEMENT-REQ-007`: replay/duplicate challenges are enforceable and slash proposer bond.
- `SETTLEMENT-REQ-008`: domain-separated inference leaf helper avoids cross-context settlement ambiguity.

### `G6_BOUNDED_SLASHING`

- `CORE-REQ-008`: slashing bounded by stake and self-challenge cannot take bounty.
- `DOMAIN-REQ-004`: slash arithmetic remains bounded across edge values.

### `G7_FEE_CAP_CREDIBILITY`

- `SETTLEMENT-REQ-002`: fee policy bounds and queue-origin safety.

### `G8_TIMELOCKED_GOVERNANCE_PATH`

- `CORE-REQ-003`: owner-action queue delay/expiry/cancel/queued-by binding.
- `SETTLEMENT-REQ-001`: settlement policy queue lifecycle and origin binding.
- `SETTLEMENT-REQ-002`: fee policy queue delay/expiry/origin binding.

## Deterministic Gate

Run:

```bash
make verify-participant-regret-frontier
```

Expected deterministic result:

- Maximal sets:
  - `G1..G8` (safety + low-regret profile)
  - `G9` (aggressive treasury-only profile)
- Minimal relaxation from full set: drop only `G9`.

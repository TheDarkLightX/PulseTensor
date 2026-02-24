# Goal Frontier Synthesis (Design-Space Exploration)

PulseTensor uses a deterministic, offline multi-goal frontier synthesis step to explore
algorithm and mechanism tradeoffs before implementation changes are promoted.

This workflow is inspired by multi-property finite-trace synthesis: instead of trying
one objective set at a time, we evaluate all goal subsets and extract maximal realizable sets.

## Why this helps

- Turns ad-hoc "try ideas" loops into structured search.
- Identifies objective conflicts early (before contract or protocol rewrites).
- Produces strategy witnesses for each maximal feasible objective set.
- Supplies deterministic artifacts under `runs/` for review and replay.

## Tool

- `scripts/synthesize_goal_frontier.py`
- Input schema: `pulsetensor/goal-frontier-model/v1`
- Output schema: `pulsetensor/goal-frontier-report/v1`

The tool models a finite turn-based safety game:

- `system` states: PulseTensor/governance/controller chooses an action.
- `environment` states: adversary/market/external conditions choose an action.
- Goal atoms are represented as forbidden labels (safety properties).

A subset of goals is realizable iff the system can keep execution forever out of states
containing any forbidden label from that subset.

## Model Format

Minimal shape:

```json
{
  "schema": "pulsetensor/goal-frontier-model/v1",
  "initial_state": "s0",
  "states": {
    "s0": {
      "controller": "environment",
      "labels": ["solvent"],
      "transitions": [{"action": "shock", "to": "s1"}]
    },
    "s1": {
      "controller": "system",
      "labels": ["mode_stress"],
      "transitions": [{"action": "pause", "to": "s2"}]
    }
  },
  "goals": [
    {
      "id": "G1_NEVER_UNDERCOLLATERALIZED",
      "description": "Never enter insolvency",
      "forbidden_labels": ["insolvent"]
    }
  ]
}
```

Rules:

- Every state must define at least one transition.
- Transition targets must exist.
- `controller` must be `system` or `environment`.
- Goal ids must be unique.

## PulseTensor Worked Example

Example model:

- `configs/formal/pulsetensor_emergency_mode_goal_frontier.json`

Run synthesis:

```bash
python3 scripts/synthesize_goal_frontier.py \
  --model configs/formal/pulsetensor_emergency_mode_goal_frontier.json \
  --out runs/formal/pulsetensor_emergency_mode_goal_frontier.report.json
```

Expected maximal frontier sets:

1. `{G1_NEVER_UNDERCOLLATERALIZED, G2_WITHDRAWALS_ALWAYS_ENABLED, G4_ACCOUNTING_CONSERVATION}`
2. `{G1_NEVER_UNDERCOLLATERALIZED, G3_FAIR_LIQUIDATION_ORDERING, G4_ACCOUNTING_CONSERVATION}`

Interpretation:

- Under modeled stress, withdrawals liveness and liquidation fairness conflict.
- Solvency + accounting can be preserved in either variant.
- The frontier returns two viable mechanism families, each with a witness strategy.

Verify example deterministically:

```bash
bash scripts/check_goal_frontier_example.sh
```

## Outputs and Review

Report fields include:

- maximal realizable goal sets,
- minimal relaxations from the full goal set,
- incompatible goal pairs,
- per-subset realizability and witness strategy.

Recommended review process:

1. Confirm modeled assumptions in state labels/transitions.
2. Review maximal sets and minimal relaxations.
3. Pick candidate strategy family.
4. Translate to contract/protocol change.
5. Re-run `make verify-release` before promotion.

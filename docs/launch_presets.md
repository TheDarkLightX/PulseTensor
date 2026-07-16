# Launch Parameter Presets (Uncalibrated Examples)

This document defines illustrative parameter tiers for testnet experiments. They bound contract inputs and express design intent; they are not empirically calibrated, independently audited, or proven safe for mainnet:

- prevent cheap Sybil validator entry,
- keep challenge incentives live,
- keep fee extraction bounded and predictable,
- keep governance changes delayed enough to be observable.

Canonical machine-readable source:

- `configs/presets/launch_presets.json`

## Preset Tiers

### `conservative`

- Security-first rollout.
- Higher entry friction (`minValidatorStake`) and longer governance delay.
- Longer settlement challenge windows and higher proposer bonds.

Consider for:

- initial testnet and tiny-value canary experiments,
- uncertain adversarial surface,
- low tolerance for parameter volatility.

### `balanced` (reference test vector)

- Middle-ground profile for broad participation with bounded risk.
- Preserves anti-spam constraints while allowing faster market iteration.
- Useful as the repository's middle test vector.

Consider only when:

- after initial smoke phase,
- on-chain activity is consistent,
- challenge participation is healthy.

### `growth`

- Throughput-biased profile.
- Lower stake and bond barriers with shorter epochs/challenge windows.
- Higher protocol fee lane for faster treasury accrual.

Consider only when:

- protocol telemetry shows resilient validator/challenger behavior,
- governance and monitoring are mature,
- ecosystem prioritizes growth over conservative latency.

## Game-Theory Rationale

- **Nominal entry cost**: validator capital lock (`minValidatorStake`) and cap (`maxValidators`) raise the PLS cost of occupying validator slots, but do not prove Sybil resistance or prevent coordinated identities.
- **Narrow duplicate/replay incentives**: proposer bonds fund bounties for the exact duplicate-leaf conditions implemented today. A unique false inference is not slashable through this path, so no general fraud-deterrence claim follows.
- **Credible fee policy**: settlement fee policy is timelocked and snapshotted at commit, removing retroactive governance rent extraction.
- **Liveness**: fee funders can withdraw pre-finalization, reducing trapped-capital griefing.
- **Governance risk control**: owner/governance actions are queued with enforced delay, creating observability and reaction time.

## Render a Preset Plan

Use the preset renderer to produce a deterministic rollout artifact and command plan:

```bash
bash scripts/render_launch_preset.sh \
  --preset balanced \
  --netuid 1 \
  --mechid 0 \
  --core 0xCore... \
  --settlement 0xSettlement... \
  --governance 0xGovernance... \
  --out runs/deployments/preset_balanced_netuid1.json
```

The script prints:

- owner-direct core calls,
- governance queue/execute calls (core + settlement),
- minimum block waits per call family.

Notes:

- settlement queue/execute actions require a 2-block delay,
- core privileged actions require `ownerActionDelayBlocks` wait,
- update treasury/miner sink addresses before production execution.

## Operational Guidance

- Start experimentation with `conservative` on testnet. Do not infer mainnet safety from a preset name or renderer output.
- Keep protocol fee lane at or below the enforced cap and avoid sudden fee shocks across epochs.
- Re-evaluate presets only after collecting on-chain evidence:
  - challenge frequency,
  - replay/duplicate fraud attempts,
  - proposer default rate,
  - validator concentration.

Before any value-bearing launch, calibrate parameters from observed PLS-denominated demand/costs, test the separate proof-backed correctness path, bind deployed bytecode to release evidence, and obtain independent review.

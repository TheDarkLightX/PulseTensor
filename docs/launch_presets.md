# Launch Presets (Safe Defaults)

This document defines startup parameter tiers for PulseTensor subnet launches, with game-theoretic intent:

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

Use when:

- initial mainnet launch,
- uncertain adversarial surface,
- low tolerance for parameter volatility.

### `balanced` (default recommendation)

- Middle-ground profile for broad participation with bounded risk.
- Preserves anti-spam constraints while allowing faster market iteration.
- Recommended first public baseline if ops capacity is moderate.

Use when:

- after initial smoke phase,
- on-chain activity is consistent,
- challenge participation is healthy.

### `growth`

- Throughput-biased profile.
- Lower stake and bond barriers with shorter epochs/challenge windows.
- Higher protocol fee lane for faster treasury accrual.

Use when:

- protocol telemetry shows resilient validator/challenger behavior,
- governance and monitoring are mature,
- ecosystem prioritizes growth over conservative latency.

## Game-Theory Rationale

- **Sybil resistance**: validator capital lock (`minValidatorStake`) and cap (`maxValidators`) raise attacker cost.
- **Fraud deterrence**: proposer bond + challenge bounty make invalid batch commits economically dominated.
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

- Start with `balanced` unless you explicitly need slower (`conservative`) or faster (`growth`) economics.
- Keep protocol fee lane at or below the enforced cap and avoid sudden fee shocks across epochs.
- Re-evaluate presets only after collecting on-chain evidence:
  - challenge frequency,
  - replay/duplicate fraud attempts,
  - proposer default rate,
  - validator concentration.

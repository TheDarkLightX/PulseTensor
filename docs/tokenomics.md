# PulseTensor Asset-Flow Economics

## Scope

PulseTensor cannot create dollars, a salary, or guaranteed purchasing power. It can route exact on-chain asset units that participants deposit.

The current contracts are native-PLS-only. Their emission pools and inference-fee escrow are funded liabilities, not promises of external value. Gas paid to execute PulseChain transactions is not PulseTensor application revenue.

The target work market is specified in:

- [`docs/protocol/defi_native_economics_v1.md`](protocol/defi_native_economics_v1.md)
- [`specs/protocol/pulsetensor_target_v1.json`](../specs/protocol/pulsetensor_target_v1.json)

Those target mechanisms are not implemented by the current contracts.

## Current native-PLS flows

### Validators and batch proposers

- Post native PLS bonds to commit inference batch roots.
- Receive bond refunds only after unchallenged finalization.
- Receive the proposer share of actual native PLS funded into a finalized batch.

### Challengers

- Receive native PLS challenge claims sourced from a slashed proposer bond for a valid supported challenge.
- Receive no bounty for self-challenge.

### Miner and treasury sinks

- Receive native PLS claims only from actually funded and finalized batch fees.
- Receive zero if no one funds batch fees.

The current settlement fee policy has:

- `protocolFeeBps`, capped at 30%,
- `treasuryFeeBps`, which divides the protocol cut between treasury and miner sinks,
- queued and expiring policy updates, and
- a batch-commit snapshot that prevents a later fee increase from changing that batch.

Current residual gap: a successful batch challenge credits the challenger portion of the slashed bond but only emits the retained portion; it does not credit that retained PLS to a named reserve or claim. The target conservation rule forbids economically unassigned bond value, so the current path needs a separate repair and regression tests.

For actual funded amount `F`:

```text
protocol = floor(F * protocolFeeBps / 10000)
treasury = floor(F * protocolFeeBps * treasuryFeeBps / 10000^2)
miner = protocol - treasury
proposer = F - protocol
```

These are quantities of native PLS. The equations do not say what those quantities can purchase.

## Target requester-and-sponsor bounty market

Target v1 uses exactly one immutable payment asset per task. Multiple sponsors may top up that same asset. Different assets remain different ledgers across tasks.

There is:

- no cross-asset addition,
- no cross-asset liability netting,
- no protocol exchange rate,
- no PLS/USD oracle in settlement,
- no unfunded credit, and
- no usage-based mint.

Provider and evaluator bonds use the same `assetId` as the task bounty. Providers choose which assets and quantities to accept. Volatility changes future acceptance and quoting; it does not change base-unit solvency.

### Accepted work

The initial hypothesis is:

| Recipient | Share |
|---|---:|
| Provider | 72% |
| Evaluators | 12% |
| Subnet builder | 5% |
| Core maintainer | 5% |
| Security reserve | 3% |
| Ecosystem or referral | 3% |

The vector totals exactly 100%. Each contribution is a multiple of 10,000 base units, so its basis-point allocations are exact.

### Valid reviewed rejection

Evaluators receive only the 12% review allocation. Each contributor receives 88% back. Provider, builder, core, security, and ecosystem accepted-work fees are not charged. A low score is not automatically a slashable protocol fault.

### Cancellation, expiry, default, or no quorum

The bounty returns fully to contributors. Objectively defaulted bonds follow a separately snapshotted, same-asset slash vector. Pause cannot block matured refunds, bond resolution, or claims.

## Creator and maintainer flow

The creator may openly receive:

1. a subnet-builder share for accepted work on a subnet they maintain,
2. a core-maintainer share for accepted work while they hold the disclosed role,
3. provider rewards for completing funded service or development bounties, and
4. accepted prefunded maintenance milestones.

These are in-kind bounty and fee claims, not a salary. If accepted externally funded work is zero, every one of these protocol flows is zero.

For asset `a` and interval `W`:

\[
CoreFlow[a,W] = \sum_{j \in Accepted(W),\ asset(j)=a}
\frac{coreBps_j \cdot bounty_j}{10{,}000}.
\]

The protocol reports the result separately for each asset. It does not convert the vector to dollars or assert that it covers off-chain needs.

## Why a new token is not a funding source

A new token can guarantee token units, not demand for them. For a finite mint `m` and externally determined price `p`:

\[
\inf_{p \ge 0} mp = 0.
\]

PulseTensor therefore does not need a separate token to launch. PLS already supplies native payment and collateral units. A future token proposal must identify a necessary technical function that PLS, task assets, prefunded reserves, and nontransferable reputation cannot provide. Fundraising by itself is not such a function.

Any finite matching program must be prefunded and asset-local:

\[
Match[a,t] \le \min(
ReserveRemaining[a,t],
\mu[a] ExternalBounty[a,t],
PerTaskCap[a],
PerEpochCap[a]).
\]

No external bounty means no match, and unused reserve remains unissued or unspent.

## Frontier models

The current goal-frontier files explore qualitative tradeoffs among solvency, liveness, bounded maintenance fees, anti-Sybil friction, and aggressive fee capture. Labels in those models are scenario classifications, not a proof that a treasury is economically adequate or that any recipient can survive on its claims.

Run:

```bash
make synth-tokenomics-frontier
make verify-tokenomics-frontier
make synth-participant-regret-frontier
make verify-participant-regret-frontier
make verify-protocol-spec
make verify-protocol-spec-checker
```

The target protocol checker enforces asset-local accounting, no oracle-dependent settlement, same-asset bonds, exact basis-point vectors, refund paths, policy snapshots, and an explicit unimplemented status. It does not prove the future contracts or an asset's purchasing power.

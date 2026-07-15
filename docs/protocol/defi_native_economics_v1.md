# DeFi-Native Work-Market Economics v1

Status: target design, not implemented by the current contracts.

Normative machine-readable source: [`specs/protocol/pulsetensor_target_v1.json`](../../specs/protocol/pulsetensor_target_v1.json).

## The correction

PulseTensor does not pay a salary and does not create dollars. The earlier dollar-runway framing in the frontier research was an off-chain company-budget abstraction, not protocol tokenomics.

The protocol can do one economically honest thing: route exact quantities of assets that participants actually deposit. Requesters and sponsors deposit bounties. Providers and evaluators deposit bonds. Accepted work converts the deposited bounty into claims for the named recipients. Rejected, cancelled, expired, or failed work follows a different, fully specified refund and bond rule.

No funded demand means no provider, builder, core-maintainer, security, or ecosystem fee flow. Minting another token does not change that fact.

Gas fees are also not PulseTensor revenue. Native PLS paid for transaction execution goes to the chain's fee recipient under PulseChain rules. PulseTensor application fees must come from the task escrow created by a requester or sponsor.

## One task, one asset

Target v1 permits exactly one immutable `assetId` per task. Multiple sponsors may top up that task only in the same asset. PulseTensor may support different assets across different tasks, but it never adds, converts, borrows, or nets their quantities.

The asset identity uses the fixed typed encoding:

\[
assetId = keccak256(abi.encode(uint256(chainId), uint8(assetKindCode), address(tokenAddress))).
\]

Target v1 fixes `NATIVE_PLS = 0` and `EXACT_ERC20 = 1`; native PLS uses the zero token address. The task contract recomputes this key rather than trusting a caller-supplied `assetId`.

Native PLS and WPLS are different assets and therefore different ledgers. WPLS is not treated as native PLS merely because an external market may quote a conversion.

The first implementation should accept only native PLS. An `EXACT_ERC20` adapter is a later module with separate proofs and hard exposure caps. ERC-20 callers are explicitly required to handle `false` returns, while `name`, `symbol`, and `decimals` are optional metadata, so generic token support is not a safe default. See [ERC-20](https://eips.ethereum.org/EIPS/eip-20).

Fee-on-transfer, rebasing, reflection, hook-bearing, silently false-returning, or otherwise balance-mutating assets are outside the base kernel. An adapter credits only the measured balance increase and must reject a transfer whose received amount differs from the authorized amount.

## Where every unit comes from

For task `j` and its immutable asset `a`, let contributor `i` deposit `g[i,j,a]`. The bounty escrow is:

\[
G[j,a] = \sum_i g[i,j,a].
\]

The only valid bounty sources are:

1. a requester deposit,
2. a sponsor deposit, or
3. an already deposited, finite matching reserve in the same asset.

Unfunded credits and future promises are not escrow. A task cannot be assigned until the required bounty and bonds are actually locked. This is similar in spirit to Filecoin's storage market, which checks locked client payment and provider collateral before accepting a deal. See the [Filecoin Storage Market Actor specification](https://spec.filecoin.io/systems/filecoin_markets/onchain_storage_market/storage_market_actor/).

Each contribution and bond must be a multiple of 10,000 base units. That makes every basis-point allocation exact per contributor and prevents a sponsor from changing rounding by splitting one deposit into many deposits.

## Accepted-job split

The launch hypothesis is the following vector:

| Recipient | Basis points | Share |
|---|---:|---:|
| Provider | 7,200 | 72% |
| Valid evaluators | 1,200 | 12% |
| Subnet builder and maintainer | 500 | 5% |
| Core maintainer | 500 | 5% |
| Security reserve and bounties | 300 | 3% |
| Ecosystem public goods or referral | 300 | 3% |
| Total | 10,000 | 100% |

For role `r`, contributor `i`, and accepted task `j`:

\[
P[i,j,a,r] = \frac{f[r] \cdot g[i,j,a]}{10{,}000}.
\]

Therefore, independently for every contribution and asset:

\[
\sum_r P[i,j,a,r] = g[i,j,a],
\qquad
\sum_i\sum_r P[i,j,a,r] = G[j,a].
\]

For a bounty of 1,000,000 PLS, the provider receives 720,000 PLS, evaluators share 120,000 PLS, the subnet builder receives 50,000 PLS, the core maintainer receives 50,000 PLS, and the security and ecosystem recipients receive 30,000 PLS each. Those are PLS units, not a dollar value.

The builder and core addresses and all six shares are snapshotted before assignment. Governance cannot replace a recipient or fee vector for live work. If a snapshotted role has no eligible recipient—for example, a requester-accepted task with no evaluator committee—its share returns pro rata to the original contribution refund recipients; it is never silently reassigned to another fee role.

The target hard bounds are:

| Role | Minimum | Maximum |
|---|---:|---:|
| Provider | 65% | 85% |
| Evaluators | 0% | 25% |
| Subnet builder | 0% | 7.5% |
| Core maintainer | 0% | 7.5% |
| Security | 1% | 5% |
| Ecosystem | 0% | 5% |

Builder plus core is capped at 12%, and every accepted-job vector must equal exactly 100%. A contract rejects an infeasible vector; it never silently normalizes it.

## Outcome rules

The bounty and each bond are separate principals. Each principal is conserved independently.

### Accepted work

The six-role accepted-job vector distributes 100% of bounty escrow. Valid provider and evaluator bonds return to their owners.

### Valid reviewed rejection

A completed review is work even when the provider's output fails the declared quality gate. Evaluators receive the same 12% review allocation and each contributor receives the remaining 88%:

\[
E[i,j,a] = \frac{1{,}200 \cdot g[i,j,a]}{10{,}000},
\qquad
R[i,j,a] = \frac{8{,}800 \cdot g[i,j,a]}{10{,}000}.
\]

Thus `E + R = g` for every contribution. The provider, builder, core, security, and ecosystem shares are not charged on rejected work. A low score is not itself fraud, so a protocol-compliant provider receives its bond back.

### Cancellation, assignment expiry, provider default, or evaluation failure

The complete bounty returns to contributors. A provider-default or objectively fraudulent provider bond follows the snapshotted bond vector:

- 60% to affected contributors as compensation,
- 20% to a non-self resolver or challenger, and
- 20% to the security reserve.

If the resolver set is empty or the resolver is the faulting party, that share joins contributor compensation. An evaluator that committed and then objectively defaulted follows the corresponding evaluator-bond vector. Subjective score disagreement is never an objective slash condition.

Every settlement record names one bounty disposition, one provider-bond disposition when a provider bond was locked, and one disposition for each locked evaluator bond. An unresolved evaluation or challenge times out to a full contributor refund. Absence of a completed fraud proof cannot slash the provider; independently proved evaluator commitment or reveal defaults may still select the evaluator-default vector. This keeps liveness failure separate from guilt.

### Pull claims

Settlement never pushes value to an arbitrary recipient. It atomically converts escrow and bonds into named pull-claim liabilities and consumes the task/receipt nullifier. A later successful withdrawal reduces both the claim and contract balance by the same quantity. A failed transfer reverts both changes.

## Per-asset solvency

For each `assetId = a`, define:

- `EscrowLiability[a]`,
- `BondLiability[a]`,
- `ClaimLiability[a]`, and
- `ReserveLiability[a]`.

The required invariant is:

\[
Balance[a] \ge
EscrowLiability[a] +
BondLiability[a] +
ClaimLiability[a] +
ReserveLiability[a].
\]

The inequality permits unsolicited native transfers or other explicitly classified surplus. No administrator can withdraw participant liabilities or unassigned surplus through the work-market kernel. A separately governed recovery module may handle proven surplus only after all liability classes and forced-transfer behavior are specified and proved.

No equation contains two asset IDs. A surplus of token `A` cannot hide a PLS deficit.

## Volatility without an oracle

PulseTensor does not need a PLS/USD feed:

- Requesters choose a quantity of PLS or another allowed asset.
- Providers publish short-lived, asset-specific quotes and accept only bounties they consider worthwhile.
- Sponsors can top up an unattractive bounty before assignment.
- Assignment freezes the asset quantity and all terms.
- Recipients decide independently whether to hold, spend, or exchange their claims.
- UI price estimates are informational and can never affect settlement.

If PLS loses external purchasing power, providers can reject or reprice future work. If it gains purchasing power, a previously unattractive bounty may be accepted. Volatility changes participation decisions, not unit accounting.

An existing stable asset may eventually be an allowlisted task asset, but PulseTensor does not guarantee its peg, blacklist behavior, redeemability, or issuer solvency. It remains a separate ledger.

## How the creator is funded

The creator can receive four disclosed, in-kind flows:

1. the `SUBNET_BUILDER` share for accepted tasks on a subnet they actually build and maintain,
2. the `CORE_MAINTAINER` share while they hold the disclosed, timelocked role,
3. the `PROVIDER` share when they complete a funded development, Guardian, Data, audit, research, or operations bounty, and
4. accepted prefunded maintenance rounds with explicit deliverables and tests.

A maintenance round is the DeFi analogue closest to recurring compensation, but it remains a bounty. Sponsors deposit the asset first, the deliverable and acceptance rule are committed, and payment occurs only after acceptance. There is no claim on unfunded future value.

For asset `a` and interval `W`, the core-maintainer flow is simply:

\[
M[a,W] = \sum_{j \in Accepted(W),\ asset(j)=a}
\frac{f_{core,j}\,G[j,a]}{10{,}000}.
\]

If the accepted externally funded task set is empty, `M[a,W] = 0`. PulseTensor reports this vector by asset. It does not collapse it to dollars or claim that it covers anyone's external needs.

The subnet-builder and core-maintainer roles may point to the same disclosed address, subject to the combined 12% cap. That address may also be the provider for a particular task. The overlap must be visible in the typed task and indexer, not hidden behind an undisclosed royalty.

## Why emissions cannot guarantee survival

Suppose a protocol mints `m[t]` new tokens to a maintainer. External purchasing power would be `m[t] * p[t]`, where the protocol does not control the external price `p[t]`. For any finite mint:

\[
\inf_{p[t] \ge 0} m[t]p[t] = 0.
\]

Minting can guarantee a number of token units. It cannot guarantee compute, housing, food, security review, or any other external resource. Infrastructure-token research models price, supply, demand, and adoption as jointly evolving rather than treating issuance as value creation. See [Akcin et al., *A Control Theoretic Approach to Infrastructure-Centric Blockchain Tokenomics*](https://arxiv.org/abs/2210.12881). Economic-security work likewise ties recurring security cost to attack value rather than nominal token counts. See [Budish, *The Economic Limits of Bitcoin and the Blockchain*](https://www.nber.org/papers/w24717).

PulseTensor v1 therefore has no usage-based mint. A finite matching reserve may match real external bounties only in the same asset:

\[
Match[a,t] \le \min(
ReserveRemaining[a,t],
\mu[a] \cdot ExternalBounty[a,t],
PerTaskCap[a],
PerEpochCap[a]).
\]

If `ExternalBounty[a,t] = 0`, then `Match[a,t] = 0`. Unused reserve remains unused. Circular deposits cannot create an uncapped positive-sum payout.

## Attack requirements

| Attack | Target v1 defense |
|---|---|
| Wash trading | No usage-based mint; a coalition can only recycle its own deposit minus gas and payments to external recipients. |
| Sponsor splitting | Every contribution is a multiple of 10,000 base units, so per-contribution basis-point math is exact. |
| Oracle manipulation | No price oracle participates in a value transition. |
| Worthless-token funding | Providers opt into each asset; one task has one asset; assets never combine into a value score. |
| Fee-on-transfer or rebasing token | Native PLS first; later adapters use balance-delta checks, allowlists, and hard liability caps. |
| Governance fee theft | Hard fee bounds, delayed activation, live-task snapshots, and no liability sweep. |
| Sponsor withdrawal after work begins | Funding locks atomically at assignment. |
| Evaluator directional bias | Evaluators receive the same review allocation for a valid accepted or rejected decision. |
| External loss larger than bond | Explicit exposure caps; no claim that an oracle-free bond covers unknown external harm. |
| Pause hostage attack | Matured refunds, resolution, bond conversion, and claims remain callable while paused. |

## Current-contract boundary

`PulseTensorInferenceSettlement` is not this work market. It is currently native-PLS-only, batch-scoped, proposer-paid, and lacks the task-local evaluator and evidence lifecycle described here. Its funders may withdraw until batch finalization, partially funded batches may finalize, batch fees become proposer/miner/treasury claims before individual leaves settle, and its optimistic challenges prove replay or duplicate leaves rather than semantic work correctness.

There is also a concrete accounting-completeness gap in the current challenge path: `_slashBatchBond` calculates `retainedBondAmount = slashedBond - challengerRewardAmount` and emits it, but does not credit that retained amount to a reserve or participant claim. The PLS remains in the contract as economically unassigned balance. This does not implement the target rule that every bond unit is refunded, slashed to a named claim, or assigned to a named reserve. Fix and test that current path before treating its bond ledger as complete.

The target should be implemented as a new, small task-market value kernel. The existing batch contract can later become an adapter that batches already typed task receipts.

## Falsification recipes

Support the design consistency claim with:

```bash
make verify-protocol-spec
```

Expected artifact: `runs/formal/pulsetensor_target_v1.report.json`.

Test that the checker is non-vacuous with:

```bash
make verify-protocol-spec-checker
```

The mutation suite must reject, at minimum, an allocation totaling 9,999 basis points, cross-asset netting, oracle-dependent settlement, a missing refund path, redirecting sponsor refunds to the requester, governance liability seizure, a missing receipt domain field, and an unsupported implementation claim.

These commands check internal target-design consistency. They do not prove the future Solidity implementation, the behavior of an external asset, or any asset's purchasing power.

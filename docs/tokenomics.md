# PulseTensor Tokenomics (Game-Theoretic Draft v1)

## Scope

PulseTensor is currently PLS-native: incentives are denominated in PLS and paid from explicit pools or escrowed usage fees.
This avoids bootstrapping risk from launching an unaudited new token too early.

## Roles and Economic Flows

- **Validators / proposers**
  - Post proposer bonds to commit inference batch roots.
  - Receive proposer-bond refunds only after unchallenged finalization.
  - Receive proposer share of finalized batch fees.
- **Challengers**
  - Earn challenge bounties only when the implemented Merkle proofs show that the exact same `bytes32` leaf appears twice in the current batch or also appears in a prior finalized batch.
  - Self-challenges receive no bounty.
- **Miners**
  - Receive miner-sink fee flow from finalized batch fees.
- **Treasury**
  - Receives treasury-sink fee flow from finalized batch fees.
  - Intended use: protocol R&D, audits, grants, and operations.

## Fee Policy Mechanism

Inference settlement supports per-`(netuid, mechid)` fee policies:

- `protocolFeeBps`: protocol cut from funded batch fees.
- `treasuryFeeBps`: share of protocol cut routed to treasury sink.
- `minerSink`: recipient of miner portion of protocol cut.
- `treasurySink`: recipient of treasury portion of protocol cut.

Security/economic constraints:

- Policy changes are governance-queued (timelocked).
- Queued policy updates are cancellable and expire if not executed within `POLICY_UPDATE_EXPIRY_BLOCKS`.
- Queued policy updates are bound to the governance identity that queued them (`queuedBy`), so governance rotations must cancel/requeue stale entries before execution.
- `protocolFeeBps <= 3000` (30% hard cap).
- Fee policy is snapshotted at batch commit, so governance cannot raise fees after work is posted.
- Settlement leaves should use domain separation (for example via `computeInferenceLeaf(netuid, mechid, epoch, requestId, resultHash)`) to prevent accidental cross-epoch or cross-request hash reuse.

Distribution on finalization for funded amount `F`:

- `protocol = F * protocolFeeBps / 10000`
- `treasury = protocol * treasuryFeeBps / 10000`
- `miner = protocol - treasury`
- `proposer = F - protocol`

The exact-inference escrow uses a simpler success-only split for task reward `R`:

- `fee = floor(R * protocolFeeBps / 10000)`
- `providerBeneficiary = R - fee`
- expiry, verifier revocation, or adapter/base-verifier unavailability: `refundTo = R`, `fee = 0`

The exact lane snapshots its capped fee and treasury at task creation. The proof binds those values and the
beneficiary, so a relayer cannot redirect payment. Verifier configuration addition/deprecation is delayed and
generation-bound; emergency revocation is immediate but can only enable the full-refund path.

## Incentives Implemented Today

- **Narrow duplicate/replay deterrence**: a proposer bond and permissionless challenges penalize the two exact duplicate-leaf conditions above. They do not prove inference correctness and do not penalize a unique false result. The canonical leaf helper includes the epoch, so a cross-epoch challenge against canonically constructed leaves cannot use an identical leaf; this replay rule must not be treated as a general fraud-proof system.
- **No retroactive rent extraction**: fee snapshot prevents governance from changing economics after batch commit.
- **Liveness under dispute**: fee payers can withdraw escrow before finalization; challenged batches do not trap user funds.
- **Usage-linked treasury inflow**: treasury receipts scale with finalized funded fees rather than a dollar-denominated promise; whether that inflow covers operating costs is not established.
- **Proof-contingent exact-task inflow**: the exact lane charges only when its configured verifier accepts the
  contract-reconstructed public values; failure/refund paths produce no treasury income.
- **Miner retention**: miner sink creates direct demand-side revenue, complementing emission schedules.

## Illustrative Starting Scenario (Not a Launch Recommendation)

The existing test vector uses:

- `protocolFeeBps = 1200` (12%)
- `treasuryFeeBps = 3500` (35% of protocol fee, 4.2% of gross)
- effective split of gross funded fees:
  - proposer: 88.0%
  - miner sink: 7.8%
  - treasury sink: 4.2%

These percentages demonstrate accounting and governance paths; they are not derived from observed demand, validator costs, Sybil resistance, PLS purchasing power, or a maintainer-runway model. They should be exercised on testnet and replaced by bounded parameters justified with measured PLS-denominated usage and cost data before value is placed at risk.

## PLS-Native Maintainer Funding

There is no protocol source of dollars and no need to invent one. A sustainable mechanism can distribute only PLS that users have actually escrowed. A future treasury/streaming contract should define, entirely in PLS:

- `realizedProtocolFees(epoch)`: fees finalized in the epoch, never forecast revenue;
- `maintainerBudget(epoch) = realizedProtocolFees(epoch) * maintainerShareBps / 10000`;
- a governance-approved per-epoch PLS cap and an emergency pause;
- pull-based claims to a replaceable maintainer payee or multisig, with no immutable secret key or lifetime entitlement;
- an epoch-denominated reserve guard based on trailing realized PLS outflow, not a dollar oracle; and
- transparent one-time bounties separated from recurring maintenance funding.

The founder can sell earned PLS if dollars are personally needed, but the protocol cannot guarantee the exchange value or that realized demand will cover living costs. Until usage data exists, any percentage is a bounded experiment rather than a salary promise. Launch should therefore avoid a new inflationary token and avoid fixed obligations funded by hoped-for future volume.

## Frontier-Derived Recommendation

Tokenomics profile exploration is modeled in:

- `configs/formal/pulsetensor_tokenomics_goal_frontier.json`

and synthesized via:

- `scripts/synthesize_goal_frontier.py`
- `scripts/check_tokenomics_goal_frontier.sh`

Run:

```bash
make synth-tokenomics-frontier
make verify-tokenomics-frontier
```

Current deterministic frontier result:

1. Safety-oriented maximal set:
   - `{G1_SOLVENCY_SAFETY, G2_LIVENESS, G3_CHALLENGE_FAIRNESS, G4_TREASURY_INFLOW_TARGET, G5_ANTI_SYBIL}`
2. Growth-oriented maximal set:
   - `{G2_LIVENESS, G4_TREASURY_INFLOW_TARGET, G6_AGGRESSIVE_TREASURY_GROWTH}`

Interpretation:

- Full objective set is unrealizable.
- Minimal relaxation from full set is dropping `G6_AGGRESSIVE_TREASURY_GROWTH`.
- Within the authored labels, `balanced` preserves more labels marked safety-oriented than `growth`.

This frontier is a deterministic consistency check over labels assigned by the model author. It does not derive demand, costs, prices, participant behavior, Sybil resistance, or treasury sufficiency from the fee parameters, and it is not empirical or game-theoretic proof that the `balanced` profile is economically sustainable.

Participant-regret invariants are also explored with:

- `configs/formal/pulsetensor_participant_regret_goal_frontier.json`
- `scripts/check_participant_regret_frontier.sh`

Within the authored labels, one maximal set keeps the states labeled solvency/accounting safety, timelocked governance, capped fees, no retroactive fee extraction, pre-finalize escrow exits, challenge fairness, and bounded slashing; aggressive treasury growth is a separate maximal set. The solver does not measure actual participant regret or establish those economic labels.

## Relation to Bittensor-Inspired Design

- Keep Bittensor-style subnet/mechanism incentives and slashing discipline.
- Add EVM-native settlement fee routing with timelocked governance and explicit caps.
- Preserve conservative launch posture: use PLS flows first, only add a separate token after sustained product-market usage and additional formal/audit evidence.

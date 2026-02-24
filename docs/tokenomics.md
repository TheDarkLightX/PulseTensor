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
  - Earn challenge bounties from slashed proposer bonds for valid fraud proofs.
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

## Why This Is Incentive-Aligned

- **Fraud deterrence**: proposer bond + permissionless challenges penalize invalid commitments.
- **No retroactive rent extraction**: fee snapshot prevents governance from changing economics after batch commit.
- **Liveness under dispute**: fee payers can withdraw escrow before finalization; challenged batches do not trap user funds.
- **Protocol sustainability**: treasury funding grows with real usage, not with inflation assumptions.
- **Miner retention**: miner sink creates direct demand-side revenue, complementing emission schedules.

## Suggested Initial Parameters

For early mainnet safety:

- `protocolFeeBps = 1200` (12%)
- `treasuryFeeBps = 3500` (35% of protocol fee, 4.2% of gross)
- effective split of gross funded fees:
  - proposer: 88.0%
  - miner sink: 7.8%
  - treasury sink: 4.2%

This keeps service providers strongly incentivized while still generating protocol-native development revenue.

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
   - `{G1_SOLVENCY_SAFETY, G2_LIVENESS, G3_CHALLENGE_FAIRNESS, G4_TREASURY_SUSTAINABILITY, G5_ANTI_SYBIL}`
2. Growth-oriented maximal set:
   - `{G2_LIVENESS, G4_TREASURY_SUSTAINABILITY, G6_AGGRESSIVE_TREASURY_GROWTH}`

Interpretation:

- Full objective set is unrealizable.
- Minimal relaxation from full set is dropping `G6_AGGRESSIVE_TREASURY_GROWTH`.
- Therefore, the recommended default remains `balanced`; `growth` should be treated as an explicit risk-accepting mode.

## Relation to Bittensor-Inspired Design

- Keep Bittensor-style subnet/mechanism incentives and slashing discipline.
- Add EVM-native settlement fee routing with timelocked governance and explicit caps.
- Preserve conservative launch posture: use PLS flows first, only add a separate token after sustained product-market usage and additional formal/audit evidence.

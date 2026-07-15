# Task-Local Quality Consensus v1

Status: target design, not implemented by the current contracts.

## Purpose

PulseTensor currently reveals validator `weightsHash` values, but those hashes do not contain an on-chain score vector and do not determine payouts. Target v1 replaces that missing link with a task-local, typed decision:

```text
funded task
  -> provider receipt
  -> evaluator commitments and evidence
  -> deterministic integer aggregation
  -> accepted or rejected decision
  -> exact snapshotted payout or refund vector
```

The goal is not to claim universal objective consensus. The goal is to make the exact claim, evidence, assumptions, aggregation rule, and payout consequence visible for each task.

## Relationship to Bittensor

Bittensor validators score miners, and Yuma Consensus combines stake-weighted validator rows into participant emissions. Its current documentation describes stake-weighted medians, clipping at consensus, and bond-based validator dividends. Bittensor also uses commit/reveal to reduce weight copying. See the current [Yuma documentation](https://www.bittensor.com/docs/internals/consensus), [emissions documentation](https://www.bittensor.com/docs/concepts/emissions), and [validator guide](https://www.bittensor.com/docs/guides/validating).

PulseTensor should not clone Yuma as the primary rule for externally funded bounties. A customer payment already names a task and expected evidence. Version 1 should decide that task directly, use stake or bond only as bounded selection and accountability inputs, and pay no provider when evidence or quorum is missing.

## EvaluationPolicyV1

Before assignment, the task snapshots a hash of a policy containing at least:

```text
evaluationPolicyVersion
assuranceMode
committeeSize
minimumRevealCount
minimumRevealWeightBps
selectionPolicyHash
randomnessPolicyHash
eligibleEvaluatorSetRoot
bondAssetId
minimumEvaluatorBond
maximumEffectiveWeight
criterionSet[]
criterionWeightBps[]
hardFloorBps[]
acceptanceThresholdBps
commitDeadline
revealDeadline
evidenceAvailabilityPolicyHash
appealOrChallengePolicyHash
```

The committee size is an odd integer from 3 through 7, with 7 as the launch target. Criterion weights total exactly 10,000. Scores and weights are bounded integers; floating-point arithmetic is forbidden in consensus.

The asset used for evaluator bonds must equal the task bounty asset. This establishes unit-level accountability without an exchange-rate oracle. It does not guarantee that the bond covers unknown external harm.

## Committee selection

Selection occurs before the provider output is known. The eligible set is snapshotted at a pinned block. Each selected hot operator must map to an active controller, required role, required same-asset bond, and unexpired descriptor at that checkpoint.

Version 1 selection is weighted random sampling without replacement. Selection weight is capped:

\[
s_i = \min(eligibleBond_i, selectionCap).
\]

Once selected, the evaluator's effective aggregation weight is independently capped:

\[
w_i = \min(eligibleBond_i, taskWeightCap).
\]

The randomness policy must combine precommitted requester entropy, evaluator entropy when used, and an unpredictable finalized-chain or independently specified beacon value. A current block producer's manipulable value alone is not sufficient. The precise beacon, finality depth, bias analysis, and fallback are part of the TCB manifest.

Bond weighting is not proof of independent identity. Capital splitting, common control, delegation, bribery, and correlated software remain explicit attack assumptions. Douceur's classic result explains why a permissionless system cannot simply assume one identity per participant. See [*The Sybil Attack*](https://www.microsoft.com/en-us/research/publication/the-sybil-attack/).

## Commit and reveal

For selected evaluator `i`:

\[
commit_i = H(
domain,
taskId,
receiptHash,
evaluationPolicyHash,
evaluator_i,
scoreVectorHash_i,
evidenceRoot_i,
salt_i).
\]

The normative reveal schema is [`evaluation_reveal_v1.schema.json`](../../specs/protocol/evaluation_reveal_v1.schema.json).

A reveal is valid only if all of these hold:

1. The evaluator belongs to the snapshotted committee.
2. The current operator is authorized for that historical evaluator seat.
3. Exactly one commitment exists for `(taskId, evaluator)`.
4. The reveal is in the reveal window.
5. Recomputed commitment bytes equal the stored commitment.
6. Criterion IDs exactly match the ordered snapshotted criterion set.
7. Every score is an integer from 0 through 10,000.
8. The evidence bytes match the committed evidence root and the availability policy.
9. Exactly one valid reveal is counted for the evaluator.

Operator rotation cannot replace the operator snapshotted for an existing task. Revocation blocks new work, but historical signatures, reveals, disputes, refunds, and claims remain verifiable.

## Quorum

Let `S` be the selected committee, `R` the valid reveal set, and `w_i` each member's snapshotted effective weight. A decision has quorum only if:

\[
|R| \ge minimumRevealCount
\]

and

\[
10{,}000 \sum_{i \in R} w_i
\ge
minimumRevealWeightBps \sum_{i \in S} w_i.
\]

The launch target is a minimum of 3 reveals and two-thirds of snapshotted committee weight. If quorum fails, the bounty follows `FULL_REFUND_BOUNTY`. The provider receives its bond back if it submitted all required evidence. An evaluator that committed and then failed an objective reveal obligation may be slashed under its separately snapshotted bond rule.

There is no fallback to owner-selected payout, stale weights, or stake-only judgment.

## Deterministic lower weighted median

For criterion `k`:

1. Build `(score[i,k], evaluatorAddress[i], w_i)` for every valid reveal.
2. Sort ascending by score, then ascending by evaluator address.
3. Let `W = sum(w_i)`.
4. Select the first score whose inclusive cumulative weight `C` satisfies `2*C >= W`.

That score is `median[k]`. The address tie-break does not change a score when equal scores tie, but it makes every implementation's trace byte-identical.

For criterion weights `c[k]` totaling 10,000:

\[
Q = \left\lfloor
\frac{\sum_k c[k] \cdot median[k]}{10{,}000}
\right\rfloor.
\]

The task is provisionally accepted only if:

1. quorum passes,
2. every `median[k]` meets its hard floor, and
3. `Q` meets the acceptance threshold.

Otherwise it is provisionally rejected. Version 1 has a binary provider payout: the provider receives the accepted-task allocation or receives no bounty allocation. This is easier to prove than a nonlinear score-to-payout curve and prevents small score changes from producing difficult rounding or manipulation surfaces.

Median and trimmed-mean methods have conditional Byzantine-robustness results in distributed learning, but their assumptions matter. See [Yin et al., *Byzantine-Robust Distributed Learning: Towards Optimal Statistical Rates*](https://arxiv.org/abs/1803.01498). PulseTensor's theorem is deliberately narrower than a model-convergence claim.

## Conditional median theorem

Let `H` be honest valid reveals. If:

\[
\sum_{i \in H} w_i > \frac{1}{2}\sum_{i \in R}w_i,
\]

then, for each criterion, the lower weighted median lies between the minimum and maximum honest revealed scores.

Reason: adversarial weight strictly below half cannot make cumulative weight reach half below the minimum honest score, and it cannot leave at least half the weight strictly above the maximum honest score.

This theorem is conditional. It does not establish:

- that honest weight exceeds one half,
- that selected identities are independent,
- that honest reports are accurate,
- that hidden labels are correct or secret,
- that a benchmark predicts deployed usefulness, or
- that an external availability or randomness service is honest.

The bounded theorem should be exhaustively checked over small integer committees and then proved as a general sorted-prefix lemma in the selected proof assistant.

## Evaluator compensation

The evaluator pool is 12% of bounty escrow for either a valid accepted review or a valid rejected review. This avoids paying more for one decision direction.

For `n` valid reveals, evaluator pool `E`, quotient `q = floor(E/n)`, and remainder `r = E mod n`:

- sort valid evaluator claim addresses ascending,
- each receives `q`, and
- the first `r` addresses receive one additional base unit.

Because the total pool is already exact, this rule preserves it exactly. No score direction or bond size changes review compensation after committee selection.

If review quorum fails, the bounty is fully refunded. Honest revealers may receive compensation only from objectively slashed non-revealer bonds according to the snapshotted bond vector, not from an unfunded promise.

Verifier participation is a real cost even when fraud is rare. TrueBit mechanism research highlights the difficulty of making verification rewards predictable and keeping independent checking attractive. See [Koch and Reitwiessner, *A Predictable Incentive Mechanism for TrueBit*](https://arxiv.org/abs/1806.11476). PulseTensor must measure evaluation cost and set the review pool through actual provider/evaluator acceptance, not assume the initial 12% is sufficient.

## Slashing boundary

Only objectively verifiable protocol faults are slashable:

- two different signed commitments or reveals for one task,
- a reveal that does not open the stored commitment,
- committed non-reveal after accepting an assignment,
- a signature from an unauthorized operator,
- evidence unavailability when availability was explicitly promised, or
- fraud proved by the snapshotted exact or optimistic verifier.

A low score, minority score, disagreement with the median, or requester dissatisfaction is not by itself fraud. Statistical and subjective judgments can be wrong without being cryptographically slashable.

For work without trusted ground truth, peer-prediction research offers mechanisms under explicit information and equilibrium assumptions. It is not a generic truth oracle. See [Kong and Schoenebeck, *An Information Theoretic Framework for Designing Information Elicitation Mechanisms That Reward Truth-telling*](https://arxiv.org/abs/1605.01021). Any future peer-prediction policy must be a separately versioned assurance mode with its assumptions and counterexamples, not an invisible change to this median rule.

## Required tests

The first implementation must cover:

- empty committee and zero total weight,
- minimum and maximum committee sizes,
- duplicate committee members,
- duplicate commitments and reveals,
- missing commitments and missing reveals,
- invalid commitment opening,
- wrong receipt or evaluation-policy hash,
- exact-half cumulative-weight ties,
- address tie-breaks,
- scores 0 and 10,000,
- maximum bounded weights and multiplication overflow edges,
- hard-floor failure with overall-score pass,
- overall-score failure with all hard floors passing,
- no-quorum refund,
- input permutation producing the same medians and decision,
- operator rotation, expiry, and revocation,
- committee collusion and Sybil-splitting simulations, and
- evidence withholding through the full challenge window.

Two independent implementations must produce identical results for every golden vector before the contracts are exposed to value.

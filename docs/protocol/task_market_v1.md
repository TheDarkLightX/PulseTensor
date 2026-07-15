# Evidence-Bearing Task Market v1

Status: target design, not implemented by the current contracts.

This document defines the first value-moving kernel that should be built after the current PulseTensor contracts. It is intentionally narrower than a general decentralized AI marketplace: one provider, one payment asset, one immutable mechanism version, and one explicit decision policy per task.

## Design objective

Every payout must answer five questions without trusting a hosted service:

1. Who deposited the bounty and in which asset?
2. What exact task, deadlines, fees, verifier, and evaluation rule did the payer authorize?
3. Which provider committed which output and evidence?
4. Which deterministic decision rule accepted or rejected it?
5. Which conservation equation converted escrow and bonds into claims?

This is the intended advantage over an opaque epoch-wide weight hash. Bittensor's current network records miners, validators, endpoints, actual weight vectors, and Yuma-derived emissions. PulseTensor should retain the useful provider/evaluator/subnet abstraction while making each paid task and its evidence individually traceable. See the current [Bittensor network model](https://www.bittensor.com/docs/concepts/network) and [emissions model](https://www.bittensor.com/docs/concepts/emissions).

## Component boundary

Do not add this logic to `PulseTensorCore`. Implement separate modules with small authority surfaces:

- `PulseTensorNodeRegistry`: controller/operator delegation, descriptor commitments, rotation, expiry, and revocation.
- `PulseTensorTaskMarket`: funding, contributions, assignment, immutable snapshots, lifecycle, decisions, refunds, claims, and nullifiers.
- `PulseTensorEvaluation`: committee snapshots, commit/reveal, quorum, integer aggregation, and decision records.
- `PulseTensorVerifierRegistry`: versioned resolver modules for each assurance mode.
- `PulseTensorMechanismRegistry`: delayed activation of immutable mechanism manifests.
- `PulseGraph`: a block-pinned indexer and query view with no settlement authority.

The current `PulseTensorInferenceSettlement` may later batch typed, already resolved receipts. It must not be treated as the task market itself.

## Mechanism manifest

Each live mechanism version commits at least:

```text
netuid
mechid
mechanismVersion
taskSchemaHash
receiptSchemaHash
evaluationPolicyHash
verifierPolicyHash
canonicalSemanticsHash
nodeCapabilityHash
softwareArtifactHash
tcbManifestHash
activationBlock
deprecationBlock
```

Activation is delayed. Deprecation blocks new tasks but cannot change or strand live tasks. A task snapshots the complete manifest version and fee schedule before assignment.

## Funding intent and TaskSpecV1

A funding intent fixes every field except the provider, selected evaluator committee, contribution root, and final funded amount. Requesters and sponsors may add contributions in the one declared asset while the task is `FUNDED_OPEN`. Each contribution records its contributor, refund recipient, amount, and nonce. Contributions are withdrawable only before assignment.

Assignment atomically:

1. verifies that the bounty meets the requester's committed minimum,
2. verifies the selected provider's signed quote and active operator delegation,
3. locks every sponsor contribution,
4. locks the provider and required evaluator bond capacity in the same asset,
5. writes the selected provider, evaluator-committee root, canonical contribution root, and final funded amount,
6. snapshots all mechanism, verifier, evaluation, asset-adapter, fee, recipient, and deadline versions, and
7. computes the immutable `TaskSpecV1` hash.

The contribution root commits an ordered list of `(contributionId, contributor, refundRecipient, amount, nonce)` leaves. Its amount sum must equal `fundedAmount`. The committee root commits the task-local ordered evaluator/operator set and each member's capped same-asset effective weight before the provider reveals output. Both encodings require golden vectors and on-chain recomputation or membership verification.

The payment-asset key is not caller-selected metadata. It is recomputed as:

\[
assetId = keccak256(abi.encode(uint256(chainId), uint8(assetKindCode), address(tokenAddress))),
\]

where `NATIVE_PLS = 0` and `EXACT_ERC20 = 1`. `paymentAsset.chainId` must equal the task's `chainId`, and native PLS requires the zero token address. A task whose supplied `assetId`, kind, chain, or token does not reproduce the same key is invalid. The machine-readable target contains the exact ABI bytes and expected hash for the chain-943 native-PLS golden vector.

The normative schema is [`task_spec_v1.schema.json`](../../specs/protocol/task_spec_v1.schema.json). Its value-relevant fields include:

```text
chainId
settlementContract
taskId
payer
requester
requesterRefundRecipient
provider
netuid
mechid
mechanismVersion
taskType
inputCommitment
inputAvailabilityPolicyHash
canonicalSemanticsId
outputSchemaHash
assuranceMode
verifierPolicyHash
evaluationPolicyHash
evaluatorCommitteeRoot
paymentAsset
contributionRoot
fundedAmount
providerBondAmount
evaluatorBondAmount
feeScheduleHash
deadlines
payerNonce
payerAuthorization
```

Consensus and value fields use bounded integers or canonical decimal strings, never JSON floating-point numbers.

## WorkReceiptV1

The provider signs the normative [`WorkReceiptV1`](../../specs/protocol/work_receipt_v1.schema.json):

```text
chainId
settlementContract
receiptVersion
taskId
attemptId
taskSpecHash
provider
inputCommitment
outputCommitment
evidenceRoot
availabilityAttestationRoot
canonicalSemanticsId
assuranceMode
proofSystemId
verifierId
modelArtifactHash
runtimeArtifactHash
tcbManifestHash
startedAtBlock
submittedAtBlock
providerNonce
providerSignature
```

The receipt signature authorizes the typed digest of every receipt field above except `providerSignature` itself; the constant schema label is validated but excluded from the digest. It does not prove that the output is correct, useful, unbiased, or produced by the claimed model. Those claims depend on the chosen assurance mode, verifier predicate, evaluation policy, evidence availability, and TCB.

## Typed domains and nullifiers

Use one fixed EIP-712-compatible type definition per object version. For `TaskSpecV1`, `WorkReceiptV1`, `EvaluationRevealV1`, `DecisionRecordV1`, `NodeDescriptorV1`, and `PTAuthEnvelopeV1`, the typed hash binds every top-level schema property except the constant `schema` label and, where present, the signature field itself. Nested payment-asset, deadline, endpoint, and score-vector values bind every nested property in its declared order. The exhaustive field inventories are the corresponding entries under `hash_domains` in `pulsetensor_target_v1.json`; an implementation may not treat them as a minimum subset.

The version field and verifying contract or registry remain signed even though EIP-712 also domain-separates the message. The payer, requester, refund recipient, provider, contribution root, committee root, bond amounts, deadlines, availability commitment, verifier and proof identifiers, artifact commitments, TCB manifest, execution blocks, and nonces are therefore authorization inputs rather than mutable annotations. `NodeDescriptorV1` likewise binds its controller/operator scope, validity interval, endpoints, capabilities, limits, and artifact commitment before applying `operatorSignature`.

The signature fields carry authorization over the corresponding typed digest. A version-1 secp256k1 verifier accepts only canonical 65-byte signatures with `s` in the lower half order and `v` equal to 27 or 28, and must recover the snapshotted signer. Future contract-wallet or account-abstraction authorization requires a new, explicitly typed authorization version.

`taskSpecHash`, `receiptHash`, and the other object hashes used by later records are these typed digests, not hashes of JSON serialization or signature bytes. Authorization is verified against the digest and signer as a separate predicate.

Task and receipt settlement use two independent nullifiers:

Here `H(tag, ...)` means `keccak256(abi.encode(keccak256(bytes(tag)), ...))` with the exact ABI types declared in the machine-readable target.

\[
N_{task} = H(
  \texttt{PULSETENSOR\_TASK\_SETTLEMENT\_NULLIFIER\_V1},
  chainId,
  settlementContract,
  taskId,
  taskSpecHash),
\]

\[
N_{receipt} = H(
  \texttt{PULSETENSOR\_RECEIPT\_SETTLEMENT\_NULLIFIER\_V1},
  chainId,
  settlementContract,
  taskId,
  attemptId,
  receiptHash).
\]

The contract requires both `consumedTaskNullifier[N_task]` and `consumedReceiptNullifier[N_receipt]` to be false, then sets both true in the same state transition that creates claims. Neither key can be cleared by governance. Raw signature bytes are deliberately excluded from nullifier derivation: a different encoding of a valid authorization must never create a second settlement identity.

The typed object encodings and the declared nullifier encodings must have cross-language golden vectors before contract implementation.

## Assurance modes

Each task chooses one mode. A mode proves only the stated predicate.

| Mode | Decision | Required boundary |
|---|---|---|
| `EXACT` | A registered verifier accepts the committed execution under canonical semantics. | The program, preprocessing, model, input, output, proof system, verifying key, and TCB are committed. |
| `OPTIMISTIC` | The trace survives the dispute window or a registered dispute verifier resolves it as valid. | Dispute data is available for the full window and at least one honest challenger can act. |
| `STATISTICAL` | A preregistered score rule passes on a committed sampling frame. | Sampling, hidden-test custody, contamination controls, sample size, uncertainty, and aggregation assumptions are explicit. |
| `ATTESTED` | A snapshotted committee reaches a threshold on a declared predicate. | The result proves who attested, not the external truth of the predicate. |
| `REQUESTER_ACCEPTED` | The snapshotted requester signs acceptance of the exact receipt. | This is subjective authorization, not a correctness proof. |

Contribution-scored training is excluded from version 1. It should not be promoted until its marginal-contribution, reproducibility, data-rights, and collusion assumptions have executable counterexamples and a separate settlement policy.

## Lifecycle

The normative states and edges are in `pulsetensor_target_v1.json`. The intended flow is:

```text
FUNDED_OPEN
  -> ASSIGNED
  -> SUBMITTED
  -> EVALUATION_COMMIT
  -> EVALUATION_REVEAL
  -> PROVISIONAL_ACCEPT | PROVISIONAL_REJECT
  -> CHALLENGED, when the snapshotted mode permits
  -> FINAL_ACCEPT | FINAL_REJECT | FINAL_PROVIDER_FAULT
  -> SETTLED
```

Failure paths are:

```text
FUNDED_OPEN -> CANCELLED_REFUND -> SETTLED
FUNDED_OPEN -> ASSIGNMENT_EXPIRED_REFUND -> SETTLED
ASSIGNED -> PROVIDER_DEFAULT_REFUND -> SETTLED
SUBMITTED/EVALUATION_* -> EVALUATION_FAILED_REFUND -> SETTLED
CHALLENGED -> CHALLENGE_EXPIRED_REFUND -> SETTLED
```

`EXACT` and `REQUESTER_ACCEPTED` may move from `SUBMITTED` directly to a provisional decision when their verifier or authorization rule completes. A statistical or attested task must pass its committee path. An optimistic task enters a challenge-capable provisional state.

`FINAL_REJECT` means the output failed the snapshotted decision rule without proving provider misconduct, so the provider bond remains valid. Only `FINAL_PROVIDER_FAULT`, reached through a registered exact/optimistic proof with committed evidence, may select `PROVABLE_PROVIDER_FAULT_BOND`.

`SETTLED` means the task escrow and bonds have been converted once into claims. Claims are separate liabilities and can remain unwithdrawn after task settlement.

### DecisionRecordV1

Every path to settlement creates a typed [`DecisionRecordV1`](../../specs/protocol/decision_record_v1.schema.json). It binds the task and receipt hashes, assurance mode, final outcome, reason code, exact bounty vector, provider-bond vector and evidence, evaluator-bond disposition root, resolver authority and policy, challenge record, and decision block.

The evaluator root commits one canonically ordered leaf per locked evaluator bond: `(controller, operator, bondAmount, vectorId, objectiveEvidenceHash)`. Each leaf selects exactly `VALID_EVALUATOR_BOND` or `PROVABLE_EVALUATOR_DEFAULT_BOND`; disagreement or a minority score is not objective evidence. The root is zero only when no evaluator bond was locked. Likewise, a provider fault vector requires a nonzero objective-evidence hash. The settlement transition recomputes this record and rejects a vector whose principal or reason is inconsistent with the terminal edge.

### Deadline rules

The assignment, submission, evaluation-commit, evaluation-reveal, challenge, and claim deadlines are strictly increasing and snapshotted. Governance cannot shorten them for a live task. Every nonterminal state has a permissionless timeout transition under the stated assumptions of chain progress, available gas, and an actor willing to submit a transaction.

The claim deadline does not authorize confiscation. If version 1 has a claim deadline, expiry moves the claim to a named long-term claimant registry or keeps it claimable; it cannot become administrator income. The safer first implementation is no claim expiry.

## Settlement algorithm

For a terminal decision:

1. Recompute and verify the typed task, receipt, decision, and policy hashes.
2. Verify the caller-independent terminal condition and deadline.
3. Reject if either the independent task nullifier or receipt nullifier is already consumed.
4. Select exactly one bounty outcome vector and one outcome vector for every locked bond.
5. Compute claims per original contribution, so refunds preserve sponsor ownership.
6. Assert each principal's basis points total 10,000.
7. Decrease escrow and bond liabilities by exactly the claim and reserve liabilities created.
8. Consume both nullifiers and set `SETTLED` in the same transaction.
9. Emit all inputs needed for an independent indexer to reconstruct the transition.

There is no partial provider payout, nonlinear quality curve, auction, or multi-provider split in version 1. Binary accepted/rejected payout is easier to specify, prove, and explain. More elaborate curves require a later version and cannot mutate existing tasks.

## Claims and external calls

Each claim is keyed by `(assetId, recipient)`. Withdrawal uses checks-effects-interactions and a reentrancy guard:

```text
require claim[assetId][recipient] >= amount
claim[assetId][recipient] -= amount
ClaimLiability[assetId] -= amount
transfer exact amount
require transfer succeeded and asset semantics hold
```

Any failure reverts the entire transition. A recipient may choose a distinct claim address when the task is assigned; subsequent operator-key rotation does not change it.

## Pause and governance

Emergency pause may block only:

- new task creation,
- new funding, and
- new assignment.

It cannot block already authorized submission, evaluator reveal, challenge, timeout/default resolution, finalization, refund conversion, bond release or slash conversion, or claim withdrawal.

Governance may activate a new policy only after the hard minimum delay. A live task never reads mutable global fee, recipient, asset, verifier, committee, or deadline configuration. Governance cannot sweep liabilities, cross-net assets, revive a settled task, or migrate a task without every payer's explicit authorization.

## Data availability

Target v1 permits only:

- small inline public data,
- content-addressed public data with committed retention,
- requester-reproducible private inputs, or
- proof-only modes whose verifier does not need the private preimage.

Threshold-encrypted committee custody is deferred because it adds key generation, availability, liveness, and collusion assumptions. A task cannot finalize if its assurance mode requires dispute data that was unavailable during the challenge window. An availability attestation establishes only that named parties made a time-bounded statement.

## Threat boundaries

The value kernel can prove asset-unit conservation, authorization, lifecycle, snapshots, nullifier uniqueness, and deterministic claim creation under declared asset and EVM assumptions. It cannot prove:

- the external price of PLS or another asset,
- that an evaluator committee is independent,
- that a hidden benchmark was not leaked,
- that a model is socially useful or unbiased,
- that a public RPC or indexer is honest,
- that an external asset remains transferable, or
- that Sybil identities are distinct people.

Each verifier and evaluation policy must publish those assumptions rather than inheriting an unqualified “verified AI” label.

## Implementation acceptance

Do not deploy the target market until all of these pass:

1. Positive and negative fixtures for every typed object.
2. Two independent implementations produce identical EIP-712 hashes and signatures.
3. Bounded state exploration covers every lifecycle edge and timeout.
4. Foundry unit, fuzz, invariant, and malicious-recipient tests cover every bounty and bond outcome.
5. Native PLS solvency, single settlement, snapshot immutability, and pause-refund liveness have named proof obligations.
6. A mutation suite demonstrates that each checked field and conservation rule is non-vacuous.
7. A local vertical slice completes funding, assignment, execution, evaluation, challenge, settlement, refund, and claim without a trusted indexer.
8. Independent reviewers evaluate both contract safety and economic attack surfaces.

The current `make verify-protocol-spec` gate checks the consistency of this target. It is not implementation or refinement evidence.

# Proof Obligations and Construction Plan v1

Status: target theorem inventory. Only the structural checks explicitly reported by `make verify-protocol-spec` are currently executable.

## Claim discipline

“Correct by construction” is a process goal, not a blanket claim. PulseTensor may claim a property only when the repository names:

- the exact theorem or checked invariant,
- the implementation and bytecode revision,
- all environmental assumptions,
- the trusted computing base,
- the proof or test tool and version,
- a replayable artifact, and
- the behaviors excluded from the claim.

The target protocol JSON and schemas are machine-checked design inputs. They are not yet an executable transition-system proof, a Solidity refinement theorem, or deployed-bytecode evidence.

## Evidence ladder

Use these rungs without collapsing them:

1. **Structural design check:** schemas, references, allocation sums, state reachability, domains, and target-status claims are internally consistent.
2. **Executable bounded model:** every transition is executable over bounded values and produces counterexample traces.
3. **Differential conformance:** generated model traces replay against the EVM implementation for finite inputs.
4. **Source-level theorem:** named safety properties hold for all reachable source states under declared assumptions.
5. **Bytecode refinement:** compiled or deployed bytecode simulates the abstract transition system for the named properties.
6. **Deployment attestation:** a deployment receipt binds the live bytecode, configuration, theorem versions, and evidence bundle.

Differential testing is not refinement. Bounded exploration is not an unbounded proof unless a completeness argument is supplied. A source proof does not automatically establish compiler or deployed-bytecode behavior.

Relevant precedents include [VerX](https://www.sri.inf.ethz.ch/publications/permenev20verx) for source-level functional safety, [KEVM](https://fsl.cs.illinois.edu/publications/hildenbrandt-saxena-zhu-rodrigues-daian-guth-moore-zhang-park-rosu-2018-csf.pdf) for executable EVM semantics, and the [Ethereum deposit-contract verification](https://daejunpark.github.io/papers/deposit.pdf) for bytecode-oriented reasoning with an explicitly bounded proof scope. They are methodological references, not PulseTensor evidence.

## Trusted computing base

The value-safety TCB includes at least:

- the normative specification and theorem statements,
- the proof assistant, SMT solver, model checker, and their encodings,
- the Solidity compiler or source-to-bytecode relation,
- PulseChain EVM and consensus/finality behavior,
- Keccak and secp256k1 assumptions,
- the native PLS transfer semantics,
- any enabled asset adapter and external token,
- registered verifier contracts and precompiles,
- canonical model and preprocessing semantics,
- randomness and evidence-availability policies,
- governance/timelock contracts and deployment procedure, and
- operator key security and transaction inclusion assumptions.

An AI-quality claim has additional TCB elements such as benchmark custody, sampling code, labels, evaluator software, data rights, model artifacts, and contamination controls.

## Normative theorem inventory

The machine-readable statements, assumptions, support recipes, refute recipes, and current proof statuses live in `pulsetensor_target_v1.json`.

| ID | Target theorem | First executable artifact | Promotion requirement |
|---|---|---|---|
| `INV-ASSET-001` | Per-asset balance covers escrow, bond, claim, and reserve liabilities. | Bounded asset-ledger model plus Foundry invariant handler. | Unbounded value-conservation proof and bytecode binding. |
| `INV-ASSET-002` | No price read, cross-asset conversion, borrowing, or netting enters a value transition. | Static transition-expression checker and malicious adapter tests. | Source theorem over every value path. |
| `INV-FUND-001` | Every bounty claim reclassifies an actual same-asset deposit or finite prefunded reserve. | Bounded funding/claim transition model. | Source and bytecode traceability proof. |
| `INV-SETTLE-001` | Independent typed task and receipt nullifiers are both consumed and settle at most once. | Race, reentrancy, and replay state exploration. | Unbounded single-settlement proof. |
| `INV-BOND-001` | Every locked bond has exactly one same-principal disposition; valid bonds refund and fault vectors require objective evidence. | Bounded terminal-reason/bond-subset exploration. | Source theorem over every bond conversion and withdrawal path. |
| `INV-AUTH-001` | Every typed object binds its complete normative inventory and signed objects require a canonical authorized signer. | Cross-language vectors plus one-field/signature mutations. | Encoding, recovery, authorization, and bytecode refinement proof. |
| `INV-LIFE-001` | Only enumerated lifecycle edges occur and `SETTLED` is terminal. | Current protocol-spec structural checker. | Executable state model and source refinement. |
| `INV-PAUSE-001` | Pause cannot strand matured refunds, resolutions, bonds, or claims. | Bounded paused-state liveness search. | Conditional liveness theorem under chain-progress assumptions. |
| `INV-GOV-001` | Live tasks never read later policy and governance cannot seize liabilities. | Configuration-drift differential tests. | Source theorem and storage-layout review. |
| `INV-EVAL-001` | Statistical acceptance implies quorum, hard floors, and threshold. | Exhaustive bounded committee evaluator. | Source-level decision theorem. |
| `INV-EVAL-002` | Honest revealed weight over one half keeps the weighted median in the honest envelope. | Exhaustive finite checker. | General sorted-prefix proof in a proof assistant. |
| `INV-NET-001` | `ptauth/1` binds every declared field and accepts a replay key at most once. | Cross-language golden vectors and distributed replay-store tests. | Protocol proof plus implementation conformance. |

No theorem in this table establishes an asset's purchasing power, Sybil-proof identity, evaluator independence, Internet liveness, benchmark validity, or real-world truth.

## Abstract value state

For each asset `a`, the formal model should contain:

```text
balance[a]
escrow[a]
bond[a]
claim[a]
reserve[a]
contribution[task][funder]
providerBond[task]
evaluatorBond[task][evaluator]
claimOf[a][recipient]
taskState[task]
taskSpecHash[task]
receiptHash[task]
decisionHash[task]
nullifierConsumed[nullifier]
```

Every value-moving action declares a conservation delta. For settlement of one principal `X`:

\[
\Delta liabilitySource[a] = -X,
\qquad
\sum_r \Delta claimOrReserve[a,r] = X,
\qquad
\Delta balance[a] = 0.
\]

For a successful claim withdrawal of `x`:

\[
\Delta claim[a] = -x,
\qquad
\Delta balance[a] = -x.
\]

No other asset index may appear in either transition. Failed transfers leave the pre-state unchanged.

## Refinement relation

The future refinement proof must map at least:

- abstract `assetId` to the contract's immutable task asset key,
- abstract liability buckets to concrete aggregate storage and per-recipient maps,
- abstract task state to the concrete enum and resolution fields,
- abstract policy snapshot to concrete task storage,
- abstract nullifier to the exact EIP-712-derived storage key,
- abstract block deadlines to EVM `block.number` comparisons,
- abstract atomic failure to concrete EVM revert behavior, and
- abstract withdrawal to external-call success and reentrancy behavior.

It must cover zero and maximum values, integer division, funding quantum, forced native transfers, failed recipients, reentrancy, governance rotation, pause, and transaction ordering. A proof that ignores external-call outcomes is not sufficient for the withdrawal theorem.

## Construction sequence

### Phase 1: checked design

- Maintain the target JSON, six canonically digest-pinned schemas, examples, documentation, and a checker mutation-tested against every security-significant inventory and conservation boundary.
- Treat all target modules as unimplemented.
- Record deterministic design-check reports.

Exit: `make verify-protocol-spec` and `make verify-protocol-spec-checker` pass.

### Phase 2: executable bounded model

- Add a standalone task-market transition model outside the current unexecuted YAML IR.
- Enumerate every lifecycle, bounty, bond, pause, governance, and claim transition.
- Emit minimal counterexample traces.
- Exhaustively check small committees and asset amounts.

Exit: every invariant has a passing support run and a refute mutation that produces a counterexample.

### Phase 3: native-PLS vertical slice

- Implement `PulseTensorNodeRegistry` and a native-PLS-only `PulseTensorTaskMarket`.
- Support one Guardian task, one provider, `REQUESTER_ACCEPTED` and `ATTESTED` modes, refunds, bonds, and claims.
- Add unit, fuzz, invariant, malicious-recipient, and local-chain tests.
- Differentially replay model traces against deployed local bytecode.

Exit: no unexplained differential divergence and no unresolved critical finding. This is conformance evidence, not refinement proof.

### Phase 4: quality consensus

- Implement committee snapshots, score commit/reveal, bounded integer aggregation, no-quorum refund, and evaluator-bond faults.
- Provide Rust and TypeScript reference implementations and golden vectors.
- Prove or exhaustively check the declared median theorem.

Exit: all consensus edge cases are byte-identical across implementations.

### Phase 5: proof modes and testnet

- Add exact and optimistic verifier modules one at a time.
- Run independent nodes, evidence replicas, watchtowers, and PulseGraph indexers.
- Test churn, partitions, withholding, RPC disagreement, key rotation, and incident recovery under bounded value.

Exit: two independent implementations interoperate and every value exposure is below its reviewed cap.

### Phase 6: refinement and capped mainnet

- Prove named value properties at source level.
- Establish a reviewed source-to-bytecode or direct-bytecode refinement relation.
- Bind the exact proof bundle to deployment receipts.
- Obtain independent contract and economic review.

Exit: only the exposure justified by the named proof, TCB, testnet history, audit, bounty, and recovery evidence.

## Current executable recipes

Design support recipe:

```bash
make verify-protocol-spec
```

Expected artifact: `runs/formal/pulsetensor_target_v1.report.json` containing the normative spec digest, referenced schema digests, counts, and current status summary.

Checker refutation recipe:

```bash
make verify-protocol-spec-checker
```

Expected behavior: every named invalid mutation is rejected. If any mutation passes, the checker is vacuous for that rule and the release gate fails.

Full repository support recipe:

```bash
make verify-release
```

Expected artifacts remain those listed in the security and release manifests, including the protocol target report after this design lands.

The present refute recipes mutate a target input and show that structural inconsistencies are caught. They do not substitute for the future model, implementation, or refinement counterexample campaigns.

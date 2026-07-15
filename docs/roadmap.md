# PulseTensor Roadmap

## Phase 0: Environment + Baseline (Current)

- Foundry workspace and protocol skeleton.
- Formalized protocol-state specifications.
- Deterministic verification scripts for build, test, and security gates.

## Phase 1: Core Contracts

- `SubnetRegistry`
- `StakeLedger`
- `CommitRevealWeights`
- `EmissionController`
- `DisputeGame`

Exit criteria:

- Specification coverage for core transitions.
- Foundry unit tests and invariants passing.

## Phase 2: Incentive and Security Hardening

- Add stake-weighted validator controls and parameter governance.
- Add challenge/slashing pathways for invalid reveals and malicious behavior.
- Add optional smooth-decay emission schedule mode behind governance timelock.
- Add optimistic inference batch-root settlement module with bonded fraud challenges.
- Harden settlement module with queued policy updates, current-epoch batch binding, and strict batch-index checks.
- Maintain OWASP/EthTrust control-matrix coverage with fail-closed CI security gates.
- Expand adversarial testing across incentive and governance paths.

Exit criteria:

- No unresolved high-severity adversarial findings.
- Formal specification coverage expanded for dispute and slashing flows.

## Phase 3: Checked Target Protocol Design

- Keep the target task-market manifest, schemas, examples, lifecycle, economics, node protocol, and theorem inventory consistent.
- Mutation-test allocation sums, asset isolation, refund paths, typed domains, governance authority, and implementation-status claims.
- Keep target modules explicitly `target_unimplemented` until source, test, and requirement evidence exists.

Exit criteria:

- `make verify-protocol-spec` passes and emits its deterministic report.
- `make verify-protocol-spec-checker` rejects every required invalid mutation.
- Independent review agrees on asset semantics, TCB, lifecycle, and proof obligations.

## Phase 4: Native-PLS Task-Market Vertical Slice

- Add controller/operator node registration.
- Add a separate native-PLS-only, one-provider task-market kernel.
- Implement one Guardian task with typed tasks and receipts, same-asset bonds, refunds, claims, and `REQUESTER_ACCEPTED` plus `ATTESTED` modes.
- Add an executable bounded transition model and differential EVM traces.

Exit criteria:

- Per-asset conservation, single settlement, immutable task policy, and refund liveness have executable counterexample searches and Foundry invariant coverage.
- Local funding, assignment, execution, resolution, settlement, refund, and claim complete without a trusted indexer.

## Phase 5: Node and Quality Network

- Ship the `ptauth/1` reference daemon and client with controller/operator separation.
- Implement evaluator committee snapshots, commit/reveal, deterministic lower weighted medians, and no-quorum refunds.
- Add evidence replication and a block-pinned PulseGraph indexer.

Exit criteria:

- Rust and TypeScript implementations match every typed-hash and consensus golden vector.
- Two independent node implementations interoperate under churn, duplicates, partitions, key rotation, and indexer restart.

## Phase 6: Testnet Integration on Pulsechain

- Deploy contracts to Pulsechain testnet.
- Stand up independent requester, provider, evaluator, challenger, evidence, and indexer operators.
- Run controlled, prefunded native-PLS bounties with asset-local metrics.

Exit criteria:

- Stable task operation and exact claim/refund accounting.
- On-chain/off-chain parity and evidence-availability checks passing.

## Phase 7: Mainnet Candidate

- External audit readiness package.
- Named source/bytecode proof evidence for the promoted value properties.
- Governance launch plan and operational runbooks.
- Value caps justified by testnet, challenge, liquidity, and recovery evidence.

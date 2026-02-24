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

## Phase 3: Testnet Integration on Pulsechain

- Deploy contracts to Pulsechain testnet.
- Stand up basic off-chain agent/validator loop.
- Run controlled reward epochs with metrics.

Exit criteria:

- Stable epoch operation and reward accounting.
- On-chain/off-chain parity checks passing.

## Phase 4: Mainnet Candidate

- External audit readiness package.
- Full verification evidence bundle.
- Governance launch plan and operational runbooks.

# PulseTensor

PulseTensor is a Pulsechain-native decentralized AI protocol inspired by Bittensor, with fail-closed contract verification gates as the default workflow.

PulseTensor currently has executable Solidity tests, fuzz/invariant campaigns, and security gates plus formalized state-model specifications. It does **not** yet have a machine-checked refinement proof from those specifications to Solidity or deployed bytecode. See [`docs/assurance_scope.md`](docs/assurance_scope.md) for the exact assurance boundary.

## Goals

- Bring agent networks and decentralized AI coordination to Pulsechain.
- Reuse what already works from Bittensor (subnets, commit/reveal, mechanism lanes, incentive alignment).
- Harden protocol behavior with deterministic tests, security analysis, and formalized specifications.
- Support isolated per-mechanism incentives inside subnets with independent epoch schedules.
- Add optional smooth-decay emission quotes (timelocked governance toggle) to reduce step shocks from pure halving schedules.
- Settle high-volume inference receipts in a separate optimistic batch-root contract with challenge windows and bonds.
- Keep settlement governance fail-closed with queued policy updates and current-epoch-only batch commits.
- Add a governance-capped inference fee policy (batch-snapshotted) so actual native-PLS deposits can create miner and maintenance claims without retroactive fee changes.
- Preserve commit/reveal liveness under pause by allowing reveal and challenge resolution while stake-changing actions remain paused.

## Local Setup

Prerequisites already supported in this environment:

- `forge` / `anvil`
- `python3`
- `docker` (required for the digest-pinned Mythril and Echidna gates)

Run:

```bash
bash scripts/bootstrap.sh
source .venv/bin/activate
make verify-private
make build
make test
make verify-security
make verify-local-e2e
make verify-requirements-traceability
make verify-protocol-spec
make verify-protocol-spec-checker
make verify-release
```

For the decentralized UI:

```bash
make ui-install
make ui-dev
```

Deploy contracts (core + settlement) with a keystore or hardware signer and write a verified deployment receipt:

```bash
RPC_URL=https://rpc.v4.testnet.pulsechain.com \
  bash scripts/deploy_pulsetensor.sh \
    --expected-chain-id 943 \
    --sender 0xYourDedicatedDeployer \
    --account pulsetensor-deployer
```

Each run atomically publishes a unique v4 receipt such as
`runs/deployments/pulsetensor_deploy_943-YYYYMMDDTHHMMSSZ-<run>_<tx>.receipt.json`
and retains an owner-only partial JSONL journal for safe recovery if the second transaction or a later check fails.

The wrapper validates successful receipts, sender-derived addresses, chain ID, explicit consecutive latest/pending nonces, gas budgets, and exact transaction inputs; links the Core address into every compiler-declared Settlement immutable offset; submits only those already-inspected creation bytes through `cast send --create`; and requires the deployed runtimes to equal both the preflight artifacts and a post-confirmation isolated rebuild made with the locked Forge/Cast/Solc binaries.

For chain 369, it also extracts the authorized commit with `git archive` and performs an isolated production rebuild before gas estimation, journal creation, or signing. Creation/runtime bytes, compiler settings, and immutable-reference locations must match the already-hashed live artifacts exactly.

Raw keys and mnemonics are intentionally unsupported. Ledger, Trezor, AWS KMS, Foundry keystore, and interactive signing are supported. The public receipt omits signer class and local signer paths, but the deployer address remains public on-chain; use a dedicated entity-controlled deployment wallet and never reuse a personal holdings wallet. See `bash scripts/deploy_pulsetensor.sh --help`.

For the testnet-to-mainnet checkpoint, fee-cap, recovery-journal, and independent receipt-verification procedure, see [`docs/security/private_launch.md`](docs/security/private_launch.md). The privacy goal is lawful key compartmentation and reduced metadata exposure, not anonymity or concealment of ownership.

Deployment requires the pinned Solidity 0.8.36 size-safe profile (`FOUNDRY_OPTIMIZER_RUNS=1`) to keep `PulseTensorCore`
within EVM code-size limits. Do not override the deployment profile; run `bash scripts/check_deploy_code_size.sh` as part of release verification.

Render launch-safe subnet/mechanism presets (with queue/execute rollout plan):

```bash
bash scripts/render_launch_preset.sh --preset balanced --netuid 1 --mechid 0 \
  --core 0x... --settlement 0x... --governance 0x... \
  --out runs/deployments/preset_balanced_netuid1.json
```

Run deterministic emergency-mode goal-frontier synthesis (design-space tradeoff extraction):

```bash
make synth-goal-frontier
make verify-goal-frontier
```

Run tokenomics profile frontier synthesis and check:

```bash
make synth-tokenomics-frontier
make verify-tokenomics-frontier
```

Run participant-regret invariant frontier synthesis and check:

```bash
make synth-participant-regret-frontier
make verify-participant-regret-frontier
```

Automated community release artifacts (deterministic hashes + tarball):

```bash
make ui-release
```

Publish release artifacts to IPFS (dist CID + tarball CID + receipt):

```bash
make ui-ipfs
```

`make verify-release` is the single canonical merge and pre-deploy assurance gate. It includes mandatory
Echidna, deploy code-size viability, encrypted-keystore deployment rehearsal, local live-chain replay, all
frontier checks, and a commit-bound evidence manifest. `make verify-complete` and
`make verify-release-full` are compatibility aliases to the same pipeline.

`make verify-local-e2e` runs a deterministic live-chain local integration flow on fresh Anvil:
deploys contracts, executes governance queue/execute paths, runs validator commit/reveal, and validates inference
commit/finalize/settle/claim behavior. Report path: `runs/local_e2e/local_e2e_report.json`.

`make verify-requirements-traceability` validates requirement-to-test/function coverage, including boundary-value
coverage targets, from `specs/formal/requirements_traceability.json`.

`make verify-protocol-spec` validates the internally consistent, still-unimplemented target task-market design and
writes `runs/formal/pulsetensor_target_v1.report.json`. `make verify-protocol-spec-checker` mutation-tests that gate.
Neither command proves a future Solidity implementation or any asset's purchasing power.

## Participation Modes

- **Subnet owner**
  - Create subnet with `createSubnet`.
  - Set governance contract via `configureSubnetGovernance` (must be a contract account, not EOA).
  - Governance then queues/executes privileged actions.
- **Validator**
  - Add stake (`addStake`), register (`registerValidator`), then run commit/reveal cycles.
  - Reveals remain callable even while a subnet is paused, so pending commitments can still be resolved and challenged.
- **Miner**
  - Register with `registerMiner`, serve inference workload off-chain.
- **Settlement proposer/challenger**
  - Proposer submits batch roots with bond (`commitInferenceBatchRoot`).
  - Prefer `computeInferenceLeaf(netuid, mechid, epoch, requestId, resultHash)` when constructing leaves off-chain to avoid cross-epoch/request collisions.
  - Fee payers escrow inference fees per batch (`fundInferenceBatchFees`) and can withdraw before finalization (`withdrawInferenceBatchFees`).
  - Finalization routes funded fees to proposer + miner sink + treasury sink using the batch-snapshotted fee policy.
  - Anyone can challenge invalid roots in challenge window.
  - Proposers/challengers claim refunds/rewards through pull claims.

## Tokenomics (PLS-native)

- PulseTensor currently uses **native PLS flows**; no separate protocol token is required to launch.
- Subnet/mechanism emissions are liabilities from explicitly funded pools and optional halving/smoothing schedules.
- Inference settlement introduces a **capped protocol fee lane**:
  - `protocolFeeBps <= 3000` (max 30% of funded batch fees).
  - Protocol fee split between treasury and miner sink (`treasuryFeeBps`), with proposer receiving the remainder.
  - Fee policy is governance-timelocked, cancellable, and expires if not executed within a bounded window.
  - Fee policy is snapshotted at batch commit to prevent ex-post governance fee extraction.
- Every current fee claim comes from native PLS actually deposited by a batch funder. No deposits means no fee flow.
- The target work market uses one immutable asset per task, same-asset bonds, no price oracle, no cross-asset netting,
  and exact accepted/rejected/refund vectors. This target is specified but not yet implemented.
- Builder, core-maintainer, and provider claims are disclosed bounties and fees in the deposited asset, not a salary
  or purchasing-power guarantee.

Fast local iteration without full security scans:

```bash
make verify-dev
```

Compatibility alias for the canonical release gate:

```bash
make verify-release-full
```

Build a static frontend bundle for host-anywhere deployments:

```bash
make ui-build
make ui-hash
```

Run only the digest-pinned Echidna campaign during local investigation:

```bash
make verify-echidna
```

## Repo Layout

- `src/`: PulseTensor smart contracts.
  - `src/PulseTensorCore.sol`: core subnet, stake, commit/reveal, slashing, and emission schedule logic.
  - `src/PulseTensorInferenceSettlement.sol`: optional inference batch-root settlement and fraud-challenge module.
- `frontend/`: backend-free static dApp UI with dedicated Core + Settlement consoles (wallet + RPC direct contract access).
- `test/`: Foundry tests.
- `specs/formal/`: formalized protocol state-model specifications.
- `specs/protocol/`: checked target schemas, examples, lifecycle, economics, network, and proof obligations.
- `scripts/`: build, security, release, and deployment automation.

`make verify-private` fail-closes if private dependency directories become tracked, if private SSH repository URLs are added to tracked files, or if public documentation references local private dependency paths.

## Documentation

- `docs/bittensor_delta.md`: what we keep vs improve from Bittensor.
- `docs/formal_workflow.md`: required verification gates.
- `docs/assurance_scope.md`: exact verified, tested, specified, and still-unproved claims.
- `specs/formal/requirements_traceability.json`: requirement-to-function/test traceability matrix with explicit BVA coverage.
- `docs/frontend_decentralization.md`: host-anywhere frontend model and trust surface.
- `docs/roadmap.md`: phased build plan.
- `docs/launch_presets.md`: safe launch parameter tiers + game-theoretic rationale.
- `docs/goal_frontier_synthesis.md`: deterministic multi-goal frontier synthesis for mechanism/design exploration.
- `docs/tokenomics.md`: current native-PLS flows and target asset-local bounty economics.
- `docs/protocol/defi_native_economics_v1.md`: oracle-free bounty, fee, refund, bond, and maintainer-flow design.
- `docs/protocol/task_market_v1.md`: typed task/receipt lifecycle and target settlement kernel.
- `docs/protocol/quality_consensus_v1.md`: task-local evaluator commit/reveal and deterministic aggregation.
- `docs/protocol/node_network_v1.md`: controller/operator discovery, `ptauth/1`, evidence transport, and PulseGraph.
- `docs/protocol/proof_obligations_v1.md`: theorem inventory, TCB, evidence ladder, and construction phases.
- `docs/participant_regret_invariants.md`: safety-oriented invariant profile selected to minimize participant regret.
- `docs/research/pulsetensor_frontier_2026.md`: 2026 Bittensor comparison, PulseChain demand thesis, architecture, asset-native funding, token-function gates, and falsifiable research plan.
- `docs/security/private_launch.md`: wallet separation, signer policy, RPC privacy limits, and authority handoff.
- `docs/security/security_standards.md`: OWASP/EthTrust/Solidity-bug standards baseline.
- `docs/security/control_matrix.json`: security control-to-evidence mapping gate.
- `docs/security/governance_committee_charter.md`: founder-balanced committee authority and independence policy.
- `docs/security/signer_selection_checklist.md`: signer onboarding and activation checklist.
- `docs/security/multisig_operations.md`: Safe-style multisig operations standard and queue discipline.
- `docs/security/slither_exclusions.allowlist`: locked Slither detector exclusions.
- `docs/security/mythril_ignored_swc.allowlist`: locked Mythril SWC ignores.
- `docs/security/artifact_manifest.security.txt`, `docs/security/artifact_manifest.release.txt`: freshness manifests for deterministic evidence artifacts.

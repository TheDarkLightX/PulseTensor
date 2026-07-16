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
- Add a governance-capped inference fee policy (batch-snapshotted) so protocol usage can fund miners and a development treasury without retroactive fee changes.
- Preserve commit/reveal liveness under pause by allowing reveal and challenge resolution while stake-changing actions remain paused.

## Local Setup

Prerequisites already supported in this environment:

- `forge` / `anvil`
- `python3`
- `docker` (required for the digest-pinned Mythril and Echidna gates)
- exact `jq`, `solhint`, and `rg` versions from `scripts/toolchain.lock`

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
make verify-release
```

For the decentralized UI:

```bash
make ui-install
make ui-dev
```

Deploy contracts (core + settlement) with a protected signer and write a deployment receipt:

```bash
RPC_URL=https://rpc.v4.testnet.pulsechain.com \
bash scripts/deploy_pulsetensor.sh \
  --expected-chain-id 943 \
  --account pulsetensor-deployer
```

Receipt path: `runs/deployments/pulsetensor_deploy_receipt.json`.

Production raw private-key and mnemonic arguments/environment variables are rejected. Encrypted Foundry
accounts/keystores (with hidden prompt or password file), Ledger, Trezor, AWS KMS, and Foundry's hidden
interactive signing are supported. See [`docs/deployment_security.md`](docs/deployment_security.md) for signer
examples, chain confirmation and rehearsal steps, the unavoidable public-chain privacy boundary, and the
local-test-only key guard.

Deployment requires the attested size-safe compiler profile (`FOUNDRY_OPTIMIZER_RUNS=1`) because `PulseTensorCore`
is close to the EVM runtime-code limit. The production script rejects profile overrides.

Render bounded, uncalibrated subnet/mechanism test presets (with queue/execute rollout plan):

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
Echidna, deploy code-size viability, local live-chain replay, all frontier checks, and a commit-bound evidence
manifest. `make verify-complete` and `make verify-release-full` are compatibility aliases to the same pipeline.

`make verify-local-e2e` runs a deterministic live-chain local integration flow on fresh Anvil:
deploys contracts, executes governance queue/execute paths, runs validator commit/reveal, and validates inference
commit/finalize/settle/claim behavior. Report path: `runs/local_e2e/local_e2e_report.json`.

`make verify-requirements-traceability` validates requirement-to-test/function coverage, including boundary-value
coverage targets, from `specs/formal/requirements_traceability.json`.

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
  - Anyone can submit the implemented identical-leaf duplicate or prior-finalized-batch replay proofs during the challenge window; these checks do not establish general result correctness.
  - Proposers/challengers claim refunds/rewards through pull claims.

## Tokenomics (PLS-native)

- PulseTensor currently uses **PLS-native flows** (no separate protocol token required to launch).
- Subnet/mechanism emissions are liabilities from explicit pools and optional halving/smoothing schedules.
- Inference settlement introduces a **capped protocol fee lane**:
  - `protocolFeeBps <= 3000` (max 30% of funded batch fees).
  - Protocol fee split between treasury and miner sink (`treasuryFeeBps`), with proposer receiving the remainder.
  - Fee policy is governance-timelocked, cancellable, and expires if not executed within a bounded window.
  - Fee policy is snapshotted at batch commit to prevent ex-post governance fee extraction.
- Development funding can come from treasury sink claims from real usage, rather than foundation grants.

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
  - `src/PulseTensorInferenceSettlement.sol`: optional optimistic batch accounting with exact duplicate-leaf/replay challenges; it is not a general inference fraud-proof module.
- `frontend/`: backend-free static dApp UI with dedicated Core + Settlement consoles (wallet + RPC direct contract access).
- `test/`: Foundry tests.
- `specs/formal/`: formalized protocol state-model specifications.
- `scripts/`: build, security, release, and deployment automation.

`make verify-private` fail-closes if private dependency directories become tracked, if private SSH repository URLs are added to tracked files, or if public documentation references local private dependency paths.

## Documentation

- `docs/bittensor_delta.md`: what we keep vs improve from Bittensor.
- `docs/formal_workflow.md`: required verification gates.
- `docs/assurance_scope.md`: exact verified, tested, specified, and still-unproved claims.
- `specs/formal/requirements_traceability.json`: requirement-to-function/test traceability matrix with explicit BVA coverage.
- `docs/frontend_decentralization.md`: host-anywhere frontend model and trust surface.
- `docs/roadmap.md`: phased build plan.
- `docs/launch_presets.md`: uncalibrated parameter tiers, limits, and design rationale.
- `docs/goal_frontier_synthesis.md`: deterministic multi-goal frontier synthesis for mechanism/design exploration.
- `docs/tokenomics.md`: game-theoretic tokenomics design and parameter recommendations.
- `docs/participant_regret_invariants.md`: safety-oriented invariant profile selected to minimize participant regret.
- `docs/security/security_standards.md`: OWASP/EthTrust/Solidity-bug standards baseline.
- `docs/security/control_matrix.json`: security control-to-evidence mapping gate.
- `docs/security/governance_committee_charter.md`: founder-balanced committee authority and independence policy.
- `docs/security/signer_selection_checklist.md`: signer onboarding and activation checklist.
- `docs/security/multisig_operations.md`: Safe-style multisig operations standard and queue discipline.
- `docs/security/slither_exclusions.allowlist`: locked Slither detector exclusions.
- `docs/security/mythril_ignored_swc.allowlist`: locked Mythril SWC ignores.
- `docs/security/artifact_manifest.security.txt`, `docs/security/artifact_manifest.release.txt`: freshness manifests for deterministic evidence artifacts.

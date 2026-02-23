# PulseTensor

PulseTensor is a Pulsechain-native decentralized AI protocol inspired by Bittensor, with formal verification gates as
the default development workflow.

## Goals

- Bring agent networks and decentralized AI coordination to Pulsechain.
- Reuse what already works from Bittensor (subnets, commit/reveal, mechanism lanes, incentive alignment).
- Improve weak points with formal methods and adversarial search (ESSO + Morph + ZAG).
- Support isolated per-mechanism incentives inside subnets (Bittensor-style mechanism tracks) with independent epoch schedules.
- Add optional smooth-decay emission quotes (timelocked governance toggle) to reduce step shocks from pure halving schedules.
- Settle high-volume inference receipts in a separate optimistic batch-root contract with challenge windows and bonds.
- Keep settlement governance fail-closed with queued policy updates and enforce current-epoch-only batch commits.
- Add a governance-capped inference fee policy (batch-snapshotted) so protocol usage can fund miners and a development treasury without retroactive fee changes.
- Ship smart contracts in a correct-by-construction process.

## Local Setup

Prerequisites already supported in this environment:

- `forge` / `anvil`
- `python3`
- `lake` (for ZAG/Lean workflows)
- `z3` and `cvc5`
- `docker` (required for Mythril gate; also used as Echidna fallback)

Run:

```bash
bash scripts/bootstrap.sh
source .venv/bin/activate
make verify-private
make build
make test
make verify-security
make verify-esso
make verify-orch
make verify-release
```

For the decentralized UI:

```bash
make ui-install
make ui-dev
```

Deploy contracts (core + settlement) and write deployment receipt:

```bash
RPC_URL=https://rpc.v4.testnet.pulsechain.com \
PRIVATE_KEY=0x... \
make deploy
```

Receipt path: `runs/deployments/pulsetensor_deploy_receipt.json`.

Automated community release artifacts (deterministic hashes + tarball):

```bash
make ui-release
```

Publish release artifacts to IPFS (dist CID + tarball CID + receipt):

```bash
make ui-ipfs
```

`make verify-release` is the canonical merge gate and enforces ZAG quick mode plus mandatory Echidna.

## Participation Modes

- **Subnet owner**
  - Create subnet with `createSubnet`.
  - Set governance contract via `configureSubnetGovernance` (must be a contract account, not EOA).
  - Governance then queues/executes privileged actions.
- **Validator**
  - Add stake (`addStake`), register (`registerValidator`), then run commit/reveal cycles.
- **Miner**
  - Register with `registerMiner`, serve inference workload off-chain.
- **Settlement proposer/challenger**
  - Proposer submits batch roots with bond (`commitInferenceBatchRoot`).
  - Fee payers escrow inference fees per batch (`fundInferenceBatchFees`) and can withdraw before finalization (`withdrawInferenceBatchFees`).
  - Finalization routes funded fees to proposer + miner sink + treasury sink using the batch-snapshotted fee policy.
  - Anyone can challenge invalid roots in challenge window.
  - Proposers/challengers claim refunds/rewards through pull claims.

## Tokenomics (PLS-native)

- PulseTensor currently uses **PLS-native flows** (no separate protocol token required to launch).
- Subnet/mechanism emissions are liabilities from explicit pools and optional halving/smoothing schedules.
- Inference settlement introduces a **capped protocol fee lane**:
  - `protocolFeeBps <= 3000` (max 30% of funded batch fees).
  - Protocol fee split between treasury and miner sink (`treasuryFeeBps`), with proposer receiving the remainder.
  - Fee policy is governance-timelocked and snapshotted at batch commit to prevent ex-post governance fee extraction.
- Development funding can come from treasury sink claims from real usage, rather than foundation grants.

Fast local iteration without Morph/ZAG:

```bash
make verify-dev
```

Full research gate:

```bash
make verify-release-full
```

`make verify-release-full` runs the same gate with ZAG full mode (Echidna still mandatory).

Build a static frontend bundle for host-anywhere deployments:

```bash
make ui-build
make ui-hash
```

Launch the innovation swarm (Morph + ESSO + ZAG-oriented prompts):

```bash
bash scripts/run_orch_algo_swarm_v2.sh
```

Optional deep fuzzing (Echidna) inside security gate:

```bash
RUN_ECHIDNA=1 make verify-release
```

## Repo Layout

- `src/`: PulseTensor smart contracts.
  - `src/PulseTensorCore.sol`: core subnet, stake, commit/reveal, slashing, and emission schedule logic.
  - `src/PulseTensorInferenceSettlement.sol`: optional inference batch-root settlement and fraud-challenge module.
- `frontend/`: backend-free static dApp UI with dedicated Core + Settlement consoles (wallet + RPC direct contract access).
- `test/`: Foundry tests.
- `specs/esso/`: ESSO formal state-machine models.
- `scripts/`: verification workflow scripts for ESSO, Morph, and ZAG.
- `external/`: pinned upstream research/tooling repos (Bittensor, go-pulse, plus private internal tools such as ESSO/Morph/ZAG/Orchestration-Unit); not protocol runtime logic and not intended for public redistribution.

`make verify-private` fail-closes if `external/` becomes tracked, if private/upstream repo URLs are added to public-tree files, or if private tool remotes are not SSH.

## Documentation

- `docs/bittensor_delta.md`: what we keep vs improve from Bittensor.
- `docs/formal_workflow.md`: required verification gates.
- `docs/frontend_decentralization.md`: host-anywhere frontend model and trust surface.
- `docs/roadmap.md`: phased build plan.
- `docs/tokenomics.md`: game-theoretic tokenomics design and parameter recommendations.
- `docs/security/security_standards.md`: OWASP/EthTrust/Solidity-bug standards baseline.
- `docs/security/control_matrix.json`: security control-to-evidence mapping gate.
- `docs/security/slither_exclusions.allowlist`: locked Slither detector exclusions.
- `docs/security/mythril_ignored_swc.allowlist`: locked Mythril SWC ignores.
- `docs/security/artifact_manifest.security.txt`, `docs/security/artifact_manifest.esso.txt`, `docs/security/artifact_manifest.release.txt`: freshness manifests for deterministic evidence artifacts.

# PulseTensor Assurance Scope

This document defines what PulseTensor's current evidence does and does not establish. Public claims must remain inside this boundary.

## Current executable evidence

| Evidence | What it establishes | What it does not establish |
|---|---|---|
| Foundry formatting and unit tests | The pinned formatter accepts the source and the tested EVM examples produce the asserted results under the configured compiler and test environment. | Correctness for every state and adversarial strategy. |
| Foundry fuzz tests and invariants | No counterexample was found within the declared run counts, sequence depths, actors, and input generators. | A proof that counterexamples do not exist outside that bounded campaign. |
| Echidna Boolean properties | When the Echidna gate completes in `property` mode, no counterexample was found within its configured campaign. | Properties outside the harness or an unbounded proof. |
| Requirements traceability | Required functions, referenced tests, evidence paths, and coverage metadata exist and satisfy the structural policy. | Execution of those tests, validity of the YAML semantics, or refinement to Solidity. |
| Security control matrix | Required OWASP and EthTrust control IDs, allowed status labels, and referenced repository paths are structurally present. | That a referenced path mitigates the control or that a `mitigated` label is independently established. |
| Slither, Mythril, Solhint, compiler-bug, and anti-pattern gates | The configured tools found no non-allowlisted issue in their supported rule sets when the recorded run completed. | Absence of all vulnerabilities, economic attacks, or specification defects. |
| Local Anvil end-to-end replay | The scripted deployment and lifecycle path completes on a fresh local chain. | PulseChain mainnet behavior, network reliability, or operator correctness. |
| Goal-frontier regressions | The deterministic solver reproduces realizability and witness outcomes for the finite states, transitions, and labels authored in each scenario model. | Validation of the state labels, probabilities, economic calibration, participant behavior, demand, Sybil resistance, PLS purchasing power, or real-world sustainability. |

The required `Contract Assurance` workflow runs the deploy-profile tests, the
security analyzers, an actual digest-pinned Echidna campaign, the local
lifecycle, and the formal-frontier regression checks. It retains a
commit-bound evidence manifest. The local `make verify-release` command remains
the canonical release gate because it runs the same release profile plus the
local lifecycle and frontier checks. Both paths enforce exact hashes for
Foundry, solc, and forge-std, exact Node.js/npm versions, and an
integrity-bearing repository lock for Solhint's full npm dependency graph. The
Solhint lockfile digest is enforced by the toolchain gate and recorded in
commit-bound evidence. The host Docker daemon is recorded rather than claimed
reproducible; Mythril and Echidna workloads use digest-pinned images.

Slither's top-level version is pinned, but its Python transitive environment is
not yet hash-locked. Its exact virtualenv Python and bundled pip versions plus
the resolved environment digest are checked and recorded, but a fresh bootstrap
can still resolve different transitive artifacts from the package index. Slither detector
and Mythril SWC exclusions are currently class-wide rather than finding-scoped;
a new occurrence under an excluded class could be missed. These are explicit
residual gaps, not evidence that the excluded vulnerability classes are absent.
Replace them with a hash-locked Slither graph plus fingerprinted, path-specific
findings and expiring rationales before a mainnet assurance claim.

The current Echidna harness is intentionally narrow. It fuzzes two validator actors through stake, registration, base-lane commit/reveal, expiry challenge, and unregister actions. It checks stake/native-liability conservation, exact validator count, validation eligibility, and commitment bookkeeping. It does not cover the inference-settlement contract, mechanism lanes, governance mutation, miner lifecycle, or emission distribution. The gate enforces the intended property/action inventory, campaign minima, nonzero coverage/corpus metrics, and a known-failing negative control; those checks establish that the selected fuzzer wiring executed and can detect one counterexample, not that each production property is semantically complete.

## Formal status

The files under `specs/formal/` are formalized, bounded transition-system specifications. They are useful design contracts and traceability anchors. The public repository currently does not execute a model checker over them and does not contain a machine-checked refinement proof connecting:

1. the state-model transitions,
2. the Solidity source,
3. compiler output, and
4. deployed PulseChain bytecode.

Accordingly, the accurate current phrase is **formal-specification-driven and adversarially tested**, not **fully formally verified**.

## Current inference-settlement boundary

`PulseTensorInferenceSettlement` is an optimistic batch-accounting shell, not a semantic or ZK verifier. It checks Merkle inclusion and can slash an identical leaf duplicated within one batch or repeated from an earlier finalized batch. It does not establish that an inference is correct, useful, available, or produced by a claimed model. A unique arbitrary result can pass the current challenge surface, and funded fees are distributed when the batch finalizes before any leaf is individually revealed or settled.

The canonical leaf includes both `epoch` and `resultHash`, while the replay challenge requires the identical leaf hash across different epochs. Consequently, canonical same-request replay across epochs—and same-request substitution with a different result—does not produce the identical hash required by that challenge. Do not place correctness-dependent value on this optimistic path. A separate proof-backed settlement path must use a request nullifier independent of epoch and output, bind every value-authoritative public input into the proof journal, and release funds only after proof verification.

## Claims that can be made after the relevant gates pass

- The named test, fuzz, invariant, static-analysis, or end-to-end gate passed at a specific commit with a specific toolchain.
- The contracts enforce the tested authorization, accounting, timing, and replay conditions for the covered paths.
- The source has formalized state-model specifications and a machine-checked structural requirements map.

Every claim should link the commit, command, toolchain, and evidence artifact.

The trusted computing base still includes the specification, test and harness
quality, Solidity compiler, EVM semantics, analyzer/prover implementations,
PulseChain consensus and data availability, external assets, governance keys,
and deployment operator. A passing gate does not remove these assumptions.

## Claims that are not yet justified

- Solidity behavior is proven equivalent to the YAML models.
- Deployed bytecode is proven equivalent to the reviewed source.
- AI outputs are correct, useful, unbiased, or generated by the claimed model.
- The system is Sybil-proof, collusion-proof, economically sustainable, or anonymous.
- Passing a release gate eliminates the need for independent audit, testnet operation, and bounded launch exposure.

## Required path to stronger formal assurance

1. Give the formal IR an executable, version-pinned checker with counterexample artifacts.
2. Differentially replay generated model traces against the EVM implementation; call this conformance testing, not refinement proof.
3. Prove a machine-checked simulation/refinement theorem plus value-conservation, single-settlement, authorization, and lifecycle properties in a Solidity-aware prover.
4. Bind verified source and compiler settings to reproducible bytecode hashes.
5. Require each deployment receipt to name the theorem/spec versions and exact evidence bundle.

Counterexamples override claims. A failing or skipped mandatory gate means the corresponding assurance claim is unavailable.

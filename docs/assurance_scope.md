# PulseTensor Assurance Scope

This document defines what PulseTensor's current evidence does and does not establish. Public claims must remain inside this boundary.

## Current executable evidence

| Evidence | What it establishes | What it does not establish |
|---|---|---|
| Foundry unit tests | The tested EVM examples produce the asserted results under the configured compiler and test environment. | Correctness for every state and adversarial strategy. |
| Foundry fuzz tests and invariants | No counterexample was found within the declared run counts, sequence depths, actors, and input generators. | A proof that counterexamples do not exist outside that bounded campaign. |
| Echidna Boolean properties | When the Echidna gate completes in `property` mode, no counterexample was found within its configured campaign. | Properties outside the harness or an unbounded proof. |
| Requirements traceability | Required functions, referenced tests, evidence paths, and coverage metadata exist and satisfy the structural policy. | Execution of those tests, validity of the YAML semantics, or refinement to Solidity. |
| Target protocol specification checker | The target JSON, schemas, examples, allocation vectors, lifecycle graph, typed domains, status claims, and referenced documents satisfy the checker's structural rules; the mutation suite rejects its named invalid changes. | That target modules exist, that the lifecycle was model-checked, that economics produce demand, or that future Solidity refines the target. |
| Security control matrix | Required OWASP and EthTrust control IDs, allowed status labels, and referenced repository paths are structurally present. | That a referenced path mitigates the control or that a `mitigated` label is independently established. |
| Slither, Mythril, Solhint, compiler-bug, and anti-pattern gates | The configured tools found no non-allowlisted issue in their supported rule sets when the recorded run completed. | Absence of all vulnerabilities, economic attacks, or specification defects. |
| Local Anvil end-to-end replay | The scripted deployment and lifecycle path completes on a fresh local chain. | PulseChain mainnet behavior, network reliability, or operator correctness. |

The required `Contract Assurance` workflow runs the deploy-profile tests, the
security analyzers, an actual digest-pinned Echidna campaign, the local
lifecycle, target-protocol checks, and the formal-frontier regression checks. It retains a
commit-bound evidence manifest. The local `make verify-release` command remains
the canonical release gate because it runs the same release profile plus the
local lifecycle and frontier checks. Both paths enforce exact hashes for
Foundry, solc, and forge-std. The host Docker daemon is recorded rather than
claimed reproducible; Mythril and Echidna workloads use digest-pinned images.

Slither's top-level version is pinned, but its Python transitive environment is
not yet hash-locked. Slither detector and Mythril SWC exclusions are currently
class-wide rather than finding-scoped; a new occurrence under an excluded class
could be missed. These are explicit residual gaps, not evidence that the
excluded vulnerability classes are absent. Replace them with fingerprinted,
path-specific findings and expiring rationales before a mainnet assurance claim.

## Formal status

The files under `specs/formal/` are formalized, bounded transition-system specifications. They are useful design contracts and traceability anchors. The public repository currently does not execute a model checker over them and does not contain a machine-checked refinement proof connecting:

1. the state-model transitions,
2. the Solidity source,
3. compiler output, and
4. deployed PulseChain bytecode.

Accordingly, the accurate current phrase is **formal-specification-driven and adversarially tested**, not **fully formally verified**.

The files under `specs/protocol/` are a separate, checked target design for modules that do not yet exist. `scripts/check_protocol_spec.py` validates canonical schema digests, a strict JSON-schema subset, examples, reference closure, asset isolation, the versioned payout/bond policy, lifecycle reachability, refund exits, ordered typed-domain fields, governance nonseizure, and evidence status. Its mutation self-test demonstrates those named rules are not vacuous. It does not execute the planned value transition system or promote `target_unimplemented` items to implementation evidence.

## Claims that can be made after the relevant gates pass

- The named test, fuzz, invariant, static-analysis, or end-to-end gate passed at a specific commit with a specific toolchain.
- The contracts enforce the tested authorization, accounting, timing, and replay conditions for the covered paths.
- The source has formalized state-model specifications and a machine-checked structural requirements map.
- The target protocol design passed its structural and mutation gates at a named commit, while remaining explicitly unimplemented.

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
- The target task market, node network, evaluator consensus, or multi-asset adapters are implemented merely because their schemas pass.

## Required path to stronger formal assurance

1. Convert the target task-market lifecycle and per-asset equations into an executable, version-pinned transition checker with counterexample artifacts.
2. Give the current formal IR the same executable semantics or replace it with the reviewed executable representation.
3. Differentially replay generated model traces against the EVM implementation; call this conformance testing, not refinement proof.
4. Prove a machine-checked simulation/refinement theorem plus value-conservation, single-settlement, authorization, and lifecycle properties in a Solidity-aware prover.
5. Bind verified source and compiler settings to reproducible bytecode hashes.
6. Require each deployment receipt to name the theorem/spec versions and exact evidence bundle.

Counterexamples override claims. A failing or skipped mandatory gate means the corresponding assurance claim is unavailable.

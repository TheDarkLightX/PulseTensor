# Keyless ZK Exact-Inference Settlement V1

## Status and assurance boundary

This document specifies the first proof-backed PulseTensor settlement lane. It is separate from
`PulseTensorInferenceSettlement`, whose duplicate/replay challenges do not establish inference correctness.

V1 is intentionally a small end-to-end relation. A valid receipt is intended to establish that one exact,
publicly committed program executed and emitted the settlement journal below. It does not establish that a
model is useful, fair, licensed, private, or economically valuable.

The Solidity implementation, bounded state model, tests, and mutation campaigns are evidence for this
specification. They are not yet a machine-checked refinement proof from this document to EVM bytecode. A
value-bearing deployment additionally requires a genuine proof fixture, a PulseChain testnet verifier canary,
measured gas/code size, and independent review.

## Why there is no immutable signing key

The verifier configuration contains no private or privileged signing key. `programId` is a public
cryptographic commitment to the exact guest program. Immutability is used only for the meaning of an already
created task:

- a configuration ID never changes its adapter, adapter runtime code hash, program ID, relation ID, or fee
  terms;
- governance can add a replacement configuration after a delay;
- governance can deprecate a configuration after a delay, stopping only new tasks;
- governance can immediately and permanently revoke a compromised configuration;
- revocation can only unlock full requester refunds; it can never authorize settlement or redirect value;
- a deprecated or revoked configuration is never reactivated.

This is append-only verifier versioning, not permanent dependence on one authority or key.

## Actors and trust boundaries

- **Requester:** escrows PLS and commits the task's input and model.
- **Provider:** performs the committed computation and is named in the proved journal.
- **Beneficiary:** receives the provider share and is named in the proved journal. Anyone may relay the proof.
- **Subnet governance:** queues verifier versions/deprecations and may emergency-revoke a version.
- **Treasury:** receives a bounded success fee. It receives nothing on expiry or verifier revocation.
- **Adapter:** converts the neutral PulseTensor verifier ABI to one pinned proof-system ABI.
- **Base verifier:** checks the cryptographic proof. It is never called through `delegatecall`.

The settlement checks the adapter runtime code hash when a configuration is queued, executed, and used. A code
hash does not bind mutable storage or an implementation behind a proxy. Production admission therefore permits
only a reviewed, stateless, non-proxy adapter whose base-verifier address and runtime hash are Solidity
immutables. The RISC Zero adapter checks that base verifier's runtime code hash and the receipt seal selector on
every verification, and its constructor requires the direct verifier's `VERSION()` to equal `3.0.0`. Solidity
immutable constructor values are embedded into runtime code, so the recorded
runtime hash commits to those values for this reviewed adapter implementation. A proxy-upgrade counterexample
test must demonstrate why a stable proxy code hash is insufficient.

The reviewed adapter exposes whether its pinned base-verifier runtime hash still matches. Configuration execution,
new-task admission, and proof settlement require both adapter and base-verifier hashes to match. If either code hash
drifts—or the availability query fails or returns malformed data—an existing task can take the permissionless
unavailable-verifier refund. The metadata availability function is a strict compatibility boundary: it must be
side-effect-free, finish within 50,000 gas, and return exactly one canonical 32-byte ABI boolean (`0` or `1`). An
adapter that cannot satisfy that bound is unavailable by definition.
This check still does not make proxies safe: a stable proxy runtime hash can conceal a changed implementation or
mutable storage, so proxy/router admission remains prohibited by the production review policy.

## Neutral proof-verifier ABI

```solidity
interface IPulseTensorProofVerifier {
    function verify(
        bytes32 programId,
        bytes calldata publicValues,
        bytes calldata proof
    ) external view;

    function proofSystemId() external view returns (bytes32);
}

interface IPulseTensorProofVerifierMetadata {
    function proofSelector() external view returns (bytes4);
    function verifierRuntimeCodeHash() external view returns (bytes32);
    function verifierRuntimeCodeHashMatches() external view returns (bool);
}
```

`verify` must revert unless `proof` establishes execution of `programId` with exactly `publicValues`. A boolean
return is deliberately not used because an ignored `false` would be a fail-open integration hazard.

For RISC Zero 3.0, the adapter calls the pinned base ABI:

```solidity
verify(proof, programId, sha256(publicValues))
```

It uses the unconditional `verify` path, not a general claim-integrity API. The V3 Groth16 seal must be exactly
260 bytes: its four-byte selector followed by eight canonical 32-byte proof words. Trailing bytes are rejected.
The selector is a routing/version identifier, not a secret and not sufficient by itself; the base-verifier address,
exact runtime code hash, and `3.0.0` version string are also bound. Version and selector checks prevent accidental family
mismatches but cannot authenticate arbitrary code. Production admission must compare the base runtime hash to a
reviewed deployment manifest derived from the pinned upstream source; accepting a caller-invented hash would merely
pin malicious code.

## Exact V1 relation

The first guest must implement only this deterministic bounded-integer relation:

```text
relation: PT_Q8_LINEAR_V1

x: int16[32]
W: int8[32][4]  // Solidity type; outer index j=0..3, inner index i=0..31
b: int32[4]

score[j] = int64(b[j]) + sum(i=0..31, int64(x[i]) * int64(W[j][i]))
classIndex = the smallest j whose score[j] is maximal
```

All guest arithmetic is checked. The canonical ABI order for `W` is row-major in the explicit Solidity sense:
encode `W[0][0..31]`, then `W[1][0..31]`, through `W[3][0..31]`. Floating point, variable shapes,
nondeterministic kernels, host callbacks, and ambiguous tie handling are outside V1.

Commitments are SHA-256 over canonical ABI bytes:

```text
relationId      = sha256(bytes("PULSETENSOR/PT_Q8_LINEAR/1"))
inputCommitment = sha256(abi.encode(INPUT_DOMAIN, uint32(1), x))
modelCommitment = sha256(abi.encode(MODEL_DOMAIN, uint32(1), W, b))
outputCommitment = sha256(abi.encode(OUTPUT_DOMAIN, uint32(1), classIndex, scores))
```

Here `INPUT_DOMAIN`, `MODEL_DOMAIN`, and `OUTPUT_DOMAIN` are the `bytes32` Keccak-256 hashes of
`PULSETENSOR_EXACT_INPUT_V1`, `PULSETENSOR_EXACT_MODEL_V1`, and `PULSETENSOR_EXACT_OUTPUT_V1`, respectively.
The Solidity settlement recomputes `outputCommitment`; the future guest must recompute all three commitments
from its witness and reject any mismatch with the public task values.

The model commitment identifies the model's exact semantic bytes. An IPFS CID is optional distribution
metadata and is not used as the semantic identity because different chunking/encodings can produce different
CIDs for equivalent content.

## Canonical public values

The settlement contract reconstructs the journal bytes. A caller can never supply an authoritative journal
digest.

```solidity
struct ExactInferencePublicValuesV1 {
    bytes32 domain;
    uint32 version;
    uint256 chainId;
    address settlement;
    uint256 taskId;
    bytes32 taskSpecHash;
    uint16 netuid;
    uint16 mechid;
    uint64 verifierConfigId;
    bytes32 relationId;
    bytes32 requestNullifier;
    bytes32 inputCommitment;
    bytes32 modelCommitment;
    uint16 protocolFeeBps;
    address treasury;
    uint8 classIndex;
    int64[4] scores;
    bytes32 outputCommitment;
    address provider;
    address beneficiary;
}
```

The bytes are `abi.encode(journal)` rather than packed encoding. The guest and Solidity must share a committed
golden byte vector. Binding the chain, settlement, task, immutable task specification, configuration, relation,
request nullifier, input, model, output, provider, and beneficiary prevents cross-chain, cross-contract,
cross-task, model/input/output-substitution, and copied-proof payout attacks.

The domain constants are exactly:

```solidity
PUBLIC_VALUES_DOMAIN = keccak256("PULSETENSOR_EXACT_PUBLIC_VALUES_V1");
REQUEST_NULLIFIER_DOMAIN = keccak256("PULSETENSOR_EXACT_REQUEST_NULLIFIER_V1");
TASK_SPEC_DOMAIN = keccak256("PULSETENSOR_EXACT_TASK_SPEC_V1");
OUTPUT_DOMAIN = keccak256("PULSETENSOR_EXACT_OUTPUT_V1");
```

`requestNullifier` is exactly:

```solidity
keccak256(
    abi.encode(
        REQUEST_NULLIFIER_DOMAIN,
        uint32(1),
        block.chainid,
        address(this),
        requester,
        requesterNonce
    )
)
```

`taskSpecHash` is exactly the following ordered, typed tuple. There are no optional or caller-appended fields:

```solidity
keccak256(
    abi.encode(
        TASK_SPEC_DOMAIN,                 // bytes32
        uint32(1),
        block.chainid,                    // uint256
        address(this),                    // address
        taskId,                           // uint256
        requester,                        // address
        refundTo,                         // address
        escrowWei,                        // uint256
        createdAtBlock,                   // uint64
        deadlineBlock,                    // uint64
        netuid,                           // uint16
        mechid,                           // uint16
        verifierConfigId,                 // uint64
        adapter,                          // address
        adapterRuntimeCodeHash,           // bytes32
        verifierRuntimeCodeHash,          // bytes32
        programId,                        // bytes32
        relationId,                       // bytes32
        proofSystemId,                    // bytes32
        proofSelector,                    // bytes4
        protocolFeeBps,                   // uint16
        treasury,                         // address
        requestNullifier,                 // bytes32
        inputCommitment,                  // bytes32
        modelCommitment                   // bytes32
    )
)
```

The committed Solidity golden vector in `testCanonicalPublicValuesGoldenVector` is 736 bytes and has SHA-256
`d6bf3e24201d46ca655687be218f9186309e1138e0866073e8fd6fabaaf02067`. A future Rust guest fixture must
produce those exact bytes before the cross-language gate is considered complete.

## Configuration lifecycle

```text
MISSING
  -- delayed add --> ACTIVE
ACTIVE
  -- delayed deprecate --> DEPRECATED (existing tasks may settle)
ACTIVE or DEPRECATED
  -- immediate revoke --> REVOKED (existing tasks may only refund)
```

Safety rules:

1. Only the current `CORE.subnetGovernance(netuid)` may queue, cancel, execute, deprecate, or revoke.
2. Queued actions are bound to both the governance address and Core governance generation that queued them.
   Rotation—including an A→B→A round trip—invalidates the old action; current governance may cancel and requeue.
3. Addition and deprecation have a minimum delay and bounded execution window; executing a queued deprecation
   stops new tasks immediately at that execution block.
4. Verification and economic identity fields never mutate after creation; the `stopNewTasksAtBlock` and
   `revoked` lifecycle fields only move one way.
5. Revocation is one-way and may not be queued as an action that settles or redirects a task.
6. New tasks require an active, non-revoked adapter and matching adapter/base-verifier runtime hashes.
7. Existing tasks retain their configuration ID and fee snapshot.

## Task state machine

```text
NONE
  -- create + escrow --> OPEN
OPEN
  -- valid proof at or before deadline --> PROOF_SETTLED
  -- block after deadline             --> EXPIRED_REFUND
  -- verifier permanently revoked     --> VERIFIER_REVOKED_REFUND
  -- adapter/base verifier unavailable --> VERIFIER_UNAVAILABLE_REFUND
```

Every terminal state is final. A task can create exactly one set of liabilities.

Proof submission order is fail closed:

1. require `OPEN`, deadline not passed, configuration not revoked, and exact adapter/base-verifier runtime hashes;
2. reconstruct the output commitment and canonical public values;
3. call the snapshotted adapter and require it not to revert;
4. mark the task `PROOF_SETTLED`;
5. reduce open escrow;
6. credit beneficiary and treasury pull balances.

The success fee is PLS-native and based only on realized settlement:

```text
fee = floor(escrowWei * protocolFeeBps / 10_000)
providerShare = escrowWei - fee
```

`protocolFeeBps` is capped at 3,000 (30%) and snapshotted in the immutable configuration/task. Expiry,
revocation, and unavailable-verifier refunds return the full escrow and create no treasury fee. This can fund
maintenance from use, but it does not promise a salary, purchasing power, or a PLS/USD value.

## Accounting proof obligations

Define:

```text
O = totalOpenEscrow
C = totalClaimable
B = address(settlement).balance
L = O + C
```

Required transition equations:

```text
create(v):           O' = O + v, C' = C
validProof(v):       O' = O - v, C' = C + v
refund(v):           O' = O - v, C' = C + v
claim(a):            O' = O,     C' = C - a, B' = B - a
```

Therefore every supported transition preserves solvency `B >= L`. Equality is not claimed because forced PLS
transfers can create unaccounted surplus. No administrative sweep is authorized by V1.

Additional invariants:

- `OPEN(task) => escrow(task) > 0`;
- terminal task states are mutually exclusive and irreversible;
- each request nullifier is used at most once in this settlement;
- a proof cannot increase aggregate liabilities;
- a refund cannot credit anyone except the snapshotted `refundTo`;
- a success fee cannot exceed escrow and cannot be charged on refund;
- a claim reduces the caller's balance before the external transfer;
- pausing a subnet may stop new tasks but cannot block proof settlement, refunds, or claims.

## Release obligations

The bounded YAML model is deliberately one configuration plus one task. The current dependency-free runner
implements that transition system in Python and binds the descriptive YAML by exact SHA-256; it does not
interpret YAML expressions. A built-in invariant-mutation negative control must prove that YAML drift is
rejected. The runner checks per-task transition equations exhaustively over its disclosed boundary set, but it
cannot by itself establish aggregate multi-task accounting.
The aggregate `totalOpenEscrow`/`totalClaimable` obligation is covered in the current merge scope by the
multi-actor Foundry invariant handler. A later two-task executable refinement model remains an additional objective.

The V1 Solidity merge evidence must include, and this repository now contains:

- state-machine unit and boundary tests using a mock adapter located only under `test/`;
- mutation tests for chain, settlement, task, config, relation, nullifier, input, model, output, provider,
  beneficiary, proof selector, program ID, and proof bytes;
- malicious/reentrant adapter tests;
- proxy-upgrade and storage-controlled-adapter counterexamples with unchanged adapter code hash;
- invariant campaigns for terminal exclusivity, no double credit, and escrow solvency;
- exact adapter/base runtime code-hash tests and unavailable-verifier refunds;
- delayed addition/deprecation, governance-rotation, expiry, and one-way revocation tests;
- a committed Solidity public-values vector.

The requirements traceability gate names the concrete unit and invariant functions for these obligations. CI must
re-execute them on the reviewed commit; their presence is not authorization for a value-bearing deployment.

Before any value-bearing deployment, additionally require:

- deterministic guest build with source/toolchain/container/ELF hashes and derived program ID;
- differential guest/reference tests for the bounded relation;
- Rust/Solidity ABI golden-vector equality;
- genuine pinned Groth16 receipt with development mode disabled;
- genuine-verifier rejection after mutating every cryptographic proof and journal field;
- deployment and genuine verification on PulseChain testnet chain ID 943;
- recorded verifier deployment bytecode/runtime hash and measured gas against live block limits;
- an independent audit and a bounded-value testnet/mainnet canary.

## Research basis

- SafetyNets demonstrates verifiable arithmetic inference for neural networks:
  <https://arxiv.org/abs/1706.10268>
- Artemis studies efficient consistency between committed ML models/data and proof witnesses:
  <https://arxiv.org/abs/2409.12055>
- zkLLM develops specialized proof machinery for much larger language-model computations:
  <https://arxiv.org/abs/2404.16109>
- RISC Zero verifier ABI and integration model:
  <https://dev.risczero.com/api/blockchain-integration/contracts/verifier>
- Pinned RISC Zero 3.0 interface used for adapter design:
  <https://github.com/risc0/risc0-ethereum/blob/dc111ded68ee013f7d44dba138d02561ee33bbf8/contracts/src/IRiscZeroVerifier.sol>
- Pinned concrete RISC Zero Groth16 verifier defining `VERSION`, `SELECTOR`, and the eight-word seal:
  <https://github.com/risc0/risc0-ethereum/blob/dc111ded68ee013f7d44dba138d02561ee33bbf8/contracts/src/groth16/RiscZeroGroth16Verifier.sol>
- SP1's compatible public-values/program-key interface, reserved for a later adapter:
  <https://github.com/succinctlabs/sp1-contracts/blob/d3629729c3216eb51bd4859d027a8eb729399fa4/contracts/src/ISP1Verifier.sol>

These works motivate the staged design; they do not prove PulseTensor's implementation. The V1 sequence is
deliberately settlement/journal/versioning first, small deterministic tensor relation second, and specialized
large-model circuits only after the complete refinement and deployment pipeline is reproducible.

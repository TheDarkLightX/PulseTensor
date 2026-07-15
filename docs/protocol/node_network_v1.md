# Node, Discovery, and Authenticated Transport v1

Status: target design, not implemented by the current repository.

## Current bar and design choice

Bittensor's current architecture keeps the commodity-specific work off-chain, advertises miner endpoints on-chain, and uses signed HTTP identity between miners and validators. Its v11 SDK no longer packages the former Axon, Dendrite, Synapse, and tensor abstractions; each subnet brings its own server, client, and schemas while the SDK supplies endpoint operations and a normative signed-request format. See the current [mining guide](https://www.bittensor.com/docs/guides/mining), [signed-request protocol](https://www.bittensor.com/docs/guides/signed-requests), and [v11 migration guide](https://www.bittensor.com/docs/migration).

PulseTensor should make the same separation explicit, with EVM-native typed authorization and evidence-bearing task schemas. It should not build a custom blockchain gossip layer for version 1.

## Four planes

1. **Control plane:** identities, controller/operator delegation, descriptor commitments, task funding, bonds, decisions, nullifiers, and claims.
2. **Data plane:** authenticated requests, work execution, evaluator traffic, and content transfer.
3. **Evidence plane:** task specs, receipts, proofs, evaluation records, challenge transcripts, availability records, and TCB manifests.
4. **Observation plane:** block-pinned indexing and query views. Observation has no settlement authority.

The control plane is on-chain. Large data and evidence are content-addressed off-chain. A contract trusts only committed hashes, registered verifiers, and the explicitly declared availability policy.

## Roles

One reference daemon may load multiple role plugins, but production deployments should be able to separate them by process and key:

- requester or optional gateway,
- provider,
- evaluator,
- challenger or watchtower,
- receipt batcher or relayer,
- evidence replica, and
- indexer or observer.

A validator is not a mandatory traffic gateway. A requester can contact a provider directly or use any gateway. A gateway cannot change a task, receipt, outcome, or claim.

## Controller and operator keys

Each participant has:

- an offline or rarely used controller/funds key,
- a constrained operational hot key,
- an independently chosen claim address, and
- optional process-specific keys below the operator, if a registered policy supports them.

The controller delegates a role bitmap, subnet/mechanism scope, sequence, activation block, and expiry to the operator. The operator signs node descriptors and protocol messages. It cannot withdraw controller stake, change claim addresses, or expand its own role.

Revocation blocks new funding, assignment, and task messages from that operator. It does not invalidate historical task or receipt signatures, prevent a matured refund, or rewrite the operator snapshotted at assignment. Rotation uses a strictly increasing sequence and cannot reuse a prior sequence.

The current `PulseTensorCore.canValidate` binds stake and validation to one address. A target authority interface must separate controller capital from constrained hot operations before public node software is launched.

## NodeDescriptorV1

The normative schema is [`node_descriptor_v1.schema.json`](../../specs/protocol/node_descriptor_v1.schema.json). It binds:

```text
descriptorVersion
chainId
nodeRegistry
netuid
mechid
controller
operator
roleBitmap
sequence
validFromBlock
validUntilBlock
endpointSet[]
tlsCertificateHash
capabilityManifestHash
supportedTaskVersions[]
supportedReceiptVersions[]
supportedAssuranceModes[]
acceptedAssetSetHash
availabilityModes[]
maxRequestBytes
maxConcurrentTasks
softwareArtifactHash
operatorSignature
```

The registry stores the descriptor digest, sequence, activation/expiry, controller/operator binding, and a bounded content locator. The full descriptor can be fetched from any mirror. A mirror is not trusted: the fetched bytes must hash to the on-chain digest.

### Discovery acceptance

A client accepts a descriptor only if:

1. its bytes match the on-chain digest at a pinned block,
2. its sequence equals the active registry sequence,
3. the currently authorized operator signed it,
4. chain, registry, subnet, and mechanism match the intended task,
5. the pinned block is inside its validity interval,
6. requested task, receipt, assurance, availability, and asset capabilities are advertised,
7. its limits cover the proposed request, and
8. an authenticated liveness challenge succeeds.

Clients must pin multi-read state to one block hash. Two independent RPC observations should agree on the checkpoint before committee selection or high-value assignment. RPC agreement is an operational guard, not chain consensus.

## `ptauth/1`

`ptauth/1` is a signed EIP-712 envelope over the exact HTTP request. The normative schema is [`ptauth_envelope_v1.schema.json`](../../specs/protocol/ptauth_envelope_v1.schema.json).

It binds:

```text
protocolVersion
chainId
nodeRegistry
netuid
mechid
senderOperator
receiverOperator
messageType
methodHash
requestTargetHash
rawBodyHash
taskId
attemptId
nonce
referenceBlockNumber
referenceBlockHash
expiresAtBlock
```

The receiver is mandatory. The method and request target are hashed exactly as transmitted. The raw body is hashed before parsing or re-encoding. The signature algorithm is fixed to EIP-712/secp256k1 in version 1; no “try another algorithm” fallback is allowed.

The replay key is:

```text
(chainId, nodeRegistry, senderOperator, receiverOperator, nonce)
```

It is accepted at most once, and replay state is shared across every server process behind the same operator. Retries use a fresh nonce.

### Verification order

1. Enforce transport byte and header limits.
2. Parse only the fixed envelope shape.
3. Reject unsupported protocol version, message type, or signature algorithm.
4. Verify receiver, chain, registry, subnet, and mechanism domain.
5. Recompute method, raw target, and raw-body hashes.
6. Verify reference-block finality policy and block-hash match.
7. Verify the block-based expiry window.
8. Resolve the sender's operator delegation at the pinned checkpoint.
9. Verify the EIP-712 signature.
10. Atomically insert the replay key if absent.
11. Enforce role, task, rate, concurrency, and compute policy.
12. Parse and execute the task-specific body.

Signature verification precedes replay-store insertion so unauthenticated garbage cannot fill the replay database. Expensive task execution occurs only after authentication, replay, size, and policy checks.

HTTPS protects transport confidentiality and integrity in transit. The application signature establishes PulseTensor protocol identity and task binding. TLS is not settlement authority, and a certificate hash alone is not a work receipt.

## Message types and routes

Version 1 message types are closed and enumerated:

```text
QUOTE_REQUEST
QUOTE_RESPONSE
TASK_ACCEPT
TASK_EXECUTE
TASK_STATUS
OBJECT_FETCH
EVALUATION_COMMIT
EVALUATION_REVEAL
CHALLENGE_SUBMIT
```

A reference HTTP API may expose:

```text
GET  /.well-known/pulsetensor/v1/node
POST /v1/quotes
POST /v1/tasks/accept
POST /v1/tasks/execute
GET  /v1/tasks/{taskId}/status
GET  /v1/objects/{digest}
POST /v1/evaluations/commit
POST /v1/evaluations/reveal
POST /v1/challenges
```

Route names are not consensus. The signed `messageType`, exact target hash, raw body hash, and task schemas are normative. Implementations may map those objects to another transport only in a later protocol version with new golden vectors.

## Evidence availability

Every content object has a digest, byte length, chunking rule, retention deadline, and availability mode. Target v1 permits:

- `INLINE_PUBLIC`,
- `CONTENT_ADDRESSED_PUBLIC`,
- `REQUESTER_REPRODUCIBLE`, and
- `PROOF_ONLY`.

Large public evidence should use multiple content-addressed replicas. Private inputs remain with the requester unless the assurance mode explicitly requires another custody model. Version 1 defers threshold-encrypted evaluator custody because it adds a materially larger cryptographic and operational TCB.

A provider cannot be paid under an optimistic or evidence-dependent mode if the required dispute material was unavailable during its challenge window. Availability challenges and their response byte limits must be specified before the task is assigned.

## PulseGraph

PulseGraph is PulseTensor's metagraph-equivalent observation view. At a pinned block it reports:

```text
checkpointBlock
checkpointHash
subnets
mechanismVersions
nodes
controllerOperatorBindings
roles
bondsByAsset
descriptorDigests
capabilities
activeTasks
settledOutcomes
qualityCounters
feeFlowsByAsset
challengeAndDefaultCounters
```

Every field is reconstructible from chain state, events, and content-addressed manifests. An indexer may cache and aggregate but cannot authorize a node, choose a committee, resolve a task, or create a claim. A node must be able to recover canonical state from the chain without the project operator's hosted API.

## Privacy boundary

Operational separation protects keys and reduces unnecessary metadata sharing; it does not create on-chain anonymity. Descriptors, task assignments, claims, timing, and funding graphs are public or inferable. Private inputs should be committed rather than published when the assurance mode permits it, and evidence endpoints should disclose only what their availability policy requires.

Do not promise unlinkability. Keep entity-controlled controller, operator, claim, governance, deployer, and personal wallets separate, while preserving lawful internal ownership, approval, tax, and source-of-funds records.

## Golden-vector and interoperability gate

Before value-bearing deployment:

1. Rust and TypeScript implementations produce identical descriptor, task, receipt, evaluation, and `ptauth/1` typed hashes.
2. Every golden signature verifies in both implementations.
3. Changing any domain, receiver, sender, route, raw body byte, task, attempt, checkpoint, nonce, or expiry invalidates the signature.
4. A repeated replay key fails across multiple server processes.
5. Descriptor rotation, expiry, revocation, stale indexers, RPC disagreement, and endpoint failover are tested.
6. Two independent node implementations complete quote, assignment, execution, evaluation, challenge, settlement, refund, and claim.
7. Churn, delayed messages, duplicates, reordering, partitions, and indexer restart have deterministic recovery rules.

Passing these tests establishes interoperability for the tested versions. It does not establish Internet availability, independent identities, or correct AI output.

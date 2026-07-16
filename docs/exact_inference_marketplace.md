# PulseTensor Exact-Inference Marketplace

## Status

The marketplace interface and exact escrow are prelaunch infrastructure. They are suitable for local rehearsal and
PulseChain testnet canaries after a real guest and verifier deployment exist. They are not an endorsed mainnet
deployment today. A passing contract/frontend test suite does not replace a genuine proof receipt, independent audit,
or live-chain evidence.

## What the Marketplace Is

The exact lane is a PLS-native proof marketplace:

1. A requester chooses a reviewed verifier configuration and escrows a PLS reward.
2. An off-chain provider obtains the public task description, performs the exact computation, and generates the
   configured proof.
3. Anyone may relay that proof. The settlement contract verifies the pinned program/image commitment and canonical
   public-value journal.
4. Success credits the beneficiary and the snapshotted protocol treasury through pull balances. Failure to produce a
   proof charges no protocol fee. Expiry, verifier revocation, or verifier-code unavailability makes the full escrow
   refundable.

There is no USD salary promise and no need to predict PLS/USD. Let task reward be `R` PLS and the reviewed protocol fee
be `f` basis points, capped on-chain at 3,000. A successful task credits:

```text
protocol_fee = floor(R × f / 10,000)
provider_credit = R - protocol_fee
```

The creator/operator is funded only by actual successful economic activity through the treasury share. Requesters set
rewards in the asset they possess; providers decide whether a task is worth accepting at the current PLS purchasing
power and proving cost. This is variable DeFi revenue, not a fixed TradFi payroll abstraction. A sustainable operator
still needs observable volume, fee sensitivity, proving cost, and treasury runway metrics before selecting a fee.

## Why ZK Instead of Three Verifier Keys

V1 does not use a three-verifier signature quorum, replay-based evaluator vote, or immutable private signing key. The
authority is a public program/image commitment plus runtime-code-pinned verifier configuration. A valid proof means only
that the admitted deterministic relation ran with the exact public journal. It does not prove that an arbitrary model
answer was truthful, useful, unbiased, or subjectively high quality.

Verifier configurations are append-only. Governance may add a new reviewed configuration after delay, deprecate it for
new tasks, or permanently revoke it so open tasks become refundable. Existing configuration meaning and fee routing
cannot be rewritten. The public program commitment is intentionally stable for a configuration; no private authority
key is treated as immutable.

## Frontend Trust States

The static frontend separates three claims:

- **Observation:** a user-selected public RPC reports marketplace and task state. This is convenient, not signing
  authority.
- **Identity:** the raw manifest bytes match a user/community-reviewed SHA-256 and the observed chain matches its chain
  ID, deployment block/hash and confirmation floor, Core and exact-settlement runtime hashes, immutable Core binding,
  and every manifest-allowed stored configuration commitment, selector, proof system, fee, and treasury. When verifier
  code is live, its adapter/base address, version, selector, seal size, and runtime hashes are checked too. Missing or
  changed verifier code is classified as unavailable readiness, not a settlement-identity failure, so it cannot disable
  the refund path intended for that outage.
- **Transaction preflight:** immediately before every exact write, the frontend checks the current reviewed settlement
  runtime, immutable Core binding, wallet chain and account through the injected provider, then simulates, broadcasts,
  and observes confirmation there. Creation additionally checks current Core/config admission; proof settlement checks
  only the task's reviewed config and verifier availability. Claim/refund intentionally omit archive, live-Core, and
  unrelated-config reads, so a pruned or censored RPC cannot make contract recovery depend on components the recovery
  method itself does not use.

New task admission additionally requires an active config, available pinned code, configured subnet governance, and an
unpaused subnet. Proof settlement additionally requires an open task and a verifier configuration that can still settle
it. Refund and claim paths require deployment identity but deliberately do not require new-task admission; otherwise a
verifier outage could trap recovery behind the failed component.

Digest equality proves that fetched bytes match the chosen digest. It does not establish who reviewed the digest or
whether their judgment was sound. Publish the digest through multiple independently controlled channels and keep the
manifest evidence reviewable.

## IPFS and Provider Architecture

IPFS is useful for:

- immutable static frontend releases;
- optional public model/input/result artifacts;
- guest source, audit reports, build recipes, and proof receipts;
- an untrusted discovery index whose entries are reconciled with on-chain tasks.

IPFS is not a private backend, durable pinning guarantee, model runner, job queue, RPC endpoint, or ZK prover. The UI's
artifact helper computes a raw CIDv1 and SHA-256 over exact UTF-8 bytes for distribution integrity. It does not pretend
that an arbitrary file hash is the guest-defined semantic `inputCommitment` or `modelCommitment`. Those commitments must
come from the reviewed canonical encoder for the admitted relation.

After downloading the exact bytes from the helper, a local Kubo node can publish the same raw block (CLI spelling may
vary by Kubo release):

```bash
ipfs block put --format=raw --mhtype=sha2-256 pulsetensor-task-artifact.bin
```

Compare the returned CID with the UI before announcing or indexing it. The current prelaunch UI deliberately has no
trusted provider directory or task-to-artifact resolver. The next protocol milestone is a versioned, untrusted discovery
document whose entries bind `(chainId, settlement, taskId, artifact CID, media type, encoder version)` and are reconciled
against on-chain task commitments; its availability must never control settlement or refund rights.

Anyone can build a ChatGPT-style or other provider frontend around the public contract and artifact formats. The safe
boundary is:

```text
public static UI / task watcher
            |
            v
operator-controlled provider + model/API credentials
            |
            v
deterministic relation adapter -> prover -> public ZK seal
            |
            v
PulseTensor exact settlement
```

OpenAI/model-provider keys, authenticated RPC URLs, pinning tokens, witnesses, and wallet secrets must stay in the
operator-controlled process. A browser/IPFS bundle exposes every compiled variable. Public gateways also learn request
metadata, and direct IPFS is not an anonymity system.

ZK hides the witness only to the extent guaranteed by the chosen proof construction and public journal. It does not hide
the requester's wallet, refund destination, provider/beneficiary, treasury, reward, commitments, timing, funding source,
or transfers. A dedicated hardware/KMS-controlled deployment and operations identity reduces accidental key reuse; it
does not guarantee unlinkability from funding flows or network metadata.

## Candidate Manifest Workflow

1. Deploy and review the exact settlement, direct RISC Zero verifier, and adapter on PulseChain testnet using a hardware
   wallet, encrypted Foundry keystore, or KMS signer. Do not place a raw private key in a CLI argument, repository,
   `.env`, shell history, or frontend variable.
2. Execute the delayed verifier-configuration admission through subnet governance.
3. Record a finalized deployment block/hash and a conservative confirmation floor.
4. Bind runtime code hashes, the single reviewed V1 verifier config, public program/relation/proof-system identities,
   selector, RISC Zero version hash, exact seal byte count, fee, and treasury in the strict manifest schema. Publish a
   credential-free HTTPS or IPFS URI plus SHA-256 for each guest source, guest build recipe, genuine proof receipt, audit
   report, and PulseChain testnet receipt; no one evidence bundle is implicitly trusted for multiple configurations.
5. Canonicalize a candidate locally:

   ```bash
   INPUT=./candidate.json \
   OUTPUT=./exact-manifest.canonical.json \
   RECEIPT=./exact-manifest.receipt.json \
   make ui-exact-manifest
   ```

6. Independently reproduce the code/evidence checks and compare the canonical SHA-256. Only then publish the manifest
   and digest. The preparation tool labels its receipt `candidate-not-endorsement` by design.
7. Build with `VITE_EXACT_MANIFEST_URL` and `VITE_EXACT_MANIFEST_SHA256`, run `make verify-ui`, produce `make ui-release`,
   and arrange multiple independent IPFS pins/mirrors.
8. Exercise create, real proof settlement, all three refund paths, and pull claims on testnet. Preserve receipts. Do not
   promote to mainnet until the blockers below are closed.

## Mainnet Blockers

- Freeze and review a real deterministic inference guest and its canonical semantic input/model encoders.
- Reproduce the guest build and publish source, toolchain/container, ELF/image, and recipe hashes.
- Generate and independently validate a genuine receipt through the admitted direct verifier.
- Complete an external security review of contract, adapter, guest, manifest workflow, and operator assumptions.
- Run sustained PulseChain testnet canaries, including verifier disappearance/replacement, revocation, expiry, replay,
  malformed journal, malformed seal, fee rounding, and claim-recipient failure cases.
- Decide initial fee and treasury policy from measured PLS task volume/proving cost, with an explicit runway and
  governance disclosure. No token issuance is required for V1.
- Publish signed/reproducible frontend release evidence and maintain independent mirrors/pins.

The current exact contract has strong executable assurance evidence, but PulseTensor still does not claim a
machine-checked refinement proof from specification to deployed EVM bytecode. See `docs/assurance_scope.md` and
`docs/zk_exact_inference_v1.md` for the exact boundary.

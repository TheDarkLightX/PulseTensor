# Privacy-Aware PulseTensor Launch

PulseChain is a public ledger. A deployment transaction always exposes its sender, time, nonce, gas use, and contract addresses. PulseTensor can reduce unnecessary linkage and local secret exposure, but it cannot make the launch anonymous.

## Wallet separation

Use separate addresses and signing devices for:

- the one-time contract deployer,
- subnet ownership before governance activation,
- governance proposers and Safe signers,
- treasury and fee collection,
- vesting or compensation,
- testnet operations, and
- personal holdings.

Fund the deployer through a lawful entity-controlled account. Do not fund it from a publicly known personal wallet. Keep the internal beneficial-owner, tax-basis, and transaction records required by counsel and accountants.

## Signer policy

The canonical deployment script does not accept raw private keys, mnemonics, or plaintext passwords. Prefer, in order:

1. hardware signing with a dedicated Ledger or Trezor,
2. a narrowly permissioned AWS KMS key,
3. an encrypted Foundry keystore whose password is entered interactively,
4. a password file readable only by its owner, or
5. Foundry's interactive key prompt for a one-time deployment.

Never paste a secret into a shell command, `.env` file, issue, CI variable, chat, or deployment receipt. A password-file path may be visible to local processes, so keep the file outside the repository and at mode `600` or stricter.

The canonical wrapper always broadcasts. It deliberately has no `--no-broadcast` mode because `forge create` simulation output is not a deployment address or an adequate launch rehearsal. Use a local Anvil chain or PulseChain testnet for rehearsal instead.

## Testnet rehearsal

Use a dedicated encrypted keystore and an owner-only password file:

```bash
export RPC_URL=https://rpc.v4.testnet.pulsechain.com
bash scripts/deploy_pulsetensor.sh \
  --expected-chain-id 943 \
  --sender 0xYOUR_DEDICATED_DEPLOYER \
  --keystore /secure/pulsetensor-deployer \
  --password-file /secure/pulsetensor-deployer.password \
  --confirmations 12 \
  --out-dir /secure/pulsetensor-receipts
```

The RPC is placed in `ETH_RPC_URL` for child processes instead of their argument lists. Same-user processes may still inspect another process's environment on many systems. The wrapper disables shell xtrace and redacts HTTP(S) endpoints from command failures, but operating-system isolation remains necessary.

Run `make verify-deploy-rehearsal` before a real launch. That gate starts a clean Anvil chain, imports a published test key into an encrypted keystore, exercises the canonical two-transaction wrapper, and independently reverifies the resulting receipt.

## Network privacy

A public RPC operator can associate IP addresses, timing, queries, and submitted transactions. For a serious launch, use a self-hosted PulseChain node or a contractually trusted RPC through an appropriate network-privacy layer. Do not claim this prevents correlation by peers, RPC providers, exchanges, bridges, or legal process.

## Authority handoff

Contract deployment and protocol control should be separate events:

1. Rehearse the exact bytecode and receipt flow on testnet.
2. Deploy from a one-time entity wallet with only the PLS needed for gas.
3. Create the first subnet with a separate operations wallet.
4. Configure a tested Safe-style governance contract and its timelock.
5. Confirm every role and queue state from two independent RPCs.
6. Remove operational reliance on the deployer and archive its records.

PulseTensor's current core has no global deployer-admin role. Subnet ownership and governance are established later through explicit calls, which makes wallet separation practical.

## Receipt interpretation

Each deployment atomically publishes one uniquely named v4 receipt. It records:

- chain ID, deployer, a Pulse-specific network anchor when applicable, and a unique run ID;
- each public transaction hash, sender-derived contract address, explicit nonce, gas estimate, gas limit, gas used, effective gas price, block number, and block hash;
- latest and pending nonce state before and after the two broadcasts;
- clean-build creation, creation-input, runtime, and artifact hashes;
- source commit, dirty/clean state, exact Forge/Cast/Solc binary hashes, compiler metadata version, optimizer runs, and deployment profile;
- the requested confirmation depth and publication block; and
- the testnet checkpoint digest used for a mainnet deployment, when applicable.

The Settlement runtime includes the Core address as an immutable value. The wrapper reads Solidity's `immutableReferences` from the clean artifact, links the deployed Core address into every declared offset, and requires the resulting runtime bytecode to equal the on-chain bytes exactly. It also checks `CORE()` independently. The Core runtime is likewise compared byte-for-byte.

Both deployment transactions are checked for successful status, sender, transaction hash, contract address, chain ID, exact creation input, explicit consecutive deployer nonces, gas limit, and capped effective gas price. The wrapper refuses to start when `latest` and `pending` nonces differ, then repeats that equality before each broadcast and after each receipt. Immediately before signing, it rechecks the source/toolchain/artifact state and the creation-input hash, then uses `cast send --create` on those already-inspected bytes; no compiler or artifact lookup occurs inside the send. It waits for the requested confirmations and repeats the receipt, block-hash, runtime, binding, chain-ID, and nonce checks.

On chain 369, the wrapper additionally extracts the authorized commit with `git archive` into an owner-only temporary directory and performs a production-only isolated rebuild before gas estimation, journal creation, or signing. The rebuilt Core and Settlement creation/runtime bytecode, compiler settings, and normalized immutable-reference locations must equal the already-hashed live artifacts. This closes the gap where a transient worktree edit could influence the preflight build and then be restored before the clean-tree check.

`scripts/verify_deployment_receipt.py` does not trust hashes merely because the receipt contains them. It verifies the locked binaries, makes an isolated clean rebuild from the checked-out source commit, recomputes creation and immutable-linked runtime bytecode, checks the recorded artifact digests, and compares those results with both public transactions and live code:

```bash
export ETH_RPC_URL=https://rpc.v4.testnet.pulsechain.com
python3 scripts/verify_deployment_receipt.py /secure/pulsetensor-receipts/RECEIPT.json \
  --min-confirmations 12 --require-clean-source
```

For chain 369, those release requirements are automatic rather than optional. The verifier requires a clean checked-out source tree, at least 12 recorded and currently observed confirmations, the pinned mainnet anchor, and the exact chain-943 checkpoint whose digest and anchor are recorded in the mainnet receipt. Supply both independent RPC contexts and the checkpoint file explicitly:

```bash
export ETH_RPC_URL=https://YOUR_TRUSTED_PULSECHAIN_RPC
export RELEASE_CHECKPOINT_RPC_URL=https://YOUR_INDEPENDENT_TESTNET_RPC
python3 scripts/verify_deployment_receipt.py \
  /secure/pulsetensor-receipts/MAINNET_RECEIPT.json \
  --release-checkpoint /secure/pulsetensor-receipts/TESTNET_RECEIPT.json
```

The verifier rejects duplicate JSON keys and unrecognized receipt fields. It snapshots the supplied checkpoint bytes before recursively rebuilding and live-reverifying that testnet receipt, so a path change cannot silently swap the evidence during the check.

Receipts have unique names and are fsynced before an atomic, no-overwrite publish. A separate append-only JSONL partial journal is created before the first transaction. Before each send it records the explicit nonce, expected CREATE address, creation-input hash, gas limit, and fee cap. `cast send --async` records the returned transaction hash before waiting for its receipt. If a response times out after submission, or the second deployment or a later check fails, preserve the journal and inspect the expected address, code, transaction history, and latest and pending nonces; do not rerun the wrapper blindly.

The receipt deliberately excludes signer class, source branch, RPC URLs, password-file path, keystore path, hardware derivation details, and all signing secrets.

## Mainnet release guard

Chain 369 refuses to broadcast unless all of these hold:

- the worktree is clean, including untracked files;
- `--source-commit` is a full hash equal to `git HEAD`;
- `--profile-id pulsetensor-size-safe-v1` is explicit, with pinned Forge/Cast/Solidity binaries, Solidity 0.8.36, via-IR/EVM settings, and optimizer runs verified from fresh artifacts;
- an isolated production rebuild extracted from the authorized commit matches the prehashed creation/runtime bytecode, compiler settings, and immutable-reference locations before any journal or transaction is created;
- `--release-checkpoint` is a verified v4 receipt from PulseChain testnet v4 (chain 943) for that same clean commit, creation/runtime bytecode, and exact toolchain;
- `RELEASE_CHECKPOINT_RPC_URL` is distinct from the mainnet RPC and live-reverifies the owner-read-only snapshot used by the gate, its chain ID, and PulseChain testnet block 16,492,700;
- the mainnet RPC must return the expected PulseChain block-17,233,000 anchor before any signing occurs;
- `--max-fee-per-gas-wei` caps both sends, while preflight estimates both deployments, adds a 20% per-transaction gas margin, and requires enough balance for the maximum combined cost; and
- at least 12 confirmations are requested.

After completing and independently checking testnet, the corresponding mainnet form is:

```bash
export RPC_URL=https://YOUR_TRUSTED_PULSECHAIN_RPC
export RELEASE_CHECKPOINT_RPC_URL=https://rpc.v4.testnet.pulsechain.com
bash scripts/deploy_pulsetensor.sh \
  --expected-chain-id 369 \
  --confirm-mainnet \
  --source-commit "$(git rev-parse HEAD)" \
  --profile-id pulsetensor-size-safe-v1 \
  --release-checkpoint /secure/pulsetensor-receipts/TESTNET_RECEIPT.json \
  --max-fee-per-gas-wei YOUR_REVIEWED_WEI_CAP \
  --confirmations 12 \
  --sender 0xYOUR_DEDICATED_DEPLOYER \
  --ledger \
  --out-dir /secure/pulsetensor-receipts
```

The Pulse-specific anchor prevents a normal local Anvil chain that merely claims chain ID 943 or 369 from qualifying. It does not make one RPC a consensus proof: a malicious provider can equivocate consistently. The configured confirmation count is also a depth heuristic, not a mathematical finality proof. Compare the checkpoint and final deployment through independently operated nodes before authorizing value. The guard is not a substitute for contract audit, governance review, explorer publication, incident rehearsal, or legal and operational launch approval. Hardware-wallet and KMS paths also require device- and policy-specific rehearsal; the automated gate exercises the encrypted-keystore path.

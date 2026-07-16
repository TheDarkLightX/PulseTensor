# Deployment and Signer Safety

PulseTensor deployment is designed so a production private key or seed phrase never has to appear in a shell argument or environment variable. The deployment script requires an explicit signer and supports encrypted Foundry accounts/keystores, Ledger, Trezor, AWS KMS, and Foundry's hidden interactive prompt.

## Prepare Before Broadcasting

1. Run `make verify-release` from the exact clean revision to be deployed.
2. Confirm the live RPC chain ID independently and pass it with `--expected-chain-id`. The script refuses a mismatch (PulseChain mainnet is `369`; testnet v4 is `943`).
3. Use a dedicated deployment identity. Hardware/KMS custody protects the signing key; it does **not** hide the deployer address or transaction graph from the public chain.
4. Fund only the dedicated identity needed for deployment and assume its funding source may be linkable on-chain. Do not reuse a personal, treasury, validator, or governance signer merely for convenience.
5. Rehearse the exact revision on an isolated local chain and PulseChain testnet, then compare the build revision and constructor arguments before broadcasting.

The output receipt names the public deployer, contract addresses, and transaction hashes. Do not treat that receipt—or a deployment transaction—as anonymous. PulseTensor cannot guarantee unlinkability at the protocol layer. Deployment is two transactions: after the first succeeds, the script persists `pulsetensor_deploy_receipt.partial.json` and refuses to overwrite it on retry. It also refuses to overwrite a completed receipt; choose a new output directory for every production deployment. If the second transaction or output validation fails, preserve the partial receipt, inspect the public transaction, and decide explicitly whether to resume with a reviewed recovery procedure or start from a new deployment identity.

> **Pre-release limitation:** this script protects signer material and confirms the live chain ID, but it does not yet bind the broadcast bytecode and transaction hashes to `runs/assurance/evidence.json`. Do not treat it as mainnet launch certification until that evidence/runtime attestation is implemented and independently reviewed.

## Protected Signer Examples

Create/import a Foundry account using its hidden prompts:

```bash
cast wallet import pulsetensor-deployer --interactive
```

Deploy with that encrypted account and an interactive keystore-password prompt:

```bash
RPC_URL=https://rpc.v4.testnet.pulsechain.com \
bash scripts/deploy_pulsetensor.sh --expected-chain-id 943 --account pulsetensor-deployer
```

The Make target forwards the same explicit arguments when preferred:

```bash
RPC_URL=https://rpc.v4.testnet.pulsechain.com \
make deploy DEPLOY_ARGS="--expected-chain-id 943 --account pulsetensor-deployer"
```

For unattended operation, use a password file that is readable only by its owner. The argument contains the file path, never the password itself:

```bash
chmod 600 "$HOME/.config/pulsetensor/deployer.password"
RPC_URL=https://rpc.v4.testnet.pulsechain.com \
bash scripts/deploy_pulsetensor.sh \
  --expected-chain-id 943 \
  --keystore "$HOME/.foundry/keystores/pulsetensor-deployer" \
  --password-file "$HOME/.config/pulsetensor/deployer.password"
```

Hardware and remote-signing modes:

```bash
RPC_URL=https://rpc.v4.testnet.pulsechain.com \
bash scripts/deploy_pulsetensor.sh --expected-chain-id 943 --ledger --from 0x...

RPC_URL=https://rpc.v4.testnet.pulsechain.com \
bash scripts/deploy_pulsetensor.sh --expected-chain-id 943 --trezor --from 0x...

RPC_URL=https://rpc.v4.testnet.pulsechain.com \
bash scripts/deploy_pulsetensor.sh --expected-chain-id 943 --aws --from 0x...
```

`--derivation-path` is available for Ledger/Trezor selection. AWS KMS credentials and key selection come from the standard AWS SDK configuration; apply least-privilege IAM permissions and require an explicit `--from` address in operator runbooks so the intended public signer is reviewable.

Foundry's hidden private-key prompt is a last-resort hot-key path that avoids argv and environment exposure:

```bash
RPC_URL=https://rpc.v4.testnet.pulsechain.com \
bash scripts/deploy_pulsetensor.sh --expected-chain-id 943 --interactive
```

The script intentionally rejects `--private-key`, `--mnemonic`, `PRIVATE_KEY`, and related raw-secret environment variables for production use.

## Deterministic Local Test Boundary

`PULSETENSOR_LOCAL_TEST_PRIVATE_KEY` exists only so the local Anvil replay can use a public deterministic test account. The deployment script checks both conditions before accepting it:

- the RPC host is loopback (`localhost`, a `127.0.0.0/8` address, or `::1`); and
- the live RPC chain ID is exactly `31337`.

The canonical local E2E run uses the public Anvil test mnemonic and rejects every `LOCAL_E2E_*` mnemonic/private-key override. A developer can deliberately run customized local fixtures only with:

```bash
PULSETENSOR_LOCAL_E2E_NON_ASSURANCE=1 \
LOCAL_E2E_MNEMONIC="a throwaway local-only mnemonic" \
bash scripts/check_local_e2e.sh
```

Never use a funded mnemonic or private key for this flow. Non-assurance artifacts are written to `runs/local_e2e_non_assurance/`, so they cannot replace the canonical `runs/local_e2e/` evidence consumed by `make verify-release`.

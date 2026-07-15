#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY_SCRIPT="${ROOT_DIR}/scripts/deploy_pulsetensor.sh"

forbidden_hits="$(
  rg -n -- '--private-key|--mnemonic|\bPRIVATE_KEY\b|--password([ =]|$)|--no-broadcast' "${DEPLOY_SCRIPT}" || true
)"
if [[ -n "${forbidden_hits}" ]]; then
  echo "Deployment script contains a secret-bearing signer path:" >&2
  echo "${forbidden_hits}" >&2
  exit 1
fi

for required_mode in '--account' '--keystore' '--ledger' '--trezor' '--aws' '--interactive'; do
  if ! rg -q --fixed-strings -- "${required_mode}" "${DEPLOY_SCRIPT}"; then
    echo "Deployment script is missing approved signer mode ${required_mode}" >&2
    exit 1
  fi
done

help_output="$(bash "${DEPLOY_SCRIPT}" --help)"
if [[ "${help_output}" != *"cannot"*"anonymous"* ]]; then
  echo "Deployment help must state the public-chain privacy limit" >&2
  exit 1
fi

set +e
conflict_output="$(
  bash "${DEPLOY_SCRIPT}" \
    --rpc-url http://127.0.0.1:1 \
    --expected-chain-id 943 \
    --sender 0x0000000000000000000000000000000000000001 \
    --ledger --trezor 2>&1
)"
conflict_status=$?
set -e
if [[ "${conflict_status}" == "0" || "${conflict_output}" != *"choose exactly one signer mode"* ]]; then
  echo "Deployment script did not fail closed on conflicting signer modes" >&2
  exit 1
fi

set +e
dry_run_output="$(bash "${DEPLOY_SCRIPT}" --no-broadcast 2>&1)"
dry_run_status=$?
set -e
if [[ "${dry_run_status}" == "0" || "${dry_run_output}" != *"unknown or unsafe argument: --no-broadcast"* ]]; then
  echo "Deployment script still permits the broken no-broadcast path" >&2
  exit 1
fi

set +e
mainnet_output="$(
  RPC_URL=http://127.0.0.1:1 bash "${DEPLOY_SCRIPT}" \
    --expected-chain-id 369 \
    --sender 0x0000000000000000000000000000000000000001 \
    --ledger \
    --confirm-mainnet \
    --confirmations 12 2>&1
)"
mainnet_status=$?
set -e
if [[ "${mainnet_status}" == "0" || "${mainnet_output}" != *"mainnet requires --source-commit"* ]]; then
  echo "Deployment script did not fail closed on missing mainnet provenance" >&2
  exit 1
fi

set +e
inherited_secret_output="$(
  PRIVATE_KEY=must-not-be-consumed bash "${DEPLOY_SCRIPT}" --help 2>&1
)"
inherited_secret_status=$?
set -e
if [[ "${inherited_secret_status}" == "0" || "${inherited_secret_output}" != *"refusing inherited signer secret"* ]]; then
  echo "Deployment script did not reject inherited signer material" >&2
  exit 1
fi

set +e
dapp_override_output="$(
  DAPP_TEST_NUMBER=1 bash "${DEPLOY_SCRIPT}" --help 2>&1
)"
dapp_override_status=$?
set -e
if [[ "${dapp_override_status}" == "0" || "${dapp_override_output}" != *"caller DAPP override is forbidden: DAPP_TEST_NUMBER"* ]]; then
  echo "Deployment script did not reject an inherited DAPP override" >&2
  exit 1
fi

set +e
foundry_override_output="$(
  FOUNDRY_SOLC_VERSION=0.8.35 bash "${DEPLOY_SCRIPT}" --help 2>&1
)"
foundry_override_status=$?
set -e
if [[ "${foundry_override_status}" == "0" || "${foundry_override_output}" != *"caller Foundry override is forbidden"* ]]; then
  echo "Deployment script did not reject an inherited Foundry override" >&2
  exit 1
fi

rpc_sentinel='http://rpc-user:rpc-leak-sentinel@127.0.0.1:1'
set +e
rpc_error_output="$(
  RPC_URL="${rpc_sentinel}" bash "${DEPLOY_SCRIPT}" \
    --expected-chain-id 943 \
    --sender 0x0000000000000000000000000000000000000001 \
    --ledger 2>&1
)"
rpc_error_status=$?
set -e
if [[ "${rpc_error_status}" == "0" ]]; then
  echo "Invalid RPC unexpectedly passed deployment preflight" >&2
  exit 1
fi
if [[ "${rpc_error_output}" == *"${rpc_sentinel}"* || "${rpc_error_output}" == *"rpc-leak-sentinel"* ]]; then
  echo "Deployment error output leaked the RPC URL" >&2
  exit 1
fi
if [[ "${rpc_error_output}" != *"<redacted-rpc>"* ]]; then
  echo "Deployment error output did not mark the RPC URL as redacted" >&2
  exit 1
fi

for required_guard in \
  'verify_deployment_receipt.py' \
  'immutableReferences' \
  'os.link(source, destination)' \
  'git status --porcelain=v1 --untracked-files=all' \
  'release checkpoint' \
  'PULSECHAIN_TESTNET_ANCHOR_HASH' \
  'core_broadcast_intent' \
  'settlement_broadcast_intent' \
  'require_exact_nonce_state' \
  'cast send' \
  '--create "${local_core_creation}"' \
  '--create "${expected_settlement_creation_input}"' \
  '--nonce' \
  'gas_budget' \
  'TOOLCHAIN_LOCK_SHA256' \
  'verify_effective_foundry_config' \
  'CHECKPOINT_SNAPSHOT_SHA256' \
  'git", "archive", "--format=tar", source_commit' \
  'authorized-commit production bytecode differs from prehashed artifacts' \
  'COMMIT_SNAPSHOT_VERIFIED=true'; do
  if ! rg -q --fixed-strings -- "${required_guard}" "${DEPLOY_SCRIPT}"; then
    echo "Deployment script is missing guard: ${required_guard}" >&2
    exit 1
  fi
done

snapshot_gate_line="$(rg -n -m 1 --fixed-strings -- 'COMMIT_SNAPSHOT_VERIFIED=true' "${DEPLOY_SCRIPT}" | cut -d: -f1)"
gas_probe_line="$(rg -n -m 1 --fixed-strings -- 'live_gas_price_wei=""' "${DEPLOY_SCRIPT}" | cut -d: -f1)"
journal_create_line="$(rg -n -m 1 --fixed-strings -- 'JOURNAL_PATH="$(mktemp' "${DEPLOY_SCRIPT}" | cut -d: -f1)"
first_broadcast_line="$(rg -n -m 1 --fixed-strings -- 'cast send "${send_args[@]}"' "${DEPLOY_SCRIPT}" | cut -d: -f1)"
if [[ -z "${snapshot_gate_line}" || -z "${gas_probe_line}" || -z "${journal_create_line}" || -z "${first_broadcast_line}" ]] ||
  (( snapshot_gate_line >= gas_probe_line || snapshot_gate_line >= journal_create_line || snapshot_gate_line >= first_broadcast_line )); then
  echo "Authorized-commit rebuild must finish before gas probing, journal creation, and broadcast" >&2
  exit 1
fi

if rg -q --fixed-strings -- 'forge create' "${DEPLOY_SCRIPT}"; then
  echo "Deployment script must not recompile while constructing a broadcast transaction" >&2
  exit 1
fi

if rg -q --fixed-strings -- '[[ -z "$(git status' "${DEPLOY_SCRIPT}"; then
  echo "Deployment script contains a fail-open git-status command substitution" >&2
  exit 1
fi

if ! rg -q --fixed-strings -- 'DEPLOY_ARGS' "${ROOT_DIR}/Makefile"; then
  echo "make deploy does not expose the documented nonsecret DEPLOY_ARGS channel" >&2
  exit 1
fi

echo "Deployment signer-safety checks passed"

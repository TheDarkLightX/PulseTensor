#!/usr/bin/env bash
# Never inherit xtrace into a signing workflow: it can expose paths, prompts,
# provider metadata, or future signer arguments added by a dependency.
set +x
set -euo pipefail
umask 077

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RPC_URL="${RPC_URL:-}"
RELEASE_CHECKPOINT_RPC_URL="${RELEASE_CHECKPOINT_RPC_URL:-}"
EXPECTED_CHAIN_ID="${EXPECTED_CHAIN_ID:-}"
SENDER="${DEPLOYER_ADDRESS:-}"
OPTIMIZER_RUNS="1"
FOUNDRY_PROFILE_ACTIVE="default"
PROFILE_ID="pulsetensor-size-safe-v1"
PULSECHAIN_MAINNET_ANCHOR_BLOCK=17233000
PULSECHAIN_MAINNET_ANCHOR_HASH="0x9c8280d1182c2648af6390d8ea4a00d5f4bb8d44bf39161cd8983ea5a5fb9fd0"
PULSECHAIN_TESTNET_ANCHOR_BLOCK=16492700
PULSECHAIN_TESTNET_ANCHOR_HASH="0x9246d58ec6dd9900040defb013ef1317f509617cbc02c9e88279f7ba70e3b323"
SOLC_VERSION=""
PROFILE_ACK=""
OUTPUT_DIR="${ROOT_DIR}/runs/deployments"
CONFIRMATIONS="${DEPLOY_CONFIRMATIONS:-2}"
CONFIRMATION_TIMEOUT_SECONDS="${DEPLOY_CONFIRMATION_TIMEOUT_SECONDS:-900}"
CONFIRMATION_POLL_SECONDS="${DEPLOY_CONFIRMATION_POLL_SECONDS:-2}"
MAX_FEE_PER_GAS_WEI="${DEPLOY_MAX_FEE_PER_GAS_WEI:-}"
GAS_ESTIMATE_MARGIN_BPS=2_000
CONFIRM_MAINNET=0
SOURCE_COMMIT_ACK=""
RELEASE_CHECKPOINT=""
SIGNER_MODE=""
KEYSTORE_PATH=""
PASSWORD_FILE=""
ACCOUNT_NAME=""
JOURNAL_PATH=""
RECEIPT_TEMP=""
CHECKPOINT_SNAPSHOT=""
CHECKPOINT_SNAPSHOT_SHA256=""
COMMIT_SNAPSHOT_VERIFIED=false
SUCCESS=0
CURRENT_STAGE="preflight"

usage() {
  cat <<'EOF'
Usage: bash scripts/deploy_pulsetensor.sh [options]

Broadcasts exactly two prebuilt creation inputs (Core, then Settlement),
validates their receipts and exact runtime bytecode, waits for confirmations,
rechecks the canonical receipts, and atomically publishes a non-overwriting
receipt.

Required:
  --expected-chain-id <id>  Chain ID that the RPC must report
  --sender <address>        Dedicated public deployer address
  RPC_URL=<url>             RPC endpoint (environment is preferred)

Choose exactly one signer:
  --account <name>          Foundry keystore account; prompts for password
  --keystore <path>         Encrypted keystore file or directory
  --password-file <path>    Optional owner-only keystore password file
  --ledger                  Ledger hardware wallet
  --trezor                  Trezor hardware wallet
  --aws                     AWS KMS signer
  --interactive             Hidden private-key prompt (never a command argument)

Other options:
  --rpc-url <url>           RPC URL; RPC_URL avoids shell-history exposure
  --confirmations <count>   Confirmations before final recheck (default: 2)
  --out-dir <path>          Receipt and partial-journal directory
  --help                    Show help

PulseChain mainnet (chain 369) additionally requires all of:
  --confirm-mainnet
  --source-commit <sha>     Exact clean git HEAD being authorized
  --profile-id pulsetensor-size-safe-v1
  --release-checkpoint <receipt.json>
                            Successful non-mainnet rehearsal from the same
                            clean commit, compiler profile, and artifact hashes
  RELEASE_CHECKPOINT_RPC_URL=<url>
                            Separate PulseChain testnet RPC used to reverify
                            the checkpoint live (must report chain 943)
  --max-fee-per-gas-wei <wei>
                            Hard transaction fee cap and balance-budget input
  --confirmations <count>   At least 12

Example (testnet):
  RPC_URL=https://rpc.v4.testnet.pulsechain.com \
    bash scripts/deploy_pulsetensor.sh \
      --expected-chain-id 943 \
      --sender 0xYourDedicatedDeployer \
      --keystore /secure/pulsetensor-deployer \
      --password-file /secure/pulsetensor-deployer.password

Security boundary:
  Deployment transactions and the deployer address are public. The wrapper
  reduces local secret leakage and records reproducible evidence; it cannot
  make public-chain activity anonymous or prove an RPC provider trustworthy.
  Pulse-specific anchor blocks plus live receipt checks cannot prevent a
  malicious RPC from equivocating; independently compare the result through
  another node. Confirmation depth is not a mathematical finality proof.
EOF
}

fail() {
  echo "deploy error: $*" >&2
  exit 1
}

redact_text() {
  RPC_REDACT_VALUE="${RPC_URL}" \
  CHECKPOINT_RPC_REDACT_VALUE="${RELEASE_CHECKPOINT_RPC_URL}" \
  KEYSTORE_REDACT_VALUE="${KEYSTORE_PATH}" \
  PASSWORD_FILE_REDACT_VALUE="${PASSWORD_FILE}" \
  CHECKPOINT_PATH_REDACT_VALUE="${RELEASE_CHECKPOINT}" \
  CHECKPOINT_SNAPSHOT_REDACT_VALUE="${CHECKPOINT_SNAPSHOT}" \
  python3 -c '
import os, re, sys
text = sys.stdin.read()
for name in (
    "RPC_REDACT_VALUE",
    "CHECKPOINT_RPC_REDACT_VALUE",
    "KEYSTORE_REDACT_VALUE",
    "PASSWORD_FILE_REDACT_VALUE",
    "CHECKPOINT_PATH_REDACT_VALUE",
    "CHECKPOINT_SNAPSHOT_REDACT_VALUE",
):
    secret = os.environ.get(name, "")
    if secret:
        replacement = "<redacted-rpc>" if "RPC" in name else "<redacted-path>"
        text = text.replace(secret, replacement)
text = re.sub(r"https?://[^\s\x27\x22]+", "<redacted-rpc>", text)
sys.stdout.write(text.rstrip("\n"))
'
}

# Foundry automatically consumes several environment variables as signer or
# compiler configuration. Refuse inherited key/password material and remove
# caller-controlled Foundry configuration before any child process is started.
for secret_name in \
  PRIVATE""_KEY MNEMONIC ETH_PRIVATE_KEY ETH_PASSWORD ETH_KEYSTORE \
  ETH_KEYSTORE_ACCOUNT ETH_FROM CAST_PRIVATE_KEY CAST_MNEMONIC \
  CAST_PASSWORD CAST_KEYSTORE; do
  if [[ -v "${secret_name}" ]]; then
    fail "refusing inherited signer secret/configuration variable: ${secret_name}"
  fi
done
for transaction_override in \
  CHAIN ETH_GAS_LIMIT ETH_GAS_PRICE ETH_PRIORITY_GAS_PRICE \
  ETH_BLOB_GAS_PRICE SVM_HOME SOLC_PATH; do
  if [[ -v "${transaction_override}" ]]; then
    fail "refusing inherited transaction/compiler override: ${transaction_override}"
  fi
done
for dapp_name in $(compgen -e); do
  [[ "${dapp_name}" == DAPP_* ]] || continue
  fail "caller DAPP override is forbidden: ${dapp_name}"
done
for foundry_name in $(compgen -e); do
  [[ "${foundry_name}" == FOUNDRY_* ]] || continue
  case "${foundry_name}" in
    FOUNDRY_OPTIMIZER_RUNS)
      [[ "${!foundry_name}" == "1" ]] || fail "caller Foundry override is forbidden: ${foundry_name}"
      ;;
    FOUNDRY_PROFILE)
      [[ "${!foundry_name}" == "default" ]] || fail "caller Foundry override is forbidden: ${foundry_name}"
      ;;
    *)
      fail "caller Foundry override is forbidden: ${foundry_name}"
      ;;
  esac
  unset "${foundry_name}"
done

capture_command() {
  local destination="$1"
  local description="$2"
  shift 2
  local captured status sanitized
  set +e
  captured="$("$@" 2>&1)"
  status=$?
  set -e
  sanitized="$(printf '%s' "${captured}" | redact_text)"
  printf -v "${destination}" '%s' "${sanitized}"
  if [[ "${status}" != "0" ]]; then
    fail "${description} failed${sanitized:+: ${sanitized}}"
  fi
}

wait_for_receipt() {
  local destination="$1"
  local description="$2"
  shift 2
  local captured status sanitized last_diagnostic=""
  local deadline="$((SECONDS + CONFIRMATION_TIMEOUT_SECONDS))"
  while true; do
    set +e
    captured="$("$@" 2>&1)"
    status=$?
    set -e
    sanitized="$(printf '%s' "${captured}" | redact_text)"
    if [[ "${status}" == "0" && -n "${sanitized}" && "${sanitized}" != "null" ]]; then
      printf -v "${destination}" '%s' "${sanitized}"
      return 0
    fi
    last_diagnostic="${sanitized}"
    if (( SECONDS >= deadline )); then
      fail "${description} timed out${last_diagnostic:+: ${last_diagnostic}}"
    fi
    sleep "${CONFIRMATION_POLL_SECONDS}"
  done
}

extract_submission_hash() {
  local label="$1"
  local output="$2"
  local parsed=""
  parsed="$({
    SUBMISSION_OUTPUT="${output}" python3 - "${label}" <<'PY'
import os
import re
import sys

label = sys.argv[1]
hashes = re.findall(r"(?<![0-9A-Fa-f])0x[0-9A-Fa-f]{64}(?![0-9A-Fa-f])", os.environ["SUBMISSION_OUTPUT"])
unique = list(dict.fromkeys(value.lower() for value in hashes))
if len(unique) != 1:
    raise SystemExit(f"{label} submission output did not contain exactly one transaction hash")
print(unique[0])
PY
  } 2>&1)" || fail "${label} transaction-hash parsing failed: ${parsed}"
  printf '%s' "${parsed}"
}

select_signer() {
  local requested="$1"
  if [[ -n "${SIGNER_MODE}" ]]; then
    fail "choose exactly one signer mode (already selected: ${SIGNER_MODE}, requested: ${requested})"
  fi
  SIGNER_MODE="${requested}"
}

require_value() {
  local option="$1"
  local value="${2:-}"
  [[ -n "${value}" ]] || fail "${option} requires a value"
}

journal_event() {
  local event="$1"
  shift
  [[ -n "${JOURNAL_PATH}" ]] || return 0
  python3 - "${JOURNAL_PATH}" "${event}" "$@" <<'PY'
import datetime
import json
import os
import sys

path, event, *pairs = sys.argv[1:]
if len(pairs) % 2:
    raise SystemExit("journal key/value arguments are unbalanced")
record = {
    "at_utc": datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "event": event,
}
for index in range(0, len(pairs), 2):
    record[pairs[index]] = pairs[index + 1]
with open(path, "a", encoding="utf-8") as handle:
    handle.write(json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n")
    handle.flush()
    os.fsync(handle.fileno())
PY
}

on_exit() {
  local status=$?
  if [[ "${status}" != "0" && "${SUCCESS}" != "1" ]]; then
    journal_event "failed" "stage" "${CURRENT_STAGE}" "exit_status" "${status}" || true
    if [[ -n "${JOURNAL_PATH}" ]]; then
      echo "Partial deployment journal retained at: ${JOURNAL_PATH}" >&2
      echo "Do not rerun blindly; inspect recorded transaction hashes and the deployer nonce first." >&2
    fi
  fi
  if [[ -n "${RECEIPT_TEMP}" && -e "${RECEIPT_TEMP}" ]]; then
    rm -f -- "${RECEIPT_TEMP}" || true
  fi
  if [[ -n "${CHECKPOINT_SNAPSHOT}" && -e "${CHECKPOINT_SNAPSHOT}" ]]; then
    chmod 600 -- "${CHECKPOINT_SNAPSHOT}" 2>/dev/null || true
    rm -f -- "${CHECKPOINT_SNAPSHOT}" || true
  fi
}
trap on_exit EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rpc-url)
      require_value "$1" "${2:-}"
      RPC_URL="$2"
      shift 2
      ;;
    --expected-chain-id)
      require_value "$1" "${2:-}"
      EXPECTED_CHAIN_ID="$2"
      shift 2
      ;;
    --sender)
      require_value "$1" "${2:-}"
      SENDER="$2"
      shift 2
      ;;
    --account)
      require_value "$1" "${2:-}"
      select_signer "account"
      ACCOUNT_NAME="$2"
      shift 2
      ;;
    --keystore)
      require_value "$1" "${2:-}"
      select_signer "keystore"
      KEYSTORE_PATH="$2"
      shift 2
      ;;
    --password-file)
      require_value "$1" "${2:-}"
      PASSWORD_FILE="$2"
      shift 2
      ;;
    --ledger)
      select_signer "ledger"
      shift
      ;;
    --trezor)
      select_signer "trezor"
      shift
      ;;
    --aws)
      select_signer "aws"
      shift
      ;;
    --interactive)
      select_signer "interactive"
      shift
      ;;
    --confirm-mainnet)
      CONFIRM_MAINNET=1
      shift
      ;;
    --source-commit)
      require_value "$1" "${2:-}"
      SOURCE_COMMIT_ACK="$2"
      shift 2
      ;;
    --profile-id)
      require_value "$1" "${2:-}"
      PROFILE_ACK="$2"
      shift 2
      ;;
    --release-checkpoint)
      require_value "$1" "${2:-}"
      RELEASE_CHECKPOINT="$2"
      shift 2
      ;;
    --confirmations)
      require_value "$1" "${2:-}"
      CONFIRMATIONS="$2"
      shift 2
      ;;
    --max-fee-per-gas-wei)
      require_value "$1" "${2:-}"
      MAX_FEE_PER_GAS_WEI="$2"
      shift 2
      ;;
    --out-dir)
      require_value "$1" "${2:-}"
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "unknown or unsafe argument: $1"
      ;;
  esac
done

[[ -n "${RPC_URL}" ]] || fail "RPC_URL is required"
[[ "${RPC_URL}" != *$'\n'* && "${RPC_URL}" != *$'\r'* ]] || fail "RPC_URL contains a line break"
[[ "${EXPECTED_CHAIN_ID}" =~ ^[0-9]+$ ]] || fail "--expected-chain-id must be a decimal integer"
[[ "${SENDER}" =~ ^0x[0-9a-fA-F]{40}$ ]] || fail "--sender must be a 20-byte hexadecimal address"
[[ "${CONFIRMATIONS}" =~ ^[1-9][0-9]*$ ]] || fail "--confirmations must be at least 1 without leading zeroes"
[[ "${CONFIRMATION_TIMEOUT_SECONDS}" =~ ^[1-9][0-9]*$ ]] || fail "DEPLOY_CONFIRMATION_TIMEOUT_SECONDS must be positive without leading zeroes"
[[ "${CONFIRMATION_POLL_SECONDS}" =~ ^[0-9]+([.][0-9]+)?$ ]] || fail "DEPLOY_CONFIRMATION_POLL_SECONDS must be numeric"
if [[ -n "${MAX_FEE_PER_GAS_WEI}" ]]; then
  [[ "${MAX_FEE_PER_GAS_WEI}" =~ ^[1-9][0-9]*$ ]] || fail "--max-fee-per-gas-wei must be a positive decimal integer"
fi
if [[ -n "${PROFILE_ACK}" && "${PROFILE_ACK}" != "${PROFILE_ID}" ]]; then
  fail "unsupported deployment profile: ${PROFILE_ACK}"
fi
if [[ -n "${RELEASE_CHECKPOINT}" && "${EXPECTED_CHAIN_ID}" != "369" ]]; then
  fail "--release-checkpoint is valid only for PulseChain mainnet deployment"
fi
[[ -n "${SIGNER_MODE}" ]] || fail "broadcasting requires exactly one approved signer mode"
if [[ -n "${PASSWORD_FILE}" && "${SIGNER_MODE}" != "keystore" ]]; then
  fail "--password-file is valid only with --keystore"
fi
if [[ "${EXPECTED_CHAIN_ID}" == "369" ]]; then
  [[ "${CONFIRM_MAINNET}" == "1" ]] || fail "PulseChain mainnet deployment requires --confirm-mainnet"
  [[ "${SOURCE_COMMIT_ACK}" =~ ^[0-9a-fA-F]{40}$ ]] || fail "mainnet requires --source-commit with a full 40-character commit"
  [[ "${PROFILE_ACK}" == "${PROFILE_ID}" ]] || fail "mainnet requires explicit --profile-id ${PROFILE_ID}"
  [[ -n "${RELEASE_CHECKPOINT}" ]] || fail "mainnet requires --release-checkpoint"
  [[ -n "${RELEASE_CHECKPOINT_RPC_URL}" ]] || fail "mainnet requires RELEASE_CHECKPOINT_RPC_URL for live testnet revalidation"
  [[ -n "${MAX_FEE_PER_GAS_WEI}" ]] || fail "mainnet requires --max-fee-per-gas-wei or DEPLOY_MAX_FEE_PER_GAS_WEI"
  [[ "${CONFIRMATIONS}" -ge 12 ]] || fail "PulseChain mainnet requires at least 12 confirmations"
fi
for required_command in forge cast python3 git realpath sha256sum stat; do
  command -v "${required_command}" >/dev/null 2>&1 || fail "required command not found: ${required_command}"
done

if [[ "${SIGNER_MODE}" == "keystore" ]]; then
  [[ -e "${KEYSTORE_PATH}" && ! -L "${KEYSTORE_PATH}" ]] || fail "keystore must be an existing, non-symlink file or directory"
  [[ -O "${KEYSTORE_PATH}" ]] || fail "keystore path must be owned by the current user"
  keystore_mode="$(stat -c '%a' "${KEYSTORE_PATH}")"
  if (( (8#${keystore_mode}) & 077 )); then
    fail "keystore path must not grant group/other permissions (found mode ${keystore_mode})"
  fi
  keystore_lexical="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "${KEYSTORE_PATH}")"
  KEYSTORE_PATH="$(realpath -e -- "${KEYSTORE_PATH}")"
  [[ "${KEYSTORE_PATH}" == "${keystore_lexical}" ]] || fail "keystore path must not traverse a symlink"
fi
if [[ -n "${PASSWORD_FILE}" ]]; then
  [[ -f "${PASSWORD_FILE}" && ! -L "${PASSWORD_FILE}" ]] || fail "password file must be a regular, non-symlink file"
  [[ -O "${PASSWORD_FILE}" ]] || fail "password file must be owned by the current user"
  password_mode="$(stat -c '%a' "${PASSWORD_FILE}")"
  if (( (8#${password_mode}) & 077 )); then
    fail "password file must not grant group/other permissions (found mode ${password_mode})"
  fi
  password_lexical="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "${PASSWORD_FILE}")"
  PASSWORD_FILE="$(realpath -e -- "${PASSWORD_FILE}")"
  [[ "${PASSWORD_FILE}" == "${password_lexical}" ]] || fail "password file path must not traverse a symlink"
fi
if [[ -n "${RELEASE_CHECKPOINT}" ]]; then
  [[ -f "${RELEASE_CHECKPOINT}" && ! -L "${RELEASE_CHECKPOINT}" ]] || fail "release checkpoint must be a regular, non-symlink file"
  checkpoint_lexical="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "${RELEASE_CHECKPOINT}")"
  RELEASE_CHECKPOINT="$(realpath -e -- "${RELEASE_CHECKPOINT}")"
  [[ "${RELEASE_CHECKPOINT}" == "${checkpoint_lexical}" ]] || fail "release checkpoint path must not traverse a symlink"
fi
[[ ! -L "${OUTPUT_DIR}" ]] || fail "output directory must not be a symlink"
output_lexical="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "${OUTPUT_DIR}")"
OUTPUT_DIR="$(realpath -m -- "${OUTPUT_DIR}")"
[[ "${OUTPUT_DIR}" == "${output_lexical}" ]] || fail "output directory path must not traverse a symlink"
if [[ -e "${OUTPUT_DIR}" ]]; then
  [[ -d "${OUTPUT_DIR}" && ! -L "${OUTPUT_DIR}" ]] || fail "output path must be a non-symlink directory"
  [[ -O "${OUTPUT_DIR}" ]] || fail "output directory must be owned by the current user"
  output_mode="$(stat -c '%a' "${OUTPUT_DIR}")"
  if (( (8#${output_mode}) & 022 )); then
    fail "output directory must not be group/world writable (found mode ${output_mode})"
  fi
fi

TOOLCHAIN_LOCK_PATH="${ROOT_DIR}/scripts/toolchain.lock"
FOUNDRY_TOML_PATH="${ROOT_DIR}/foundry.toml"
[[ -f "${TOOLCHAIN_LOCK_PATH}" && ! -L "${TOOLCHAIN_LOCK_PATH}" ]] || fail "missing non-symlink scripts/toolchain.lock"
[[ -f "${FOUNDRY_TOML_PATH}" && ! -L "${FOUNDRY_TOML_PATH}" ]] || fail "missing non-symlink foundry.toml"
# The lock is repository-controlled shell syntax and is covered by the clean
# source-commit gate on mainnet.
source "${TOOLCHAIN_LOCK_PATH}"
for lock_name in \
  FORGE_RELEASE_VERSION FORGE_RELEASE_SHA256 CAST_RELEASE_SHA256 \
  SOLC_VERSION SOLC_RELEASE_SHA256; do
  [[ -n "${!lock_name:-}" ]] || fail "toolchain lock is missing ${lock_name}; stack this launch change on the executable-assurance PR"
done
[[ "${SOLC_VERSION}" == "0.8.36" ]] || fail "deployment requires locked Solidity 0.8.36"

TOOLCHAIN_LOCK_SHA256="$(sha256sum "${TOOLCHAIN_LOCK_PATH}" | awk '{print $1}')"
FOUNDRY_TOML_SHA256="$(sha256sum "${FOUNDRY_TOML_PATH}" | awk '{print $1}')"
FORGE_BINARY_PATH="$(type -P forge)"
CAST_BINARY_PATH="$(type -P cast)"
[[ -n "${FORGE_BINARY_PATH}" && -n "${CAST_BINARY_PATH}" ]] || fail "forge/cast must resolve to executable files"
FORGE_BINARY_PATH="$(realpath -e -- "${FORGE_BINARY_PATH}")"
CAST_BINARY_PATH="$(realpath -e -- "${CAST_BINARY_PATH}")"
SOLC_BINARY_CANDIDATE="${HOME:?HOME is required}/.svm/${SOLC_VERSION}/solc-${SOLC_VERSION}"
[[ -x "${SOLC_BINARY_CANDIDATE}" ]] || fail "locked solc binary is not installed at ${SOLC_BINARY_CANDIDATE}"
SOLC_BINARY_PATH="$(realpath -e -- "${SOLC_BINARY_CANDIDATE}")"
[[ -f "${FORGE_BINARY_PATH}" && -x "${FORGE_BINARY_PATH}" ]] || fail "forge does not resolve to an executable regular file"
[[ -f "${CAST_BINARY_PATH}" && -x "${CAST_BINARY_PATH}" ]] || fail "cast does not resolve to an executable regular file"
[[ -f "${SOLC_BINARY_PATH}" && -x "${SOLC_BINARY_PATH}" ]] || fail "solc does not resolve to an executable regular file"
FORGE_SHA256="$(sha256sum "${FORGE_BINARY_PATH}" | awk '{print $1}')"
CAST_SHA256="$(sha256sum "${CAST_BINARY_PATH}" | awk '{print $1}')"
SOLC_SHA256="$(sha256sum "${SOLC_BINARY_PATH}" | awk '{print $1}')"
[[ "${FORGE_SHA256}" == "${FORGE_RELEASE_SHA256}" ]] || fail "forge binary digest does not match scripts/toolchain.lock"
[[ "${CAST_SHA256}" == "${CAST_RELEASE_SHA256}" ]] || fail "cast binary digest does not match scripts/toolchain.lock"
[[ "${SOLC_SHA256}" == "${SOLC_RELEASE_SHA256}" ]] || fail "solc binary digest does not match scripts/toolchain.lock"
forge() {
  command "${FORGE_BINARY_PATH}" "$@"
}
cast() {
  command "${CAST_BINARY_PATH}" "$@"
}

forge_version="$(forge --version | head -n 1)"
[[ "${forge_version}" == "${FORGE_RELEASE_VERSION}" ]] || fail "forge version does not match scripts/toolchain.lock"

verify_toolchain_unchanged() {
  [[ "$(sha256sum "${TOOLCHAIN_LOCK_PATH}" | awk '{print $1}')" == "${TOOLCHAIN_LOCK_SHA256}" ]] || fail "toolchain lock changed during deployment"
  [[ "$(sha256sum "${FOUNDRY_TOML_PATH}" | awk '{print $1}')" == "${FOUNDRY_TOML_SHA256}" ]] || fail "foundry.toml changed during deployment"
  [[ "$(sha256sum "${FORGE_BINARY_PATH}" | awk '{print $1}')" == "${FORGE_SHA256}" ]] || fail "forge binary changed during deployment"
  [[ "$(sha256sum "${CAST_BINARY_PATH}" | awk '{print $1}')" == "${CAST_SHA256}" ]] || fail "cast binary changed during deployment"
  [[ "$(sha256sum "${SOLC_BINARY_PATH}" | awk '{print $1}')" == "${SOLC_SHA256}" ]] || fail "solc binary changed during deployment"
  [[ "$(forge --version | head -n 1)" == "${forge_version}" ]] || fail "forge version changed during deployment"
}

pushd "${ROOT_DIR}" >/dev/null
SOURCE_COMMIT="$(git rev-parse --verify HEAD)"
SOURCE_CLEAN=true
source_tree_status="$(git status --porcelain=v1 --untracked-files=all)"
if [[ -n "${source_tree_status}" ]]; then
  SOURCE_CLEAN=false
fi

if [[ "${EXPECTED_CHAIN_ID}" == "369" ]]; then
  [[ "${CONFIRM_MAINNET}" == "1" ]] || fail "PulseChain mainnet deployment requires --confirm-mainnet"
  [[ "${SOURCE_COMMIT_ACK}" =~ ^[0-9a-fA-F]{40}$ ]] || fail "mainnet requires --source-commit with a full 40-character commit"
  [[ "${SOURCE_COMMIT_ACK,,}" == "${SOURCE_COMMIT,,}" ]] || fail "--source-commit does not match git HEAD"
  [[ "${SOURCE_CLEAN}" == "true" ]] || fail "mainnet deployment requires a clean git worktree, including no untracked files"
  [[ "${PROFILE_ACK}" == "${PROFILE_ID}" ]] || fail "mainnet requires explicit --profile-id ${PROFILE_ID}"
  [[ -f "${RELEASE_CHECKPOINT}" && ! -L "${RELEASE_CHECKPOINT}" ]] || fail "mainnet requires a regular, non-symlink --release-checkpoint"
  [[ -n "${RELEASE_CHECKPOINT_RPC_URL}" ]] || fail "mainnet requires RELEASE_CHECKPOINT_RPC_URL for live testnet revalidation"
  [[ "${RELEASE_CHECKPOINT_RPC_URL}" != *$'\n'* && "${RELEASE_CHECKPOINT_RPC_URL}" != *$'\r'* ]] || fail "RELEASE_CHECKPOINT_RPC_URL contains a line break"
  [[ "${RELEASE_CHECKPOINT_RPC_URL}" != "${RPC_URL}" ]] || fail "mainnet and release-checkpoint RPC URLs must be distinct"
  [[ -n "${MAX_FEE_PER_GAS_WEI}" ]] || fail "mainnet requires --max-fee-per-gas-wei or DEPLOY_MAX_FEE_PER_GAS_WEI"
  [[ "${CONFIRMATIONS}" -ge 12 ]] || fail "PulseChain mainnet requires at least 12 confirmations"
  output_realpath="$(realpath -m -- "${OUTPUT_DIR}")"
  root_realpath="$(realpath -m -- "${ROOT_DIR}")"
  if [[ "${output_realpath}" == "${root_realpath}" || "${output_realpath}" == "${root_realpath}/"* ]]; then
    git check-ignore -q -- "${output_realpath}/.pulsetensor-deployment-probe" || \
      fail "mainnet output directory inside the worktree must be git-ignored"
  fi
fi

# Keep the RPC out of forge/cast argument vectors. It may still be visible to
# same-user processes through the environment, which is documented explicitly.
export ETH_RPC_URL="${RPC_URL}"
export -n RPC_URL 2>/dev/null || true
export -n RELEASE_CHECKPOINT_RPC_URL 2>/dev/null || true

actual_chain_id=""
capture_command actual_chain_id "reading RPC chain ID" cast chain-id
[[ "${actual_chain_id}" == "${EXPECTED_CHAIN_ID}" ]] || fail "RPC chain ID mismatch: expected ${EXPECTED_CHAIN_ID}, received ${actual_chain_id}"

network_anchor_block_number=""
network_anchor_block_hash=""
if [[ "${actual_chain_id}" == "369" || "${actual_chain_id}" == "943" ]]; then
  expected_anchor_block="${PULSECHAIN_MAINNET_ANCHOR_BLOCK}"
  expected_anchor_hash="${PULSECHAIN_MAINNET_ANCHOR_HASH}"
  if [[ "${actual_chain_id}" == "943" ]]; then
    expected_anchor_block="${PULSECHAIN_TESTNET_ANCHOR_BLOCK}"
    expected_anchor_hash="${PULSECHAIN_TESTNET_ANCHOR_HASH}"
  fi
  network_anchor_json=""
  capture_command network_anchor_json "reading PulseChain network anchor block" cast block "${expected_anchor_block}" --json
  network_anchor_result="$({
    BLOCK_JSON="${network_anchor_json}" python3 - "${expected_anchor_block}" "${expected_anchor_hash}" <<'PY'
import json
import os
import re
import sys

block = json.loads(os.environ["BLOCK_JSON"])
expected_number = int(sys.argv[1])
expected_hash = sys.argv[2].lower()
number = block.get("number")
if isinstance(number, str):
    number = int(number, 16 if number.lower().startswith("0x") else 10)
if type(number) is not int or number != expected_number:
    raise SystemExit("PulseChain network anchor block number mismatch")
value = block.get("hash")
if not isinstance(value, str) or not re.fullmatch(r"0x[0-9a-fA-F]{64}", value):
    raise SystemExit("PulseChain network anchor block hash is invalid")
if value.lower() != expected_hash:
    raise SystemExit("PulseChain network anchor block hash mismatch")
print(number, value.lower(), sep="\t")
PY
  } 2>&1)" || fail "PulseChain network anchor validation failed: ${network_anchor_result}"
  IFS=$'\t' read -r network_anchor_block_number network_anchor_block_hash <<<"${network_anchor_result}"
fi

sender_balance=""
sender_nonce_before=""
sender_nonce_pending_before=""
capture_command sender_balance "reading deployer balance" cast balance "${SENDER}"
capture_command sender_nonce_before "reading latest deployer nonce" cast nonce "${SENDER}" --block latest
capture_command sender_nonce_pending_before "reading pending deployer nonce" cast nonce "${SENDER}" --block pending
[[ "${sender_balance}" =~ ^[0-9]+$ ]] || fail "RPC returned a non-decimal deployer balance"
[[ "${sender_balance}" != "0" ]] || fail "deployer has zero native balance"
[[ "${sender_nonce_before}" =~ ^[0-9]+$ ]] || fail "RPC returned a non-decimal deployer nonce"
[[ "${sender_nonce_pending_before}" =~ ^[0-9]+$ ]] || fail "RPC returned a non-decimal pending deployer nonce"
[[ "${sender_nonce_pending_before}" == "${sender_nonce_before}" ]] || fail "deployer has pending transactions; reconcile them before deployment"

expected_core_address_output=""
expected_settlement_address_output=""
capture_command expected_core_address_output "computing expected Core address" cast compute-address --nonce "${sender_nonce_before}" "${SENDER}"
capture_command expected_settlement_address_output "computing expected Settlement address" cast compute-address --nonce "$((sender_nonce_before + 1))" "${SENDER}"
expected_core_address="$(printf '%s\n' "${expected_core_address_output}" | awk '/Computed Address:/ {print $3}' | tail -n 1)"
expected_settlement_address="$(printf '%s\n' "${expected_settlement_address_output}" | awk '/Computed Address:/ {print $3}' | tail -n 1)"
[[ "${expected_core_address}" =~ ^0x[0-9a-fA-F]{40}$ ]] || fail "unable to derive expected Core address"
[[ "${expected_settlement_address}" =~ ^0x[0-9a-fA-F]{40}$ ]] || fail "unable to derive expected Settlement address"

mkdir -p -- "${OUTPUT_DIR}"
[[ -d "${OUTPUT_DIR}" && ! -L "${OUTPUT_DIR}" ]] || fail "output directory must not be a symlink"
[[ -O "${OUTPUT_DIR}" ]] || fail "output directory must be owned by the current user"
output_mode="$(stat -c '%a' "${OUTPUT_DIR}")"
if (( (8#${output_mode}) & 022 )); then
  fail "output directory must not be group/world writable (found mode ${output_mode})"
fi

if [[ -n "${RELEASE_CHECKPOINT}" ]]; then
  checkpoint_snapshot_result="$({
    python3 - "${RELEASE_CHECKPOINT}" "${OUTPUT_DIR}" <<'PY'
import hashlib
import os
import stat
import sys
import tempfile

source, output_dir = sys.argv[1:]
flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
source_fd = os.open(source, flags)
try:
    before = os.fstat(source_fd)
    if not stat.S_ISREG(before.st_mode):
        raise SystemExit("release checkpoint source is not a regular file")
    chunks = []
    while True:
        chunk = os.read(source_fd, 1024 * 1024)
        if not chunk:
            break
        chunks.append(chunk)
    after = os.fstat(source_fd)
finally:
    os.close(source_fd)

identity_before = (
    before.st_dev,
    before.st_ino,
    before.st_mode,
    before.st_uid,
    before.st_size,
    before.st_mtime_ns,
    before.st_ctime_ns,
)
identity_after = (
    after.st_dev,
    after.st_ino,
    after.st_mode,
    after.st_uid,
    after.st_size,
    after.st_mtime_ns,
    after.st_ctime_ns,
)
if identity_before != identity_after:
    raise SystemExit("release checkpoint changed while it was being snapshotted")

raw = b"".join(chunks)
fd, path = tempfile.mkstemp(
    prefix=".pulsetensor_release_checkpoint.", suffix=".json", dir=output_dir
)
try:
    view = memoryview(raw)
    while view:
        written = os.write(fd, view)
        view = view[written:]
    os.fsync(fd)
    os.fchmod(fd, 0o400)
finally:
    os.close(fd)
directory_fd = os.open(output_dir, os.O_RDONLY)
try:
    os.fsync(directory_fd)
finally:
    os.close(directory_fd)
print(path, hashlib.sha256(raw).hexdigest(), sep="\t")
PY
  } 2>&1)" || fail "release checkpoint snapshot failed: ${checkpoint_snapshot_result}"
  IFS=$'\t' read -r CHECKPOINT_SNAPSHOT CHECKPOINT_SNAPSHOT_SHA256 <<<"${checkpoint_snapshot_result}"
  [[ -f "${CHECKPOINT_SNAPSHOT}" && ! -L "${CHECKPOINT_SNAPSHOT}" ]] || fail "release checkpoint snapshot is invalid"
  [[ -O "${CHECKPOINT_SNAPSHOT}" ]] || fail "release checkpoint snapshot must be owned by the current user"
  [[ "$(stat -c '%a' "${CHECKPOINT_SNAPSHOT}")" == "400" ]] || fail "release checkpoint snapshot must be owner-read-only"
  [[ "${CHECKPOINT_SNAPSHOT_SHA256}" =~ ^[0-9a-f]{64}$ ]] || fail "release checkpoint snapshot digest is invalid"
fi

export FOUNDRY_OPTIMIZER_RUNS="${OPTIMIZER_RUNS}"
export FOUNDRY_SOLC_VERSION="${SOLC_VERSION}"
export FOUNDRY_PROFILE="${FOUNDRY_PROFILE_ACTIVE}"
export FOUNDRY_SRC="src"
export FOUNDRY_OUT="out"
export FOUNDRY_LIBS='["lib"]'
export FOUNDRY_FFI="false"
export FOUNDRY_EVM_VERSION="paris"
export FOUNDRY_VIA_IR="true"
export FOUNDRY_OPTIMIZER="true"
export FOUNDRY_AUTO_DETECT_SOLC="false"
export FOUNDRY_AUTO_DETECT_REMAPPINGS="false"
export FOUNDRY_REMAPPINGS="forge-std/=lib/forge-std/src/"

verify_effective_foundry_config() {
  local config_json=""
  local validation=""
  capture_command config_json "reading effective Foundry configuration" forge config --json
  validation="$({
    CONFIG_JSON="${config_json}" python3 - "${SOLC_VERSION}" "${OPTIMIZER_RUNS}" <<'PY'
import json
import os
import sys

config = json.loads(os.environ["CONFIG_JSON"])
solc_version, optimizer_runs = sys.argv[1:]
expected = {
    "src": "src",
    "out": "out",
    "libs": ["lib"],
    "remappings": ["forge-std/=lib/forge-std/src/"],
    "auto_detect_remappings": False,
    "libraries": [],
    "allow_paths": [],
    "include_paths": [],
    "evm_version": "paris",
    "solc": solc_version,
    "auto_detect_solc": False,
    "optimizer": True,
    "optimizer_runs": int(optimizer_runs),
    "via_ir": True,
    "ffi": False,
    "extra_output": [],
    "extra_output_files": [],
    "build_info": False,
    "sparse_mode": False,
    "isolate": False,
    "fs_permissions": [{"access": "read", "path": "./"}],
}
for key, value in expected.items():
    if config.get(key) != value:
        raise SystemExit(f"effective Foundry configuration mismatch: {key}")
print("ok")
PY
  } 2>&1)" || fail "effective Foundry configuration validation failed: ${validation}"
  [[ "${validation}" == "ok" ]] || fail "effective Foundry configuration validation produced unexpected output"
}

verify_effective_foundry_config
build_output=""
capture_command build_output "clean deployment build" forge build --force
[[ -z "${build_output}" ]] || printf '%s\n' "${build_output}"
verify_toolchain_unchanged

core_artifact="${ROOT_DIR}/out/PulseTensorCore.sol/PulseTensorCore.json"
settlement_artifact="${ROOT_DIR}/out/PulseTensorInferenceSettlement.sol/PulseTensorInferenceSettlement.json"
[[ -f "${core_artifact}" && -f "${settlement_artifact}" ]] || fail "deployment build did not produce expected artifacts"
core_artifact_sha256="$(sha256sum "${core_artifact}" | awk '{print $1}')"
settlement_artifact_sha256="$(sha256sum "${settlement_artifact}" | awk '{print $1}')"

verify_release_inputs_unchanged() {
  verify_toolchain_unchanged
  verify_effective_foundry_config
  [[ "$(sha256sum "${core_artifact}" | awk '{print $1}')" == "${core_artifact_sha256}" ]] || fail "Core artifact changed during deployment"
  [[ "$(sha256sum "${settlement_artifact}" | awk '{print $1}')" == "${settlement_artifact_sha256}" ]] || fail "Settlement artifact changed during deployment"
  if [[ -n "${CHECKPOINT_SNAPSHOT}" ]]; then
    [[ -f "${CHECKPOINT_SNAPSHOT}" && ! -L "${CHECKPOINT_SNAPSHOT}" && -O "${CHECKPOINT_SNAPSHOT}" ]] || fail "release checkpoint snapshot identity changed"
    [[ "$(stat -c '%a' "${CHECKPOINT_SNAPSHOT}")" == "400" ]] || fail "release checkpoint snapshot permissions changed"
    [[ "$(sha256sum "${CHECKPOINT_SNAPSHOT}" | awk '{print $1}')" == "${CHECKPOINT_SNAPSHOT_SHA256}" ]] || fail "release checkpoint snapshot changed during deployment"
  fi
  if [[ "${EXPECTED_CHAIN_ID}" == "369" ]]; then
    [[ "$(git rev-parse --verify HEAD)" == "${SOURCE_COMMIT}" ]] || fail "git HEAD changed during mainnet deployment"
    current_tree_status="$(git status --porcelain=v1 --untracked-files=all)"
    [[ -z "${current_tree_status}" ]] || fail "git worktree changed during mainnet deployment"
  fi
}

compiler_version="$({
  python3 - "${core_artifact}" "${settlement_artifact}" "${OPTIMIZER_RUNS}" "${SOLC_VERSION}" <<'PY'
import json
import sys

versions = set()
for path in sys.argv[1:3]:
    artifact = json.load(open(path, encoding="utf-8"))
    metadata = artifact.get("metadata")
    if not isinstance(metadata, dict):
        raise SystemExit("artifact metadata is missing")
    compiler = metadata.get("compiler", {}).get("version")
    settings = metadata.get("settings", {})
    optimizer = settings.get("optimizer", {})
    if not isinstance(compiler, str) or not compiler.startswith(sys.argv[4] + "+"):
        raise SystemExit(f"deployment profile requires Solidity {sys.argv[4]}")
    if optimizer.get("enabled") is not True or optimizer.get("runs") != int(sys.argv[3]):
        raise SystemExit("artifact optimizer settings do not match the deployment profile")
    if settings.get("viaIR") is not True or settings.get("evmVersion") != "paris":
        raise SystemExit("artifact via-IR/EVM settings do not match the deployment profile")
    versions.add(compiler)
if len(versions) != 1:
    raise SystemExit("contract artifacts use different compiler versions")
print(versions.pop())
PY
} 2>&1)" || fail "artifact profile validation failed: ${compiler_version}"

local_core_runtime=""
local_core_creation=""
local_settlement_template=""
local_settlement_creation=""
capture_command local_core_runtime "reading Core runtime artifact" forge inspect src/PulseTensorCore.sol:PulseTensorCore deployedBytecode
capture_command local_core_creation "reading Core creation artifact" forge inspect src/PulseTensorCore.sol:PulseTensorCore bytecode
capture_command local_settlement_template "reading Settlement runtime template" forge inspect src/PulseTensorInferenceSettlement.sol:PulseTensorInferenceSettlement deployedBytecode
capture_command local_settlement_creation "reading Settlement creation artifact" forge inspect src/PulseTensorInferenceSettlement.sol:PulseTensorInferenceSettlement bytecode
local_core_runtime_hash=""
local_core_creation_hash=""
local_settlement_template_hash=""
local_settlement_creation_hash=""
capture_command local_core_runtime_hash "hashing Core runtime" cast keccak "${local_core_runtime}"
capture_command local_core_creation_hash "hashing Core creation bytecode" cast keccak "${local_core_creation}"
capture_command local_settlement_template_hash "hashing Settlement runtime template" cast keccak "${local_settlement_template}"
capture_command local_settlement_creation_hash "hashing Settlement creation bytecode" cast keccak "${local_settlement_creation}"

core_address_word="$(printf '%064s' "${expected_core_address#0x}" | tr ' ' '0')"
expected_settlement_creation_input="${local_settlement_creation}${core_address_word}"
core_creation_input_hash="${local_core_creation_hash}"
settlement_creation_input_hash=""
capture_command settlement_creation_input_hash "hashing Settlement creation transaction input" cast keccak "${expected_settlement_creation_input}"

if [[ "${EXPECTED_CHAIN_ID}" == "369" ]]; then
  commit_snapshot_result="$({
    EXPECTED_CORE_CREATION="${local_core_creation}" \
    EXPECTED_CORE_RUNTIME="${local_core_runtime}" \
    EXPECTED_SETTLEMENT_CREATION="${local_settlement_creation}" \
    EXPECTED_SETTLEMENT_RUNTIME="${local_settlement_template}" \
    python3 - \
      "${ROOT_DIR}" \
      "${SOURCE_COMMIT}" \
      "${FORGE_BINARY_PATH}" \
      "${core_artifact}" \
      "${settlement_artifact}" \
      "${core_artifact_sha256}" \
      "${settlement_artifact_sha256}" \
      "${FOUNDRY_TOML_SHA256}" \
      "${TOOLCHAIN_LOCK_SHA256}" <<'PY'
import hashlib
import json
import os
import pathlib
import subprocess
import sys
import tarfile
import tempfile

(
    project_root_raw,
    source_commit,
    forge_path,
    live_core_path_raw,
    live_settlement_path_raw,
    live_core_sha256,
    live_settlement_sha256,
    foundry_toml_sha256,
    toolchain_lock_sha256,
) = sys.argv[1:]
project_root = pathlib.Path(project_root_raw)
live_core_path = pathlib.Path(live_core_path_raw)
live_settlement_path = pathlib.Path(live_settlement_path_raw)

def sha256_file(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def load_artifact(path):
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise SystemExit("deployment artifact is not a JSON object")
    return value

def metadata(artifact):
    value = artifact.get("metadata")
    if isinstance(value, str):
        value = json.loads(value)
    if not isinstance(value, dict):
        raise SystemExit("deployment artifact metadata is missing")
    return value

def artifact_profile(artifact):
    value = metadata(artifact)
    settings = value.get("settings")
    if not isinstance(settings, dict):
        raise SystemExit("deployment artifact settings are missing")
    return {
        "compiler": value.get("compiler"),
        "optimizer": settings.get("optimizer"),
        "viaIR": settings.get("viaIR"),
        "evmVersion": settings.get("evmVersion"),
        "compilationTarget": settings.get("compilationTarget"),
        "remappings": settings.get("remappings"),
        "libraries": settings.get("libraries"),
        "metadata": settings.get("metadata"),
    }

def bytecode(artifact, section):
    value = artifact.get(section)
    if not isinstance(value, dict) or not isinstance(value.get("object"), str):
        raise SystemExit(f"deployment artifact {section} bytecode is missing")
    result = value["object"].lower()
    if not result.startswith("0x"):
        result = "0x" + result
    return result

def normalized_immutable_references(value):
    if value is None:
        value = {}
    if not isinstance(value, dict):
        raise SystemExit("deployment artifact immutable references are malformed")
    groups = []
    for locations in value.values():
        if not isinstance(locations, list):
            raise SystemExit("deployment artifact immutable references are malformed")
        normalized_locations = []
        for location in locations:
            if not isinstance(location, dict):
                raise SystemExit("deployment artifact immutable references are malformed")
            start = location.get("start")
            length = location.get("length")
            if type(start) is not int or type(length) is not int or start < 0 or length <= 0:
                raise SystemExit("deployment artifact immutable references are malformed")
            normalized_locations.append((start, length))
        groups.append(tuple(sorted(normalized_locations)))
    return tuple(sorted(groups))

if sha256_file(live_core_path) != live_core_sha256:
    raise SystemExit("live Core artifact changed before commit-snapshot comparison")
if sha256_file(live_settlement_path) != live_settlement_sha256:
    raise SystemExit("live Settlement artifact changed before commit-snapshot comparison")
live_core = load_artifact(live_core_path)
live_settlement = load_artifact(live_settlement_path)

expected_bytes = {
    "Core creation": os.environ["EXPECTED_CORE_CREATION"].lower(),
    "Core runtime": os.environ["EXPECTED_CORE_RUNTIME"].lower(),
    "Settlement creation": os.environ["EXPECTED_SETTLEMENT_CREATION"].lower(),
    "Settlement runtime": os.environ["EXPECTED_SETTLEMENT_RUNTIME"].lower(),
}
live_bytes = {
    "Core creation": bytecode(live_core, "bytecode"),
    "Core runtime": bytecode(live_core, "deployedBytecode"),
    "Settlement creation": bytecode(live_settlement, "bytecode"),
    "Settlement runtime": bytecode(live_settlement, "deployedBytecode"),
}
if live_bytes != expected_bytes:
    raise SystemExit("forge inspect output differs from the prehashed deployment artifacts")

with tempfile.TemporaryDirectory(prefix="pulsetensor-mainnet-source-snapshot-") as raw_temp:
    temp_root = pathlib.Path(raw_temp)
    archive_path = temp_root / "source.tar"
    with archive_path.open("wb") as archive_output:
        archived = subprocess.run(
            ["git", "archive", "--format=tar", source_commit],
            cwd=project_root,
            stdout=archive_output,
            stderr=subprocess.PIPE,
            check=False,
        )
    if archived.returncode != 0:
        raise SystemExit("git archive of the authorized source commit failed")
    source_root = temp_root / "source"
    source_root.mkdir(mode=0o700)
    with tarfile.open(archive_path, mode="r:") as archive:
        archive.extractall(source_root, filter="data")
    if sha256_file(source_root / "foundry.toml") != foundry_toml_sha256:
        raise SystemExit("authorized commit foundry.toml differs from the preflight profile")
    if sha256_file(source_root / "scripts" / "toolchain.lock") != toolchain_lock_sha256:
        raise SystemExit("authorized commit toolchain lock differs from preflight")

    # git archive omits the ignored Forge dependency. Production sources do not
    # import it, but the declared remapping must remain present in build metadata.
    (source_root / "lib" / "forge-std" / "src").mkdir(parents=True, mode=0o700)

    build_root = temp_root / "build"
    env = {
        key: value
        for key, value in os.environ.items()
        if key != "ETH_RPC_URL"
        and key != "RELEASE_CHECKPOINT_RPC_URL"
        and not key.startswith("DAPP_")
    }
    env["FOUNDRY_OUT"] = str(build_root / "out")
    env["FOUNDRY_CACHE_PATH"] = str(build_root / "cache")

    configured = subprocess.run(
        [forge_path, "config", "--json"],
        cwd=source_root,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    if configured.returncode != 0:
        raise SystemExit("authorized-commit Foundry configuration failed")
    config = json.loads(configured.stdout)
    expected_config = {
        "src": "src",
        "libs": ["lib"],
        "remappings": ["forge-std/=lib/forge-std/src/"],
        "auto_detect_remappings": False,
        "libraries": [],
        "allow_paths": [],
        "include_paths": [],
        "evm_version": "paris",
        "solc": "0.8.36",
        "auto_detect_solc": False,
        "optimizer": True,
        "optimizer_runs": 1,
        "via_ir": True,
        "ffi": False,
        "extra_output": [],
        "extra_output_files": [],
        "build_info": False,
        "sparse_mode": False,
        "isolate": False,
        "fs_permissions": [{"access": "read", "path": "./"}],
    }
    for key, expected in expected_config.items():
        if config.get(key) != expected:
            raise SystemExit(f"authorized-commit Foundry configuration mismatch: {key}")
    if config.get("out") != str(build_root / "out"):
        raise SystemExit("authorized-commit Foundry output is not isolated")
    if config.get("cache_path") != str(build_root / "cache"):
        raise SystemExit("authorized-commit Foundry cache is not isolated")

    built = subprocess.run(
        [
            forge_path,
            "build",
            "--force",
            "src/PulseTensorCore.sol",
            "src/PulseTensorInferenceSettlement.sol",
        ],
        cwd=source_root,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    if built.returncode != 0:
        raise SystemExit("authorized-commit production build failed")
    snapshot_core = load_artifact(
        build_root / "out" / "PulseTensorCore.sol" / "PulseTensorCore.json"
    )
    snapshot_settlement = load_artifact(
        build_root
        / "out"
        / "PulseTensorInferenceSettlement.sol"
        / "PulseTensorInferenceSettlement.json"
    )
    snapshot_bytes = {
        "Core creation": bytecode(snapshot_core, "bytecode"),
        "Core runtime": bytecode(snapshot_core, "deployedBytecode"),
        "Settlement creation": bytecode(snapshot_settlement, "bytecode"),
        "Settlement runtime": bytecode(snapshot_settlement, "deployedBytecode"),
    }
    if snapshot_bytes != expected_bytes:
        mismatches = sorted(
            label for label in expected_bytes if snapshot_bytes[label] != expected_bytes[label]
        )
        raise SystemExit(
            "authorized-commit production bytecode differs from prehashed artifacts: "
            + ", ".join(mismatches)
        )
    if artifact_profile(snapshot_core) != artifact_profile(live_core):
        raise SystemExit("authorized-commit Core compiler settings differ from live artifact")
    if artifact_profile(snapshot_settlement) != artifact_profile(live_settlement):
        raise SystemExit("authorized-commit Settlement compiler settings differ from live artifact")
    snapshot_core_references = normalized_immutable_references(
        snapshot_core["deployedBytecode"].get("immutableReferences")
    )
    live_core_references = normalized_immutable_references(
        live_core["deployedBytecode"].get("immutableReferences")
    )
    if snapshot_core_references != live_core_references or snapshot_core_references != ():
        raise SystemExit("Core immutable references differ from authorized commit")
    snapshot_settlement_references = normalized_immutable_references(
        snapshot_settlement["deployedBytecode"].get("immutableReferences")
    )
    live_settlement_references = normalized_immutable_references(
        live_settlement["deployedBytecode"].get("immutableReferences")
    )
    if snapshot_settlement_references != live_settlement_references:
        raise SystemExit("Settlement immutable references differ from authorized commit")
print("ok")
PY
  } 2>&1)" || fail "authorized-commit production rebuild failed: ${commit_snapshot_result}"
  [[ "${commit_snapshot_result}" == "ok" ]] || fail "authorized-commit production rebuild produced unexpected output"
  COMMIT_SNAPSHOT_VERIFIED=true
fi

live_gas_price_wei=""
capture_command live_gas_price_wei "reading current gas price" cast gas-price
[[ "${live_gas_price_wei}" =~ ^[1-9][0-9]*$ ]] || fail "RPC returned a non-positive gas price"
fee_budget_per_gas_wei="${MAX_FEE_PER_GAS_WEI:-${live_gas_price_wei}}"
if (( live_gas_price_wei > fee_budget_per_gas_wei )); then
  fail "current gas price exceeds the configured max fee per gas"
fi
core_gas_estimate=""
settlement_gas_estimate=""
capture_command core_gas_estimate "estimating Core deployment gas" cast estimate --create "${local_core_creation}"
capture_command settlement_gas_estimate "estimating Settlement deployment gas" cast estimate --create "${expected_settlement_creation_input}"
[[ "${core_gas_estimate}" =~ ^[1-9][0-9]*$ ]] || fail "Core gas estimate is not a positive decimal integer"
[[ "${settlement_gas_estimate}" =~ ^[1-9][0-9]*$ ]] || fail "Settlement gas estimate is not a positive decimal integer"
gas_budget_result="$({
  python3 - "${core_gas_estimate}" "${settlement_gas_estimate}" "${fee_budget_per_gas_wei}" "${GAS_ESTIMATE_MARGIN_BPS//_/}" "${sender_balance}" <<'PY'
import sys

core, settlement, fee, margin_bps, balance = map(int, sys.argv[1:])
core_limit = (core * (10_000 + margin_bps) + 9_999) // 10_000
settlement_limit = (settlement * (10_000 + margin_bps) + 9_999) // 10_000
total_limit = core_limit + settlement_limit
maximum_cost = total_limit * fee
if balance < maximum_cost:
    raise SystemExit(f"insufficient balance for both deployments plus margin: balance={balance} required={maximum_cost}")
print(core_limit, settlement_limit, total_limit, maximum_cost, sep="\t")
PY
} 2>&1)" || fail "deployment gas budget validation failed: ${gas_budget_result}"
IFS=$'\t' read -r core_gas_limit_budget settlement_gas_limit_budget total_gas_limit_budget required_balance_wei <<<"${gas_budget_result}"

checkpoint_sha256=""
checkpoint_chain_id=""
checkpoint_run_id=""
checkpoint_anchor_block_number=""
checkpoint_anchor_block_hash=""
if [[ -n "${RELEASE_CHECKPOINT}" ]]; then
  checkpoint_result="$({
    python3 - \
      "${CHECKPOINT_SNAPSHOT}" \
      "${SOURCE_COMMIT}" \
      "${PROFILE_ID}" \
      "${OPTIMIZER_RUNS}" \
      "${compiler_version}" \
      "${local_core_creation_hash}" \
      "${local_core_runtime_hash}" \
      "${local_settlement_creation_hash}" \
      "${local_settlement_template_hash}" \
      "${TOOLCHAIN_LOCK_SHA256}" \
      "${FOUNDRY_TOML_SHA256}" \
      "${forge_version}" \
      "${FORGE_SHA256}" \
      "${CAST_SHA256}" \
      "${SOLC_VERSION}" \
      "${SOLC_SHA256}" \
      "${PULSECHAIN_TESTNET_ANCHOR_BLOCK}" \
      "${PULSECHAIN_TESTNET_ANCHOR_HASH}" <<'PY'
import hashlib
import json
import sys

(
    path,
    commit,
    profile,
    runs,
    compiler,
    core_creation_hash,
    core_runtime_hash,
    settlement_creation_hash,
    settlement_template_hash,
    toolchain_lock_sha256,
    foundry_toml_sha256,
    forge_version,
    forge_sha256,
    cast_sha256,
    solc_version,
    solc_sha256,
    testnet_anchor_block,
    testnet_anchor_hash,
) = sys.argv[1:]
raw = open(path, "rb").read()
receipt = json.loads(raw)
if receipt.get("schema") != "pulsetensor/deployment-receipt/v4":
    raise SystemExit("release checkpoint has an unsupported schema")
if type(receipt.get("chain_id")) is not int or receipt["chain_id"] != 943:
    raise SystemExit("release checkpoint must be from PulseChain testnet chain 943")
if not isinstance(receipt.get("run_id"), str) or not receipt["run_id"]:
    raise SystemExit("release checkpoint run_id is invalid")
if receipt.get("verification", {}).get("passed") is not True:
    raise SystemExit("release checkpoint is not marked verified")
expected_network_anchor = {
    "block_number": int(testnet_anchor_block),
    "block_hash": testnet_anchor_hash,
}
if receipt.get("network_anchor") != expected_network_anchor:
    raise SystemExit("release checkpoint PulseChain testnet anchor mismatch")
provenance = receipt.get("provenance", {})
expected = {
    "source_commit": commit,
    "source_clean": True,
    "profile_id": profile,
    "foundry_profile": "default",
    "optimizer_runs": int(runs),
    "compiler_version": compiler,
}
for key, value in expected.items():
    if provenance.get(key) != value:
        raise SystemExit(f"release checkpoint provenance mismatch: {key}")
toolchain = provenance.get("toolchain", {})
expected_toolchain = {
    "toolchain_lock_sha256": toolchain_lock_sha256,
    "foundry_toml_sha256": foundry_toml_sha256,
    "forge_version": forge_version,
    "forge_sha256": forge_sha256,
    "cast_sha256": cast_sha256,
    "solc_version": solc_version,
    "solc_long_version": compiler,
    "solc_sha256": solc_sha256,
}
for key, value in expected_toolchain.items():
    if toolchain.get(key) != value:
        raise SystemExit(f"release checkpoint toolchain mismatch: {key}")
contracts = receipt.get("contracts", {})
core = contracts.get("core", {})
settlement = contracts.get("settlement", {})
hash_checks = {
    "Core creation bytecode": (core.get("creation_bytecode_hash"), core_creation_hash),
    "Core runtime": (core.get("expected_runtime_hash"), core_runtime_hash),
    "Settlement creation bytecode": (settlement.get("creation_bytecode_hash"), settlement_creation_hash),
    "Settlement runtime template": (settlement.get("local_runtime_template_hash"), settlement_template_hash),
}
for label, (actual, expected_hash) in hash_checks.items():
    if not isinstance(actual, str) or actual.lower() != expected_hash.lower():
        raise SystemExit(f"release checkpoint {label} hash mismatch")
confirmations = receipt.get("confirmations", {})
required = confirmations.get("required")
observed = confirmations.get("observed_at_publication")
if type(required) is not int or type(observed) is not int or required < 12 or observed < required:
    raise SystemExit("release checkpoint requires at least 12 observed confirmations")
print(hashlib.sha256(raw).hexdigest(), receipt["chain_id"], receipt["run_id"], sep="\t")
PY
  } 2>&1)" || fail "release checkpoint validation failed: ${checkpoint_result}"
  IFS=$'\t' read -r checkpoint_sha256 checkpoint_chain_id checkpoint_run_id <<<"${checkpoint_result}"
  [[ "${checkpoint_sha256}" == "${CHECKPOINT_SNAPSHOT_SHA256}" ]] || fail "release checkpoint snapshot digest changed during validation"

  checkpoint_live_chain_id=""
  checkpoint_anchor_json=""
  checkpoint_live_verification=""
  capture_command checkpoint_live_chain_id "reading release-checkpoint RPC chain ID" \
    env ETH_RPC_URL="${RELEASE_CHECKPOINT_RPC_URL}" "${CAST_BINARY_PATH}" chain-id
  [[ "${checkpoint_live_chain_id}" == "943" ]] || fail "release-checkpoint RPC must report PulseChain testnet chain 943"
  capture_command checkpoint_anchor_json "reading release-checkpoint PulseChain testnet anchor block" \
    env ETH_RPC_URL="${RELEASE_CHECKPOINT_RPC_URL}" "${CAST_BINARY_PATH}" block "${PULSECHAIN_TESTNET_ANCHOR_BLOCK}" --json
  checkpoint_anchor_result="$({
    BLOCK_JSON="${checkpoint_anchor_json}" python3 - "${PULSECHAIN_TESTNET_ANCHOR_BLOCK}" "${PULSECHAIN_TESTNET_ANCHOR_HASH}" <<'PY'
import json
import os
import re
import sys

block = json.loads(os.environ["BLOCK_JSON"])
expected_number = int(sys.argv[1])
expected_hash = sys.argv[2].lower()
number = block.get("number")
if isinstance(number, str):
    number = int(number, 16 if number.lower().startswith("0x") else 10)
if type(number) is not int or number != expected_number:
    raise SystemExit("release-checkpoint network anchor block number mismatch")
value = block.get("hash")
if not isinstance(value, str) or not re.fullmatch(r"0x[0-9a-fA-F]{64}", value):
    raise SystemExit("release-checkpoint network anchor block hash is invalid")
if value.lower() != expected_hash:
    raise SystemExit("release-checkpoint network anchor block hash mismatch")
print(number, value.lower(), sep="\t")
PY
  } 2>&1)" || fail "release-checkpoint network anchor validation failed: ${checkpoint_anchor_result}"
  IFS=$'\t' read -r checkpoint_anchor_block_number checkpoint_anchor_block_hash <<<"${checkpoint_anchor_result}"
  verify_release_inputs_unchanged
  capture_command checkpoint_live_verification "live release-checkpoint verification" \
    env ETH_RPC_URL="${RELEASE_CHECKPOINT_RPC_URL}" \
      python3 "${ROOT_DIR}/scripts/verify_deployment_receipt.py" \
        "${CHECKPOINT_SNAPSHOT}" --min-confirmations 12 --require-clean-source
  verify_release_inputs_unchanged
fi

if [[ "${EXPECTED_CHAIN_ID}" == "369" ]]; then
  [[ "$(git rev-parse --verify HEAD)" == "${SOURCE_COMMIT}" ]] || fail "git HEAD changed during preflight"
  preflight_tree_status="$(git status --porcelain=v1 --untracked-files=all)"
  [[ -z "${preflight_tree_status}" ]] || fail "git worktree changed during preflight"
fi

run_timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
run_random="$(python3 -c 'import secrets; print(secrets.token_hex(4))')"
RUN_ID="${actual_chain_id}-${run_timestamp}-${run_random}"
JOURNAL_PATH="$(mktemp "${OUTPUT_DIR}/pulsetensor_deploy_${RUN_ID}.XXXXXX.journal.jsonl")"
journal_event "preflight_complete" \
  "run_id" "${RUN_ID}" \
  "chain_id" "${actual_chain_id}" \
  "deployer" "${SENDER}" \
  "nonce_before" "${sender_nonce_before}" \
  "pending_nonce_before" "${sender_nonce_pending_before}" \
  "source_commit" "${SOURCE_COMMIT}" \
  "profile_id" "${PROFILE_ID}" \
  "commit_snapshot_verified" "${COMMIT_SNAPSHOT_VERIFIED}" \
  "toolchain_lock_sha256" "${TOOLCHAIN_LOCK_SHA256}" \
  "foundry_toml_sha256" "${FOUNDRY_TOML_SHA256}" \
  "fee_budget_per_gas_wei" "${fee_budget_per_gas_wei}" \
  "maximum_total_cost_wei" "${required_balance_wei}"
journal_event "deployment_intent" \
  "core_expected_address" "${expected_core_address}" \
  "core_nonce" "${sender_nonce_before}" \
  "core_creation_input_hash" "${core_creation_input_hash}" \
  "settlement_expected_address" "${expected_settlement_address}" \
  "settlement_nonce" "$((sender_nonce_before + 1))" \
  "settlement_creation_input_hash" "${settlement_creation_input_hash}" \
  "core_gas_estimate" "${core_gas_estimate}" \
  "core_gas_limit" "${core_gas_limit_budget}" \
  "settlement_gas_estimate" "${settlement_gas_estimate}" \
  "settlement_gas_limit" "${settlement_gas_limit_budget}"

signer_args=()
case "${SIGNER_MODE}" in
  account)
    signer_args=(--account "${ACCOUNT_NAME}")
    ;;
  keystore)
    signer_args=(--keystore "${KEYSTORE_PATH}")
    if [[ -n "${PASSWORD_FILE}" ]]; then
      signer_args+=(--password-file "${PASSWORD_FILE}")
    fi
    ;;
  ledger)
    signer_args=(--ledger)
    ;;
  trezor)
    signer_args=(--trezor)
    ;;
  aws)
    signer_args=(--aws)
    ;;
  interactive)
    signer_args=(--interactive)
    ;;
  *)
    fail "internal signer-mode error"
    ;;
esac
send_args=(--from "${SENDER}" "${signer_args[@]}" --gas-price "${fee_budget_per_gas_wei}" --async)

require_exact_nonce_state() {
  local expected="$1"
  local label="$2"
  local latest=""
  local pending=""
  capture_command latest "reading ${label} latest nonce" cast nonce "${SENDER}" --block latest
  capture_command pending "reading ${label} pending nonce" cast nonce "${SENDER}" --block pending
  [[ "${latest}" == "${expected}" && "${pending}" == "${expected}" ]] || \
    fail "${label} nonce state is not exact: expected=${expected} latest=${latest} pending=${pending}"
}

inspect_deployment_transaction() {
  local label="$1"
  local receipt_json="$2"
  local transaction_json="$3"
  local expected_hash="$4"
  local expected_address="$5"
  local expected_nonce="$6"
  local expected_input="$7"
  local result
  result="$({
    RECEIPT_JSON="${receipt_json}" TRANSACTION_JSON="${transaction_json}" EXPECTED_INPUT="${expected_input}" \
      python3 - "${label}" "${expected_hash}" "${expected_address}" "${SENDER}" "${expected_nonce}" "${actual_chain_id}" "${fee_budget_per_gas_wei}" <<'PY'
import json
import os
import re
import sys

label, expected_hash, expected_address, sender, expected_nonce, expected_chain_id, max_fee = sys.argv[1:]
receipt = json.loads(os.environ["RECEIPT_JSON"])
transaction = json.loads(os.environ["TRANSACTION_JSON"])
expected_input = os.environ["EXPECTED_INPUT"]

def integer(value):
    if isinstance(value, int):
        return value
    return int(value, 16 if str(value).lower().startswith("0x") else 10)

def same(left, right):
    return isinstance(left, str) and left.lower() == right.lower()

checks = [
    (integer(receipt.get("status")) == 1, "receipt status"),
    (same(receipt.get("transactionHash"), expected_hash), "receipt transaction hash"),
    (same(receipt.get("from"), sender), "receipt sender"),
    (same(receipt.get("contractAddress"), expected_address), "receipt contract address"),
    (same(transaction.get("hash"), expected_hash), "transaction hash"),
    (same(transaction.get("from"), sender), "transaction sender"),
    (integer(transaction.get("nonce")) == int(expected_nonce), "transaction nonce"),
    (integer(transaction.get("chainId")) == int(expected_chain_id), "transaction chain ID"),
    (transaction.get("to") in (None, "", "0x"), "contract-creation destination"),
    (same(transaction.get("input"), expected_input), "creation input"),
]
for passed, check in checks:
    if not passed:
        raise SystemExit(f"{label} {check} mismatch")
block = integer(receipt.get("blockNumber"))
block_hash = receipt.get("blockHash", "")
if not re.fullmatch(r"0x[0-9a-fA-F]{64}", block_hash):
    raise SystemExit(f"{label} receipt block hash is invalid")
gas_limit = integer(transaction.get("gas"))
gas_used = integer(receipt.get("gasUsed"))
effective_gas_price = integer(receipt.get("effectiveGasPrice"))
if gas_limit <= 0 or gas_used <= 0 or gas_used > gas_limit:
    raise SystemExit(f"{label} gas accounting is invalid")
if effective_gas_price <= 0 or effective_gas_price > int(max_fee):
    raise SystemExit(f"{label} effective gas price exceeds the configured cap")
print(block, block_hash, gas_limit, gas_used, effective_gas_price, sep="\t")
PY
  } 2>&1)" || fail "${label} transaction validation failed: ${result}"
  printf '%s' "${result}"
}

CURRENT_STAGE="core_broadcast"
require_exact_nonce_state "${sender_nonce_before}" "pre-Core"
journal_event "core_broadcast_intent" \
  "expected_address" "${expected_core_address}" \
  "nonce" "${sender_nonce_before}" \
  "creation_input_hash" "${core_creation_input_hash}" \
  "gas_estimate" "${core_gas_estimate}" \
  "gas_limit" "${core_gas_limit_budget}" \
  "max_fee_per_gas_wei" "${fee_budget_per_gas_wei}"
verify_release_inputs_unchanged
core_creation_recheck_hash=""
capture_command core_creation_recheck_hash "rehashing exact Core creation input before signing" cast keccak "${local_core_creation}"
[[ "${core_creation_recheck_hash,,}" == "${core_creation_input_hash,,}" ]] || fail "Core creation input changed immediately before signing"
echo "Deploying PulseTensorCore on chain ${actual_chain_id}..."
core_submission_output=""
capture_command core_submission_output "PulseTensorCore exact-initcode submission" \
  cast send "${send_args[@]}" \
    --nonce "${sender_nonce_before}" \
    --gas-limit "${core_gas_limit_budget}" \
    --create "${local_core_creation}"
core_tx_hash="$(extract_submission_hash "Core" "${core_submission_output}")"
[[ "${core_tx_hash}" =~ ^0x[0-9a-fA-F]{64}$ ]] || fail "unable to parse PulseTensorCore transaction hash"
core_address="${expected_core_address}"
journal_event "core_broadcast" "transaction_hash" "${core_tx_hash}" "contract_address" "${core_address}" "nonce" "${sender_nonce_before}"
printf '  expected_address: %s\n  transaction_hash: %s\n' "${core_address}" "${core_tx_hash}"

core_receipt_json=""
core_transaction_json=""
wait_for_receipt core_receipt_json "waiting for Core transaction receipt" cast receipt --async --json "${core_tx_hash}"
capture_command core_transaction_json "reading Core transaction" cast tx --json "${core_tx_hash}"
core_tx_validation="$(inspect_deployment_transaction "Core" "${core_receipt_json}" "${core_transaction_json}" "${core_tx_hash}" "${core_address}" "${sender_nonce_before}" "${local_core_creation}")"
IFS=$'\t' read -r core_block_number core_block_hash core_gas_limit core_gas_used core_effective_gas_price <<<"${core_tx_validation}"
[[ "${core_gas_limit}" == "${core_gas_limit_budget}" ]] || fail "Core transaction gas limit differs from the preflight budget"

deployed_core_code=""
capture_command deployed_core_code "reading deployed Core code" cast code "${core_address}"
[[ "${deployed_core_code,,}" == "${local_core_runtime,,}" ]] || fail "deployed Core runtime bytecode differs from the local artifact"
deployed_core_runtime_hash=""
capture_command deployed_core_runtime_hash "hashing deployed Core runtime" cast keccak "${deployed_core_code}"
[[ "${deployed_core_runtime_hash,,}" == "${local_core_runtime_hash,,}" ]] || fail "deployed Core runtime hash mismatch"
journal_event "core_verified" "block_number" "${core_block_number}" "block_hash" "${core_block_hash}" "runtime_hash" "${deployed_core_runtime_hash}"

sender_nonce_after_core="$((sender_nonce_before + 1))"
require_exact_nonce_state "${sender_nonce_after_core}" "post-Core"
chain_id_after_core=""
capture_command chain_id_after_core "rechecking chain ID before Settlement deployment" cast chain-id
[[ "${chain_id_after_core}" == "${actual_chain_id}" ]] || fail "RPC chain ID changed during deployment"
verify_release_inputs_unchanged

expected_settlement_runtime="$({
  python3 - "${settlement_artifact}" "${core_address}" <<'PY'
import json
import re
import sys

artifact = json.load(open(sys.argv[1], encoding="utf-8"))
address = sys.argv[2]
if not re.fullmatch(r"0x[0-9a-fA-F]{40}", address):
    raise SystemExit("invalid immutable Core address")
deployed = artifact.get("deployedBytecode", {})
bytecode = deployed.get("object", "")
references = deployed.get("immutableReferences", {})
if not bytecode or not references or len(references) != 1:
    raise SystemExit("Settlement artifact must contain one immutable reference group")
raw = bytearray.fromhex(bytecode.removeprefix("0x"))
replacement = bytes.fromhex(address[2:].rjust(64, "0"))
locations = next(iter(references.values()))
if not locations:
    raise SystemExit("Settlement immutable reference group is empty")
for location in locations:
    start = location.get("start")
    length = location.get("length")
    if not isinstance(start, int) or length != 32 or start < 0 or start + length > len(raw):
        raise SystemExit("Settlement immutable reference metadata is invalid")
    raw[start:start + length] = replacement
print("0x" + raw.hex())
PY
} 2>&1)" || fail "rendering exact Settlement runtime failed: ${expected_settlement_runtime}"
expected_settlement_runtime_hash=""
capture_command expected_settlement_runtime_hash "hashing expected Settlement runtime" cast keccak "${expected_settlement_runtime}"
linked_core_address_word="$(printf '%064s' "${core_address#0x}" | tr ' ' '0')"
[[ "${local_settlement_creation}${linked_core_address_word}" == "${expected_settlement_creation_input}" ]] || fail "Settlement creation input changed after Core deployment"

CURRENT_STAGE="settlement_broadcast"
require_exact_nonce_state "$((sender_nonce_before + 1))" "pre-Settlement"
journal_event "settlement_broadcast_intent" \
  "expected_address" "${expected_settlement_address}" \
  "nonce" "$((sender_nonce_before + 1))" \
  "creation_input_hash" "${settlement_creation_input_hash}" \
  "core_binding" "${core_address}" \
  "gas_estimate" "${settlement_gas_estimate}" \
  "gas_limit" "${settlement_gas_limit_budget}" \
  "max_fee_per_gas_wei" "${fee_budget_per_gas_wei}"
verify_release_inputs_unchanged
settlement_creation_recheck_hash=""
capture_command settlement_creation_recheck_hash "rehashing exact Settlement creation input before signing" cast keccak "${expected_settlement_creation_input}"
[[ "${settlement_creation_recheck_hash,,}" == "${settlement_creation_input_hash,,}" ]] || fail "Settlement creation input changed immediately before signing"
echo "Deploying PulseTensorInferenceSettlement..."
settlement_submission_output=""
capture_command settlement_submission_output "PulseTensorInferenceSettlement exact-initcode submission" \
  cast send "${send_args[@]}" \
    --nonce "$((sender_nonce_before + 1))" \
    --gas-limit "${settlement_gas_limit_budget}" \
    --create "${expected_settlement_creation_input}"
settlement_tx_hash="$(extract_submission_hash "Settlement" "${settlement_submission_output}")"
[[ "${settlement_tx_hash}" =~ ^0x[0-9a-fA-F]{64}$ ]] || fail "unable to parse Settlement transaction hash"
settlement_address="${expected_settlement_address}"
journal_event "settlement_broadcast" "transaction_hash" "${settlement_tx_hash}" "contract_address" "${settlement_address}" "nonce" "$((sender_nonce_before + 1))"
printf '  expected_address: %s\n  transaction_hash: %s\n' "${settlement_address}" "${settlement_tx_hash}"

settlement_receipt_json=""
settlement_transaction_json=""
wait_for_receipt settlement_receipt_json "waiting for Settlement transaction receipt" cast receipt --async --json "${settlement_tx_hash}"
capture_command settlement_transaction_json "reading Settlement transaction" cast tx --json "${settlement_tx_hash}"
settlement_tx_validation="$(inspect_deployment_transaction "Settlement" "${settlement_receipt_json}" "${settlement_transaction_json}" "${settlement_tx_hash}" "${settlement_address}" "$((sender_nonce_before + 1))" "${expected_settlement_creation_input}")"
IFS=$'\t' read -r settlement_block_number settlement_block_hash settlement_gas_limit settlement_gas_used settlement_effective_gas_price <<<"${settlement_tx_validation}"
[[ "${settlement_gas_limit}" == "${settlement_gas_limit_budget}" ]] || fail "Settlement transaction gas limit differs from the preflight budget"

deployed_settlement_code=""
capture_command deployed_settlement_code "reading deployed Settlement code" cast code "${settlement_address}"
[[ "${deployed_settlement_code,,}" == "${expected_settlement_runtime,,}" ]] || fail "deployed Settlement runtime differs from the immutable-linked local artifact"
deployed_settlement_runtime_hash=""
capture_command deployed_settlement_runtime_hash "hashing deployed Settlement runtime" cast keccak "${deployed_settlement_code}"
[[ "${deployed_settlement_runtime_hash,,}" == "${expected_settlement_runtime_hash,,}" ]] || fail "deployed Settlement runtime hash mismatch"
configured_core=""
capture_command configured_core "reading Settlement CORE binding" cast call "${settlement_address}" 'CORE()(address)'
[[ "${configured_core,,}" == "${core_address,,}" ]] || fail "Settlement CORE binding mismatch"

sender_nonce_after="$((sender_nonce_before + 2))"
require_exact_nonce_state "${sender_nonce_after}" "post-Settlement"
verify_release_inputs_unchanged
journal_event "settlement_verified" "block_number" "${settlement_block_number}" "block_hash" "${settlement_block_hash}" "runtime_hash" "${deployed_settlement_runtime_hash}"

CURRENT_STAGE="confirmation_wait"
last_deployment_block="${core_block_number}"
if (( settlement_block_number > last_deployment_block )); then
  last_deployment_block="${settlement_block_number}"
fi
target_block="$((last_deployment_block + CONFIRMATIONS - 1))"
deadline="$((SECONDS + CONFIRMATION_TIMEOUT_SECONDS))"
journal_event "confirmation_wait" "required" "${CONFIRMATIONS}" "target_block" "${target_block}"
while true; do
  confirmed_at_block=""
  capture_command confirmed_at_block "reading confirmation head" cast block-number
  if (( confirmed_at_block >= target_block )); then
    break
  fi
  if (( SECONDS >= deadline )); then
    fail "confirmation wait timed out before block ${target_block}"
  fi
  sleep "${CONFIRMATION_POLL_SECONDS}"
done

CURRENT_STAGE="final_recheck"
final_chain_id=""
capture_command final_chain_id "final chain ID recheck" cast chain-id
[[ "${final_chain_id}" == "${actual_chain_id}" ]] || fail "RPC chain ID changed before final verification"
core_receipt_recheck=""
core_transaction_recheck=""
settlement_receipt_recheck=""
settlement_transaction_recheck=""
capture_command core_receipt_recheck "rechecking Core receipt" cast receipt --json "${core_tx_hash}"
capture_command core_transaction_recheck "rechecking Core transaction" cast tx --json "${core_tx_hash}"
capture_command settlement_receipt_recheck "rechecking Settlement receipt" cast receipt --json "${settlement_tx_hash}"
capture_command settlement_transaction_recheck "rechecking Settlement transaction" cast tx --json "${settlement_tx_hash}"
core_tx_recheck="$(inspect_deployment_transaction "Core" "${core_receipt_recheck}" "${core_transaction_recheck}" "${core_tx_hash}" "${core_address}" "${sender_nonce_before}" "${local_core_creation}")"
settlement_tx_recheck="$(inspect_deployment_transaction "Settlement" "${settlement_receipt_recheck}" "${settlement_transaction_recheck}" "${settlement_tx_hash}" "${settlement_address}" "$((sender_nonce_before + 1))" "${expected_settlement_creation_input}")"
[[ "${core_tx_recheck}" == "${core_tx_validation}" ]] || fail "Core receipt block changed during confirmation wait"
[[ "${settlement_tx_recheck}" == "${settlement_tx_validation}" ]] || fail "Settlement receipt block changed during confirmation wait"
capture_command deployed_core_code "final Core code recheck" cast code "${core_address}"
capture_command deployed_settlement_code "final Settlement code recheck" cast code "${settlement_address}"
[[ "${deployed_core_code,,}" == "${local_core_runtime,,}" ]] || fail "Core runtime changed during confirmation wait"
[[ "${deployed_settlement_code,,}" == "${expected_settlement_runtime,,}" ]] || fail "Settlement runtime changed during confirmation wait"
capture_command configured_core "final Settlement CORE binding recheck" cast call "${settlement_address}" 'CORE()(address)'
[[ "${configured_core,,}" == "${core_address,,}" ]] || fail "Settlement CORE binding changed during confirmation wait"
require_exact_nonce_state "$((sender_nonce_before + 2))" "final"
sender_nonce_after="$((sender_nonce_before + 2))"
verify_release_inputs_unchanged

confirmations_observed="$((confirmed_at_block - last_deployment_block + 1))"
generated_at_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
journal_name="$(basename -- "${JOURNAL_PATH}")"
RECEIPT_TEMP="$(mktemp "${OUTPUT_DIR}/.pulsetensor_deploy_${RUN_ID}.XXXXXX.receipt.tmp")"

GENERATED_AT_UTC="${generated_at_utc}" \
RUN_ID="${RUN_ID}" \
CHAIN_ID="${actual_chain_id}" \
DEPLOYER="${SENDER}" \
NETWORK_ANCHOR_BLOCK_NUMBER="${network_anchor_block_number}" \
NETWORK_ANCHOR_BLOCK_HASH="${network_anchor_block_hash}" \
CORE_ADDRESS="${core_address}" \
CORE_TX_HASH="${core_tx_hash}" \
CORE_TX_NONCE="${sender_nonce_before}" \
CORE_GAS_ESTIMATE="${core_gas_estimate}" \
CORE_GAS_LIMIT="${core_gas_limit}" \
CORE_GAS_USED="${core_gas_used}" \
CORE_EFFECTIVE_GAS_PRICE="${core_effective_gas_price}" \
CORE_BLOCK_NUMBER="${core_block_number}" \
CORE_BLOCK_HASH="${core_block_hash}" \
CORE_CREATION_HASH="${local_core_creation_hash}" \
CORE_CREATION_INPUT_HASH="${core_creation_input_hash}" \
CORE_EXPECTED_HASH="${local_core_runtime_hash}" \
CORE_DEPLOYED_HASH="${deployed_core_runtime_hash}" \
SETTLEMENT_ADDRESS="${settlement_address}" \
SETTLEMENT_TX_HASH="${settlement_tx_hash}" \
SETTLEMENT_TX_NONCE="$((sender_nonce_before + 1))" \
SETTLEMENT_GAS_ESTIMATE="${settlement_gas_estimate}" \
SETTLEMENT_GAS_LIMIT="${settlement_gas_limit}" \
SETTLEMENT_GAS_USED="${settlement_gas_used}" \
SETTLEMENT_EFFECTIVE_GAS_PRICE="${settlement_effective_gas_price}" \
SETTLEMENT_BLOCK_NUMBER="${settlement_block_number}" \
SETTLEMENT_BLOCK_HASH="${settlement_block_hash}" \
SETTLEMENT_CREATION_HASH="${local_settlement_creation_hash}" \
SETTLEMENT_CREATION_INPUT_HASH="${settlement_creation_input_hash}" \
SETTLEMENT_TEMPLATE_HASH="${local_settlement_template_hash}" \
SETTLEMENT_EXPECTED_HASH="${expected_settlement_runtime_hash}" \
SETTLEMENT_DEPLOYED_HASH="${deployed_settlement_runtime_hash}" \
NONCE_BEFORE="${sender_nonce_before}" \
PENDING_NONCE_BEFORE="${sender_nonce_pending_before}" \
NONCE_AFTER="${sender_nonce_after}" \
SENDER_BALANCE_BEFORE="${sender_balance}" \
MAX_FEE_PER_GAS_WEI="${fee_budget_per_gas_wei}" \
GAS_MARGIN_BPS="${GAS_ESTIMATE_MARGIN_BPS//_/}" \
REQUIRED_BALANCE_WEI="${required_balance_wei}" \
CONFIRMATIONS_REQUIRED="${CONFIRMATIONS}" \
CONFIRMED_AT_BLOCK="${confirmed_at_block}" \
CONFIRMATIONS_OBSERVED="${confirmations_observed}" \
SOURCE_COMMIT="${SOURCE_COMMIT}" \
SOURCE_CLEAN="${SOURCE_CLEAN}" \
PROFILE_ID="${PROFILE_ID}" \
FOUNDRY_PROFILE_ACTIVE="${FOUNDRY_PROFILE_ACTIVE}" \
OPTIMIZER_RUNS="${OPTIMIZER_RUNS}" \
COMPILER_VERSION="${compiler_version}" \
FORGE_VERSION="${forge_version}" \
TOOLCHAIN_LOCK_SHA256="${TOOLCHAIN_LOCK_SHA256}" \
FOUNDRY_TOML_SHA256="${FOUNDRY_TOML_SHA256}" \
FORGE_SHA256="${FORGE_SHA256}" \
CAST_SHA256="${CAST_SHA256}" \
SOLC_VERSION="${SOLC_VERSION}" \
SOLC_SHA256="${SOLC_SHA256}" \
CORE_ARTIFACT_SHA256="${core_artifact_sha256}" \
SETTLEMENT_ARTIFACT_SHA256="${settlement_artifact_sha256}" \
CHECKPOINT_SHA256="${checkpoint_sha256}" \
CHECKPOINT_CHAIN_ID="${checkpoint_chain_id}" \
CHECKPOINT_RUN_ID="${checkpoint_run_id}" \
CHECKPOINT_ANCHOR_BLOCK_NUMBER="${checkpoint_anchor_block_number}" \
CHECKPOINT_ANCHOR_BLOCK_HASH="${checkpoint_anchor_block_hash}" \
JOURNAL_NAME="${journal_name}" \
python3 - "${RECEIPT_TEMP}" <<'PY'
import json
import os
import sys

def optional(value):
    return value or None

def optional_anchor(block_number, block_hash):
    if not block_number and not block_hash:
        return None
    if not block_number or not block_hash:
        raise SystemExit("incomplete network anchor evidence")
    return {"block_number": int(block_number), "block_hash": block_hash}

receipt = {
    "schema": "pulsetensor/deployment-receipt/v4",
    "generated_at_utc": os.environ["GENERATED_AT_UTC"],
    "run_id": os.environ["RUN_ID"],
    "chain_id": int(os.environ["CHAIN_ID"]),
    "deployer": os.environ["DEPLOYER"],
    "network_anchor": optional_anchor(
        os.environ["NETWORK_ANCHOR_BLOCK_NUMBER"],
        os.environ["NETWORK_ANCHOR_BLOCK_HASH"],
    ),
    "deployer_nonce_before": int(os.environ["NONCE_BEFORE"]),
    "deployer_nonce_after": int(os.environ["NONCE_AFTER"]),
    "nonce_policy": {
        "latest_before": int(os.environ["NONCE_BEFORE"]),
        "pending_before": int(os.environ["PENDING_NONCE_BEFORE"]),
        "core_nonce": int(os.environ["CORE_TX_NONCE"]),
        "settlement_nonce": int(os.environ["SETTLEMENT_TX_NONCE"]),
        "latest_after": int(os.environ["NONCE_AFTER"]),
        "pending_after": int(os.environ["NONCE_AFTER"]),
        "explicit_nonces_used": True,
    },
    "contracts": {
        "core": {
            "address": os.environ["CORE_ADDRESS"],
            "transaction_hash": os.environ["CORE_TX_HASH"],
            "nonce": int(os.environ["CORE_TX_NONCE"]),
            "gas_estimate": int(os.environ["CORE_GAS_ESTIMATE"]),
            "gas_limit": int(os.environ["CORE_GAS_LIMIT"]),
            "gas_used": int(os.environ["CORE_GAS_USED"]),
            "effective_gas_price_wei": int(os.environ["CORE_EFFECTIVE_GAS_PRICE"]),
            "block_number": int(os.environ["CORE_BLOCK_NUMBER"]),
            "block_hash": os.environ["CORE_BLOCK_HASH"],
            "creation_bytecode_hash": os.environ["CORE_CREATION_HASH"],
            "creation_transaction_input_hash": os.environ["CORE_CREATION_INPUT_HASH"],
            "expected_runtime_hash": os.environ["CORE_EXPECTED_HASH"],
            "deployed_runtime_hash": os.environ["CORE_DEPLOYED_HASH"],
        },
        "settlement": {
            "address": os.environ["SETTLEMENT_ADDRESS"],
            "transaction_hash": os.environ["SETTLEMENT_TX_HASH"],
            "nonce": int(os.environ["SETTLEMENT_TX_NONCE"]),
            "gas_estimate": int(os.environ["SETTLEMENT_GAS_ESTIMATE"]),
            "gas_limit": int(os.environ["SETTLEMENT_GAS_LIMIT"]),
            "gas_used": int(os.environ["SETTLEMENT_GAS_USED"]),
            "effective_gas_price_wei": int(os.environ["SETTLEMENT_EFFECTIVE_GAS_PRICE"]),
            "block_number": int(os.environ["SETTLEMENT_BLOCK_NUMBER"]),
            "block_hash": os.environ["SETTLEMENT_BLOCK_HASH"],
            "creation_bytecode_hash": os.environ["SETTLEMENT_CREATION_HASH"],
            "creation_transaction_input_hash": os.environ["SETTLEMENT_CREATION_INPUT_HASH"],
            "local_runtime_template_hash": os.environ["SETTLEMENT_TEMPLATE_HASH"],
            "expected_runtime_hash": os.environ["SETTLEMENT_EXPECTED_HASH"],
            "deployed_runtime_hash": os.environ["SETTLEMENT_DEPLOYED_HASH"],
            "core_binding": os.environ["CORE_ADDRESS"],
        },
    },
    "confirmations": {
        "required": int(os.environ["CONFIRMATIONS_REQUIRED"]),
        "confirmed_at_block": int(os.environ["CONFIRMED_AT_BLOCK"]),
        "observed_at_publication": int(os.environ["CONFIRMATIONS_OBSERVED"]),
    },
    "provenance": {
        "source_commit": os.environ["SOURCE_COMMIT"],
        "source_clean": os.environ["SOURCE_CLEAN"] == "true",
        "profile_id": os.environ["PROFILE_ID"],
        "foundry_profile": os.environ["FOUNDRY_PROFILE_ACTIVE"],
        "optimizer_runs": int(os.environ["OPTIMIZER_RUNS"]),
        "compiler_version": os.environ["COMPILER_VERSION"],
        "forge_version": os.environ["FORGE_VERSION"],
        "toolchain": {
            "toolchain_lock_sha256": os.environ["TOOLCHAIN_LOCK_SHA256"],
            "foundry_toml_sha256": os.environ["FOUNDRY_TOML_SHA256"],
            "forge_version": os.environ["FORGE_VERSION"],
            "forge_sha256": os.environ["FORGE_SHA256"],
            "cast_sha256": os.environ["CAST_SHA256"],
            "solc_version": os.environ["SOLC_VERSION"],
            "solc_long_version": os.environ["COMPILER_VERSION"],
            "solc_sha256": os.environ["SOLC_SHA256"],
        },
        "artifacts": {
            "core_artifact_sha256": os.environ["CORE_ARTIFACT_SHA256"],
            "settlement_artifact_sha256": os.environ["SETTLEMENT_ARTIFACT_SHA256"],
        },
        "release_checkpoint": {
            "sha256": optional(os.environ["CHECKPOINT_SHA256"]),
            "chain_id": int(os.environ["CHECKPOINT_CHAIN_ID"]) if os.environ["CHECKPOINT_CHAIN_ID"] else None,
            "run_id": optional(os.environ["CHECKPOINT_RUN_ID"]),
            "network_anchor": optional_anchor(
                os.environ["CHECKPOINT_ANCHOR_BLOCK_NUMBER"],
                os.environ["CHECKPOINT_ANCHOR_BLOCK_HASH"],
            ),
            "live_reverified": bool(os.environ["CHECKPOINT_SHA256"]),
        },
    },
    "verification": {
        "passed": True,
        "chain_id_rechecked": True,
        "transaction_receipts_rechecked": True,
        "sender_and_nonce_sequence_checked": True,
        "exact_runtime_bytecode_checked": True,
        "immutable_core_binding_checked": True,
    },
    "partial_journal": os.environ["JOURNAL_NAME"],
}

if receipt["chain_id"] == 369:
    receipt["gas_budget"] = {
        "max_fee_per_gas_wei": int(os.environ["MAX_FEE_PER_GAS_WEI"]),
        "core_estimated_gas": int(os.environ["CORE_GAS_ESTIMATE"]),
        "settlement_estimated_gas": int(os.environ["SETTLEMENT_GAS_ESTIMATE"]),
        "margin_bps": int(os.environ["GAS_MARGIN_BPS"]),
        "maximum_total_cost_wei": int(os.environ["REQUIRED_BALANCE_WEI"]),
        "deployer_balance_before_wei": int(os.environ["SENDER_BALANCE_BEFORE"]),
    }

with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(receipt, handle, indent=2, sort_keys=True)
    handle.write("\n")
    handle.flush()
    os.fsync(handle.fileno())
PY

verifier_output=""
receipt_verifier_args=(
  "${RECEIPT_TEMP}"
  --min-confirmations "${CONFIRMATIONS}"
  --require-current-nonce
)
if [[ "${EXPECTED_CHAIN_ID}" == "369" ]]; then
  receipt_verifier_args+=(
    --require-clean-source
    --release-checkpoint "${CHECKPOINT_SNAPSHOT}"
  )
fi
if [[ "${EXPECTED_CHAIN_ID}" == "369" ]]; then
  capture_command verifier_output "independent deployment receipt verification" \
    env RELEASE_CHECKPOINT_RPC_URL="${RELEASE_CHECKPOINT_RPC_URL}" \
      python3 "${ROOT_DIR}/scripts/verify_deployment_receipt.py" "${receipt_verifier_args[@]}"
else
  capture_command verifier_output "independent deployment receipt verification" \
    python3 "${ROOT_DIR}/scripts/verify_deployment_receipt.py" "${receipt_verifier_args[@]}"
fi
verify_release_inputs_unchanged

receipt_path="${OUTPUT_DIR}/pulsetensor_deploy_${RUN_ID}_${core_tx_hash:2:10}.receipt.json"
python3 - "${RECEIPT_TEMP}" "${receipt_path}" <<'PY'
import os
import sys

source, destination = sys.argv[1:]
try:
    os.link(source, destination)
except FileExistsError as exc:
    raise SystemExit(f"refusing to overwrite existing receipt: {destination}") from exc
os.unlink(source)
directory = os.open(os.path.dirname(destination) or ".", os.O_RDONLY)
try:
    os.fsync(directory)
finally:
    os.close(directory)
PY
RECEIPT_TEMP=""
journal_event "receipt_published" "receipt" "$(basename -- "${receipt_path}")" "confirmations_observed" "${confirmations_observed}"

SUCCESS=1
CURRENT_STAGE="complete"
echo "Deployment complete and independently reverified:"
echo "  core_address: ${core_address}"
echo "  settlement_address: ${settlement_address}"
echo "  receipt: ${receipt_path}"
echo "  partial_journal: ${JOURNAL_PATH}"
echo "  verification: ${verifier_output}"
echo "The deployer and both transactions are public. Do not reuse this wallet for personal holdings."
popd >/dev/null

#!/usr/bin/env bash
set -euo pipefail

umask 077

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RPC_URL="${RPC_URL:-}"
OPTIMIZER_RUNS="${FOUNDRY_OPTIMIZER_RUNS:-1}"
OUTPUT_DIR="${ROOT_DIR}/runs/deployments"
EXPECTED_CHAIN_ID=""

SIGNER_MODE=""
ACCOUNT_NAME=""
KEYSTORE_PATH=""
PASSWORD_FILE=""
FROM_ADDRESS=""
DERIVATION_PATH=""
LOCAL_TEST_PRIVATE_KEY="${PULSETENSOR_LOCAL_TEST_PRIVATE_KEY:-}"

usage() {
  cat <<'EOF'
Usage: bash scripts/deploy_pulsetensor.sh [options]

Deploys:
  - PulseTensorCore
  - PulseTensorInferenceSettlement (constructor arg: core address)

Connection and output:
  --rpc-url <url>          RPC URL (or set RPC_URL env var)
  --expected-chain-id <id> Required live-chain confirmation (PulseChain: 369; testnet v4: 943)
  --out-dir <path>         Output directory for deployment receipt

Choose exactly one signer when broadcasting:
  --account <name>         Foundry account in ~/.foundry/keystores
  --keystore <path>        Encrypted JSON keystore file
  --password-file <path>   Password file for --account or --keystore
  --ledger                 Ledger hardware signer
  --trezor                 Trezor hardware signer
  --aws                    AWS KMS signer configured through the AWS SDK
  --interactive            Read a private key from Foundry's hidden prompt

Signer selection:
  --from <address>         Expected/specific signer address (recommended for hardware/KMS)
  --derivation-path <path> Hardware-wallet derivation path

Other:
  --help                   Show help

Environment:
  FOUNDRY_OPTIMIZER_RUNS   Must be exactly 1, matching the attested deploy profile

Local-test-only escape hatch:
  PULSETENSOR_LOCAL_TEST_PRIVATE_KEY may hold a deterministic Anvil key. The
  script accepts it only for a loopback RPC whose live chain ID is 31337. It is
  rejected for every production or public-network deployment.

Raw private keys and mnemonics are intentionally not accepted as production
CLI arguments or production environment variables.

Output:
  runs/deployments/pulsetensor_deploy_receipt.json
EOF
}

fail() {
  echo "deploy: ERROR: $*" >&2
  exit 1
}

select_signer() {
  local requested="$1"
  if [[ -n "${SIGNER_MODE}" ]]; then
    fail "choose exactly one signer; both ${SIGNER_MODE} and ${requested} were requested"
  fi
  SIGNER_MODE="${requested}"
}

is_loopback_rpc() {
  python3 - "${RPC_URL}" <<'PY'
import ipaddress
import sys
from urllib.parse import urlsplit

try:
    parsed = urlsplit(sys.argv[1])
    host = parsed.hostname
except ValueError:
    raise SystemExit(1)

if not host:
    raise SystemExit(1)
if host.lower() == "localhost":
    raise SystemExit(0)
try:
    raise SystemExit(0 if ipaddress.ip_address(host).is_loopback else 1)
except ValueError:
    raise SystemExit(1)
PY
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rpc-url)
      [[ $# -ge 2 ]] || fail "--rpc-url requires a value"
      RPC_URL="$2"
      shift 2
      ;;
    --out-dir)
      [[ $# -ge 2 ]] || fail "--out-dir requires a value"
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --expected-chain-id)
      [[ $# -ge 2 ]] || fail "--expected-chain-id requires a value"
      EXPECTED_CHAIN_ID="$2"
      shift 2
      ;;
    --account)
      [[ $# -ge 2 ]] || fail "--account requires a value"
      select_signer "account"
      ACCOUNT_NAME="$2"
      shift 2
      ;;
    --keystore)
      [[ $# -ge 2 ]] || fail "--keystore requires a value"
      select_signer "keystore"
      KEYSTORE_PATH="$2"
      shift 2
      ;;
    --password-file)
      [[ $# -ge 2 ]] || fail "--password-file requires a value"
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
    --from)
      [[ $# -ge 2 ]] || fail "--from requires a value"
      FROM_ADDRESS="$2"
      shift 2
      ;;
    --derivation-path)
      [[ $# -ge 2 ]] || fail "--derivation-path requires a value"
      DERIVATION_PATH="$2"
      shift 2
      ;;
    --private-key|--mnemonic|--password)
      fail "$1 is intentionally unsupported; use an encrypted keystore, hardware/KMS signer, or --interactive"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1 (run with --help)"
      ;;
  esac
done

[[ -n "${RPC_URL}" ]] || fail "RPC URL is required; set RPC_URL or pass --rpc-url"
[[ "${EXPECTED_CHAIN_ID}" =~ ^[0-9]+$ ]] || fail "--expected-chain-id is required and must be an integer"
[[ "${OPTIMIZER_RUNS}" == "1" ]] || fail \
  "FOUNDRY_OPTIMIZER_RUNS must be exactly 1 to match the attested, size-checked deployment profile"

for legacy_secret_var in PRIVATE_KEY ETH_PRIVATE_KEY MNEMONIC ETH_MNEMONIC MNEMONIC_PATH ETH_MNEMONIC_PATH; do
  if [[ -n "${!legacy_secret_var+x}" ]]; then
    fail "${legacy_secret_var} is not accepted; remove it and select a protected signer explicitly"
  fi
done

if [[ -n "${LOCAL_TEST_PRIVATE_KEY}" ]]; then
  select_signer "local-test-key"
fi

if [[ -z "${SIGNER_MODE}" ]]; then
  fail "broadcasting requires exactly one protected signer (run with --help)"
fi

if [[ -n "${PASSWORD_FILE}" ]]; then
  if [[ "${SIGNER_MODE}" != "account" && "${SIGNER_MODE}" != "keystore" ]]; then
    fail "--password-file is valid only with --account or --keystore"
  fi
  [[ -f "${PASSWORD_FILE}" && -r "${PASSWORD_FILE}" ]] || fail "password file must be a readable regular file"
  password_mode="$(stat -c '%a' "${PASSWORD_FILE}" 2>/dev/null || true)"
  if [[ -z "${password_mode}" || ! "${password_mode}" =~ ^[0-7]*[046]00$ ]]; then
    fail "password file permissions must not grant group/other access (use chmod 600)"
  fi
fi
if [[ "${SIGNER_MODE}" == "keystore" ]]; then
  [[ -f "${KEYSTORE_PATH}" && -r "${KEYSTORE_PATH}" ]] || fail "--keystore must name a readable regular file"
fi
if [[ -n "${DERIVATION_PATH}" && "${SIGNER_MODE}" != "ledger" && "${SIGNER_MODE}" != "trezor" ]]; then
  fail "--derivation-path is valid only with --ledger or --trezor"
fi
if [[ "${SIGNER_MODE}" == "local-test-key" ]] && ! is_loopback_rpc; then
  fail "PULSETENSOR_LOCAL_TEST_PRIVATE_KEY is restricted to a loopback RPC"
fi

# Do not let inherited Foundry wallet variables silently select or alter a signer.
unset ETH_KEYSTORE ETH_KEYSTORE_ACCOUNT ETH_PASSWORD ETH_FROM

CHAIN_ID="$(cast chain-id --rpc-url "${RPC_URL}" 2>/dev/null)" || fail "unable to read chain ID from RPC"
CHAIN_ID="$(printf '%s\n' "${CHAIN_ID}" | awk '{print $1}')"
[[ "${CHAIN_ID}" =~ ^[0-9]+$ ]] || fail "RPC returned an invalid chain ID"
if [[ "${CHAIN_ID}" != "${EXPECTED_CHAIN_ID}" ]]; then
  fail "live chain ID ${CHAIN_ID} does not match --expected-chain-id ${EXPECTED_CHAIN_ID}"
fi
if [[ "${SIGNER_MODE}" == "local-test-key" && "${CHAIN_ID}" != "31337" ]]; then
  fail "PULSETENSOR_LOCAL_TEST_PRIVATE_KEY is restricted to chain ID 31337 (RPC reported ${CHAIN_ID})"
fi

signer_args=()
case "${SIGNER_MODE}" in
  account)
    signer_args+=(--account "${ACCOUNT_NAME}")
    ;;
  keystore)
    signer_args+=(--keystore "${KEYSTORE_PATH}")
    ;;
  ledger)
    signer_args+=(--ledger)
    ;;
  trezor)
    signer_args+=(--trezor)
    ;;
  aws)
    signer_args+=(--aws)
    ;;
  interactive)
    signer_args+=(--interactive)
    ;;
  local-test-key)
    signer_args+=(--private-key "${LOCAL_TEST_PRIVATE_KEY}")
    ;;
  "")
    ;;
  *)
    fail "internal signer selection error"
    ;;
esac
if [[ -n "${PASSWORD_FILE}" ]]; then
  signer_args+=(--password-file "${PASSWORD_FILE}")
fi
if [[ -n "${FROM_ADDRESS}" ]]; then
  signer_args+=(--from "${FROM_ADDRESS}")
fi
if [[ -n "${DERIVATION_PATH}" ]]; then
  signer_args+=(--mnemonic-derivation-path "${DERIVATION_PATH}")
fi

mkdir -p "${OUTPUT_DIR}"
[[ -d "${OUTPUT_DIR}" && ! -L "${OUTPUT_DIR}" ]] || fail \
  "deployment output path must be a real directory: ${OUTPUT_DIR}"
chmod 700 "${OUTPUT_DIR}"
RECEIPT_PATH="${OUTPUT_DIR}/pulsetensor_deploy_receipt.json"
PARTIAL_RECEIPT_PATH="${OUTPUT_DIR}/pulsetensor_deploy_receipt.partial.json"
[[ ! -e "${RECEIPT_PATH}" && ! -L "${RECEIPT_PATH}" ]] || fail \
  "complete deployment receipt already exists: ${RECEIPT_PATH}; preserve it and choose a new --out-dir"
[[ ! -e "${PARTIAL_RECEIPT_PATH}" && ! -L "${PARTIAL_RECEIPT_PATH}" ]] || fail \
  "unresolved partial deployment receipt exists: ${PARTIAL_RECEIPT_PATH}; preserve and reconcile it before retrying"
CORE_OUTPUT_LOG="$(mktemp "${OUTPUT_DIR}/.pulsetensor-core-create.XXXXXX")"
SETTLEMENT_OUTPUT_LOG="$(mktemp "${OUTPUT_DIR}/.pulsetensor-settlement-create.XXXXXX")"
cleanup() {
  rm -f "${CORE_OUTPUT_LOG}" "${SETTLEMENT_OUTPUT_LOG}"
}
trap cleanup EXIT

json_address_or_null() {
  local value="$1"
  if [[ "${value}" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
    printf '"%s"' "${value}"
  else
    printf 'null'
  fi
}

json_hash_or_null() {
  local value="$1"
  if [[ "${value}" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
    printf '"%s"' "${value}"
  else
    printf 'null'
  fi
}

write_partial_receipt() {
  local status="$1"
  local deployer="$2"
  local core="$3"
  local core_tx="$4"
  local settlement="$5"
  local settlement_tx="$6"
  local pending_path
  pending_path="$(mktemp "${OUTPUT_DIR}/.pulsetensor-receipt.XXXXXX")"

  if ! cat > "${pending_path}" <<EOF
{
  "schema": "pulsetensor/deployment-receipt/v1",
  "generated_at_utc": "${GENERATED_AT_UTC}",
  "status": "${status}",
  "chain_id": ${CHAIN_ID},
  "deployer": $(json_address_or_null "${deployer}"),
  "core_address": $(json_address_or_null "${core}"),
  "core_transaction_hash": $(json_hash_or_null "${core_tx}"),
  "settlement_address": $(json_address_or_null "${settlement}"),
  "settlement_transaction_hash": $(json_hash_or_null "${settlement_tx}"),
  "broadcast": true
}
EOF
  then
    rm -f "${pending_path}"
    fail "could not write pending deployment receipt"
  fi
  mv "${pending_path}" "${PARTIAL_RECEIPT_PATH}"
}

pushd "${ROOT_DIR}" >/dev/null
export FOUNDRY_OPTIMIZER_RUNS="${OPTIMIZER_RUNS}"
forge build

forge_args=(--rpc-url "${RPC_URL}" "${signer_args[@]}" --broadcast)

echo "Deploying PulseTensorCore..."
if ! forge create src/PulseTensorCore.sol:PulseTensorCore "${forge_args[@]}" 2>&1 | tee "${CORE_OUTPUT_LOG}"; then
  fail "PulseTensorCore deployment failed"
fi
core_address="$(awk '/Deployed to:/ {print $3}' "${CORE_OUTPUT_LOG}" | tail -n 1)"
deployer_address="$(awk '/Deployer:/ {print $2}' "${CORE_OUTPUT_LOG}" | tail -n 1)"
if [[ -z "${deployer_address}" ]]; then
  deployer_address="${FROM_ADDRESS}"
fi
core_transaction_hash="$(awk '/Transaction hash:/ {print $3}' "${CORE_OUTPUT_LOG}" | tail -n 1)"
GENERATED_AT_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
write_partial_receipt \
  "core_deployed" \
  "${deployer_address}" \
  "${core_address}" \
  "${core_transaction_hash}" \
  "" \
  ""
[[ "${core_address}" =~ ^0x[0-9a-fA-F]{40}$ ]] || fail "invalid PulseTensorCore deployment address"
[[ "${deployer_address}" =~ ^0x[0-9a-fA-F]{40}$ ]] || fail "failed to parse a valid deployer address"
[[ "${core_transaction_hash}" =~ ^0x[0-9a-fA-F]{64}$ ]] || fail \
  "failed to parse PulseTensorCore transaction hash; partial receipt retained"

echo "Deploying PulseTensorInferenceSettlement..."
if ! forge create src/PulseTensorInferenceSettlement.sol:PulseTensorInferenceSettlement \
  "${forge_args[@]}" \
  --constructor-args "${core_address}" 2>&1 | tee "${SETTLEMENT_OUTPUT_LOG}"; then
  fail "PulseTensorInferenceSettlement deployment failed"
fi
settlement_address="$(awk '/Deployed to:/ {print $3}' "${SETTLEMENT_OUTPUT_LOG}" | tail -n 1)"
settlement_transaction_hash="$(awk '/Transaction hash:/ {print $3}' "${SETTLEMENT_OUTPUT_LOG}" | tail -n 1)"
settlement_deployer="$(awk '/Deployer:/ {print $2}' "${SETTLEMENT_OUTPUT_LOG}" | tail -n 1)"
write_partial_receipt \
  "settlement_deployed_unvalidated" \
  "${deployer_address}" \
  "${core_address}" \
  "${core_transaction_hash}" \
  "${settlement_address}" \
  "${settlement_transaction_hash}"
[[ "${settlement_address}" =~ ^0x[0-9a-fA-F]{40}$ ]] || fail \
  "invalid PulseTensorInferenceSettlement deployment address; partial receipt retained"
[[ "${settlement_transaction_hash}" =~ ^0x[0-9a-fA-F]{64}$ ]] || fail \
  "failed to parse PulseTensorInferenceSettlement transaction hash; partial receipt retained"
[[ "${settlement_deployer,,}" == "${deployer_address,,}" ]] || fail \
  "settlement deployer does not match core deployer; partial receipt retained"

write_partial_receipt \
  "complete" \
  "${deployer_address}" \
  "${core_address}" \
  "${core_transaction_hash}" \
  "${settlement_address}" \
  "${settlement_transaction_hash}"
mv "${PARTIAL_RECEIPT_PATH}" "${RECEIPT_PATH}"

echo "Deployment complete:"
echo "  core_address: ${core_address}"
echo "  settlement_address: ${settlement_address}"
echo "  receipt: ${RECEIPT_PATH}"

popd >/dev/null

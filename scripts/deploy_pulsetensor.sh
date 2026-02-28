#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RPC_URL="${RPC_URL:-}"
PRIVATE_KEY="${PRIVATE_KEY:-}"
OPTIMIZER_RUNS="${FOUNDRY_OPTIMIZER_RUNS:-1}"
OUTPUT_DIR="${ROOT_DIR}/runs/deployments"
BROADCAST=1

usage() {
  cat <<'EOF'
Usage: bash scripts/deploy_pulsetensor.sh [options]

Deploys:
  - PulseTensorCore
  - PulseTensorInferenceSettlement (constructor arg: core address)

Options:
  --rpc-url <url>         RPC URL (or set RPC_URL env var)
  --private-key <hex>     Deployer private key (or set PRIVATE_KEY env var)
  --out-dir <path>        Output directory for deployment receipt
  --no-broadcast          Dry-run deployment without broadcasting
  --help                  Show help

Environment:
  FOUNDRY_OPTIMIZER_RUNS  Optimizer runs used for deploy build/create (default: 1)

Outputs:
  runs/deployments/pulsetensor_deploy_receipt.json
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rpc-url)
      if [[ $# -lt 2 ]]; then
        echo "--rpc-url requires a value"
        exit 1
      fi
      RPC_URL="$2"
      shift 2
      ;;
    --private-key)
      if [[ $# -lt 2 ]]; then
        echo "--private-key requires a value"
        exit 1
      fi
      PRIVATE_KEY="$2"
      shift 2
      ;;
    --out-dir)
      if [[ $# -lt 2 ]]; then
        echo "--out-dir requires a value"
        exit 1
      fi
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --no-broadcast)
      BROADCAST=0
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${RPC_URL}" ]]; then
  echo "RPC URL is required. Set RPC_URL or pass --rpc-url"
  exit 1
fi

if [[ "${BROADCAST}" == "1" && -z "${PRIVATE_KEY}" ]]; then
  echo "PRIVATE_KEY is required when broadcasting."
  echo "Set PRIVATE_KEY or pass --private-key"
  exit 1
fi

mkdir -p "${OUTPUT_DIR}"
pushd "${ROOT_DIR}" >/dev/null

export FOUNDRY_OPTIMIZER_RUNS="${OPTIMIZER_RUNS}"
forge build

forge_args=(--rpc-url "${RPC_URL}")
if [[ "${BROADCAST}" == "1" ]]; then
  forge_args+=(--private-key "${PRIVATE_KEY}" --broadcast)
fi

echo "Deploying PulseTensorCore..."
core_output="$(
  forge create src/PulseTensorCore.sol:PulseTensorCore "${forge_args[@]}" 2>&1
)"
echo "${core_output}"
core_address="$(printf '%s\n' "${core_output}" | awk '/Deployed to:/ {print $3}' | tail -n 1)"
if [[ -z "${core_address}" ]]; then
  echo "Failed to parse PulseTensorCore deployment address."
  exit 1
fi

echo "Deploying PulseTensorInferenceSettlement..."
settlement_output="$(
  forge create src/PulseTensorInferenceSettlement.sol:PulseTensorInferenceSettlement \
    "${forge_args[@]}" \
    --constructor-args "${core_address}" 2>&1
)"
echo "${settlement_output}"
settlement_address="$(printf '%s\n' "${settlement_output}" | awk '/Deployed to:/ {print $3}' | tail -n 1)"
if [[ -z "${settlement_address}" ]]; then
  echo "Failed to parse PulseTensorInferenceSettlement deployment address."
  exit 1
fi

chain_id="$(cast chain-id --rpc-url "${RPC_URL}")"
deployer_address="$(cast wallet address --private-key "${PRIVATE_KEY}" 2>/dev/null || true)"
generated_at_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
receipt_path="${OUTPUT_DIR}/pulsetensor_deploy_receipt.json"

cat > "${receipt_path}" <<EOF
{
  "generated_at_utc": "${generated_at_utc}",
  "chain_id": ${chain_id},
  "deployer": "${deployer_address}",
  "core_address": "${core_address}",
  "settlement_address": "${settlement_address}",
  "broadcast": ${BROADCAST}
}
EOF

echo "Deployment complete:"
echo "  core_address: ${core_address}"
echo "  settlement_address: ${settlement_address}"
echo "  receipt: ${receipt_path}"

popd >/dev/null

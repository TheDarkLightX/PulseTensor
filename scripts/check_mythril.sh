#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT_DIR}/runs/security"
source "${ROOT_DIR}/scripts/toolchain.lock"
IMAGE="${MYTHRIL_IMAGE_LOCK}"
MAX_DEPTH="${MYTHRIL_MAX_DEPTH_LOCK}"
TX_COUNT="${MYTHRIL_TRANSACTION_COUNT_LOCK}"
EXEC_TIMEOUT="${MYTHRIL_EXECUTION_TIMEOUT_LOCK}"
SOLVER_TIMEOUT_MS="${MYTHRIL_SOLVER_TIMEOUT_MS_LOCK}"
WALL_TIMEOUT_SECONDS="${MYTHRIL_WALL_TIMEOUT_SECONDS_LOCK}"
ALLOWLIST_PATH="${ROOT_DIR}/docs/security/mythril_ignored_swc.allowlist"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required for Mythril gate"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for Mythril gate"
  exit 1
fi

bash "${ROOT_DIR}/scripts/check_mythril_allowlist.sh"
bash "${ROOT_DIR}/scripts/test_mythril_report_checker.sh"

if [[ ! -f "${ALLOWLIST_PATH}" ]]; then
  echo "Mythril SWC allowlist not found: ${ALLOWLIST_PATH}"
  exit 1
fi

mapfile -t IGNORED_SWC_IDS < <(awk '
  {
    line=$0
    sub(/#.*/, "", line)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
    if (line != "") print line
  }
' "${ALLOWLIST_PATH}")

if [[ ${#IGNORED_SWC_IDS[@]} -eq 0 ]]; then
  echo "Mythril SWC allowlist is empty: ${ALLOWLIST_PATH}"
  exit 1
fi

mkdir -p "${OUT_DIR}"
rm -f "${OUT_DIR}/mythril_core_findings.json" \
      "${OUT_DIR}/mythril_settlement_findings.json" \
      "${OUT_DIR}/mythril_summary.json" \
      "${OUT_DIR}/mythril_core.stderr.log" \
      "${OUT_DIR}/mythril_settlement.stderr.log" \
      "${OUT_DIR}/PulseTensorCore.bin-runtime" \
      "${OUT_DIR}/PulseTensorInferenceSettlement.bin-runtime"

pushd "${ROOT_DIR}" >/dev/null
forge build >/dev/null
popd >/dev/null

extract_bytecode() {
  local artifact_path="$1"
  local output_path="$2"

  if [[ ! -f "${artifact_path}" ]]; then
    echo "Missing artifact for Mythril: ${artifact_path}"
    exit 1
  fi

  jq -r '.deployedBytecode.object' "${artifact_path}" > "${output_path}"
  if [[ ! -s "${output_path}" ]]; then
    echo "Empty runtime bytecode extracted: ${output_path}"
    exit 1
  fi
}

run_mythril() {
  local bin_path="$1"
  local out_json="$2"
  local stderr_log="$3"

  set +e
  timeout "${WALL_TIMEOUT_SECONDS}s" docker run --rm \
    --network none \
    -v "${ROOT_DIR}:/src:ro" \
    -w /src \
    "${IMAGE}" \
      myth analyze \
      -f "${bin_path}" \
      --bin-runtime \
      --max-depth "${MAX_DEPTH}" \
      --transaction-count "${TX_COUNT}" \
      --execution-timeout "${EXEC_TIMEOUT}" \
      --solver-timeout "${SOLVER_TIMEOUT_MS}" \
      --strategy bfs \
      --no-onchain-data \
      --outform jsonv2 \
      > "${out_json}" \
      2> "${stderr_log}"
  local status=$?
  set -e

  if [[ ${status} -eq 124 ]]; then
    echo "Mythril timed out (${WALL_TIMEOUT_SECONDS}s): ${bin_path}"
    exit 1
  fi
  if [[ ${status} -ne 0 && ${status} -ne 1 ]]; then
    echo "Mythril failed with status ${status}: ${bin_path}"
    if [[ -s "${stderr_log}" ]]; then
      echo "stderr:"
      cat "${stderr_log}"
    fi
    exit 1
  fi
  if [[ ! -s "${out_json}" ]]; then
    echo "Mythril did not produce output: ${out_json}"
    exit 1
  fi
}

extract_bytecode \
  "${ROOT_DIR}/out/PulseTensorCore.sol/PulseTensorCore.json" \
  "${OUT_DIR}/PulseTensorCore.bin-runtime"
extract_bytecode \
  "${ROOT_DIR}/out/PulseTensorInferenceSettlement.sol/PulseTensorInferenceSettlement.json" \
  "${OUT_DIR}/PulseTensorInferenceSettlement.bin-runtime"

run_mythril \
  "runs/security/PulseTensorCore.bin-runtime" \
  "${OUT_DIR}/mythril_core_findings.json" \
  "${OUT_DIR}/mythril_core.stderr.log"
run_mythril \
  "runs/security/PulseTensorInferenceSettlement.bin-runtime" \
  "${OUT_DIR}/mythril_settlement_findings.json" \
  "${OUT_DIR}/mythril_settlement.stderr.log"

python3 "${ROOT_DIR}/scripts/check_mythril_report.py" "${OUT_DIR}/mythril_core_findings.json"
python3 "${ROOT_DIR}/scripts/check_mythril_report.py" "${OUT_DIR}/mythril_settlement_findings.json"

python3 "${ROOT_DIR}/scripts/check_mythril_findings.py" \
  --root "${ROOT_DIR}" \
  --core-report "${OUT_DIR}/mythril_core_findings.json" \
  --settlement-report "${OUT_DIR}/mythril_settlement_findings.json" \
  --image "${IMAGE}" \
  --max-depth "${MAX_DEPTH}" \
  --transaction-count "${TX_COUNT}" \
  --execution-timeout "${EXEC_TIMEOUT}" \
  --solver-timeout-ms "${SOLVER_TIMEOUT_MS}" \
  --wall-timeout-seconds "${WALL_TIMEOUT_SECONDS}" \
  --output "${OUT_DIR}/mythril_summary.json"

echo "Mythril gate passed (reports: ${OUT_DIR}/mythril_core_findings.json, ${OUT_DIR}/mythril_settlement_findings.json, ${OUT_DIR}/mythril_summary.json)"

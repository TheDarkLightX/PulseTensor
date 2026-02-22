#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT_DIR}/runs/slither"
SLITHER_BIN="${ROOT_DIR}/.venv/bin/slither"
ALLOWLIST_PATH="${ROOT_DIR}/docs/security/slither_exclusions.allowlist"

if [[ ! -x "${SLITHER_BIN}" ]]; then
  if ! command -v slither >/dev/null 2>&1; then
    echo "slither not found (install in .venv or on PATH)"
    exit 1
  fi
  SLITHER_BIN="slither"
fi

if [[ ! -f "${ALLOWLIST_PATH}" ]]; then
  echo "Slither exclusion allowlist not found: ${ALLOWLIST_PATH}"
  exit 1
fi

bash "${ROOT_DIR}/scripts/check_slither_exclusions.sh"
mapfile -t EXCLUDE_DETECTORS < <(awk '
  {
    line=$0
    sub(/#.*/, "", line)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
    if (line != "") print line
  }
' "${ALLOWLIST_PATH}")
if [[ ${#EXCLUDE_DETECTORS[@]} -eq 0 ]]; then
  echo "Slither exclusion allowlist is empty: ${ALLOWLIST_PATH}"
  exit 1
fi
EXCLUDE_CSV="$(IFS=, ; echo "${EXCLUDE_DETECTORS[*]}")"

mkdir -p "${OUT_DIR}"
rm -f "${OUT_DIR}/slither_report.json" "${OUT_DIR}/slither_inference_settlement_report.json"

pushd "${ROOT_DIR}" >/dev/null
"${SLITHER_BIN}" src/PulseTensorCore.sol \
  --exclude-dependencies \
  --exclude-informational \
  --exclude-low \
  --exclude-optimization \
  --exclude "${EXCLUDE_CSV}" \
  --json "${OUT_DIR}/slither_report.json"
"${SLITHER_BIN}" src/PulseTensorInferenceSettlement.sol \
  --exclude-dependencies \
  --exclude-informational \
  --exclude-low \
  --exclude-optimization \
  --exclude "${EXCLUDE_CSV}" \
  --json "${OUT_DIR}/slither_inference_settlement_report.json"
popd >/dev/null

echo "Slither checks passed (exclude=${EXCLUDE_CSV}; reports: ${OUT_DIR}/slither_report.json, ${OUT_DIR}/slither_inference_settlement_report.json)"

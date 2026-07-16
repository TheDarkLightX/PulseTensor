#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT_DIR}/runs/slither"
SLITHER_BIN="${ROOT_DIR}/.venv/bin/slither"
SLITHER_PYTHON="${ROOT_DIR}/.venv/bin/python"
ALLOWLIST_PATH="${ROOT_DIR}/docs/security/slither_exclusions.allowlist"
source "${ROOT_DIR}/scripts/toolchain.lock"

if [[ ! -x "${SLITHER_BIN}" || ! -x "${SLITHER_PYTHON}" ]]; then
  echo "pinned Slither environment not found; run scripts/bootstrap.sh"
  exit 1
fi
actual_slither_version="$("${SLITHER_PYTHON}" -c 'import importlib.metadata; print(importlib.metadata.version("slither-analyzer"))')"
if [[ "${actual_slither_version}" != "${SLITHER_VERSION}" ]]; then
  echo "Slither version mismatch: expected ${SLITHER_VERSION}, found ${actual_slither_version}"
  exit 1
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

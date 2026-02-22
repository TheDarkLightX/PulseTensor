#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_MORPH="${RUN_MORPH:-1}"
RUN_ZAG="${RUN_ZAG:-1}"
RUN_ORCH="${RUN_ORCH:-1}"
RUN_SECURITY="${RUN_SECURITY:-1}"
RUN_ECHIDNA="${RUN_ECHIDNA:-0}"
ZAG_MODE="${ZAG_MODE:-quick}"
RUN_START_EPOCH="${RUN_START_EPOCH:-$(date +%s)}"
ARTIFACT_MANIFEST_PATH="docs/security/artifact_manifest.esso.txt"

pushd "${ROOT_DIR}" >/dev/null
bash scripts/check_private_boundaries.sh
forge build
forge test
if [[ "${RUN_SECURITY}" == "1" ]]; then
  RUN_ECHIDNA="${RUN_ECHIDNA}" RUN_START_EPOCH="${RUN_START_EPOCH}" bash scripts/check_security.sh
  ARTIFACT_MANIFEST_PATH="docs/security/artifact_manifest.release.txt"
else
  echo "Security checks skipped (RUN_SECURITY=${RUN_SECURITY})"
fi
bash scripts/check_esso.sh
popd >/dev/null

if [[ "${RUN_MORPH}" == "1" ]]; then
  bash "${ROOT_DIR}/scripts/check_morph.sh"
else
  echo "Morph checks skipped (RUN_MORPH=${RUN_MORPH})"
fi

if [[ "${RUN_ZAG}" == "1" ]]; then
  bash "${ROOT_DIR}/scripts/check_zag.sh" "${ZAG_MODE}"
else
  echo "ZAG checks skipped (RUN_ZAG=${RUN_ZAG})"
fi

if [[ "${RUN_ORCH}" == "1" ]]; then
  bash "${ROOT_DIR}/scripts/check_orch_unit.sh"
else
  echo "Orchestration-Unit checks skipped (RUN_ORCH=${RUN_ORCH})"
fi

bash "${ROOT_DIR}/scripts/check_artifact_freshness.sh" \
  "${ARTIFACT_MANIFEST_PATH}" \
  "${RUN_START_EPOCH}"

echo "Verification pipeline complete"

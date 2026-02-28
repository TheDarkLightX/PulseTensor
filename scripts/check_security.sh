#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_ECHIDNA="${RUN_ECHIDNA:-0}"
RUN_START_EPOCH="${RUN_START_EPOCH:-$(date +%s)}"

bash "${ROOT_DIR}/scripts/check_compiler_known_bugs.sh"
bash "${ROOT_DIR}/scripts/check_security_controls.sh"
bash "${ROOT_DIR}/scripts/check_requirements_traceability.sh"
bash "${ROOT_DIR}/scripts/check_security_antipatterns.sh"
bash "${ROOT_DIR}/scripts/check_security_readiness_docs.sh"
bash "${ROOT_DIR}/scripts/check_solhint.sh"
bash "${ROOT_DIR}/scripts/check_slither.sh"
bash "${ROOT_DIR}/scripts/check_mythril.sh"
bash "${ROOT_DIR}/scripts/check_fuzz_invariant.sh"

if [[ "${RUN_ECHIDNA}" == "1" ]]; then
  bash "${ROOT_DIR}/scripts/check_echidna.sh"
else
  echo "Echidna checks skipped (RUN_ECHIDNA=${RUN_ECHIDNA})"
fi

bash "${ROOT_DIR}/scripts/check_artifact_freshness.sh" \
  "docs/security/artifact_manifest.security.txt" \
  "${RUN_START_EPOCH}"

echo "Security checks passed"

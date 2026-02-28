#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_START_EPOCH="${RUN_START_EPOCH:-$(date +%s)}"

bash "${ROOT_DIR}/scripts/verify_toolchain.sh"
bash "${ROOT_DIR}/scripts/check_deploy_code_size.sh"
bash "${ROOT_DIR}/scripts/check_requirements_traceability.sh"

RUN_START_EPOCH="${RUN_START_EPOCH}" \
RUN_SECURITY=1 \
RUN_ECHIDNA=1 \
ALLOW_STALE_BUG_DB=0 \
SECURITY_CONTROL_STRICT_STATUSES=1 \
bash "${ROOT_DIR}/scripts/verify_all.sh"

bash "${ROOT_DIR}/scripts/check_local_e2e.sh"
bash "${ROOT_DIR}/scripts/check_goal_frontier_example.sh"
bash "${ROOT_DIR}/scripts/check_tokenomics_goal_frontier.sh"

bash "${ROOT_DIR}/scripts/check_artifact_freshness.sh" \
  "docs/security/artifact_manifest.complete.txt" \
  "${RUN_START_EPOCH}"

echo "Complete verification pipeline finished"

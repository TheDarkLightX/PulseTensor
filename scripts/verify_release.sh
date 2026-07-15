#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export FOUNDRY_OPTIMIZER_RUNS="1"

bash "${ROOT_DIR}/scripts/verify_toolchain.sh"
bash "${ROOT_DIR}/scripts/test_echidna_harness_checker.sh"
bash "${ROOT_DIR}/scripts/check_deploy_code_size.sh"
RUN_START_EPOCH="$(date +%s)" \
RUN_SECURITY=1 \
RUN_ECHIDNA=1 \
ALLOW_STALE_BUG_DB=0 \
SECURITY_CONTROL_STRICT_STATUSES=1 \
bash "${ROOT_DIR}/scripts/verify_all.sh"
bash "${ROOT_DIR}/scripts/check_local_e2e.sh"
bash "${ROOT_DIR}/scripts/check_goal_frontier_example.sh"
bash "${ROOT_DIR}/scripts/check_tokenomics_goal_frontier.sh"
bash "${ROOT_DIR}/scripts/check_participant_regret_frontier.sh"
bash "${ROOT_DIR}/scripts/write_assurance_evidence.sh"

echo "Release verification pipeline complete"

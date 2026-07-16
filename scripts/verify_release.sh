#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_START_EPOCH="$(date +%s)"
ASSURANCE_DIR="${ROOT_DIR}/runs/assurance"
RELEASE_LOG="${ASSURANCE_DIR}/release.log"
RELEASE_LOG_PENDING="${ASSURANCE_DIR}/release.pending.${RUN_START_EPOCH}.log"
EVIDENCE_PATH="${ASSURANCE_DIR}/evidence.json"
export FOUNDRY_OPTIMIZER_RUNS="1"

mkdir -p "${ASSURANCE_DIR}"
if [[ -f "${EVIDENCE_PATH}" ]]; then
  mv "${EVIDENCE_PATH}" "${EVIDENCE_PATH}.previous.${RUN_START_EPOCH}"
fi
if [[ -f "${RELEASE_LOG}" ]]; then
  mv "${RELEASE_LOG}" "${RELEASE_LOG}.previous.${RUN_START_EPOCH}"
fi

run_release_checks() {
  bash "${ROOT_DIR}/scripts/verify_toolchain.sh"
  bash "${ROOT_DIR}/scripts/test_echidna_harness_checker.sh"
  bash "${ROOT_DIR}/scripts/check_deploy_code_size.sh"
  RUN_START_EPOCH="${RUN_START_EPOCH}" \
  RUN_SECURITY=1 \
  RUN_ECHIDNA=1 \
  ALLOW_STALE_BUG_DB=0 \
  SECURITY_CONTROL_STRICT_STATUSES=1 \
  bash "${ROOT_DIR}/scripts/verify_all.sh"
  bash "${ROOT_DIR}/scripts/check_local_e2e.sh"
  bash "${ROOT_DIR}/scripts/check_goal_frontier_example.sh"
  bash "${ROOT_DIR}/scripts/check_tokenomics_goal_frontier.sh"
  bash "${ROOT_DIR}/scripts/check_participant_regret_frontier.sh"
  bash "${ROOT_DIR}/scripts/check_artifact_freshness.sh" \
    "docs/security/artifact_manifest.complete.txt" \
    "${RUN_START_EPOCH}"
}

set +e
run_release_checks 2>&1 | tee "${RELEASE_LOG_PENDING}"
pipeline_status=("${PIPESTATUS[@]}")
set -e
release_status="${pipeline_status[0]}"
tee_status="${pipeline_status[1]}"
if [[ "${release_status}" != "0" || "${tee_status}" != "0" ]]; then
  echo "Release verification failed; no current evidence.json was written"
  if [[ "${release_status}" != "0" ]]; then
    exit "${release_status}"
  fi
  exit "${tee_status}"
fi
mv "${RELEASE_LOG_PENDING}" "${RELEASE_LOG}"

bash "${ROOT_DIR}/scripts/write_assurance_evidence.sh"
set +e
bash "${ROOT_DIR}/scripts/verify_assurance_evidence.sh"
evidence_status=$?
set -e
if [[ "${evidence_status}" != "0" ]]; then
  if [[ -f "${EVIDENCE_PATH}" ]]; then
    mv "${EVIDENCE_PATH}" "${EVIDENCE_PATH}.rejected.${RUN_START_EPOCH}"
  fi
  echo "Assurance evidence verification failed; current evidence was not promoted"
  exit "${evidence_status}"
fi

echo "Release verification pipeline complete"

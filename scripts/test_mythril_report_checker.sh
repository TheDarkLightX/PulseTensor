#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_DIR="${ROOT_DIR}/test/security/fixtures"
CHECKER="${ROOT_DIR}/scripts/check_mythril_report.py"
FINDINGS_CHECKER="${ROOT_DIR}/scripts/check_mythril_findings.py"
TEMP_SUMMARY="$(mktemp)"
trap 'rm -f "${TEMP_SUMMARY}"' EXIT

python3 "${CHECKER}" "${FIXTURE_DIR}/mythril_jsonv2_success.json" >/dev/null
python3 "${CHECKER}" "${FIXTURE_DIR}/mythril_jsonv2_disallowed_finding.json" >/dev/null

for rejected_fixture in \
  mythril_jsonv2_error_exit_zero.json \
  mythril_jsonv2_missing_execution_info.json \
  mythril_jsonv2_empty_source_list.json; do
  if python3 "${CHECKER}" "${FIXTURE_DIR}/${rejected_fixture}" >/dev/null 2>&1; then
    echo "Mythril checker accepted known-invalid fixture: ${rejected_fixture}"
    exit 1
  fi
done

findings_args=(
  --root "${ROOT_DIR}"
  --core-report "${FIXTURE_DIR}/mythril_jsonv2_success.json"
  --image "mythril/test@sha256:fixture"
  --max-depth 8
  --transaction-count 1
  --execution-timeout 15
  --solver-timeout-ms 8000
  --wall-timeout-seconds 120
  --output "${TEMP_SUMMARY}"
)
python3 "${FINDINGS_CHECKER}" \
  "${findings_args[@]}" \
  --settlement-report "${FIXTURE_DIR}/mythril_jsonv2_success.json" >/dev/null
jq -e '.ok == true and ([.contracts[].total_issues] | add) == 0' "${TEMP_SUMMARY}" >/dev/null

if python3 "${FINDINGS_CHECKER}" \
  "${findings_args[@]}" \
  --settlement-report "${FIXTURE_DIR}/mythril_jsonv2_disallowed_finding.json" >/dev/null 2>&1; then
  echo "Mythril findings checker accepted a disallowed SWC mutation"
  exit 1
fi
jq -e '.ok == false and .contracts[1].disallowed_issues[0].swc_id == "SWC-999"' \
  "${TEMP_SUMMARY}" >/dev/null

echo "Mythril report checker negative controls passed"

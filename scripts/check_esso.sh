#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ESSO_DIR="${ROOT_DIR}/external/ESSO"
PYTHON_BIN="${ROOT_DIR}/.venv/bin/python"
OUT_DIR="${ROOT_DIR}/runs/esso_verify"
ESSO_TIMEOUT_MS="${ESSO_TIMEOUT_MS:-10000}"
ESSO_DETERMINISM_TRIALS="${ESSO_DETERMINISM_TRIALS:-2}"

if [[ ! -d "${ESSO_DIR}" ]]; then
  echo "ESSO repo not found at ${ESSO_DIR}"
  exit 1
fi

if [[ ! -x "${PYTHON_BIN}" ]]; then
  PYTHON_BIN="python3"
fi

if ! command -v z3 >/dev/null 2>&1; then
  echo "z3 binary not found"
  exit 1
fi

if ! command -v cvc5 >/dev/null 2>&1; then
  echo "cvc5 binary not found"
  exit 1
fi

declare -a SPEC_PATHS=()
if [[ $# -ge 1 ]]; then
  SPEC_PATHS=("$1")
else
  mapfile -t SPEC_PATHS < <(find "${ROOT_DIR}/specs/esso" -maxdepth 1 -type f -name "*.yaml" | sort)
fi

if [[ ${#SPEC_PATHS[@]} -eq 0 ]]; then
  echo "No ESSO specs found under ${ROOT_DIR}/specs/esso"
  exit 1
fi

for SPEC_PATH in "${SPEC_PATHS[@]}"; do
  if [[ ! -f "${SPEC_PATH}" ]]; then
    echo "ESSO spec not found at ${SPEC_PATH}"
    exit 1
  fi
done

rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}"

check_report() {
  local report_path="$1"
  if [[ ! -f "${report_path}" ]]; then
    echo "ESSO verification report missing: ${report_path}"
    exit 1
  fi
  REPORT_PATH="${report_path}" "${PYTHON_BIN}" - <<'PY'
import json
import os
import sys

report_path = os.environ["REPORT_PATH"]
with open(report_path, "r", encoding="utf-8") as handle:
    payload = json.load(handle)

report = payload.get("report")
if not isinstance(report, dict):
    report = payload

errors = []
ok_value = payload.get("ok")
if ok_value is False:
    errors.append("verify-multi returned ok=false")
if report.get("verdict") != "VERIFIED":
    errors.append(f"unexpected verdict {report.get('verdict')!r}")
if report.get("z3_passed") is not True:
    errors.append("z3_passed was not true")
if report.get("cvc5_passed") is not True:
    errors.append("cvc5_passed was not true")
if report.get("solvers_agreed") is not True:
    errors.append("solvers_agreed was not true")
if report.get("failed_queries") != 0:
    errors.append(f"failed_queries={report.get('failed_queries')}")
if report.get("inconclusive_queries") != 0:
    errors.append(f"inconclusive_queries={report.get('inconclusive_queries')}")

if errors:
    for error in errors:
        print(f"ESSO fail-closed check failed: {error}", file=sys.stderr)
    sys.exit(1)
PY
}

declare -a VERIFIED_SPECS=()
for SPEC_PATH in "${SPEC_PATHS[@]}"; do
  SPEC_NAME="$(basename "${SPEC_PATH}" .yaml)"
  SPEC_OUT_DIR="${OUT_DIR}/${SPEC_NAME}"
  mkdir -p "${SPEC_OUT_DIR}"

  pushd "${ESSO_DIR}" >/dev/null
  "${PYTHON_BIN}" -m ESSO validate "${SPEC_PATH}"
  "${PYTHON_BIN}" -m ESSO verify-multi \
    "${SPEC_PATH}" \
    --solvers z3,cvc5 \
    --timeout-ms "${ESSO_TIMEOUT_MS}" \
    --determinism-trials "${ESSO_DETERMINISM_TRIALS}" \
    --write-report \
    --output "${SPEC_OUT_DIR}"
  popd >/dev/null

  check_report "${SPEC_OUT_DIR}/verification_report.json"
  VERIFIED_SPECS+=("${SPEC_PATH}")
done

echo "ESSO checks passed for ${#VERIFIED_SPECS[@]} spec(s): ${VERIFIED_SPECS[*]} (timeout_ms=${ESSO_TIMEOUT_MS}, determinism_trials=${ESSO_DETERMINISM_TRIALS})"

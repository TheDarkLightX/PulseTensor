#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT_DIR}/runs/security"
IMAGE="${MYTHRIL_IMAGE:-mythril/myth@sha256:49e11758e359d0b410f648df5bbcba28a52e091a78e4772b5c02b9043666b4ff}"
MAX_DEPTH="${MYTHRIL_MAX_DEPTH:-8}"
TX_COUNT="${MYTHRIL_TRANSACTION_COUNT:-1}"
EXEC_TIMEOUT="${MYTHRIL_EXECUTION_TIMEOUT:-15}"
SOLVER_TIMEOUT_MS="${MYTHRIL_SOLVER_TIMEOUT_MS:-8000}"
WALL_TIMEOUT_SECONDS="${MYTHRIL_WALL_TIMEOUT_SECONDS:-120}"
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
    -v "${ROOT_DIR}:/src" \
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

ROOT_DIR="${ROOT_DIR}" OUT_DIR="${OUT_DIR}" MYTHRIL_IMAGE="${IMAGE}" MYTHRIL_MAX_DEPTH="${MAX_DEPTH}" \
MYTHRIL_TRANSACTION_COUNT="${TX_COUNT}" MYTHRIL_EXECUTION_TIMEOUT="${EXEC_TIMEOUT}" \
MYTHRIL_SOLVER_TIMEOUT_MS="${SOLVER_TIMEOUT_MS}" python3 - <<'PY'
import json
import os
import pathlib
import sys

root = pathlib.Path(os.environ["ROOT_DIR"])
out_dir = pathlib.Path(os.environ["OUT_DIR"])
allowlist_path = root / "docs/security/mythril_ignored_swc.allowlist"

allowlisted = []
for raw_line in allowlist_path.read_text(encoding="utf-8").splitlines():
    line = raw_line.split("#", 1)[0].strip()
    if line:
        allowlisted.append(line)
allowlisted_set = set(allowlisted)

targets = [
    ("PulseTensorCore", out_dir / "mythril_core_findings.json"),
    ("PulseTensorInferenceSettlement", out_dir / "mythril_settlement_findings.json"),
]

summary_contracts = []
total_disallowed = 0
for contract_name, report_path in targets:
    payload = json.loads(report_path.read_text(encoding="utf-8"))
    if not isinstance(payload, list) or len(payload) == 0:
        raise SystemExit(f"Mythril output is malformed: {report_path}")

    issues = payload[0].get("issues")
    if not isinstance(issues, list):
        raise SystemExit(f"Mythril issues list missing: {report_path}")

    allowed_count = 0
    disallowed = []
    for issue in issues:
        swc_id = issue.get("swcID")
        if not isinstance(swc_id, str) or swc_id.strip() == "":
            swc_id = "UNKNOWN"
        if swc_id in allowlisted_set:
            allowed_count += 1
        else:
            disallowed.append(
                {
                    "swc_id": swc_id,
                    "severity": issue.get("severity"),
                    "title": issue.get("swcTitle"),
                }
            )

    total_disallowed += len(disallowed)
    summary_contracts.append(
        {
            "contract": contract_name,
            "report": str(report_path.relative_to(root)),
            "total_issues": len(issues),
            "allowlisted_issues": allowed_count,
            "disallowed_issues": disallowed,
        }
    )

summary = {
    "schema": "pulsetensor/security-mythril-summary/v1",
    "image": os.environ.get("MYTHRIL_IMAGE", "mythril/myth"),
    "params": {
        "max_depth": os.environ.get("MYTHRIL_MAX_DEPTH", "8"),
        "transaction_count": os.environ.get("MYTHRIL_TRANSACTION_COUNT", "1"),
        "execution_timeout": os.environ.get("MYTHRIL_EXECUTION_TIMEOUT", "15"),
        "solver_timeout_ms": os.environ.get("MYTHRIL_SOLVER_TIMEOUT_MS", "8000"),
    },
    "allowlisted_swc_ids": allowlisted,
    "contracts": summary_contracts,
    "ok": total_disallowed == 0,
}
(out_dir / "mythril_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")

if total_disallowed != 0:
    for contract in summary_contracts:
        if contract["disallowed_issues"]:
            print(
                f"Mythril disallowed findings in {contract['contract']}: "
                f"{len(contract['disallowed_issues'])}",
                file=sys.stderr,
            )
    raise SystemExit(1)
PY

echo "Mythril gate passed (reports: ${OUT_DIR}/mythril_core_findings.json, ${OUT_DIR}/mythril_settlement_findings.json, ${OUT_DIR}/mythril_summary.json)"

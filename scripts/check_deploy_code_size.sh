#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY_OPTIMIZER_RUNS="${FOUNDRY_OPTIMIZER_RUNS:-1}"
OUT_DIR="${ROOT_DIR}/runs/security"
REPORT_PATH="${OUT_DIR}/deploy_code_size_report.json"
SIZES_LOG="${OUT_DIR}/deploy_code_size_sizes.log"

mkdir -p "${OUT_DIR}"

pushd "${ROOT_DIR}" >/dev/null
if ! FOUNDRY_OPTIMIZER_RUNS="${DEPLOY_OPTIMIZER_RUNS}" forge build --sizes >"${SIZES_LOG}" 2>&1; then
  cat "${SIZES_LOG}"
  echo "Deploy code-size gate failed: forge build --sizes returned non-zero"
  exit 1
fi
popd >/dev/null

SIZES_LOG="${SIZES_LOG}" REPORT_PATH="${REPORT_PATH}" DEPLOY_OPTIMIZER_RUNS="${DEPLOY_OPTIMIZER_RUNS}" python3 - <<'PY'
import json
import os
import re
import sys
from datetime import datetime, timezone

sizes_log = os.environ["SIZES_LOG"]
report_path = os.environ["REPORT_PATH"]
deploy_optimizer_runs = os.environ["DEPLOY_OPTIMIZER_RUNS"]
target_contracts = ("PulseTensorCore", "PulseTensorInferenceSettlement")

with open(sizes_log, "r", encoding="utf-8") as handle:
    lines = handle.readlines()

results = {}
for raw in lines:
    line = raw.strip()
    if not line.startswith("|"):
        continue
    if "Contract" in line or "====" in line or line.startswith("|-"):
        continue
    parts = [part.strip() for part in line.split("|") if part.strip()]
    if len(parts) != 5:
        continue
    name, runtime_size, initcode_size, runtime_margin, initcode_margin = parts
    if name not in target_contracts:
        continue
    def to_int(value: str) -> int:
        value = value.replace(",", "")
        return int(value)
    results[name] = {
        "runtime_size": to_int(runtime_size),
        "initcode_size": to_int(initcode_size),
        "runtime_margin": to_int(runtime_margin),
        "initcode_margin": to_int(initcode_margin),
    }

missing = [name for name in target_contracts if name not in results]
if missing:
    print(f"Deploy code-size gate failed: missing contracts in --sizes output: {missing}", file=sys.stderr)
    sys.exit(1)

for name, metrics in results.items():
    if metrics["runtime_margin"] < 0:
        print(f"Deploy code-size gate failed: {name} runtime margin is negative", file=sys.stderr)
        sys.exit(1)
    if metrics["initcode_margin"] < 0:
        print(f"Deploy code-size gate failed: {name} initcode margin is negative", file=sys.stderr)
        sys.exit(1)

report = {
    "schema": "pulsetensor/deploy-code-size-report/v1",
    "generated_at_utc": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "deploy_optimizer_runs": int(deploy_optimizer_runs),
    "contracts": results,
    "ok": True,
}
with open(report_path, "w", encoding="utf-8") as handle:
    json.dump(report, handle, indent=2)
    handle.write("\n")

print(
    "Deploy code-size gate passed "
    f"(optimizer_runs={deploy_optimizer_runs}, "
    f"PulseTensorCore_margin={results['PulseTensorCore']['runtime_margin']}, "
    f"PulseTensorInferenceSettlement_margin={results['PulseTensorInferenceSettlement']['runtime_margin']})"
)
PY

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_PATH="${ROOT_DIR}/configs/formal/pulsetensor_tokenomics_goal_frontier.json"
OUT_PATH="${ROOT_DIR}/runs/formal/pulsetensor_tokenomics_goal_frontier.report.json"

python3 "${ROOT_DIR}/scripts/synthesize_goal_frontier.py" \
  --model "${MODEL_PATH}" \
  --out "${OUT_PATH}"

python3 - "${OUT_PATH}" <<'PY'
import json
import pathlib
import sys

report_path = pathlib.Path(sys.argv[1])
report = json.loads(report_path.read_text(encoding="utf-8"))
summary = report["summary"]

if summary["full_goal_set_realizable"] is not False:
    raise SystemExit("expected full tokenomics goal set to be unrealizable")

expected_maximal = [
    [
        "G1_SOLVENCY_SAFETY",
        "G2_LIVENESS",
        "G3_CHALLENGE_FAIRNESS",
        "G4_TREASURY_SUSTAINABILITY",
        "G5_ANTI_SYBIL",
    ],
    [
        "G2_LIVENESS",
        "G4_TREASURY_SUSTAINABILITY",
        "G6_AGGRESSIVE_TREASURY_GROWTH",
    ],
]

actual_maximal = summary["maximal_realizable_goal_sets"]
if actual_maximal != expected_maximal:
    raise SystemExit(
        "unexpected tokenomics maximal frontier sets:\n"
        f"expected={expected_maximal}\n"
        f"actual={actual_maximal}"
    )

expected_relaxations = [["G6_AGGRESSIVE_TREASURY_GROWTH"]]
if summary["minimal_relaxations_from_full"] != expected_relaxations:
    raise SystemExit(
        "unexpected tokenomics minimal relaxations:\n"
        f"expected={expected_relaxations}\n"
        f"actual={summary['minimal_relaxations_from_full']}"
    )

print("Tokenomics goal frontier check passed")
PY

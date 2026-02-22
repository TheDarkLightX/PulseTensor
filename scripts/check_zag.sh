#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ZAG_DIR="${ROOT_DIR}/external/ZAG"
MODE="${1:-quick}"
ZAG_SEED="${ZAG_SEED:-1}"
ZAG_QUICK_TRIALS="${ZAG_QUICK_TRIALS:-200}"
ZAG_FULL_TRIALS="${ZAG_FULL_TRIALS:-2000}"
ZAG_FULL_BENCH_REPEATS="${ZAG_FULL_BENCH_REPEATS:-30}"

if [[ ! -d "${ZAG_DIR}" ]]; then
  echo "ZAG repo not found at ${ZAG_DIR}"
  exit 1
fi

if [[ "${MODE}" != "quick" && "${MODE}" != "full" ]]; then
  echo "Invalid ZAG mode: ${MODE}. Expected: quick|full"
  exit 1
fi

pushd "${ZAG_DIR}" >/dev/null
lake build

if [[ "${MODE}" == "full" ]]; then
  lake exe zenith_test -- --seed "${ZAG_SEED}" --trials "${ZAG_FULL_TRIALS}" --candidate all
  lake exe zenith_bench -- --suite smoke --repeats "${ZAG_FULL_BENCH_REPEATS}" --out runs/pulsetensor_timings.json --candidate all
else
  lake exe zenith_test -- --seed "${ZAG_SEED}" --trials "${ZAG_QUICK_TRIALS}" --candidate all
fi
popd >/dev/null

echo "ZAG checks completed in ${MODE} mode (seed=${ZAG_SEED})"

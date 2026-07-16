#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_DIR="${ROOT_DIR}/runs/security"
RUN_EPOCH="$(date +%s)"
FUZZ_LOG="${RUN_DIR}/fuzz.log"
INVARIANT_LOG="${RUN_DIR}/invariant.log"
SUMMARY="${RUN_DIR}/fuzz_invariant_summary.json"
FUZZ_PENDING="${FUZZ_LOG}.pending.${RUN_EPOCH}"
INVARIANT_PENDING="${INVARIANT_LOG}.pending.${RUN_EPOCH}"
SUMMARY_PENDING="${SUMMARY}.pending.${RUN_EPOCH}"

# These are evidence-producing campaigns, so their bounds are constants rather
# than caller-tunable minima. This prevents an environment override from making
# a release receipt describe a stronger campaign than the one that ran.
export FOUNDRY_OPTIMIZER_RUNS=1
export FOUNDRY_FUZZ_SEED=1
export FOUNDRY_FUZZ_RUNS=1024
export FOUNDRY_INVARIANT_RUNS=256
export FOUNDRY_INVARIANT_DEPTH=64
export FOUNDRY_INVARIANT_FAIL_ON_REVERT=true

mkdir -p "${RUN_DIR}"
for artifact in "${FUZZ_LOG}" "${INVARIANT_LOG}" "${SUMMARY}"; do
  if [[ -e "${artifact}" ]]; then
    mv "${artifact}" "${artifact}.stale.${RUN_EPOCH}"
  fi
done

run_and_capture() {
  local output_path="$1"
  shift

  set +e
  "$@" 2>&1 | tee "${output_path}"
  local statuses=("${PIPESTATUS[@]}")
  set -e

  if (( statuses[0] != 0 )); then
    echo "Forge campaign failed with exit code ${statuses[0]}"
    exit "${statuses[0]}"
  fi
  if (( statuses[1] != 0 )); then
    echo "Could not retain Forge campaign log (tee exit ${statuses[1]})"
    exit "${statuses[1]}"
  fi
}

pushd "${ROOT_DIR}" >/dev/null
run_and_capture "${FUZZ_PENDING}" forge test --match-contract PulseTensorCoreFuzzTest
run_and_capture "${INVARIANT_PENDING}" forge test --match-contract PulseTensorCoreInvariantTest
python3 scripts/check_fuzz_invariant_campaign.py \
  --fuzz-log "${FUZZ_PENDING}" \
  --invariant-log "${INVARIANT_PENDING}" \
  --output "${SUMMARY_PENDING}"
popd >/dev/null

mv "${FUZZ_PENDING}" "${FUZZ_LOG}"
mv "${INVARIANT_PENDING}" "${INVARIANT_LOG}"
mv "${SUMMARY_PENDING}" "${SUMMARY}"

echo "Fuzz and invariant checks passed with exact receipt (fuzz=1024, invariant=256x64, seed=1)"

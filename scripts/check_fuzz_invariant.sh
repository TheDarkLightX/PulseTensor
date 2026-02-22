#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
FOUNDRY_FUZZ_SEED="${FOUNDRY_FUZZ_SEED:-1}"
FOUNDRY_INVARIANT_SEED="${FOUNDRY_INVARIANT_SEED:-1}"
FOUNDRY_FUZZ_RUNS="${FOUNDRY_FUZZ_RUNS:-1024}"
FOUNDRY_INVARIANT_RUNS="${FOUNDRY_INVARIANT_RUNS:-256}"
FOUNDRY_INVARIANT_DEPTH="${FOUNDRY_INVARIANT_DEPTH:-64}"
MIN_FUZZ_RUNS=1024
MIN_INVARIANT_RUNS=256
MIN_INVARIANT_DEPTH=64

require_min_int() {
  local name="$1"
  local value="$2"
  local minimum="$3"
  if [[ ! "${value}" =~ ^[0-9]+$ ]]; then
    echo "${name} must be a positive integer: ${value}"
    exit 1
  fi
  if (( value < minimum )); then
    echo "${name}=${value} is below required minimum ${minimum}"
    exit 1
  fi
}

require_min_int "FOUNDRY_FUZZ_RUNS" "${FOUNDRY_FUZZ_RUNS}" "${MIN_FUZZ_RUNS}"
require_min_int "FOUNDRY_INVARIANT_RUNS" "${FOUNDRY_INVARIANT_RUNS}" "${MIN_INVARIANT_RUNS}"
require_min_int "FOUNDRY_INVARIANT_DEPTH" "${FOUNDRY_INVARIANT_DEPTH}" "${MIN_INVARIANT_DEPTH}"

pushd "${ROOT_DIR}" >/dev/null
FOUNDRY_FUZZ_SEED="${FOUNDRY_FUZZ_SEED}" \
FOUNDRY_FUZZ_RUNS="${FOUNDRY_FUZZ_RUNS}" \
forge test --match-contract PulseTensorCoreFuzzTest

FOUNDRY_FUZZ_SEED="${FOUNDRY_INVARIANT_SEED}" \
FOUNDRY_INVARIANT_RUNS="${FOUNDRY_INVARIANT_RUNS}" \
FOUNDRY_INVARIANT_DEPTH="${FOUNDRY_INVARIANT_DEPTH}" \
forge test --match-contract PulseTensorCoreInvariantTest
popd >/dev/null

echo "Fuzz and invariant checks passed (fuzz_seed=${FOUNDRY_FUZZ_SEED}, invariant_seed=${FOUNDRY_INVARIANT_SEED})"

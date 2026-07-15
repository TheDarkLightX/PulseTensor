#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKER="${ROOT_DIR}/scripts/check_echidna_harness.sh"
CONFIG="${ROOT_DIR}/test/echidna/echidna.yaml"
INVALID_CONTRACT="test/echidna/fixtures/InvalidEchidnaHarness.sol:InvalidEchidnaHarness"
TEMP_CONFIG="$(mktemp)"
trap 'rm -f "${TEMP_CONFIG}"' EXIT

bash "${CHECKER}" "${CONFIG}"

cp "${CONFIG}" "${TEMP_CONFIG}"
printf '\ntestMode: assertion\n' >>"${TEMP_CONFIG}"
if bash "${CHECKER}" "${TEMP_CONFIG}" >/dev/null 2>&1; then
  echo "harness checker accepted a duplicate testMode mutation"
  exit 1
fi

if bash "${CHECKER}" "${CONFIG}" "${INVALID_CONTRACT}" >/dev/null 2>&1; then
  echo "harness checker accepted an invalid ABI mutation"
  exit 1
fi

echo "Echidna harness checker mutation tests passed"

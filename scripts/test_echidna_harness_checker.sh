#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKER="${ROOT_DIR}/scripts/check_echidna_harness.sh"
CONFIG="${ROOT_DIR}/test/echidna/echidna.yaml"
INVALID_CONTRACT="test/echidna/fixtures/InvalidEchidnaHarness.sol:InvalidEchidnaHarness"
TEMP_CONFIG="$(mktemp)"
CAMPAIGN_FIXTURE="${ROOT_DIR}/test/echidna/fixtures/valid_campaign.log"
TEMP_CAMPAIGN="$(mktemp)"
TEMP_SUMMARY="$(mktemp)"
trap 'rm -f "${TEMP_CONFIG}" "${TEMP_CAMPAIGN}" "${TEMP_SUMMARY}"' EXIT

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

cp "${CONFIG}" "${TEMP_CONFIG}"
sed -i 's/^testLimit: 8000$/testLimit: 1/' "${TEMP_CONFIG}"
if bash "${CHECKER}" "${TEMP_CONFIG}" >/dev/null 2>&1; then
  echo "harness checker accepted an under-strength campaign"
  exit 1
fi

python3 "${ROOT_DIR}/scripts/check_echidna_campaign.py" "${CAMPAIGN_FIXTURE}" "${TEMP_SUMMARY}" >/dev/null

cp "${CAMPAIGN_FIXTURE}" "${TEMP_CAMPAIGN}"
sed -i 's/^Total calls: 8000$/Total calls: 1/' "${TEMP_CAMPAIGN}"
if python3 "${ROOT_DIR}/scripts/check_echidna_campaign.py" "${TEMP_CAMPAIGN}" "${TEMP_SUMMARY}" >/dev/null 2>&1; then
  echo "campaign checker accepted an under-strength report"
  exit 1
fi

cp "${CAMPAIGN_FIXTURE}" "${TEMP_CAMPAIGN}"
sed -i 's/echidna_gate_known_failure: failed/echidna_gate_known_failure: passing/' "${TEMP_CAMPAIGN}"
if python3 "${ROOT_DIR}/scripts/check_echidna_campaign.py" "${TEMP_CAMPAIGN}" "${TEMP_SUMMARY}" >/dev/null 2>&1; then
  echo "campaign checker accepted a missed negative control"
  exit 1
fi

cp "${CAMPAIGN_FIXTURE}" "${TEMP_CAMPAIGN}"
sed -i '/echidna_stake_and_native_liabilities_conserved: passing/a echidna_stake_and_native_liabilities_conserved: failed with no transactions made' "${TEMP_CAMPAIGN}"
if python3 "${ROOT_DIR}/scripts/check_echidna_campaign.py" "${TEMP_CAMPAIGN}" "${TEMP_SUMMARY}" >/dev/null 2>&1; then
  echo "campaign checker accepted contradictory property states"
  exit 1
fi

cp "${CAMPAIGN_FIXTURE}" "${TEMP_CAMPAIGN}"
sed -i '/echidna_validator_count_exact_and_bounded: passing/a echidna_validator_count_exact_and_bounded: passing' "${TEMP_CAMPAIGN}"
if python3 "${ROOT_DIR}/scripts/check_echidna_campaign.py" "${TEMP_CAMPAIGN}" "${TEMP_SUMMARY}" >/dev/null 2>&1; then
  echo "campaign checker accepted a duplicate property report"
  exit 1
fi

echo "Echidna harness and campaign checker mutation tests passed"

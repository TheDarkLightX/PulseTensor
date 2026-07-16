#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

while IFS= read -r foundry_env_name; do
  if [[ "${foundry_env_name}" == "FOUNDRY_OPTIMIZER_RUNS" && "${!foundry_env_name}" == "1" ]]; then
    continue
  fi
  echo "refusing unapproved Foundry environment override: ${foundry_env_name}"
  exit 1
done < <(compgen -A variable FOUNDRY_)
export FOUNDRY_OPTIMIZER_RUNS=1

forge build >/dev/null

exec python3 "${ROOT_DIR}/scripts/check_assurance_evidence.py" \
  "${ROOT_DIR}" \
  "${ROOT_DIR}/runs/assurance/evidence.json"

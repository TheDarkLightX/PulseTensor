#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_SECURITY="${RUN_SECURITY:-1}"
RUN_ECHIDNA="${RUN_ECHIDNA:-0}"
RUN_DEPLOY_REHEARSAL="${RUN_DEPLOY_REHEARSAL:-1}"
RUN_START_EPOCH="${RUN_START_EPOCH:-$(date +%s)}"
export FOUNDRY_OPTIMIZER_RUNS="1"

pushd "${ROOT_DIR}" >/dev/null
bash scripts/check_private_boundaries.sh
bash scripts/check_deploy_signer_safety.sh
bash scripts/check_protocol_spec.sh
if [[ "${RUN_DEPLOY_REHEARSAL}" == "1" ]]; then
  bash scripts/check_deploy_rehearsal.sh
else
  echo "Encrypted-keystore deployment rehearsal skipped (RUN_DEPLOY_REHEARSAL=${RUN_DEPLOY_REHEARSAL})"
fi
forge build
forge test
if [[ "${RUN_SECURITY}" == "1" ]]; then
  RUN_ECHIDNA="${RUN_ECHIDNA}" RUN_START_EPOCH="${RUN_START_EPOCH}" bash scripts/check_security.sh
else
  echo "Security checks skipped (RUN_SECURITY=${RUN_SECURITY})"
fi
popd >/dev/null

if [[ "${RUN_SECURITY}" == "1" ]]; then
  artifact_manifest="docs/security/artifact_manifest.security.txt"
  if [[ "${RUN_ECHIDNA}" == "1" ]]; then
    artifact_manifest="docs/security/artifact_manifest.release.txt"
  fi
  bash "${ROOT_DIR}/scripts/check_artifact_freshness.sh" \
    "${artifact_manifest}" \
    "${RUN_START_EPOCH}"
fi

echo "Verification pipeline complete"

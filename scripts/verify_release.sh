#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -n "${ZAG_MODE:-}" && "${ZAG_MODE}" != "quick" ]]; then
  echo "verify_release enforces ZAG quick mode; use scripts/verify_release_full.sh for full mode"
  exit 1
fi

bash "${ROOT_DIR}/scripts/verify_toolchain.sh"
RUN_START_EPOCH="$(date +%s)" \
RUN_MORPH=1 \
RUN_ZAG=1 \
RUN_ORCH=1 \
RUN_SECURITY=1 \
RUN_ECHIDNA=1 \
ALLOW_STALE_BUG_DB=0 \
SECURITY_CONTROL_STRICT_STATUSES=1 \
ZAG_MODE=quick \
bash "${ROOT_DIR}/scripts/verify_all.sh"

echo "Release verification pipeline complete"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

bash "${ROOT_DIR}/scripts/verify_toolchain.sh"
bash "${ROOT_DIR}/scripts/check_deploy_code_size.sh"
RUN_START_EPOCH="$(date +%s)" \
RUN_SECURITY=1 \
RUN_ECHIDNA=1 \
ALLOW_STALE_BUG_DB=0 \
SECURITY_CONTROL_STRICT_STATUSES=1 \
bash "${ROOT_DIR}/scripts/verify_all.sh"

echo "Release verification pipeline complete"

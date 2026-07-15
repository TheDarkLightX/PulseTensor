#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK_FILE="${ROOT_DIR}/scripts/toolchain.lock"

if [[ ! -f "${LOCK_FILE}" ]]; then
  echo "Toolchain lock file not found: ${LOCK_FILE}"
  exit 1
fi

source "${LOCK_FILE}"

if ! command -v forge >/dev/null 2>&1; then
  echo "Foundry is required. Install from https://book.getfoundry.sh/getting-started/installation"
  exit 1
fi

if [[ ! -d "${ROOT_DIR}/lib/forge-std" ]]; then
  forge install "foundry-rs/forge-std@${FORGE_STD_REVISION}" --no-git
fi

expected_forge_std_version="${FORGE_STD_VERSION#v}"
actual_forge_std_version="$(
  python3 - "${ROOT_DIR}/lib/forge-std/package.json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    print(json.load(handle).get("version", ""))
PY
)"
if [[ "${actual_forge_std_version}" != "${expected_forge_std_version}" ]]; then
  echo "forge-std version mismatch"
  echo "  expected: ${expected_forge_std_version}"
  echo "  actual:   ${actual_forge_std_version:-<unknown>}"
  echo "Remove lib/forge-std and rerun bootstrap to install the pinned dependency."
  exit 1
fi

actual_forge_std_content_sha256="$(
  cd "${ROOT_DIR}/lib/forge-std"
  find . -type f -not -path './.git/*' -print0 \
    | LC_ALL=C sort -z \
    | xargs -0 sha256sum \
    | sha256sum \
    | awk '{print $1}'
)"
if [[ "${actual_forge_std_content_sha256}" != "${FORGE_STD_CONTENT_SHA256}" ]]; then
  echo "forge-std content digest mismatch"
  echo "  revision: ${FORGE_STD_REVISION}"
  echo "  expected: ${FORGE_STD_CONTENT_SHA256}"
  echo "  actual:   ${actual_forge_std_content_sha256}"
  echo "Remove lib/forge-std and rerun bootstrap to install the pinned dependency."
  exit 1
fi

if [[ ! -d "${ROOT_DIR}/.venv" ]]; then
  python3 -m venv "${ROOT_DIR}/.venv"
fi

"${ROOT_DIR}/.venv/bin/pip" install --upgrade pip
"${ROOT_DIR}/.venv/bin/pip" install "slither-analyzer==${SLITHER_VERSION}"

echo "Bootstrap complete"
echo "Next:"
echo "  source .venv/bin/activate"
echo "  make build"
echo "  make test"
echo "  make verify-release"

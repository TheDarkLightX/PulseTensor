#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_PATH="${ROOT_DIR}/scripts/solhint.security.json"
SOLHINT_BIN="${ROOT_DIR}/scripts/solhint/node_modules/.bin/solhint"
SOLHINT_LOCK="${ROOT_DIR}/scripts/solhint/package-lock.json"
source "${ROOT_DIR}/scripts/toolchain.lock"

if [[ ! -x "${SOLHINT_BIN}" ]]; then
  echo "repository-locked Solhint environment not found; run scripts/bootstrap.sh"
  exit 1
fi

if [[ ! -f "${CONFIG_PATH}" ]]; then
  echo "solhint config not found: ${CONFIG_PATH}"
  exit 1
fi

actual_solhint_lock_sha256="$(sha256sum "${SOLHINT_LOCK}" | awk '{print $1}')"
if [[ "${actual_solhint_lock_sha256}" != "${SOLHINT_PACKAGE_LOCK_SHA256}" ]]; then
  echo "Solhint package lock digest mismatch"
  echo "  expected: ${SOLHINT_PACKAGE_LOCK_SHA256}"
  echo "  actual:   ${actual_solhint_lock_sha256}"
  exit 1
fi

actual_solhint_version="$("${SOLHINT_BIN}" --version | head -n 1)"
if [[ "${actual_solhint_version}" != "${SOLHINT_VERSION_PREFIX}" ]]; then
  echo "Solhint version mismatch: expected ${SOLHINT_VERSION_PREFIX}, found ${actual_solhint_version}"
  exit 1
fi

pushd "${ROOT_DIR}" >/dev/null
"${SOLHINT_BIN}" --disc -c "${CONFIG_PATH}" --max-warnings 0 "src/**/*.sol"
popd >/dev/null

echo "Solhint checks passed"

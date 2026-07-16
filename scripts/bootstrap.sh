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

for command_name in node npm; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "${command_name} is required to install the repository-locked Solhint toolchain"
    exit 1
  fi
done

actual_node_version="$(node --version | head -n 1)"
if [[ "${actual_node_version}" != "${NODE_VERSION_PREFIX}" ]]; then
  echo "Node.js version mismatch: expected ${NODE_VERSION_PREFIX}, found ${actual_node_version}"
  exit 1
fi

actual_npm_version="$(npm --version | head -n 1)"
if [[ "${actual_npm_version}" != "${NPM_VERSION_PREFIX}" ]]; then
  echo "npm version mismatch: expected ${NPM_VERSION_PREFIX}, found ${actual_npm_version}"
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

actual_venv_python_version="$("${ROOT_DIR}/.venv/bin/python" --version | head -n 1)"
if [[ "${actual_venv_python_version}" != "${PYTHON_VERSION_PREFIX}" ]]; then
  echo "Slither virtualenv Python version mismatch"
  echo "  expected: ${PYTHON_VERSION_PREFIX}"
  echo "  actual:   ${actual_venv_python_version}"
  echo "Remove .venv and rerun bootstrap with the pinned Python interpreter."
  exit 1
fi

actual_venv_pip_version="$("${ROOT_DIR}/.venv/bin/python" -c 'import importlib.metadata; print(importlib.metadata.version("pip"))')"
if [[ "${actual_venv_pip_version}" != "${PIP_VERSION}" ]]; then
  echo "Slither virtualenv pip version mismatch"
  echo "  expected: ${PIP_VERSION}"
  echo "  actual:   ${actual_venv_pip_version}"
  echo "Remove .venv and rerun bootstrap with the pinned Python interpreter."
  exit 1
fi

"${ROOT_DIR}/.venv/bin/pip" install "slither-analyzer==${SLITHER_VERSION}"

SOLHINT_ROOT="${ROOT_DIR}/scripts/solhint"
SOLHINT_LOCK="${SOLHINT_ROOT}/package-lock.json"
if [[ ! -f "${SOLHINT_LOCK}" ]]; then
  echo "Solhint package lock not found: ${SOLHINT_LOCK}"
  exit 1
fi

actual_solhint_lock_sha256="$(sha256sum "${SOLHINT_LOCK}" | awk '{print $1}')"
if [[ "${actual_solhint_lock_sha256}" != "${SOLHINT_PACKAGE_LOCK_SHA256}" ]]; then
  echo "Solhint package lock digest mismatch"
  echo "  expected: ${SOLHINT_PACKAGE_LOCK_SHA256}"
  echo "  actual:   ${actual_solhint_lock_sha256}"
  exit 1
fi

npm ci \
  --prefix "${SOLHINT_ROOT}" \
  --ignore-scripts \
  --no-audit \
  --no-fund

actual_solhint_version="$("${SOLHINT_ROOT}/node_modules/.bin/solhint" --version | head -n 1)"
if [[ "${actual_solhint_version}" != "${SOLHINT_VERSION_PREFIX}" ]]; then
  echo "Solhint version mismatch: expected ${SOLHINT_VERSION_PREFIX}, found ${actual_solhint_version}"
  exit 1
fi

echo "Bootstrap complete"
echo "Next:"
echo "  source .venv/bin/activate"
echo "  make build"
echo "  make test"
echo "  make verify-release"

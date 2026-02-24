#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK_FILE="${ROOT_DIR}/scripts/toolchain.lock"

if [[ ! -f "${LOCK_FILE}" ]]; then
  echo "Toolchain lock file not found: ${LOCK_FILE}"
  exit 1
fi

source "${LOCK_FILE}"

require_prefix() {
  local label="$1"
  local actual="$2"
  local expected_prefix="$3"
  if [[ "${actual}" != "${expected_prefix}"* ]]; then
    echo "${label} mismatch"
    echo "  expected prefix: ${expected_prefix}"
    echo "  actual:          ${actual}"
    exit 1
  fi
}

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "required command not found: ${command_name}"
    exit 1
  fi
}

require_command forge
require_command python3
require_command docker
require_command jq
require_command solhint

require_prefix "forge version" "$(forge --version | head -n 1)" "${FORGE_VERSION_PREFIX}"
require_prefix "python version" "$(python3 --version | head -n 1)" "${PYTHON_VERSION_PREFIX}"
require_prefix "docker version" "$(docker --version | head -n 1)" "${DOCKER_VERSION_PREFIX}"
require_prefix "jq version" "$(jq --version | head -n 1)" "${JQ_VERSION_PREFIX}"
require_prefix "solhint version" "$(solhint --version | head -n 1)" "${SOLHINT_VERSION_PREFIX}"

echo "Toolchain lock verified"

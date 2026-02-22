#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK_FILE="${ROOT_DIR}/scripts/toolchain.lock"

if [[ ! -f "${LOCK_FILE}" ]]; then
  echo "Toolchain lock file not found: ${LOCK_FILE}"
  exit 1
fi

source "${LOCK_FILE}"

require_exact() {
  local label="$1"
  local actual="$2"
  local expected="$3"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "${label} mismatch"
    echo "  expected: ${expected}"
    echo "  actual:   ${actual}"
    exit 1
  fi
}

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

require_clean_git() {
  local label="$1"
  local repo_dir="$2"
  if [[ -n "$(git -C "${repo_dir}" status --porcelain)" ]]; then
    echo "${label} working tree is dirty: ${repo_dir}"
    exit 1
  fi
}

require_exact "ESSO commit" "$(git -C "${ROOT_DIR}/external/ESSO" rev-parse HEAD)" "${ESSO_COMMIT}"
require_exact "Morph commit" "$(git -C "${ROOT_DIR}/external/Morph" rev-parse HEAD)" "${MORPH_COMMIT}"
require_exact "ZAG commit" "$(git -C "${ROOT_DIR}/external/ZAG" rev-parse HEAD)" "${ZAG_COMMIT}"
require_exact "Bittensor commit" "$(git -C "${ROOT_DIR}/external/bittensor" rev-parse HEAD)" "${BITTENSOR_COMMIT}"
require_exact "go-pulse commit" "$(git -C "${ROOT_DIR}/external/go-pulse" rev-parse HEAD)" "${GO_PULSE_COMMIT}"
require_exact "Orchestration-Unit commit" "$(git -C "${ROOT_DIR}/external/Orchestration-Unit" rev-parse HEAD)" "${ORCH_UNIT_COMMIT}"
require_clean_git "ESSO" "${ROOT_DIR}/external/ESSO"
require_clean_git "Morph" "${ROOT_DIR}/external/Morph"
require_clean_git "ZAG" "${ROOT_DIR}/external/ZAG"
require_clean_git "Bittensor" "${ROOT_DIR}/external/bittensor"
require_clean_git "go-pulse" "${ROOT_DIR}/external/go-pulse"
require_clean_git "Orchestration-Unit" "${ROOT_DIR}/external/Orchestration-Unit"

require_prefix "forge version" "$(forge --version | head -n 1)" "${FORGE_VERSION_PREFIX}"
require_prefix "z3 version" "$(z3 --version | head -n 1)" "${Z3_VERSION_PREFIX}"
require_prefix "cvc5 version" "$(cvc5 --version | head -n 1)" "${CVC5_VERSION_PREFIX}"
require_prefix "lake version" "$(lake --version | head -n 1)" "${LAKE_VERSION_PREFIX}"
require_prefix "python version" "$(python3 --version | head -n 1)" "${PYTHON_VERSION_PREFIX}"
require_prefix "docker version" "$(docker --version | head -n 1)" "${DOCKER_VERSION_PREFIX}"
require_prefix "jq version" "$(jq --version | head -n 1)" "${JQ_VERSION_PREFIX}"
require_prefix "solhint version" "$(solhint --version | head -n 1)" "${SOLHINT_VERSION_PREFIX}"

echo "Toolchain lock verified"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/toolchain.lock"

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "required command not found: $1"
    exit 1
  }
}

require_equal() {
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

for command_name in forge cast anvil python3 docker jq solhint sha256sum; do
  require_command "${command_name}"
done

require_equal "architecture" "$(uname -m)" "x86_64"
require_equal "forge version" "$(forge --version | head -n 1)" "${FORGE_RELEASE_VERSION}"
require_equal "python version" "$(python3 --version | head -n 1)" "${PYTHON_VERSION_PREFIX}"
require_equal "jq version" "$(jq --version | head -n 1)" "${JQ_VERSION_PREFIX}"
require_equal "solhint version" "$(solhint --version | head -n 1)" "${SOLHINT_VERSION_PREFIX}"
require_equal "forge binary digest" "$(sha256sum "$(command -v forge)" | awk '{print $1}')" "${FORGE_RELEASE_SHA256}"
require_equal "cast binary digest" "$(sha256sum "$(command -v cast)" | awk '{print $1}')" "${CAST_RELEASE_SHA256}"
require_equal "anvil binary digest" "$(sha256sum "$(command -v anvil)" | awk '{print $1}')" "${ANVIL_RELEASE_SHA256}"

# The hosted runner owns the Docker daemon, so its version is evidence rather
# than a reproducibility claim. Security workloads themselves use image digests.
echo "docker_host=$(docker --version | head -n 1)"
echo "CI toolchain verified"

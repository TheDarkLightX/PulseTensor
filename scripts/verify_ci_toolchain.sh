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

for command_name in forge cast anvil python3 docker jq node npm rg sha256sum; do
  require_command "${command_name}"
done

require_equal "architecture" "$(uname -m)" "x86_64"
require_equal "forge version" "$(forge --version | head -n 1)" "${FORGE_RELEASE_VERSION}"
require_equal "python version" "$(python3 --version | head -n 1)" "${PYTHON_VERSION_PREFIX}"
require_equal "jq version" "$(jq --version | head -n 1)" "${JQ_VERSION_PREFIX}"
require_equal "Node version" "$(node --version | head -n 1)" "${NODE_VERSION_PREFIX}"
require_equal "npm version" "$(npm --version | head -n 1)" "${NPM_VERSION_PREFIX}"
require_equal "ripgrep version" "$(rg --version | head -n 1)" "${RIPGREP_VERSION}"
require_equal "forge binary digest" "$(sha256sum "$(command -v forge)" | awk '{print $1}')" "${FORGE_RELEASE_SHA256}"
require_equal "cast binary digest" "$(sha256sum "$(command -v cast)" | awk '{print $1}')" "${CAST_RELEASE_SHA256}"
require_equal "anvil binary digest" "$(sha256sum "$(command -v anvil)" | awk '{print $1}')" "${ANVIL_RELEASE_SHA256}"

[[ -f "${ROOT_DIR}/lib/forge-std/package.json" ]] || {
  echo "pinned forge-std dependency not found"
  exit 1
}
require_equal \
  "forge-std version" \
  "$(python3 - "${ROOT_DIR}/lib/forge-std/package.json" <<'PY'
import json
import sys
print(json.load(open(sys.argv[1], encoding="utf-8")).get("version", ""))
PY
)" \
  "${FORGE_STD_VERSION#v}"
forge_std_content_sha256="$(
  cd "${ROOT_DIR}/lib/forge-std"
  find . -type f -not -path './.git/*' -print0 \
    | LC_ALL=C sort -z \
    | xargs -0 sha256sum \
    | sha256sum \
    | awk '{print $1}'
)"
require_equal "forge-std content digest" "${forge_std_content_sha256}" "${FORGE_STD_CONTENT_SHA256}"
solhint_root="${ROOT_DIR}/scripts/solhint"
solhint_bin="${solhint_root}/node_modules/.bin/solhint"
solhint_lock="${solhint_root}/package-lock.json"
[[ -x "${solhint_bin}" && -f "${solhint_lock}" ]] || {
  echo "repository-locked Solhint environment not found; run scripts/bootstrap.sh"
  exit 1
}
require_equal "Solhint version" "$("${solhint_bin}" --version | head -n 1)" "${SOLHINT_VERSION_PREFIX}"
require_equal \
  "Solhint package lock digest" \
  "$(sha256sum "${solhint_lock}" | awk '{print $1}')" \
  "${SOLHINT_PACKAGE_LOCK_SHA256}"
[[ -x "${ROOT_DIR}/.venv/bin/python" && -x "${ROOT_DIR}/.venv/bin/slither" ]] || {
  echo "pinned Slither environment not found; run scripts/bootstrap.sh"
  exit 1
}
require_equal \
  "Slither virtualenv Python version" \
  "$("${ROOT_DIR}/.venv/bin/python" --version | head -n 1)" \
  "${PYTHON_VERSION_PREFIX}"
require_equal \
  "Slither virtualenv pip version" \
  "$("${ROOT_DIR}/.venv/bin/python" -c 'import importlib.metadata; print(importlib.metadata.version("pip"))')" \
  "${PIP_VERSION}"
require_equal \
  "Slither top-level version" \
  "$("${ROOT_DIR}/.venv/bin/python" -c 'import importlib.metadata; print(importlib.metadata.version("slither-analyzer"))')" \
  "${SLITHER_VERSION}"

forge build >/dev/null
solc_path="${HOME}/.svm/${SOLC_VERSION}/solc-${SOLC_VERSION}"
[[ -x "${solc_path}" ]] || {
  echo "pinned solc binary not found: ${solc_path}"
  exit 1
}
require_equal "solc binary digest" "$(sha256sum "${solc_path}" | awk '{print $1}')" "${SOLC_RELEASE_SHA256}"

# The hosted runner owns the Docker daemon, so its version is evidence rather
# than a reproducibility claim. Security workloads themselves use image digests.
echo "docker_host=$(docker --version | head -n 1)"
echo "Exact pinned release components verified"

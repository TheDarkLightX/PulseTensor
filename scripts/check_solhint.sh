#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_PATH="${ROOT_DIR}/scripts/solhint.security.json"

if ! command -v solhint >/dev/null 2>&1; then
  echo "solhint not found"
  exit 1
fi

if [[ ! -f "${CONFIG_PATH}" ]]; then
  echo "solhint config not found: ${CONFIG_PATH}"
  exit 1
fi

pushd "${ROOT_DIR}" >/dev/null
solhint -c "${CONFIG_PATH}" --max-warnings 0 "src/**/*.sol"
popd >/dev/null

echo "Solhint checks passed"

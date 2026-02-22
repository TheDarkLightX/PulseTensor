#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v forge >/dev/null 2>&1; then
  echo "Foundry is required. Install from https://book.getfoundry.sh/getting-started/installation"
  exit 1
fi

if [[ ! -d "${ROOT_DIR}/lib/forge-std" ]]; then
  forge install foundry-rs/forge-std --no-git
fi

if [[ ! -d "${ROOT_DIR}/.venv" ]]; then
  python3 -m venv "${ROOT_DIR}/.venv"
fi

"${ROOT_DIR}/.venv/bin/pip" install --upgrade pip
"${ROOT_DIR}/.venv/bin/pip" install -e "${ROOT_DIR}/external/ESSO"
"${ROOT_DIR}/.venv/bin/pip" install slither-analyzer==0.10.4

echo "Bootstrap complete"
echo "Next:"
echo "  source .venv/bin/activate"
echo "  make build"
echo "  make test"
echo "  make verify-esso"

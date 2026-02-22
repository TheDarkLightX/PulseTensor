#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MORPH_DIR="${ROOT_DIR}/external/Morph"
OUT_DIR="${ROOT_DIR}/runs/morph_campaign"
PYTHON_BIN="${ROOT_DIR}/.venv/bin/python"

if [[ ! -d "${MORPH_DIR}" ]]; then
  echo "Morph repo not found at ${MORPH_DIR}"
  exit 1
fi

mkdir -p "${OUT_DIR}"

if [[ ! -x "${PYTHON_BIN}" ]]; then
  PYTHON_BIN="python3"
fi

pushd "${MORPH_DIR}" >/dev/null
"${PYTHON_BIN}" -m morph scientist campaign \
  --domain sat_cnf \
  --out "${OUT_DIR}" \
  --seed 1 \
  --max-rounds 2 \
  --max-wall-seconds 120
popd >/dev/null

echo "Morph campaign completed: ${OUT_DIR}"

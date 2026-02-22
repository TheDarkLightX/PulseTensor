#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ORCH_DIR="${ROOT_DIR}/external/Orchestration-Unit"
PYTHON_BIN="${ROOT_DIR}/.venv/bin/python"

if [[ ! -d "${ORCH_DIR}" ]]; then
  echo "Orchestration-Unit repo not found at ${ORCH_DIR}"
  exit 1
fi

if [[ ! -x "${PYTHON_BIN}" ]]; then
  PYTHON_BIN="python3"
fi

TMP_ONE="$(mktemp)"
TMP_TWO="$(mktemp)"
trap 'rm -f "${TMP_ONE}" "${TMP_TWO}"' EXIT

pushd "${ORCH_DIR}" >/dev/null
"${PYTHON_BIN}" -m orch_unit.cli --help >/dev/null
"${PYTHON_BIN}" -m orch_unit.cli kernels >"${TMP_ONE}"
"${PYTHON_BIN}" -m orch_unit.cli kernels >"${TMP_TWO}"
popd >/dev/null

if ! cmp -s "${TMP_ONE}" "${TMP_TWO}"; then
  echo "Orchestration-Unit deterministic kernel listing check failed"
  exit 1
fi

"${PYTHON_BIN}" - <<'PY' "${TMP_ONE}"
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8"))
kernels = payload.get("kernels")
if not isinstance(kernels, list) or len(kernels) == 0:
    raise SystemExit("Orchestration-Unit kernels output did not include non-empty kernels list")
PY

echo "Orchestration-Unit checks passed"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_PATH="${1:-${ROOT_DIR}/test/echidna/echidna.yaml}"
CONTRACT_ID="${2:-test/echidna/PulseTensorCoreEchidna.sol:PulseTensorCoreEchidna}"

pushd "${ROOT_DIR}" >/dev/null
python3 - "${CONFIG_PATH}" "${CONTRACT_ID}" <<'PY'
import json
import re
import subprocess
import sys
from pathlib import Path

config_path = Path(sys.argv[1])
contract_id = sys.argv[2]

top_level = {}
for line_number, raw_line in enumerate(config_path.read_text(encoding="utf-8").splitlines(), start=1):
    if not raw_line.strip() or raw_line.lstrip().startswith("#"):
        continue
    if raw_line[:1].isspace():
        continue
    match = re.fullmatch(r"([A-Za-z][A-Za-z0-9_-]*):\s*([^#]*?)\s*(?:#.*)?", raw_line)
    if match is None:
        raise SystemExit(f"unsupported top-level YAML at {config_path}:{line_number}")
    key, value = match.groups()
    if key in top_level:
        raise SystemExit(f"duplicate YAML key {key!r} at {config_path}:{line_number}")
    top_level[key] = value.strip().strip("\"'")

mode = top_level.get("testMode")
if mode is None:
    raise SystemExit("Echidna config must declare testMode")

result = subprocess.run(
    ["forge", "inspect", contract_id, "abi", "--json"],
    check=True,
    text=True,
    capture_output=True,
)
abi = json.loads(result.stdout)
properties = [
    entry for entry in abi
    if entry.get("type") == "function" and entry.get("name", "").startswith("echidna_")
]
if not properties:
    raise SystemExit("Echidna harness declares no echidna_* Boolean properties")
if mode != "property":
    raise SystemExit(
        f"Echidna testMode must be property for echidna_* Boolean properties; found {mode!r}"
    )

invalid = []
for entry in properties:
    valid = (
        entry.get("inputs") == []
        and entry.get("outputs") == [{"name": "", "type": "bool", "internalType": "bool"}]
        and entry.get("stateMutability") in {"view", "pure"}
    )
    if not valid:
        invalid.append(entry.get("name", "<unnamed>"))
if invalid:
    raise SystemExit(
        "Echidna properties must be zero-argument view/pure functions returning exactly bool: "
        + ", ".join(sorted(invalid))
    )

print(f"Echidna harness/config alignment passed (mode={mode}, properties={len(properties)})")
PY
popd >/dev/null

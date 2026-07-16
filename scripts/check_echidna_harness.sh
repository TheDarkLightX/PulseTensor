#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_PATH="${1:-${ROOT_DIR}/test/echidna/echidna.yaml}"
CONTRACT_ID="${2:-echidna/PulseTensorCoreEchidna.sol:PulseTensorCoreEchidna}"

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


def require_exact(key: str, expected: str) -> None:
    actual = top_level.get(key)
    if actual != expected:
        raise SystemExit(f"Echidna config {key} must be {expected!r}; found {actual!r}")


def require_int(key: str, *, minimum: int | None = None, exact: int | None = None) -> int:
    raw = top_level.get(key)
    if raw is None or not re.fullmatch(r"[0-9]+", raw):
        raise SystemExit(f"Echidna config {key} must be a non-negative integer")
    value = int(raw)
    if minimum is not None and value < minimum:
        raise SystemExit(f"Echidna config {key} must be at least {minimum}; found {value}")
    if exact is not None and value != exact:
        raise SystemExit(f"Echidna config {key} must be {exact}; found {value}")
    return value


require_exact("testMode", "property")
require_int("testLimit", minimum=8000)
require_int("seqLen", minimum=30)
require_int("workers", exact=1)
require_int("seed", exact=1)
require_exact("coverage", "true")
require_exact("format", "text")
require_exact("stopOnFail", "false")
require_int("maxTimeDelay", exact=0)
require_int("maxBlockDelay", exact=4)
require_int("balanceContract", exact=100_000_000_000_000_000_000)
require_exact("filterBlacklist", "false")

try:
    crytic_args = json.loads(top_level.get("cryticArgs", "null"))
except json.JSONDecodeError as exc:
    raise SystemExit(f"Echidna config cryticArgs must be a JSON array: {exc}") from exc
if crytic_args != ["--compile-force-framework", "foundry"]:
    raise SystemExit(f"unexpected Echidna cryticArgs: {crytic_args!r}")

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

expected_properties = {
    "echidna_stake_and_native_liabilities_conserved",
    "echidna_validator_count_exact_and_bounded",
    "echidna_registered_validators_can_validate",
    "echidna_pending_commitment_count_bounded",
    "echidna_active_commit_epoch_consistent_with_pending_count",
}
actual_properties = {entry["name"] for entry in properties}
if actual_properties != expected_properties:
    missing = sorted(expected_properties - actual_properties)
    unexpected = sorted(actual_properties - expected_properties)
    raise SystemExit(
        f"Echidna property inventory mismatch; missing={missing}, unexpected={unexpected}"
    )

expected_action_signatures = {
    "act_addStakeA(uint96)",
    "act_addStakeB(uint96)",
    "act_removeStakeA(uint96)",
    "act_removeStakeB(uint96)",
    "act_registerA()",
    "act_registerB()",
    "act_unregisterA()",
    "act_unregisterB()",
    "act_commitA(bytes32)",
    "act_commitB(bytes32)",
    "act_revealA()",
    "act_revealB()",
    "act_challengeA(bool)",
    "act_challengeB(bool)",
}
actual_action_signatures = {
    f'{entry["name"]}({",".join(item["type"] for item in entry.get("inputs", []))})'
    for entry in abi
    if entry.get("type") == "function" and entry.get("name", "").startswith("act_")
}
if actual_action_signatures != expected_action_signatures:
    raise SystemExit(
        "Echidna action inventory mismatch; "
        f"missing={sorted(expected_action_signatures - actual_action_signatures)}, "
        f"unexpected={sorted(actual_action_signatures - expected_action_signatures)}"
    )

try:
    configured_filters = json.loads(top_level.get("filterFunctions", "null"))
except json.JSONDecodeError as exc:
    raise SystemExit(f"Echidna config filterFunctions must be a JSON array: {exc}") from exc
expected_filters = {
    f"PulseTensorCoreEchidna.{signature}" for signature in expected_action_signatures
}
if not isinstance(configured_filters, list) or set(configured_filters) != expected_filters:
    raise SystemExit("Echidna filterFunctions must be the exact action allowlist")

print(
    "Echidna harness/config alignment passed "
    f"(mode={mode}, properties={len(properties)}, actions={len(actual_action_signatures)})"
)
PY
popd >/dev/null

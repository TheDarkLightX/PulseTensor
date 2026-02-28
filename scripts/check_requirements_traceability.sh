#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MATRIX_PATH="${ROOT_DIR}/specs/formal/requirements_traceability.json"
OUT_DIR="${ROOT_DIR}/runs/security"
REPORT_PATH="${OUT_DIR}/requirements_traceability_report.json"

if [[ ! -f "${MATRIX_PATH}" ]]; then
  echo "Requirements traceability matrix not found: ${MATRIX_PATH}"
  exit 1
fi

mkdir -p "${OUT_DIR}"

ROOT_DIR="${ROOT_DIR}" MATRIX_PATH="${MATRIX_PATH}" REPORT_PATH="${REPORT_PATH}" python3 - <<'PY'
import json
import os
import pathlib
import re
import sys
from datetime import datetime, timezone

ROOT = pathlib.Path(os.environ["ROOT_DIR"])
MATRIX_PATH = pathlib.Path(os.environ["MATRIX_PATH"])
REPORT_PATH = pathlib.Path(os.environ["REPORT_PATH"])

EXPECTED_SCHEMA = "pulsetensor/requirements-traceability/v1"
REPORT_SCHEMA = "pulsetensor/requirements-traceability-report/v1"


def fail(msg: str) -> None:
    print(msg, file=sys.stderr)
    raise SystemExit(1)


def require_path(path_str: str, *, field: str) -> pathlib.Path:
    if not isinstance(path_str, str) or path_str.strip() == "":
        fail(f"{field} must be a non-empty string path")
    path = ROOT / path_str
    if not path.exists():
        fail(f"{field} does not exist: {path_str}")
    return path


def as_string_list(value: object, *, field: str, non_empty: bool = True) -> list[str]:
    if not isinstance(value, list):
        fail(f"{field} must be a list")
    out: list[str] = []
    seen: set[str] = set()
    for idx, raw in enumerate(value):
        if not isinstance(raw, str) or raw.strip() == "":
            fail(f"{field}[{idx}] must be a non-empty string")
        item = raw.strip()
        if item in seen:
            fail(f"{field} contains duplicate value: {item}")
        seen.add(item)
        out.append(item)
    if non_empty and not out:
        fail(f"{field} must be non-empty")
    return out


payload = json.loads(MATRIX_PATH.read_text(encoding="utf-8"))
if not isinstance(payload, dict):
    fail("requirements traceability matrix must be a JSON object")

if payload.get("schema") != EXPECTED_SCHEMA:
    fail(f"unexpected schema: {payload.get('schema')!r} (expected {EXPECTED_SCHEMA!r})")

as_of_utc = payload.get("as_of_utc")
if not isinstance(as_of_utc, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", as_of_utc):
    fail("as_of_utc must use YYYY-MM-DD format")

contracts_raw = payload.get("contracts")
if not isinstance(contracts_raw, list) or len(contracts_raw) == 0:
    fail("contracts must be a non-empty list")

contract_defs: dict[str, dict] = {}
contract_function_sets: dict[str, set[str]] = {}
contract_covered_functions: dict[str, set[str]] = {}
for idx, contract in enumerate(contracts_raw):
    if not isinstance(contract, dict):
        fail(f"contracts[{idx}] must be an object")

    contract_id = contract.get("id")
    if not isinstance(contract_id, str) or contract_id.strip() == "":
        fail(f"contracts[{idx}].id must be a non-empty string")
    contract_id = contract_id.strip()
    if contract_id in contract_defs:
        fail(f"duplicate contract id: {contract_id}")

    contract_path_str = contract.get("path")
    contract_path = require_path(contract_path_str, field=f"contracts[{idx}].path")
    spec_path_str = contract.get("spec")
    require_path(spec_path_str, field=f"contracts[{idx}].spec")

    required_functions = as_string_list(contract.get("required_functions"), field=f"contracts[{idx}].required_functions")
    contract_source = contract_path.read_text(encoding="utf-8")
    for fn in required_functions:
        fn_re = re.compile(rf"\bfunction\s+{re.escape(fn)}\s*\(")
        if not fn_re.search(contract_source):
            fail(
                f"contracts[{idx}].required_functions references missing function {fn!r} in {contract_path_str}"
            )

    contract_defs[contract_id] = {
        "path": contract_path_str,
        "spec": spec_path_str,
        "required_functions": required_functions,
    }
    contract_function_sets[contract_id] = set(required_functions)
    contract_covered_functions[contract_id] = set()

commands_raw = payload.get("verification_commands")
if not isinstance(commands_raw, list) or len(commands_raw) == 0:
    fail("verification_commands must be a non-empty list")

commands: dict[str, str] = {}
for idx, cmd in enumerate(commands_raw):
    if not isinstance(cmd, dict):
        fail(f"verification_commands[{idx}] must be an object")
    command_id = cmd.get("id")
    command_text = cmd.get("command")
    if not isinstance(command_id, str) or command_id.strip() == "":
        fail(f"verification_commands[{idx}].id must be a non-empty string")
    if not isinstance(command_text, str) or command_text.strip() == "":
        fail(f"verification_commands[{idx}].command must be a non-empty string")
    command_id = command_id.strip()
    if command_id in commands:
        fail(f"duplicate verification command id: {command_id}")
    commands[command_id] = command_text.strip()

coverage_targets = payload.get("coverage_targets")
if not isinstance(coverage_targets, dict):
    fail("coverage_targets must be an object")

min_req = coverage_targets.get("min_requirements_per_contract")
min_bva = coverage_targets.get("min_bva_requirements_per_contract")
if not isinstance(min_req, dict) or not isinstance(min_bva, dict):
    fail("coverage_targets must define min_requirements_per_contract and min_bva_requirements_per_contract")

for contract_id in contract_defs.keys():
    if contract_id not in min_req or contract_id not in min_bva:
        fail(f"coverage target missing contract id: {contract_id}")
    if not isinstance(min_req[contract_id], int) or min_req[contract_id] < 1:
        fail(f"invalid min_requirements_per_contract[{contract_id}]")
    if not isinstance(min_bva[contract_id], int) or min_bva[contract_id] < 0:
        fail(f"invalid min_bva_requirements_per_contract[{contract_id}]")

requirements = payload.get("requirements")
if not isinstance(requirements, list) or len(requirements) == 0:
    fail("requirements must be a non-empty list")

allowed_criticalities = {"critical", "high", "medium", "low"}
allowed_verification_kinds = {"test", "command"}
requirement_ids: set[str] = set()
req_count_by_contract = {k: 0 for k in contract_defs.keys()}
bva_count_by_contract = {k: 0 for k in contract_defs.keys()}

for idx, req in enumerate(requirements):
    if not isinstance(req, dict):
        fail(f"requirements[{idx}] must be an object")

    req_id = req.get("id")
    if not isinstance(req_id, str) or req_id.strip() == "":
        fail(f"requirements[{idx}].id must be a non-empty string")
    req_id = req_id.strip()
    if req_id in requirement_ids:
        fail(f"duplicate requirement id: {req_id}")
    requirement_ids.add(req_id)

    contract_id = req.get("contract")
    if contract_id not in contract_defs:
        fail(f"requirements[{idx}] references unknown contract id: {contract_id!r}")

    title = req.get("title")
    if not isinstance(title, str) or title.strip() == "":
        fail(f"requirements[{idx}].title must be a non-empty string")

    criticality = req.get("criticality")
    if criticality not in allowed_criticalities:
        fail(
            f"requirements[{idx}].criticality must be one of {sorted(allowed_criticalities)}"
        )

    as_string_list(req.get("categories"), field=f"requirements[{idx}].categories")
    covered_functions = as_string_list(
        req.get("covered_functions"),
        field=f"requirements[{idx}].covered_functions",
    )
    for fn in covered_functions:
        if fn not in contract_function_sets[contract_id]:
            fail(
                f"requirements[{idx}] covered function {fn!r} is not declared in contracts[{contract_id}].required_functions"
            )
        contract_covered_functions[contract_id].add(fn)

    bva = req.get("boundary_value_analysis")
    if not isinstance(bva, bool):
        fail(f"requirements[{idx}].boundary_value_analysis must be boolean")
    if bva:
        as_string_list(
            req.get("bva_dimensions"),
            field=f"requirements[{idx}].bva_dimensions",
        )
        bva_count_by_contract[contract_id] += 1

    spec_refs = as_string_list(req.get("spec_refs"), field=f"requirements[{idx}].spec_refs")
    for spec_ref in spec_refs:
        require_path(spec_ref, field=f"requirements[{idx}].spec_refs")

    evidence = as_string_list(req.get("evidence"), field=f"requirements[{idx}].evidence")
    for evidence_path in evidence:
        require_path(evidence_path, field=f"requirements[{idx}].evidence")

    verifications = req.get("verifications")
    if not isinstance(verifications, list) or len(verifications) == 0:
        fail(f"requirements[{idx}].verifications must be a non-empty list")

    test_verification_count = 0
    for v_idx, verification in enumerate(verifications):
        if not isinstance(verification, dict):
            fail(f"requirements[{idx}].verifications[{v_idx}] must be an object")
        kind = verification.get("kind")
        if kind not in allowed_verification_kinds:
            fail(
                f"requirements[{idx}].verifications[{v_idx}].kind must be one of {sorted(allowed_verification_kinds)}"
            )
        if kind == "command":
            command_id = verification.get("id")
            if not isinstance(command_id, str) or command_id.strip() == "":
                fail(f"requirements[{idx}].verifications[{v_idx}].id must be non-empty string")
            if command_id.strip() not in commands:
                fail(
                    f"requirements[{idx}].verifications[{v_idx}] references unknown command id {command_id!r}"
                )
            continue

        test_verification_count += 1
        test_file = verification.get("file")
        test_fn = verification.get("function")
        test_path = require_path(test_file, field=f"requirements[{idx}].verifications[{v_idx}].file")
        if not isinstance(test_fn, str) or test_fn.strip() == "":
            fail(f"requirements[{idx}].verifications[{v_idx}].function must be non-empty string")
        test_fn = test_fn.strip()
        source = test_path.read_text(encoding="utf-8")
        fn_re = re.compile(rf"\bfunction\s+{re.escape(test_fn)}\s*\(")
        if not fn_re.search(source):
            fail(
                f"requirements[{idx}].verifications[{v_idx}] function {test_fn!r} not found in {test_file}"
            )

    if test_verification_count == 0:
        fail(f"requirements[{idx}] must include at least one test verification")

    req_count_by_contract[contract_id] += 1

for contract_id, required in contract_function_sets.items():
    missing = sorted(required - contract_covered_functions[contract_id])
    if missing:
        fail(
            f"missing function coverage for contract {contract_id}: {missing}"
        )

for contract_id in contract_defs.keys():
    if req_count_by_contract[contract_id] < min_req[contract_id]:
        fail(
            f"requirements coverage below target for {contract_id}: "
            f"{req_count_by_contract[contract_id]} < {min_req[contract_id]}"
        )
    if bva_count_by_contract[contract_id] < min_bva[contract_id]:
        fail(
            f"BVA coverage below target for {contract_id}: "
            f"{bva_count_by_contract[contract_id]} < {min_bva[contract_id]}"
        )

report = {
    "schema": REPORT_SCHEMA,
    "generated_at_utc": datetime.now(tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "matrix_path": str(MATRIX_PATH.relative_to(ROOT)),
    "as_of_utc": as_of_utc,
    "total_contracts": len(contract_defs),
    "total_requirements": len(requirements),
    "total_verification_commands": len(commands),
    "coverage_by_contract": {
        cid: {
            "requirements": req_count_by_contract[cid],
            "minimum_requirements": min_req[cid],
            "bva_requirements": bva_count_by_contract[cid],
            "minimum_bva_requirements": min_bva[cid],
            "required_functions": sorted(contract_function_sets[cid]),
            "covered_functions": sorted(contract_covered_functions[cid]),
        }
        for cid in sorted(contract_defs.keys())
    },
    "ok": True,
}
REPORT_PATH.write_text(json.dumps(report, indent=2), encoding="utf-8")
print(
    "Requirements traceability gate passed "
    f"(requirements={len(requirements)}, report={REPORT_PATH})"
)
PY

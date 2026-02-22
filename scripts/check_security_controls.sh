#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MATRIX_PATH="${ROOT_DIR}/docs/security/control_matrix.json"
OUT_DIR="${ROOT_DIR}/runs/security"
SECURITY_CONTROL_STRICT_STATUSES="1"

if [[ ! -f "${MATRIX_PATH}" ]]; then
  echo "Security control matrix not found: ${MATRIX_PATH}"
  exit 1
fi

mkdir -p "${OUT_DIR}"

ROOT_DIR="${ROOT_DIR}" MATRIX_PATH="${MATRIX_PATH}" OUT_DIR="${OUT_DIR}" SECURITY_CONTROL_STRICT_STATUSES="${SECURITY_CONTROL_STRICT_STATUSES}" python3 - <<'PY'
import json
import os
import pathlib
import re
import sys


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def validate_evidence(root: pathlib.Path, evidence: list[str], control_id: str) -> int:
    root_resolved = root.resolve()
    valid = 0
    for item in evidence:
        if not isinstance(item, str) or item.strip() == "":
            fail(f"{control_id}: evidence entry must be a non-empty string")
        path_part = item.split(":", 1)[0]
        if path_part.startswith("./"):
            path_part = path_part[2:]
        candidate = (root / path_part).resolve()
        if candidate != root_resolved and root_resolved not in candidate.parents:
            fail(f"{control_id}: evidence path escapes repository root: {item}")
        if not candidate.exists():
            fail(f"{control_id}: evidence path does not exist: {item}")
        valid += 1
    return valid


def validate_controls(
    controls: list[dict[str, object]],
    *,
    allowed_statuses: set[str],
    forbidden_statuses: set[str],
    root: pathlib.Path
) -> tuple[int, int]:
    seen = set()
    total_evidence = 0
    not_applicable = 0
    for control in controls:
        if not isinstance(control, dict):
            fail("control entry must be an object")
        control_id = control.get("id")
        if not isinstance(control_id, str) or control_id.strip() == "":
            fail("control entry missing non-empty id")
        if control_id in seen:
            fail(f"duplicate control id: {control_id}")
        seen.add(control_id)
        status = control.get("status")
        if not isinstance(status, str):
            fail(f"{control_id}: status must be a string")
        normalized = status.strip().lower()
        if normalized not in allowed_statuses:
            fail(f"{control_id}: unsupported status {status!r}")
        if normalized in forbidden_statuses:
            fail(f"{control_id}: forbidden status {status!r}")
        if normalized == "not_applicable":
            rationale = control.get("rationale")
            if not isinstance(rationale, str) or rationale.strip() == "":
                fail(f"{control_id}: not_applicable controls require rationale")
            not_applicable += 1
        evidence = control.get("evidence")
        if not isinstance(evidence, list) or len(evidence) == 0:
            fail(f"{control_id}: evidence must be a non-empty list")
        total_evidence += validate_evidence(root, evidence, control_id)
    return len(seen), total_evidence


root_dir = pathlib.Path(os.environ["ROOT_DIR"])
matrix_path = pathlib.Path(os.environ["MATRIX_PATH"])
out_dir = pathlib.Path(os.environ["OUT_DIR"])
strict_statuses = os.environ.get("SECURITY_CONTROL_STRICT_STATUSES", "0").strip().lower() in {"1", "true", "yes"}

matrix = json.loads(matrix_path.read_text(encoding="utf-8"))
if matrix.get("schema") != "pulsetensor/security-control-matrix/v1":
    fail("unexpected security control matrix schema")

allowed = {"mitigated", "not_applicable"}
if not strict_statuses:
    allowed.add("tracked")
forbidden = {"open", "partial", "todo", "unknown"}

top10 = matrix.get("owasp_top10_2026")
if not isinstance(top10, list):
    fail("owasp_top10_2026 must be a list")
required_top10 = {f"SC{i:02d}" for i in range(1, 11)}
present_top10 = {entry.get("id") for entry in top10 if isinstance(entry, dict)}
if required_top10 != present_top10:
    missing = sorted(required_top10 - present_top10)
    extra = sorted(str(item) for item in (present_top10 - required_top10))
    fail(f"Top10 control coverage mismatch; missing={missing}, extra={extra}")
top10_count, top10_evidence = validate_controls(top10, allowed_statuses=allowed, forbidden_statuses=forbidden, root=root_dir)

scsvs = matrix.get("owasp_scsvs_controls")
if not isinstance(scsvs, list) or len(scsvs) < 4:
    fail("owasp_scsvs_controls must include at least 4 controls")
scsvs_count, scsvs_evidence = validate_controls(scsvs, allowed_statuses=allowed, forbidden_statuses=forbidden, root=root_dir)

ethtrust = matrix.get("ethtrust_v3_controls")
if not isinstance(ethtrust, list) or len(ethtrust) < 4:
    fail("ethtrust_v3_controls must include at least 4 controls")
levels = {entry.get("level") for entry in ethtrust if isinstance(entry, dict)}
if "S" not in levels or "M" not in levels:
    fail("ethtrust_v3_controls must include both S and M level entries")
ethtrust_count, ethtrust_evidence = validate_controls(ethtrust, allowed_statuses=allowed, forbidden_statuses={"open", "partial", "todo", "unknown"}, root=root_dir)

policy = matrix.get("solidity_compiler_policy")
if not isinstance(policy, dict):
    fail("solidity_compiler_policy must be present")
min_solc = policy.get("min_solc_version")
if not isinstance(min_solc, str) or not re.match(r"^\d+\.\d+\.\d+$", min_solc):
    fail("solidity_compiler_policy.min_solc_version must be semantic version string")
if policy.get("disallow_known_bugs") is not True:
    fail("solidity_compiler_policy.disallow_known_bugs must be true")

report = {
    "schema": "pulsetensor/security-control-matrix-report/v1",
    "matrix_path": str(matrix_path),
    "top10_controls": top10_count,
    "scsvs_controls": scsvs_count,
    "ethtrust_controls": ethtrust_count,
    "total_evidence_entries": top10_evidence + scsvs_evidence + ethtrust_evidence,
    "ok": True
}
(out_dir / "control_matrix_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print(
    f"Security control matrix gate passed "
    f"(Top10={top10_count}, SCSVS={scsvs_count}, EthTrust={ethtrust_count})"
)
PY

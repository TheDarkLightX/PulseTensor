#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
FOUNDRY_TOML="${ROOT_DIR}/foundry.toml"
MATRIX_PATH="${ROOT_DIR}/docs/security/control_matrix.json"
CACHE_DIR="${ROOT_DIR}/cache/solidity"
OUT_DIR="${ROOT_DIR}/runs/security"
ALLOW_STALE_BUG_DB="${ALLOW_STALE_BUG_DB:-0}"

mkdir -p "${CACHE_DIR}" "${OUT_DIR}"

ROOT_DIR="${ROOT_DIR}" \
FOUNDRY_TOML="${FOUNDRY_TOML}" \
MATRIX_PATH="${MATRIX_PATH}" \
CACHE_DIR="${CACHE_DIR}" \
OUT_DIR="${OUT_DIR}" \
ALLOW_STALE_BUG_DB="${ALLOW_STALE_BUG_DB}" \
python3 - <<'PY'
import json
import datetime
import hashlib
import os
import pathlib
import re
import sys
import urllib.request


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def parse_bool(raw: str, *, default: bool = False) -> bool:
    lowered = raw.strip().lower()
    if lowered in {"true", "1", "yes"}:
        return True
    if lowered in {"false", "0", "no"}:
        return False
    return default


def parse_foundry_config(path: pathlib.Path) -> dict[str, str]:
    if not path.exists():
        fail(f"foundry config not found: {path}")
    payload = path.read_text(encoding="utf-8")
    fields: dict[str, str] = {}
    patterns = {
        "solc_version": r'^\s*solc_version\s*=\s*"([^"]+)"\s*$',
        "via_ir": r"^\s*via_ir\s*=\s*(true|false)\s*$",
        "optimizer": r"^\s*optimizer\s*=\s*(true|false)\s*$",
        "evm_version": r'^\s*evm_version\s*=\s*"([^"]+)"\s*$'
    }
    for key, pattern in patterns.items():
        match = re.search(pattern, payload, flags=re.MULTILINE)
        if match:
            fields[key] = match.group(1)
    missing = [key for key in ("solc_version", "via_ir", "optimizer", "evm_version") if key not in fields]
    if missing:
        fail(f"missing required foundry fields: {', '.join(missing)}")
    return fields


def parse_semver(value: str) -> tuple[int, int, int]:
    match = re.match(r"^(\d+)\.(\d+)\.(\d+)$", value.strip())
    if not match:
        fail(f"invalid semantic version: {value}")
    return tuple(int(group) for group in match.groups())


def fetch_json(url: str, destination: pathlib.Path, allow_stale: bool) -> object:
    headers = {"User-Agent": "PulseTensor-SecurityGate/1.0"}
    github_token = os.environ.get("GITHUB_TOKEN", "").strip()
    if github_token and url.startswith("https://api.github.com/"):
        headers["Authorization"] = f"Bearer {github_token}"
    request = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            raw = response.read().decode("utf-8")
        destination.write_text(raw, encoding="utf-8")
        return json.loads(raw)
    except Exception as exc:
        if allow_stale and destination.exists():
            print(f"warning: failed to refresh {url}, using stale cache {destination}: {exc}", file=sys.stderr)
            return json.loads(destination.read_text(encoding="utf-8"))
        fail(f"unable to fetch required compiler bug feed {url}: {exc}")


def evm_condition_matches(condition: str, evm_version: str) -> bool:
    order = [
        "homestead",
        "tangerinewhistle",
        "spuriousdragon",
        "byzantium",
        "constantinople",
        "petersburg",
        "istanbul",
        "berlin",
        "london",
        "paris",
        "shanghai",
        "cancun",
        "prague",
        "osaka"
    ]
    normalized_map = {name: index for index, name in enumerate(order)}
    current = evm_version.strip().lower()
    if current not in normalized_map:
        return True

    match = re.match(r"^(>=|<=|>|<|=)?\s*([A-Za-z0-9_]+)$", condition.strip())
    if not match:
        return True
    operator = match.group(1) or "="
    target = match.group(2).strip().lower()
    if target not in normalized_map:
        return True

    lhs = normalized_map[current]
    rhs = normalized_map[target]
    if operator == "=":
        return lhs == rhs
    if operator == ">":
        return lhs > rhs
    if operator == "<":
        return lhs < rhs
    if operator == ">=":
        return lhs >= rhs
    if operator == "<=":
        return lhs <= rhs
    return True


def condition_matches(conditions: dict[str, object], *, via_ir: bool, optimizer: bool, evm_version: str) -> bool:
    if not conditions:
        return True
    for key, value in conditions.items():
        if key == "viaIR":
            if bool(value) != via_ir:
                return False
        elif key == "optimizer":
            if bool(value) != optimizer:
                return False
        elif key == "evmVersion":
            if not isinstance(value, str):
                return True
            if not evm_condition_matches(value, evm_version):
                return False
        else:
            return True
    return True


root_dir = pathlib.Path(os.environ["ROOT_DIR"])
foundry_toml = pathlib.Path(os.environ["FOUNDRY_TOML"])
matrix_path = pathlib.Path(os.environ["MATRIX_PATH"])
cache_dir = pathlib.Path(os.environ["CACHE_DIR"])
out_dir = pathlib.Path(os.environ["OUT_DIR"])
allow_stale = parse_bool(os.environ.get("ALLOW_STALE_BUG_DB", "0"))

if not matrix_path.exists():
    fail(f"security control matrix not found: {matrix_path}")
matrix = json.loads(matrix_path.read_text(encoding="utf-8"))
compiler_policy = matrix.get("solidity_compiler_policy") or {}
min_solc_version = str(compiler_policy.get("min_solc_version", "0.8.36"))
fail_on_low = bool(compiler_policy.get("fail_on_low_severity", True))
official_branch_source = "https://raw.githubusercontent.com/ethereum/solidity/develop/docs/"
configured_bugs_source = str(compiler_policy.get("bugs_source", official_branch_source)).rstrip("/") + "/"
if configured_bugs_source != official_branch_source:
    fail(f"compiler bug source must be the official Solidity develop feed: {official_branch_source}")

revision_metadata = fetch_json(
    "https://api.github.com/repos/ethereum/solidity/commits/develop",
    cache_dir / "solidity_develop_commit.json",
    allow_stale,
)
if not isinstance(revision_metadata, dict):
    fail("unexpected Solidity develop commit response")
bugs_source_revision = revision_metadata.get("sha")
if not isinstance(bugs_source_revision, str) or not re.fullmatch(r"[0-9a-f]{40}", bugs_source_revision):
    fail("Solidity develop commit response has no valid commit SHA")

bugs_source = f"https://raw.githubusercontent.com/ethereum/solidity/{bugs_source_revision}/docs/"
bugs_url = bugs_source + "bugs.json"
bugs_by_version_url = bugs_source + "bugs_by_version.json"

foundry = parse_foundry_config(foundry_toml)
solc_version = foundry["solc_version"]
via_ir = parse_bool(foundry["via_ir"])
optimizer = parse_bool(foundry["optimizer"])
evm_version = foundry["evm_version"]

if parse_semver(solc_version) < parse_semver(min_solc_version):
    fail(f"solc_version {solc_version} is below policy minimum {min_solc_version}")

bugs_by_version_path = cache_dir / f"bugs_by_version.{bugs_source_revision}.json"
bugs_path = cache_dir / f"bugs.{bugs_source_revision}.json"
bugs_by_version = fetch_json(bugs_by_version_url, bugs_by_version_path, allow_stale)
bugs = fetch_json(bugs_url, bugs_path, allow_stale)

if not isinstance(bugs_by_version, dict):
    fail("unexpected bugs_by_version feed format")
if not isinstance(bugs, list):
    fail("unexpected bugs feed format")

version_entry = bugs_by_version.get(solc_version)
if not isinstance(version_entry, dict):
    fail(f"compiler bug feed does not contain configured solc_version {solc_version}")

active_bug_names = version_entry.get("bugs", [])
if not isinstance(active_bug_names, list):
    fail(f"unexpected bug list for compiler version {solc_version}")

bugs_by_name: dict[str, dict[str, object]] = {}
for item in bugs:
    if not isinstance(item, dict):
        continue
    name = item.get("name")
    if isinstance(name, str):
        bugs_by_name[name] = item

applicable: list[dict[str, object]] = []
for bug_name in active_bug_names:
    detail = bugs_by_name.get(str(bug_name))
    if detail is None:
        applicable.append(
            {
                "name": str(bug_name),
                "uid": "",
                "severity": "unknown",
                "reason": "missing bug metadata"
            }
        )
        continue
    if not condition_matches(
        detail.get("conditions") or {},
        via_ir=via_ir,
        optimizer=optimizer,
        evm_version=evm_version
    ):
        continue
    applicable.append(
        {
            "name": str(detail.get("name", bug_name)),
            "uid": str(detail.get("uid", "")),
            "severity": str(detail.get("severity", "unknown")).lower(),
            "introduced": str(detail.get("introduced", "")),
            "fixed": str(detail.get("fixed", "")),
            "link": str(detail.get("link", ""))
        }
    )

disallowed = {"critical", "high", "medium"}
if fail_on_low:
    disallowed.add("low")
disallowed.add("unknown")
violations = [item for item in applicable if str(item.get("severity", "unknown")).lower() in disallowed]

report = {
    "schema": "pulsetensor/compiler-bug-report/v1",
    "as_of_utc": datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
    "solc_version": solc_version,
    "min_solc_version": min_solc_version,
    "via_ir": via_ir,
    "optimizer": optimizer,
    "evm_version": evm_version,
    "bugs_source": bugs_source,
    "bugs_source_branch": official_branch_source,
    "bugs_source_revision": bugs_source_revision,
    "bugs_json_sha256": hashlib.sha256(bugs_path.read_bytes()).hexdigest(),
    "bugs_by_version_json_sha256": hashlib.sha256(bugs_by_version_path.read_bytes()).hexdigest(),
    "active_known_bugs": applicable,
    "violations": violations,
    "fail_on_low_severity": fail_on_low,
    "ok": len(violations) == 0
}
(out_dir / "compiler_bug_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")

if violations:
    summary = ", ".join(f"{item['name']}[{item['severity']}]" for item in violations)
    fail(f"compiler bug gate failed for solc {solc_version}: {summary}")

print(f"Compiler bug gate passed for solc {solc_version} (active applicable bugs: {len(applicable)})")
PY

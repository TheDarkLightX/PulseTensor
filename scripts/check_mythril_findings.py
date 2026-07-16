#!/usr/bin/env python3
"""Apply PulseTensor's SWC policy and emit a deterministic Mythril summary."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def fail(message: str) -> None:
    raise SystemExit(f"Mythril findings rejected: {message}")


def read_report(path: Path) -> list[dict[str, Any]]:
    if not path.is_file() or path.is_symlink():
        fail(f"missing or non-regular report: {path}")
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        fail(f"invalid report JSON {path}: {error}")
    if not isinstance(payload, list) or len(payload) != 1 or not isinstance(payload[0], dict):
        fail(f"jsonv2 report must contain exactly one object: {path}")
    issues = payload[0].get("issues")
    if not isinstance(issues, list) or any(not isinstance(issue, dict) for issue in issues):
        fail(f"issues must be a list of objects: {path}")
    return issues


def relative_report(root: Path, report: Path) -> str:
    try:
        return report.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        fail(f"report is outside repository: {report}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--core-report", required=True, type=Path)
    parser.add_argument("--settlement-report", required=True, type=Path)
    parser.add_argument("--exact-settlement-report", required=True, type=Path)
    parser.add_argument("--adapter-report", required=True, type=Path)
    parser.add_argument("--image", required=True)
    parser.add_argument("--max-depth", required=True)
    parser.add_argument("--transaction-count", required=True)
    parser.add_argument("--execution-timeout", required=True)
    parser.add_argument("--solver-timeout-ms", required=True)
    parser.add_argument("--wall-timeout-seconds", required=True)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    root = args.root.resolve()
    allowlist_path = root / "docs/security/mythril_ignored_swc.allowlist"
    if not allowlist_path.is_file() or allowlist_path.is_symlink():
        fail("missing or non-regular SWC allowlist")
    allowlisted = [
        line
        for raw_line in allowlist_path.read_text(encoding="utf-8").splitlines()
        if (line := raw_line.split("#", 1)[0].strip())
    ]
    if not allowlisted or len(allowlisted) != len(set(allowlisted)):
        fail("SWC allowlist must be non-empty and duplicate-free")
    allowlisted_set = set(allowlisted)

    targets = (
        ("PulseTensorCore", args.core_report),
        ("PulseTensorInferenceSettlement", args.settlement_report),
        ("PulseTensorExactInferenceSettlementV1", args.exact_settlement_report),
        ("RiscZeroVerifierAdapter", args.adapter_report),
    )
    contracts: list[dict[str, Any]] = []
    total_disallowed = 0
    for contract_name, report_path in targets:
        issues = read_report(report_path)
        allowed_count = 0
        disallowed: list[dict[str, Any]] = []
        for issue in issues:
            swc_id = issue.get("swcID")
            if not isinstance(swc_id, str) or not swc_id.strip():
                swc_id = "UNKNOWN"
            if swc_id in allowlisted_set:
                allowed_count += 1
            else:
                disallowed.append(
                    {
                        "swc_id": swc_id,
                        "severity": issue.get("severity"),
                        "title": issue.get("swcTitle"),
                    }
                )
        total_disallowed += len(disallowed)
        contracts.append(
            {
                "contract": contract_name,
                "report": relative_report(root, report_path),
                "total_issues": len(issues),
                "allowlisted_issues": allowed_count,
                "disallowed_issues": disallowed,
            }
        )

    summary = {
        "schema": "pulsetensor/security-mythril-summary/v1",
        "image": args.image,
        "params": {
            "max_depth": args.max_depth,
            "transaction_count": args.transaction_count,
            "execution_timeout": args.execution_timeout,
            "solver_timeout_ms": args.solver_timeout_ms,
            "wall_timeout_seconds": args.wall_timeout_seconds,
        },
        "allowlisted_swc_ids": allowlisted,
        "contracts": contracts,
        "ok": total_disallowed == 0,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")

    if total_disallowed:
        for contract in contracts:
            if contract["disallowed_issues"]:
                print(
                    f"Mythril disallowed findings in {contract['contract']}: "
                    f"{len(contract['disallowed_issues'])}"
                )
        raise SystemExit(1)
    print(f"Mythril findings accepted: {sum(item['total_issues'] for item in contracts)} total issues")


if __name__ == "__main__":
    main()

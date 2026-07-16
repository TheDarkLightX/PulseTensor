#!/usr/bin/env python3
"""Reject incomplete or error-shaped Mythril jsonv2 reports."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def fail(message: str) -> None:
    raise SystemExit(f"Mythril report rejected: {message}")


def nonempty_string(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("report", type=Path)
    args = parser.parse_args()

    if not args.report.is_file() or args.report.is_symlink():
        fail(f"missing or non-regular report: {args.report}")
    try:
        payload = json.loads(args.report.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        fail(f"invalid JSON: {error}")

    if not isinstance(payload, list) or len(payload) != 1:
        fail("jsonv2 root must contain exactly one report object")
    report = payload[0]
    if not isinstance(report, dict):
        fail("jsonv2 report entry must be an object")

    issues = report.get("issues")
    if not isinstance(issues, list) or any(not isinstance(issue, dict) for issue in issues):
        fail("issues must be a list of objects")
    if not nonempty_string(report.get("sourceType")):
        fail("completed report must have a non-empty sourceType")
    if not nonempty_string(report.get("sourceFormat")):
        fail("completed report must have a non-empty sourceFormat")
    source_list = report.get("sourceList")
    if (
        not isinstance(source_list, list)
        or not source_list
        or any(not nonempty_string(item) for item in source_list)
    ):
        fail("completed report must have a non-empty sourceList of non-empty strings")

    meta = report.get("meta")
    if not isinstance(meta, dict):
        fail("meta must be an object")
    logs = meta.get("logs", [])
    if not isinstance(logs, list) or any(not isinstance(item, dict) for item in logs):
        fail("meta.logs must be a list of objects when present")
    for log in logs:
        level = log.get("level")
        if isinstance(level, str) and level.strip().lower() in {"error", "critical", "fatal"}:
            fail(f"Mythril reported an analysis error: {log.get('msg', '<no message>')}")

    execution_info = meta.get("mythril_execution_info")
    if not isinstance(execution_info, dict):
        fail("completed report is missing meta.mythril_execution_info")
    duration = execution_info.get("analysis_duration")
    if isinstance(duration, bool) or not isinstance(duration, int) or duration < 0:
        fail("analysis_duration must be a non-negative integer")

    print(
        f"Mythril report accepted: {args.report} "
        f"(issues={len(issues)}, analysis_duration={duration})"
    )


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Fail-closed parser for the pinned Echidna v2.3.2 text report."""

from __future__ import annotations

import argparse
import json
import pathlib
import re


EXPECTED_PROPERTIES = {
    "echidna_stake_and_native_liabilities_conserved",
    "echidna_validator_count_exact_and_bounded",
    "echidna_registered_validators_can_validate",
    "echidna_pending_commitment_count_bounded",
    "echidna_active_commit_epoch_consistent_with_pending_count",
}
PRIMARY_MARKER = "--- PULSETENSOR ECHIDNA PRIMARY END status=0 ---"
NEGATIVE_MARKER = "--- PULSETENSOR ECHIDNA NEGATIVE END status=1 ---"


def fail(message: str) -> None:
    raise SystemExit(message)


def one_integer(report: str, label: str) -> int:
    matches = re.findall(rf"(?m)^{re.escape(label)}:\s*([0-9]+)\s*$", report)
    if len(matches) != 1:
        fail(f"expected exactly one {label!r} metric; found {len(matches)}")
    return int(matches[0])


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("log", type=pathlib.Path)
    parser.add_argument("summary", type=pathlib.Path)
    args = parser.parse_args()

    raw = args.log.read_text(encoding="utf-8")
    if raw.count(PRIMARY_MARKER) != 1:
        fail("missing or duplicate successful primary-campaign marker")
    if raw.count(NEGATIVE_MARKER) != 1:
        fail("missing or duplicate detected-negative-control marker")
    primary, remainder = raw.split(PRIMARY_MARKER, 1)
    negative, trailing = remainder.split(NEGATIVE_MARKER, 1)

    if "Echidna 2.3.2" not in primary:
        fail("pinned Echidna version was not reported")
    property_lines = re.findall(r"(?m)^(echidna_[A-Za-z0-9_]+):\s*(.*?)\s*$", primary)
    reported_names = [name for name, _state in property_lines]
    if len(property_lines) != len(EXPECTED_PROPERTIES) or set(reported_names) != EXPECTED_PROPERTIES:
        fail(
            "primary property report mismatch; "
            f"missing={sorted(EXPECTED_PROPERTIES - set(reported_names))}, "
            f"unexpected={sorted(set(reported_names) - EXPECTED_PROPERTIES)}, "
            f"reported_lines={len(property_lines)}"
        )
    non_passing = {name: state for name, state in property_lines if state != "passing"}
    if non_passing:
        fail(f"primary campaign contains non-passing property states: {non_passing}")

    unique_instructions = one_integer(primary, "Unique instructions")
    corpus_size = one_integer(primary, "Corpus size")
    seed = one_integer(primary, "Seed")
    total_calls = one_integer(primary, "Total calls")
    if unique_instructions <= 0:
        fail("primary campaign covered no instructions")
    if corpus_size <= 0:
        fail("primary campaign retained no coverage-increasing corpus")
    if seed != 1:
        fail(f"primary campaign seed mismatch: {seed}")
    if total_calls < 8000:
        fail(f"primary campaign executed too few calls: {total_calls}")

    negative_lines = re.findall(r"(?m)^echidna_gate_known_failure:\s*(.*?)\s*$", negative)
    if len(negative_lines) != 1 or not negative_lines[0].startswith("failed"):
        fail("negative-control property was not reported as failed")
    if "status=0" in trailing:
        fail("unexpected success marker after the negative control")

    summary = {
        "schema": "pulsetensor/echidna-campaign-summary/v1",
        "echidna_version": "2.3.2",
        "seed": seed,
        "total_calls": total_calls,
        "unique_instructions": unique_instructions,
        "corpus_size": corpus_size,
        "properties": sorted(reported_names),
        "negative_control_detected": True,
        "ok": True,
    }
    args.summary.parent.mkdir(parents=True, exist_ok=True)
    args.summary.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(
        "Echidna campaign report passed "
        f"(calls={total_calls}, instructions={unique_instructions}, corpus={corpus_size})"
    )


if __name__ == "__main__":
    main()

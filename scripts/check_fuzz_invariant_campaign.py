#!/usr/bin/env python3
"""Fail-closed parser for the canonical Foundry fuzz/invariant campaigns."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path


FUZZ_TESTS = {
    "testFuzz_ChallengeExpiredCommitSlashesBoundedAmount",
    "testFuzz_CommitLifecycleMaintainsActiveEpochAndPendingCount",
    "testFuzz_CommitRevealIsBoundToEpochSaltAndValidator",
    "testFuzz_DefaultEmissionSplitConservesTotal",
    "testFuzz_MechanismCommitRevealIsBoundToEpochSaltValidatorAndMechid",
    "testFuzz_MechanismEmissionPoolAccounting",
    "testFuzz_MechanismEpochEmissionQuoteRespectsBounds",
    "testFuzz_PendingCommitmentLocksStakeUntilReveal",
    "testFuzz_SelfChallengeRoutesFullSlashToPool",
    "testFuzz_StakeAccountingRemainsConservative",
    "testFuzz_ValidatorWithdrawEnforcesMinimumStake",
}

INVARIANT_TESTS = {
    "invariant_RegisteredValidatorsRespectBounds",
    "invariant_TotalStakeMatchesTrackedActors",
    "invariant_TrackedValidatorsCanValidate",
    "invariant_ValidatorCountMatchesTrackedActors",
}

ANSI_ESCAPE = re.compile(r"\x1b\[[0-9;]*m")
PASS_LINE = re.compile(
    r"^\[PASS\] (?P<name>[A-Za-z0-9_]+)\(.*\) "
    r"\(runs: (?P<runs>[0-9]+), (?P<metrics>.+)\)$"
)
INVARIANT_METRICS = re.compile(r"^calls: (?P<calls>[0-9]+), reverts: (?P<reverts>[0-9]+)$")


def fail(message: str) -> None:
    raise SystemExit(f"Foundry campaign receipt rejected: {message}")


def read_log(path: Path) -> tuple[bytes, str]:
    if not path.is_file() or path.is_symlink():
        fail(f"missing or non-regular log: {path}")
    raw = path.read_bytes()
    if not raw:
        fail(f"empty log: {path}")
    return raw, ANSI_ESCAPE.sub("", raw.decode("utf-8", errors="strict"))


def parse_campaign(
    text: str,
    *,
    expected: set[str],
    contract: str,
    runs: int,
    calls: int | None = None,
) -> list[str]:
    expected_count = len(expected)
    suite_start = f"Ran {expected_count} tests for {contract}"
    suite_end = f"Suite result: ok. {expected_count} passed; 0 failed; 0 skipped;"
    if text.count(suite_start) != 1:
        fail(f"expected exactly one suite header: {suite_start}")
    if text.count(suite_end) != 1:
        fail(f"expected exactly one successful suite footer: {suite_end}")
    if "[FAIL" in text or "Suite result: FAILED" in text:
        fail(f"failure marker found in {contract}")

    observed: list[str] = []
    for line in text.splitlines():
        match = PASS_LINE.match(line)
        if not match:
            continue
        name = match.group("name")
        observed.append(name)
        if int(match.group("runs")) != runs:
            fail(f"{name} ran {match.group('runs')} times, expected {runs}")
        if calls is None:
            if INVARIANT_METRICS.fullmatch(match.group("metrics")):
                fail(f"unexpected invariant metrics on fuzz test {name}")
        else:
            metrics = INVARIANT_METRICS.fullmatch(match.group("metrics"))
            if metrics is None or int(metrics.group("calls")) != calls:
                observed_calls = None if metrics is None else metrics.group("calls")
                fail(f"{name} executed {observed_calls} calls, expected {calls}")
            if int(metrics.group("reverts")) != 0:
                fail(f"{name} reported {metrics.group('reverts')} reverts, expected 0")

    if len(observed) != expected_count:
        fail(f"{contract} reported {len(observed)} passing tests, expected {expected_count}")
    if len(set(observed)) != len(observed):
        fail(f"duplicate passing test report in {contract}")
    if set(observed) != expected:
        missing = sorted(expected - set(observed))
        extra = sorted(set(observed) - expected)
        fail(f"test inventory mismatch in {contract}; missing={missing}, extra={extra}")
    return sorted(observed)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fuzz-log", required=True, type=Path)
    parser.add_argument("--invariant-log", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    fuzz_raw, fuzz_text = read_log(args.fuzz_log)
    invariant_raw, invariant_text = read_log(args.invariant_log)
    fuzz_tests = parse_campaign(
        fuzz_text,
        expected=FUZZ_TESTS,
        contract="test/PulseTensorCore.fuzz.t.sol:PulseTensorCoreFuzzTest",
        runs=1024,
    )
    invariant_tests = parse_campaign(
        invariant_text,
        expected=INVARIANT_TESTS,
        contract="test/PulseTensorCore.invariant.t.sol:PulseTensorCoreInvariantTest",
        runs=256,
        calls=256 * 64,
    )

    receipt = {
        "schema_version": 1,
        "ok": True,
        "fuzz": {
            "seed": "1",
            "runs_per_test": 1024,
            "tests": fuzz_tests,
            "log_sha256": hashlib.sha256(fuzz_raw).hexdigest(),
        },
        "invariant": {
            "seed": "1",
            "runs_per_invariant": 256,
            "depth": 64,
            "calls_per_invariant": 256 * 64,
            "reverts": 0,
            "tests": invariant_tests,
            "log_sha256": hashlib.sha256(invariant_raw).hexdigest(),
        },
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "Foundry campaign receipt accepted: "
        f"{len(fuzz_tests)} fuzz tests and {len(invariant_tests)} invariants"
    )


if __name__ == "__main__":
    main()

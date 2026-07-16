#!/usr/bin/env python3
"""Recompute and validate a PulseTensor commit-bound assurance bundle."""

from __future__ import annotations

import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
from typing import Any


def fail(message: str) -> None:
    raise SystemExit(message)


def run(*args: str, cwd: pathlib.Path) -> str:
    return subprocess.run(args, cwd=cwd, check=True, text=True, capture_output=True).stdout.strip()


def digest_file(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def toolchain_value(root: pathlib.Path, name: str) -> str:
    prefix = f"{name}="
    for line in (root / "scripts/toolchain.lock").read_text(encoding="utf-8").splitlines():
        if line.startswith(prefix):
            encoded = line[len(prefix) :]
            try:
                value = json.loads(encoded)
            except json.JSONDecodeError as error:
                fail(f"invalid toolchain value for {name}: {error}")
            if not isinstance(value, str):
                fail(f"toolchain value for {name} must be a quoted string")
            return value
    fail(f"toolchain value is missing: {name}")


def safe_repo_file(root: pathlib.Path, relative: str) -> pathlib.Path:
    pure = pathlib.PurePosixPath(relative)
    if pure.is_absolute() or not pure.parts or ".." in pure.parts:
        fail(f"unsafe evidence artifact path: {relative}")
    cursor = root
    for part in pure.parts:
        cursor = cursor / part
        if cursor.is_symlink():
            fail(f"evidence artifact path traverses symlink: {relative}")
    resolved = cursor.resolve()
    if root != resolved and root not in resolved.parents:
        fail(f"evidence artifact escapes repository: {relative}")
    if not resolved.is_file():
        fail(f"evidence artifact is missing: {relative}")
    return resolved


def tracked_digest(root: pathlib.Path) -> str:
    raw = subprocess.run(
        ["git", "ls-files", "-z"], cwd=root, check=True, capture_output=True
    ).stdout
    names = sorted(item for item in raw.split(b"\0") if item)
    aggregate = hashlib.sha256()
    for name in names:
        path = root / os.fsdecode(name)
        aggregate.update(hashlib.sha256(path.read_bytes()).hexdigest().encode("ascii"))
        aggregate.update(b"  ")
        aggregate.update(name)
        aggregate.update(b"\n")
    return aggregate.hexdigest()


def forge_std_digest(root: pathlib.Path) -> str:
    dependency = root / "lib/forge-std"
    lines: list[bytes] = []
    for path in dependency.rglob("*"):
        if not path.is_file() or ".git" in path.relative_to(dependency).parts:
            continue
        relative = "./" + path.relative_to(dependency).as_posix()
        line = f"{digest_file(path)}  {relative}\n".encode()
        lines.append(line)
    return hashlib.sha256(b"".join(sorted(lines, key=lambda item: item.split(b"  ", 1)[1]))).hexdigest()


def selected_profile(root: pathlib.Path) -> dict[str, Any]:
    config = json.loads(run("forge", "config", "--json", cwd=root))
    return {
        "src": config["src"],
        "test": config["test"],
        "out": config["out"],
        "libs": config["libs"],
        "remappings": config["remappings"],
        "ffi": config["ffi"],
        "fs_permissions": config["fs_permissions"],
        "script": config["script"],
        "cache_path": config["cache_path"],
        "broadcast": config["broadcast"],
        "allow_paths": config["allow_paths"],
        "include_paths": config["include_paths"],
        "solc": config["solc"],
        "optimizer": config["optimizer"],
        "optimizer_runs": config["optimizer_runs"],
        "via_ir": config["via_ir"],
        "evm": config["evm_version"],
        "bytecode_hash": config["bytecode_hash"],
        "cbor_metadata": config["cbor_metadata"],
        "fuzz": {
            key: config["fuzz"][key]
            for key in (
                "runs",
                "max_test_rejects",
                "seed",
                "dictionary_weight",
                "include_storage",
                "include_push_bytes",
            )
        },
        "invariant": {
            key: config["invariant"][key]
            for key in (
                "runs",
                "depth",
                "fail_on_revert",
                "dictionary_weight",
                "include_storage",
                "include_push_bytes",
            )
        },
    }


def require_equal(label: str, actual: Any, expected: Any) -> None:
    if actual != expected:
        fail(f"{label} mismatch: expected {expected!r}, found {actual!r}")


def main() -> None:
    if len(sys.argv) != 3:
        fail("usage: check_assurance_evidence.py ROOT EVIDENCE")
    root = pathlib.Path(sys.argv[1]).resolve()
    evidence_path = pathlib.Path(sys.argv[2]).resolve()
    evidence = json.loads(evidence_path.read_text(encoding="utf-8"))

    require_equal("evidence schema", evidence.get("schema"), "pulsetensor-assurance-evidence-v3")
    require_equal("tree state", evidence.get("tree_state"), "clean")
    status = run("git", "status", "--porcelain", "--untracked-files=all", cwd=root)
    require_equal("current worktree state", status, "")
    require_equal("commit", evidence.get("commit"), run("git", "rev-parse", "HEAD", cwd=root))
    require_equal("Foundry profile", evidence.get("profile"), selected_profile(root))

    inputs = evidence.get("inputs") or {}
    require_equal("tracked-files digest", inputs.get("tracked_files_sha256"), tracked_digest(root))
    require_equal("foundry.toml digest", inputs.get("foundry_config_sha256"), digest_file(root / "foundry.toml"))
    require_equal("toolchain lock digest", inputs.get("toolchain_lock_sha256"), digest_file(root / "scripts/toolchain.lock"))

    tools = evidence.get("tools") or {}
    for binary in ("forge", "cast", "anvil"):
        location = shutil.which(binary)
        if location is None:
            fail(f"required evidence tool not found: {binary}")
        current_digest = digest_file(pathlib.Path(location))
        require_equal(f"{binary} digest", tools.get(f"{binary}_sha256"), current_digest)
        require_equal(
            f"pinned {binary} digest",
            current_digest,
            toolchain_value(root, f"{binary.upper()}_RELEASE_SHA256"),
        )
    require_equal("forge version", tools.get("forge"), run("forge", "--version", cwd=root).splitlines()[0])
    require_equal("pinned forge version", tools.get("forge"), toolchain_value(root, "FORGE_RELEASE_VERSION"))

    solc_version = evidence["profile"]["solc"]
    require_equal("pinned solc profile version", solc_version, toolchain_value(root, "SOLC_VERSION"))
    solc_path = pathlib.Path.home() / ".svm" / solc_version / f"solc-{solc_version}"
    current_solc_digest = digest_file(solc_path)
    require_equal("solc digest", tools.get("solc_sha256"), current_solc_digest)
    require_equal(
        "pinned solc digest",
        current_solc_digest,
        toolchain_value(root, "SOLC_RELEASE_SHA256"),
    )
    require_equal("solc version", tools.get("solc"), run(str(solc_path), "--version", cwd=root).splitlines()[-1])
    current_forge_std_digest = forge_std_digest(root)
    require_equal("forge-std content digest", tools.get("forge_std_content_sha256"), current_forge_std_digest)
    require_equal(
        "pinned forge-std content digest",
        current_forge_std_digest,
        toolchain_value(root, "FORGE_STD_CONTENT_SHA256"),
    )
    require_equal("Python version", tools.get("python"), run("python3", "--version", cwd=root).splitlines()[0])
    require_equal("Node.js version", tools.get("node"), run("node", "--version", cwd=root).splitlines()[0])
    require_equal("npm version", tools.get("npm"), run("npm", "--version", cwd=root).splitlines()[0])
    require_equal("pinned Node.js version", tools.get("node"), toolchain_value(root, "NODE_VERSION_PREFIX"))
    require_equal("pinned npm version", tools.get("npm"), toolchain_value(root, "NPM_VERSION_PREFIX"))
    require_equal("Docker version", tools.get("docker"), run("docker", "--version", cwd=root).splitlines()[0])
    solhint_bin = root / "scripts/solhint/node_modules/.bin/solhint"
    solhint_lock = root / "scripts/solhint/package-lock.json"
    require_equal(
        "Solhint version", tools.get("solhint"), run(str(solhint_bin), "--version", cwd=root).splitlines()[0]
    )
    require_equal(
        "pinned Solhint version",
        tools.get("solhint"),
        toolchain_value(root, "SOLHINT_VERSION_PREFIX"),
    )
    solhint_lock_digest = digest_file(solhint_lock)
    require_equal(
        "Solhint package-lock evidence digest",
        tools.get("solhint_package_lock_sha256"),
        solhint_lock_digest,
    )
    require_equal(
        "Solhint package-lock toolchain digest",
        toolchain_value(root, "SOLHINT_PACKAGE_LOCK_SHA256"),
        solhint_lock_digest,
    )

    slither_python = root / ".venv/bin/python"
    slither_pip = root / ".venv/bin/pip"
    require_equal(
        "Slither virtualenv Python version",
        tools.get("slither_python"),
        run(str(slither_python), "--version", cwd=root).splitlines()[0],
    )
    require_equal("system/Slither Python version", tools.get("python"), tools.get("slither_python"))
    require_equal(
        "pinned Slither Python version",
        tools.get("slither_python"),
        toolchain_value(root, "PYTHON_VERSION_PREFIX"),
    )
    slither_pip_version = run(
        str(slither_python),
        "-c",
        "import importlib.metadata; print(importlib.metadata.version('pip'))",
        cwd=root,
    )
    require_equal("Slither virtualenv pip version", tools.get("slither_pip"), slither_pip_version)
    require_equal("pinned Slither pip version", tools.get("slither_pip"), toolchain_value(root, "PIP_VERSION"))
    slither_version = run(
        str(slither_python),
        "-c",
        "import importlib.metadata; print(importlib.metadata.version('slither-analyzer'))",
        cwd=root,
    )
    require_equal("Slither version", tools.get("slither"), slither_version)
    require_equal("pinned Slither version", slither_version, toolchain_value(root, "SLITHER_VERSION"))
    slither_pip_version = run(
        str(slither_python),
        "-c",
        "import importlib.metadata; print(importlib.metadata.version('pip'))",
        cwd=root,
    )
    require_equal("pinned Slither pip version", slither_pip_version, toolchain_value(root, "PIP_VERSION"))
    frozen = run(str(slither_pip), "freeze", "--all", cwd=root).splitlines()
    frozen_digest = hashlib.sha256(("\n".join(sorted(frozen)) + "\n").encode()).hexdigest()
    require_equal("Slither environment digest", tools.get("slither_environment_sha256"), frozen_digest)

    artifacts = evidence.get("artifacts_sha256")
    if not isinstance(artifacts, dict) or not artifacts:
        fail("evidence contains no artifact hashes")
    manifest_paths = {
        line.split("#", 1)[0].strip()
        for line in (root / "docs/security/artifact_manifest.complete.txt").read_text(encoding="utf-8").splitlines()
        if line.split("#", 1)[0].strip()
    }
    expected_artifacts = manifest_paths | {
        "runs/security/artifact_freshness_report.txt",
        "runs/assurance/release.log",
    }
    require_equal("artifact inventory", set(artifacts), expected_artifacts)
    for relative, expected_digest in artifacts.items():
        path = safe_repo_file(root, relative)
        require_equal(f"artifact digest {relative}", expected_digest, digest_file(path))
        if path.suffix == ".json":
            payload = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(payload, dict) and payload.get("ok") is False:
                fail(f"artifact reports failure: {relative}")

    for mythril_report in (
        "runs/security/mythril_core_findings.json",
        "runs/security/mythril_settlement_findings.json",
        "runs/security/mythril_exact_settlement_findings.json",
        "runs/security/mythril_risc_zero_adapter_findings.json",
    ):
        subprocess.run(
            [
                sys.executable,
                str(root / "scripts/check_mythril_report.py"),
                str(safe_repo_file(root, mythril_report)),
            ],
            cwd=root,
            check=True,
            capture_output=True,
            text=True,
        )

    mythril_summary = json.loads(
        safe_repo_file(root, "runs/security/mythril_summary.json").read_text(encoding="utf-8")
    )
    require_equal("Mythril summary ok", mythril_summary.get("ok"), True)
    require_equal(
        "pinned Mythril image",
        mythril_summary.get("image"),
        toolchain_value(root, "MYTHRIL_IMAGE_LOCK"),
    )
    mythril_params = mythril_summary.get("params") or {}
    for receipt_name, lock_name in (
        ("max_depth", "MYTHRIL_MAX_DEPTH_LOCK"),
        ("transaction_count", "MYTHRIL_TRANSACTION_COUNT_LOCK"),
        ("execution_timeout", "MYTHRIL_EXECUTION_TIMEOUT_LOCK"),
        ("solver_timeout_ms", "MYTHRIL_SOLVER_TIMEOUT_MS_LOCK"),
        ("wall_timeout_seconds", "MYTHRIL_WALL_TIMEOUT_SECONDS_LOCK"),
    ):
        require_equal(
            f"pinned Mythril {receipt_name}",
            mythril_params.get(receipt_name),
            toolchain_value(root, lock_name),
        )
    with tempfile.TemporaryDirectory(prefix="pulsetensor-mythril-evidence-") as temp_dir:
        regenerated_path = pathlib.Path(temp_dir) / "mythril_summary.json"
        subprocess.run(
            [
                sys.executable,
                str(root / "scripts/check_mythril_findings.py"),
                "--root",
                str(root),
                "--core-report",
                str(safe_repo_file(root, "runs/security/mythril_core_findings.json")),
                "--settlement-report",
                str(safe_repo_file(root, "runs/security/mythril_settlement_findings.json")),
                "--exact-settlement-report",
                str(safe_repo_file(root, "runs/security/mythril_exact_settlement_findings.json")),
                "--adapter-report",
                str(safe_repo_file(root, "runs/security/mythril_risc_zero_adapter_findings.json")),
                "--image",
                toolchain_value(root, "MYTHRIL_IMAGE_LOCK"),
                "--max-depth",
                toolchain_value(root, "MYTHRIL_MAX_DEPTH_LOCK"),
                "--transaction-count",
                toolchain_value(root, "MYTHRIL_TRANSACTION_COUNT_LOCK"),
                "--execution-timeout",
                toolchain_value(root, "MYTHRIL_EXECUTION_TIMEOUT_LOCK"),
                "--solver-timeout-ms",
                toolchain_value(root, "MYTHRIL_SOLVER_TIMEOUT_MS_LOCK"),
                "--wall-timeout-seconds",
                toolchain_value(root, "MYTHRIL_WALL_TIMEOUT_SECONDS_LOCK"),
                "--output",
                str(regenerated_path),
            ],
            cwd=root,
            check=True,
            capture_output=True,
            text=True,
        )
        require_equal(
            "regenerated Mythril summary",
            mythril_summary,
            json.loads(regenerated_path.read_text(encoding="utf-8")),
        )

    echidna_log_path = safe_repo_file(root, "runs/security/echidna.log")
    echidna_log = echidna_log_path.read_text(encoding="utf-8")
    echidna_headers = {
        "echidna_image": toolchain_value(root, "ECHIDNA_IMAGE"),
        "echidna_config_sha256": digest_file(root / "test/echidna/echidna.yaml"),
        "echidna_negative_config_sha256": digest_file(root / "test/echidna/negative-control.yaml"),
        "echidna_seed": "1",
        "echidna_workers": "1",
    }
    for name, expected in echidna_headers.items():
        line = f"{name}={expected}"
        require_equal(f"Echidna log header {name}", echidna_log.splitlines().count(line), 1)
    echidna_summary = json.loads(
        safe_repo_file(root, "runs/security/echidna_summary.json").read_text(encoding="utf-8")
    )
    require_equal("Echidna summary ok", echidna_summary.get("ok"), True)
    require_equal("Echidna negative control", echidna_summary.get("negative_control_detected"), True)
    require_equal(
        "pinned Echidna version",
        f"Echidna {echidna_summary.get('echidna_version')}",
        toolchain_value(root, "ECHIDNA_VERSION"),
    )
    with tempfile.TemporaryDirectory(prefix="pulsetensor-evidence-") as temp_dir:
        regenerated_path = pathlib.Path(temp_dir) / "echidna_summary.json"
        subprocess.run(
            [
                sys.executable,
                str(root / "scripts/check_echidna_campaign.py"),
                str(echidna_log_path),
                str(regenerated_path),
            ],
            cwd=root,
            check=True,
            capture_output=True,
            text=True,
        )
        require_equal(
            "regenerated Echidna summary",
            echidna_summary,
            json.loads(regenerated_path.read_text(encoding="utf-8")),
        )
    freshness = safe_repo_file(root, "runs/security/artifact_freshness_report.txt").read_text(encoding="utf-8")
    if "missing=0" not in freshness or "stale=0" not in freshness:
        fail("artifact freshness report is not successful")

    fuzz_invariant_summary = json.loads(
        safe_repo_file(root, "runs/security/fuzz_invariant_summary.json").read_text(encoding="utf-8")
    )
    require_equal("Foundry fuzz/invariant summary ok", fuzz_invariant_summary.get("ok"), True)
    with tempfile.TemporaryDirectory(prefix="pulsetensor-foundry-evidence-") as temp_dir:
        regenerated_path = pathlib.Path(temp_dir) / "fuzz_invariant_summary.json"
        subprocess.run(
            [
                sys.executable,
                str(root / "scripts/check_fuzz_invariant_campaign.py"),
                "--fuzz-log",
                str(safe_repo_file(root, "runs/security/fuzz.log")),
                "--invariant-log",
                str(safe_repo_file(root, "runs/security/invariant.log")),
                "--output",
                str(regenerated_path),
            ],
            cwd=root,
            check=True,
            capture_output=True,
            text=True,
        )
        require_equal(
            "regenerated Foundry fuzz/invariant summary",
            fuzz_invariant_summary,
            json.loads(regenerated_path.read_text(encoding="utf-8")),
        )

    local_e2e_report = json.loads(
        safe_repo_file(root, "runs/local_e2e/local_e2e_report.json").read_text(encoding="utf-8")
    )
    require_equal("local E2E assurance mode", local_e2e_report.get("assurance_mode"), True)
    require_equal(
        "local E2E credential profile",
        local_e2e_report.get("credential_profile"),
        "public-anvil-test-accounts",
    )
    require_equal("local E2E chain ID", local_e2e_report.get("chain_id"), 31337)

    deployment_receipt = json.loads(
        safe_repo_file(root, "runs/local_e2e/pulsetensor_deploy_receipt.json").read_text(encoding="utf-8")
    )
    require_equal(
        "local deployment receipt schema",
        deployment_receipt.get("schema"),
        "pulsetensor/deployment-receipt/v1",
    )
    require_equal("local deployment receipt status", deployment_receipt.get("status"), "complete")
    require_equal("local deployment receipt chain ID", deployment_receipt.get("chain_id"), 31337)
    require_equal("local deployment receipt broadcast", deployment_receipt.get("broadcast"), True)
    for field in ("deployer", "core_address", "settlement_address"):
        value = deployment_receipt.get(field)
        if not isinstance(value, str) or re.fullmatch(r"0x[0-9a-fA-F]{40}", value) is None:
            fail(f"local deployment receipt has invalid {field}")
    for field in ("core_transaction_hash", "settlement_transaction_hash"):
        value = deployment_receipt.get(field)
        if not isinstance(value, str) or re.fullmatch(r"0x[0-9a-fA-F]{64}", value) is None:
            fail(f"local deployment receipt has invalid {field}")

    runtime = evidence.get("deploy_profile_runtime") or {}
    core_object = json.loads(
        (root / "out/PulseTensorCore.sol/PulseTensorCore.json").read_text(encoding="utf-8")
    )["deployedBytecode"]["object"]
    settlement_object = json.loads(
        (root / "out/PulseTensorInferenceSettlement.sol/PulseTensorInferenceSettlement.json").read_text(
            encoding="utf-8"
        )
    )["deployedBytecode"]["object"]
    require_equal("core runtime hash", runtime.get("core_keccak256"), run("cast", "keccak", core_object, cwd=root))
    require_equal(
        "settlement runtime hash",
        runtime.get("settlement_template_keccak256"),
        run("cast", "keccak", settlement_object, cwd=root),
    )

    print(f"Assurance evidence verified for commit {evidence['commit']}")


if __name__ == "__main__":
    main()

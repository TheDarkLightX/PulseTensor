#!/usr/bin/env python3
"""Rebuild and recheck a PulseTensor v4 deployment receipt.

The verifier binds a receipt to the checked-out source, the exact pinned local
toolchain, freshly rebuilt deployment artifacts, and fresh reads from the
chain selected by ``ETH_RPC_URL``.  The endpoint is never accepted on the
command line and is redacted from diagnostics and output.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
from datetime import datetime, timedelta, timezone
from dataclasses import dataclass
from pathlib import Path
from typing import Any, NoReturn


ADDRESS_RE = re.compile(r"^0x[0-9a-fA-F]{40}$")
HASH_RE = re.compile(r"^0x[0-9a-fA-F]{64}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")
HEX_BYTES_RE = re.compile(r"^0x(?:[0-9a-fA-F]{2})+$")
URL_RE = re.compile(r"https?://[^\s'\"]+")
LOCK_LINE_RE = re.compile(r'^([A-Z][A-Z0-9_]*)="([^"\r\n]*)"$')

SCHEMA = "pulsetensor/deployment-receipt/v4"
PROFILE_ID = "pulsetensor-size-safe-v1"
PROFILE_NAME = "default"
OPTIMIZER_RUNS = 1
EVM_VERSION = "paris"
FOUNDRY_REMAPPING = "forge-std/=lib/forge-std/src/"
GAS_MARGIN_BPS = 2_000
MIN_RELEASE_CONFIRMATIONS = 12
MAINNET_CHAIN_ID = 369
TESTNET_CHAIN_ID = 943
MAINNET_ANCHOR_BLOCK = 17_233_000
MAINNET_ANCHOR_HASH = "0x9c8280d1182c2648af6390d8ea4a00d5f4bb8d44bf39161cd8983ea5a5fb9fd0"
TESTNET_ANCHOR_BLOCK = 16_492_700
TESTNET_ANCHOR_HASH = "0x9246d58ec6dd9900040defb013ef1317f509617cbc02c9e88279f7ba70e3b323"
GENERATED_AT_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
RUN_ID_RE = re.compile(r"^([1-9][0-9]*)-(\d{8}T\d{6}Z)-([0-9a-f]{8})$")


class VerificationError(RuntimeError):
    """A receipt, toolchain, artifact, or live-chain check failed."""


class DuplicateJSONKey(ValueError):
    """A JSON object repeated a key and is therefore ambiguous."""


@dataclass(frozen=True)
class Toolchain:
    lock_sha256: str
    foundry_toml_sha256: str
    forge_path: Path
    forge_version: str
    forge_sha256: str
    cast_path: Path
    cast_sha256: str
    solc_path: Path
    solc_version: str
    solc_long_version: str
    solc_sha256: str


@dataclass(frozen=True)
class LocalArtifacts:
    core_creation: str
    core_runtime: str
    settlement_creation: str
    settlement_runtime_template: str
    settlement_immutable_references: dict[str, Any]
    compiler_version: str
    core_artifact_sha256: str
    settlement_artifact_sha256: str


@dataclass(frozen=True)
class GasBudget:
    max_fee_per_gas_wei: int
    core_estimated_gas: int
    settlement_estimated_gas: int
    margin_bps: int
    maximum_total_cost_wei: int
    deployer_balance_before_wei: int


def fail(message: str) -> NoReturn:
    raise VerificationError(message)


def redact(text: str) -> str:
    for name in ("ETH_RPC_URL", "RELEASE_CHECKPOINT_RPC_URL"):
        rpc_url = os.environ.get(name, "")
        if rpc_url:
            text = text.replace(rpc_url, "<redacted-rpc>")
    return URL_RE.sub("<redacted-rpc>", text)


def reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateJSONKey(key)
        result[key] = value
    return result


def reject_nonfinite_json(value: str) -> NoReturn:
    raise VerificationError(f"JSON contains forbidden non-finite number: {value}")


def strict_json_loads(raw: str, label: str) -> Any:
    try:
        return json.loads(
            raw,
            object_pairs_hook=reject_duplicate_keys,
            parse_constant=reject_nonfinite_json,
        )
    except DuplicateJSONKey as exc:
        raise VerificationError(f"{label} contains duplicate JSON key: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise VerificationError(f"{label} contains malformed JSON") from exc


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as exc:
        raise VerificationError(f"cannot hash required file: {path}") from exc
    return digest.hexdigest()


def run_command(
    command: list[str],
    *,
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
    label: str,
) -> str:
    try:
        result = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            cwd=cwd,
            env=env,
        )
    except FileNotFoundError as exc:
        raise VerificationError(f"{label} executable is not installed") from exc
    if result.returncode != 0:
        detail = redact((result.stderr or result.stdout).strip())
        raise VerificationError(f"{label} failed: {detail or 'no diagnostic'}")
    return result.stdout.strip()


def run_cast(toolchain: Toolchain, *args: str) -> str:
    return run_command(
        [str(toolchain.cast_path), *args],
        env=os.environ.copy(),
        label=f"cast {args[0] if args else 'command'}",
    )


def parse_object(label: str, raw: str) -> dict[str, Any]:
    value = strict_json_loads(raw, label)
    if not isinstance(value, dict):
        fail(f"{label} did not return a JSON object")
    return value


def load_object(path: Path, label: str) -> dict[str, Any]:
    try:
        raw = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        raise VerificationError(f"cannot read {label}: {path}") from exc
    value = strict_json_loads(raw, label)
    if not isinstance(value, dict):
        fail(f"{label} must be a JSON object")
    return value


def field(mapping: dict[str, Any], name: str, label: str) -> Any:
    if name not in mapping:
        fail(f"{label} is missing {name}")
    return mapping[name]


def object_field(mapping: dict[str, Any], name: str, label: str) -> dict[str, Any]:
    value = field(mapping, name, label)
    if not isinstance(value, dict):
        fail(f"{label}.{name} must be an object")
    return value


def require_exact_keys(mapping: dict[str, Any], expected: set[str], label: str) -> None:
    actual = set(mapping)
    if actual == expected:
        return
    missing = sorted(expected - actual)
    extra = sorted(actual - expected)
    fail(
        f"{label} keys are not exact"
        + (f"; missing: {', '.join(missing)}" if missing else "")
        + (f"; unexpected: {', '.join(extra)}" if extra else "")
    )


def recorded_integer(value: Any, label: str, *, minimum: int = 0) -> int:
    # bool is a subclass of int in Python, so use an exact type check.
    if type(value) is not int:  # noqa: E721 - intentional strict JSON type check
        fail(f"{label} must be a JSON integer")
    if value < minimum:
        fail(f"{label} must be at least {minimum}")
    return value


def live_integer(value: Any, label: str, *, minimum: int = 0) -> int:
    if type(value) is int:  # noqa: E721 - deliberately reject booleans
        parsed = value
    elif isinstance(value, str):
        try:
            parsed = int(value, 16 if value.lower().startswith("0x") else 10)
        except ValueError as exc:
            raise VerificationError(f"{label} is not an integer") from exc
    else:
        fail(f"{label} is not an integer")
    if parsed < minimum:
        fail(f"{label} must be at least {minimum}")
    return parsed


def require_string(value: Any, label: str, *, nonempty: bool = True) -> str:
    if not isinstance(value, str) or (nonempty and not value):
        fail(f"{label} must be {'a nonempty' if nonempty else 'a'} string")
    return value


def require_bool(value: Any, label: str) -> bool:
    if type(value) is not bool:  # noqa: E721 - intentional strict JSON type check
        fail(f"{label} must be a JSON boolean")
    return value


def require_address(value: Any, label: str) -> str:
    if not isinstance(value, str) or not ADDRESS_RE.fullmatch(value):
        fail(f"{label} is not a valid address")
    return value.lower()


def require_hash(value: Any, label: str) -> str:
    if not isinstance(value, str) or not HASH_RE.fullmatch(value):
        fail(f"{label} is not a valid hash")
    return value.lower()


def require_sha256(value: Any, label: str) -> str:
    if not isinstance(value, str) or not SHA256_RE.fullmatch(value):
        fail(f"{label} is not a lowercase SHA-256 digest")
    return value


def require_hex_bytes(value: Any, label: str) -> str:
    if not isinstance(value, str) or not HEX_BYTES_RE.fullmatch(value):
        fail(f"{label} is not nonempty byte-aligned hex data")
    return value.lower()


def first_line(text: str) -> str:
    return text.splitlines()[0] if text.splitlines() else ""


def parse_lock(path: Path) -> dict[str, str]:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise VerificationError(f"cannot read toolchain lock: {path}") from exc
    values: dict[str, str] = {}
    for number, raw in enumerate(lines, start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        match = LOCK_LINE_RE.fullmatch(line)
        if not match:
            fail(f"unsupported toolchain lock syntax on line {number}")
        key, value = match.groups()
        if key in values:
            fail(f"duplicate toolchain lock key: {key}")
        values[key] = value
    required = {
        "FORGE_RELEASE_VERSION",
        "FORGE_RELEASE_SHA256",
        "CAST_RELEASE_SHA256",
        "SOLC_VERSION",
        "SOLC_RELEASE_SHA256",
    }
    missing = sorted(required - values.keys())
    if missing:
        fail(f"toolchain lock is missing exact release keys: {', '.join(missing)}")
    for key in ("FORGE_RELEASE_SHA256", "CAST_RELEASE_SHA256", "SOLC_RELEASE_SHA256"):
        require_sha256(values[key], f"toolchain lock {key}")
    return values


def resolve_executable(name: str) -> Path:
    path = shutil.which(name)
    if path is None:
        fail(f"{name} is not installed")
    resolved = Path(path).resolve()
    if not resolved.is_file():
        fail(f"{name} does not resolve to a regular file")
    return resolved


def inspect_toolchain(project_root: Path) -> Toolchain:
    lock_path = project_root / "scripts" / "toolchain.lock"
    foundry_toml = project_root / "foundry.toml"
    if not foundry_toml.is_file():
        fail(f"foundry.toml is missing under project root: {project_root}")
    locked = parse_lock(lock_path)

    forge_path = resolve_executable("forge")
    cast_path = resolve_executable("cast")
    forge_sha256 = sha256_file(forge_path)
    cast_sha256 = sha256_file(cast_path)
    if forge_sha256 != locked["FORGE_RELEASE_SHA256"]:
        fail("forge binary SHA-256 does not match scripts/toolchain.lock")
    if cast_sha256 != locked["CAST_RELEASE_SHA256"]:
        fail("cast binary SHA-256 does not match scripts/toolchain.lock")

    forge_version = first_line(
        run_command([str(forge_path), "--version"], label="forge --version")
    )
    if forge_version != locked["FORGE_RELEASE_VERSION"]:
        fail("forge version does not match scripts/toolchain.lock")

    solc_version = locked["SOLC_VERSION"]
    home = Path(os.environ.get("HOME", "")).resolve()
    solc_path = home / ".svm" / solc_version / f"solc-{solc_version}"
    if not solc_path.is_file() or not os.access(solc_path, os.X_OK):
        fail(f"pinned solc binary is missing: {solc_path}")
    solc_path = solc_path.resolve()
    solc_sha256 = sha256_file(solc_path)
    if solc_sha256 != locked["SOLC_RELEASE_SHA256"]:
        fail("solc binary SHA-256 does not match scripts/toolchain.lock")
    solc_output = run_command([str(solc_path), "--version"], label="solc --version")
    match = re.search(
        r"^Version: (\d+\.\d+\.\d+\+commit\.[0-9a-fA-F]+)(?:\.\S+)?$",
        solc_output,
        flags=re.MULTILINE,
    )
    if match is None or not match.group(1).startswith(solc_version + "+"):
        fail("solc executable version does not match scripts/toolchain.lock")

    return Toolchain(
        lock_sha256=sha256_file(lock_path),
        foundry_toml_sha256=sha256_file(foundry_toml),
        forge_path=forge_path,
        forge_version=forge_version,
        forge_sha256=forge_sha256,
        cast_path=cast_path,
        cast_sha256=cast_sha256,
        solc_path=solc_path,
        solc_version=solc_version,
        solc_long_version=match.group(1),
        solc_sha256=solc_sha256,
    )


def verify_toolchain_unchanged(project_root: Path, toolchain: Toolchain) -> None:
    if sha256_file(project_root / "scripts" / "toolchain.lock") != toolchain.lock_sha256:
        fail("scripts/toolchain.lock changed during receipt verification")
    if sha256_file(project_root / "foundry.toml") != toolchain.foundry_toml_sha256:
        fail("foundry.toml changed during receipt verification")
    for label, path, expected in (
        ("forge", toolchain.forge_path, toolchain.forge_sha256),
        ("cast", toolchain.cast_path, toolchain.cast_sha256),
        ("solc", toolchain.solc_path, toolchain.solc_sha256),
    ):
        if sha256_file(path) != expected:
            fail(f"{label} binary changed during receipt verification")
    version = first_line(
        run_command([str(toolchain.forge_path), "--version"], label="forge --version")
    )
    if version != toolchain.forge_version:
        fail("forge version changed during receipt verification")


def sanitized_foundry_env(temp_root: Path, toolchain: Toolchain) -> dict[str, str]:
    env = {
        key: value
        for key, value in os.environ.items()
        if not key.startswith(("FOUNDRY_", "DAPP_", "CAST_", "ETH_"))
        and key
        not in {
            "RPC_URL",
            "RELEASE_CHECKPOINT_RPC_URL",
            "PRIVATE_KEY",
            "MNEMONIC",
            "PASSWORD",
            "DEPLOY_KEYSTORE",
            "DEPLOY_PASSWORD_FILE",
            "AWS_ACCESS_KEY_ID",
            "AWS_SECRET_ACCESS_KEY",
            "AWS_SESSION_TOKEN",
        }
    }
    # The build is local-only.  Do not expose the deployment RPC to compiler
    # subprocesses or allow its state to influence compilation.
    env.pop("SOLC_PATH", None)
    env.update(
        {
            "FOUNDRY_PROFILE": PROFILE_NAME,
            "FOUNDRY_SOLC_VERSION": toolchain.solc_version,
            "FOUNDRY_OPTIMIZER": "true",
            "FOUNDRY_OPTIMIZER_RUNS": str(OPTIMIZER_RUNS),
            "FOUNDRY_EVM_VERSION": EVM_VERSION,
            "FOUNDRY_VIA_IR": "true",
            "FOUNDRY_FFI": "false",
            "FOUNDRY_SRC": "src",
            "FOUNDRY_LIBS": '["lib"]',
            "FOUNDRY_AUTO_DETECT_SOLC": "false",
            "FOUNDRY_AUTO_DETECT_REMAPPINGS": "false",
            "FOUNDRY_REMAPPINGS": FOUNDRY_REMAPPING,
            "FOUNDRY_OUT": str(temp_root / "out"),
            "FOUNDRY_CACHE_PATH": str(temp_root / "cache"),
            "SVM_HOME": str(toolchain.solc_path.parent.parent),
        }
    )
    return env


def artifact_metadata(artifact: dict[str, Any], label: str) -> dict[str, Any]:
    metadata = field(artifact, "metadata", label)
    if isinstance(metadata, str):
        metadata = strict_json_loads(metadata, f"{label}.metadata")
    if not isinstance(metadata, dict):
        fail(f"{label}.metadata must be an object")
    return metadata


def artifact_bytecode(artifact: dict[str, Any], section: str, label: str) -> str:
    section_value = object_field(artifact, section, label)
    return require_hex_bytes(
        field(section_value, "object", f"{label}.{section}"),
        f"{label}.{section}.object",
    )


def normalized_immutable_locations(value: Any, label: str) -> tuple[tuple[int, int], ...]:
    """Return stable immutable offsets, ignoring compiler-assigned AST-ID keys."""

    if not isinstance(value, dict) or len(value) != 1:
        fail(f"{label} must contain exactly one immutable reference group")
    locations = next(iter(value.values()))
    if not isinstance(locations, list) or not locations:
        fail(f"{label} immutable reference group is empty")
    normalized: list[tuple[int, int]] = []
    for index, location in enumerate(locations):
        if not isinstance(location, dict):
            fail(f"{label} immutable reference {index} is not an object")
        require_exact_keys(location, {"start", "length"}, f"{label}[{index}]")
        normalized.append(
            (
                recorded_integer(
                    field(location, "start", f"{label}[{index}]"),
                    f"{label}[{index}].start",
                ),
                recorded_integer(
                    field(location, "length", f"{label}[{index}]"),
                    f"{label}[{index}].length",
                    minimum=1,
                ),
            )
        )
    if len(set(normalized)) != len(normalized):
        fail(f"{label} contains duplicate immutable references")
    return tuple(sorted(normalized))


def verify_artifact_profile(
    artifact: dict[str, Any],
    *,
    label: str,
    source: str,
    contract: str,
    toolchain: Toolchain,
) -> str:
    metadata = artifact_metadata(artifact, label)
    compiler = object_field(metadata, "compiler", f"{label}.metadata")
    compiler_version = require_string(
        field(compiler, "version", f"{label}.metadata.compiler"),
        f"{label}.metadata.compiler.version",
    )
    if compiler_version != toolchain.solc_long_version:
        fail(f"{label} compiler version differs from the pinned solc executable")

    settings = object_field(metadata, "settings", f"{label}.metadata")
    optimizer = object_field(settings, "optimizer", f"{label}.metadata.settings")
    if require_bool(
        field(optimizer, "enabled", f"{label}.metadata.settings.optimizer"),
        f"{label}.metadata.settings.optimizer.enabled",
    ) is not True:
        fail(f"{label} optimizer is disabled")
    if recorded_integer(
        field(optimizer, "runs", f"{label}.metadata.settings.optimizer"),
        f"{label}.metadata.settings.optimizer.runs",
    ) != OPTIMIZER_RUNS:
        fail(f"{label} optimizer runs are not {OPTIMIZER_RUNS}")
    if require_bool(
        field(settings, "viaIR", f"{label}.metadata.settings"),
        f"{label}.metadata.settings.viaIR",
    ) is not True:
        fail(f"{label} was not built via IR")
    if field(settings, "evmVersion", f"{label}.metadata.settings") != EVM_VERSION:
        fail(f"{label} EVM version is not {EVM_VERSION}")
    target = object_field(settings, "compilationTarget", f"{label}.metadata.settings")
    if target != {source: contract}:
        fail(f"{label} compilation target is not exact")
    return compiler_version


def rebuild_artifacts(project_root: Path, toolchain: Toolchain) -> LocalArtifacts:
    with tempfile.TemporaryDirectory(prefix="pulsetensor-receipt-build-") as raw_temp:
        temp_root = Path(raw_temp)
        env = sanitized_foundry_env(temp_root, toolchain)
        config = parse_object(
            "forge config",
            run_command(
                [str(toolchain.forge_path), "config", "--json"],
                cwd=project_root,
                env=env,
                label="forge config",
            ),
        )
        expected_config = {
            "optimizer": True,
            "optimizer_runs": OPTIMIZER_RUNS,
            "via_ir": True,
            "evm_version": EVM_VERSION,
            "ffi": False,
            "libs": ["lib"],
            "auto_detect_solc": False,
            "auto_detect_remappings": False,
            "remappings": [FOUNDRY_REMAPPING],
        }
        for key, expected in expected_config.items():
            if config.get(key) != expected:
                fail(f"sanitized Foundry configuration mismatch for {key}")
        configured_solc = str(config.get("solc", config.get("solc_version", "")))
        if toolchain.solc_version not in configured_solc:
            fail("sanitized Foundry configuration does not select pinned solc")

        run_command(
            [str(toolchain.forge_path), "build", "--force"],
            cwd=project_root,
            env=env,
            label="clean isolated deployment build",
        )
        out = temp_root / "out"
        core_path = out / "PulseTensorCore.sol" / "PulseTensorCore.json"
        settlement_path = (
            out
            / "PulseTensorInferenceSettlement.sol"
            / "PulseTensorInferenceSettlement.json"
        )
        core = load_object(core_path, "Core artifact")
        settlement = load_object(settlement_path, "Settlement artifact")
        core_version = verify_artifact_profile(
            core,
            label="Core artifact",
            source="src/PulseTensorCore.sol",
            contract="PulseTensorCore",
            toolchain=toolchain,
        )
        settlement_version = verify_artifact_profile(
            settlement,
            label="Settlement artifact",
            source="src/PulseTensorInferenceSettlement.sol",
            contract="PulseTensorInferenceSettlement",
            toolchain=toolchain,
        )
        if core_version != settlement_version:
            fail("deployment artifacts use different compiler versions")

        core_abi = field(core, "abi", "Core artifact")
        settlement_abi = field(settlement, "abi", "Settlement artifact")
        if not isinstance(core_abi, list) or not isinstance(settlement_abi, list):
            fail("deployment artifact ABI must be an array")
        core_constructors = [
            item
            for item in core_abi
            if isinstance(item, dict) and item.get("type") == "constructor"
        ]
        if core_constructors:
            fail("Core artifact unexpectedly declares constructor arguments")
        settlement_constructors = [
            item
            for item in settlement_abi
            if isinstance(item, dict) and item.get("type") == "constructor"
        ]
        if len(settlement_constructors) != 1:
            fail("Settlement artifact must declare exactly one constructor")
        constructor = settlement_constructors[0]
        if constructor.get("stateMutability") != "nonpayable" or constructor.get(
            "inputs"
        ) != [
            {
                "name": "coreAddress",
                "type": "address",
                "internalType": "address",
            }
        ]:
            fail("Settlement constructor ABI is not exactly constructor(address)")

        core_deployed = object_field(core, "deployedBytecode", "Core artifact")
        core_creation_section = object_field(core, "bytecode", "Core artifact")
        settlement_creation_section = object_field(
            settlement, "bytecode", "Settlement artifact"
        )
        core_references = core_deployed.get("immutableReferences") or {}
        if core_references != {}:
            fail("Core artifact unexpectedly contains immutable references")
        settlement_deployed = object_field(
            settlement, "deployedBytecode", "Settlement artifact"
        )
        references = field(
            settlement_deployed,
            "immutableReferences",
            "Settlement artifact.deployedBytecode",
        )
        if not isinstance(references, dict) or len(references) != 1:
            fail("Settlement artifact must contain one immutable reference group")
        for section, label in (
            (core_creation_section, "Core creation artifact"),
            (core_deployed, "Core runtime artifact"),
            (settlement_creation_section, "Settlement creation artifact"),
            (settlement_deployed, "Settlement runtime artifact"),
        ):
            if section.get("linkReferences") not in (None, {}):
                fail(f"{label} unexpectedly contains unresolved library links")

        return LocalArtifacts(
            core_creation=artifact_bytecode(core, "bytecode", "Core artifact"),
            core_runtime=artifact_bytecode(
                core, "deployedBytecode", "Core artifact"
            ),
            settlement_creation=artifact_bytecode(
                settlement, "bytecode", "Settlement artifact"
            ),
            settlement_runtime_template=artifact_bytecode(
                settlement, "deployedBytecode", "Settlement artifact"
            ),
            settlement_immutable_references=references,
            compiler_version=core_version,
            core_artifact_sha256=sha256_file(core_path),
            settlement_artifact_sha256=sha256_file(settlement_path),
        )


def materialize_commit_snapshot(
    project_root: Path, source_commit: str, destination: Path
) -> None:
    archive_path = destination.parent / "source.tar"
    try:
        with archive_path.open("wb") as output:
            result = subprocess.run(
                ["git", "archive", "--format=tar", source_commit],
                cwd=project_root,
                stdout=output,
                stderr=subprocess.PIPE,
                check=False,
            )
    except (OSError, FileNotFoundError) as exc:
        raise VerificationError("cannot materialize recorded Git source commit") from exc
    if result.returncode != 0:
        detail = redact(result.stderr.decode("utf-8", errors="replace").strip())
        fail(f"git archive of recorded source commit failed: {detail}")
    destination.mkdir(mode=0o700)
    try:
        with tarfile.open(archive_path, mode="r:") as archive:
            archive.extractall(destination, filter="data")
    except (OSError, tarfile.TarError) as exc:
        raise VerificationError("recorded Git source archive is invalid") from exc


def verify_commit_snapshot_artifacts(
    *,
    project_root: Path,
    source_commit: str,
    toolchain: Toolchain,
    live_artifacts: LocalArtifacts,
) -> None:
    """Compile production contracts from immutable Git objects and compare bytes."""

    with tempfile.TemporaryDirectory(prefix="pulsetensor-source-snapshot-") as raw:
        temp_root = Path(raw)
        snapshot = temp_root / "source"
        materialize_commit_snapshot(project_root, source_commit, snapshot)
        # forge-std is an ignored development dependency, so it is intentionally
        # absent from git archive.  Foundry drops a remapping whose target path
        # does not exist, which changes Solidity's metadata hash even though the
        # production contracts import no forge-std code.  An empty target keeps
        # the authorized foundry.toml remapping exact without trusting ignored
        # dependency contents during the production-only build.
        (snapshot / "lib" / "forge-std" / "src").mkdir(parents=True)
        snapshot_foundry = snapshot / "foundry.toml"
        if sha256_file(snapshot_foundry) != toolchain.foundry_toml_sha256:
            fail("recorded commit foundry.toml differs from the verified local profile")
        build_root = temp_root / "build"
        env = sanitized_foundry_env(build_root, toolchain)
        run_command(
            [
                str(toolchain.forge_path),
                "build",
                "--force",
                "src/PulseTensorCore.sol",
                "src/PulseTensorInferenceSettlement.sol",
            ],
            cwd=snapshot,
            env=env,
            label="recorded-commit production build",
        )
        out = build_root / "out"
        core = load_object(
            out / "PulseTensorCore.sol" / "PulseTensorCore.json",
            "recorded-commit Core artifact",
        )
        settlement = load_object(
            out
            / "PulseTensorInferenceSettlement.sol"
            / "PulseTensorInferenceSettlement.json",
            "recorded-commit Settlement artifact",
        )
        verify_artifact_profile(
            core,
            label="recorded-commit Core artifact",
            source="src/PulseTensorCore.sol",
            contract="PulseTensorCore",
            toolchain=toolchain,
        )
        verify_artifact_profile(
            settlement,
            label="recorded-commit Settlement artifact",
            source="src/PulseTensorInferenceSettlement.sol",
            contract="PulseTensorInferenceSettlement",
            toolchain=toolchain,
        )
        comparisons = (
            (
                artifact_bytecode(core, "bytecode", "recorded-commit Core artifact"),
                live_artifacts.core_creation,
                "Core creation bytecode",
            ),
            (
                artifact_bytecode(
                    core, "deployedBytecode", "recorded-commit Core artifact"
                ),
                live_artifacts.core_runtime,
                "Core runtime bytecode",
            ),
            (
                artifact_bytecode(
                    settlement, "bytecode", "recorded-commit Settlement artifact"
                ),
                live_artifacts.settlement_creation,
                "Settlement creation bytecode",
            ),
            (
                artifact_bytecode(
                    settlement,
                    "deployedBytecode",
                    "recorded-commit Settlement artifact",
                ),
                live_artifacts.settlement_runtime_template,
                "Settlement runtime template",
            ),
        )
        for snapshot_value, live_value, label in comparisons:
            if snapshot_value != live_value:
                fail(f"live isolated build differs from recorded Git commit: {label}")
        snapshot_references = object_field(
            settlement,
            "deployedBytecode",
            "recorded-commit Settlement artifact",
        ).get("immutableReferences")
        if normalized_immutable_locations(
            snapshot_references, "recorded-commit Settlement artifact"
        ) != normalized_immutable_locations(
            live_artifacts.settlement_immutable_references,
            "live Settlement artifact",
        ):
            fail("Settlement immutable references differ from recorded Git commit")


def patch_settlement_runtime(artifacts: LocalArtifacts, core_address: str) -> str:
    raw = bytearray.fromhex(artifacts.settlement_runtime_template[2:])
    replacement = bytes.fromhex(core_address[2:].rjust(64, "0"))
    locations = next(iter(artifacts.settlement_immutable_references.values()))
    if not isinstance(locations, list) or not locations:
        fail("Settlement immutable reference group is empty")
    seen: set[tuple[int, int]] = set()
    for index, location in enumerate(locations):
        if not isinstance(location, dict):
            fail(f"Settlement immutable reference {index} is not an object")
        start = recorded_integer(
            field(location, "start", f"Settlement immutable reference {index}"),
            f"Settlement immutable reference {index}.start",
        )
        length = recorded_integer(
            field(location, "length", f"Settlement immutable reference {index}"),
            f"Settlement immutable reference {index}.length",
            minimum=1,
        )
        if length != 32 or start + length > len(raw):
            fail(f"Settlement immutable reference {index} is out of bounds")
        if (start, length) in seen:
            fail("Settlement artifact contains duplicate immutable references")
        seen.add((start, length))
        raw[start : start + length] = replacement
    return "0x" + raw.hex()


def keccak(toolchain: Toolchain, value: str, label: str) -> str:
    require_hex_bytes(value, label)
    return require_hash(run_cast(toolchain, "keccak", value), f"{label} hash")


def verify_recorded_toolchain(
    provenance: dict[str, Any], toolchain: Toolchain, artifacts: LocalArtifacts
) -> None:
    if field(provenance, "profile_id", "provenance") != PROFILE_ID:
        fail(f"provenance.profile_id must be {PROFILE_ID}")
    if field(provenance, "foundry_profile", "provenance") != PROFILE_NAME:
        fail(f"provenance.foundry_profile must be {PROFILE_NAME}")
    if recorded_integer(
        field(provenance, "optimizer_runs", "provenance"),
        "provenance.optimizer_runs",
    ) != OPTIMIZER_RUNS:
        fail(f"provenance.optimizer_runs must be {OPTIMIZER_RUNS}")
    if field(provenance, "compiler_version", "provenance") != artifacts.compiler_version:
        fail("provenance.compiler_version differs from rebuilt artifacts")
    if field(provenance, "forge_version", "provenance") != toolchain.forge_version:
        fail("provenance.forge_version differs from the pinned forge executable")

    recorded = object_field(provenance, "toolchain", "provenance")
    expected = {
        "toolchain_lock_sha256": toolchain.lock_sha256,
        "foundry_toml_sha256": toolchain.foundry_toml_sha256,
        "forge_version": toolchain.forge_version,
        "forge_sha256": toolchain.forge_sha256,
        "cast_sha256": toolchain.cast_sha256,
        "solc_version": toolchain.solc_version,
        "solc_long_version": toolchain.solc_long_version,
        "solc_sha256": toolchain.solc_sha256,
    }
    if set(recorded) != set(expected):
        missing = sorted(set(expected) - set(recorded))
        extra = sorted(set(recorded) - set(expected))
        fail(
            "provenance.toolchain keys are not exact"
            + (f"; missing: {', '.join(missing)}" if missing else "")
            + (f"; unexpected: {', '.join(extra)}" if extra else "")
        )
    for name, expected_value in expected.items():
        value = require_string(
            field(recorded, name, "provenance.toolchain"),
            f"provenance.toolchain.{name}",
        )
        if name.endswith("sha256"):
            require_sha256(value, f"provenance.toolchain.{name}")
        if value != expected_value:
            fail(f"provenance.toolchain.{name} differs from the verified local value")

    recorded_artifacts = object_field(provenance, "artifacts", "provenance")
    expected_artifacts = {
        "core_artifact_sha256": artifacts.core_artifact_sha256,
        "settlement_artifact_sha256": artifacts.settlement_artifact_sha256,
    }
    if set(recorded_artifacts) != set(expected_artifacts):
        fail("provenance.artifacts keys are not exact")
    for name, expected_value in expected_artifacts.items():
        value = require_sha256(
            field(recorded_artifacts, name, "provenance.artifacts"),
            f"provenance.artifacts.{name}",
        )
        if value != expected_value:
            fail(f"provenance.artifacts.{name} differs from the isolated rebuild")


def git_output(project_root: Path, *args: str, label: str) -> str:
    return run_command(["git", *args], cwd=project_root, label=label)


def verify_source(
    provenance: dict[str, Any], project_root: Path, require_clean_source: bool
) -> tuple[str, bool, str]:
    source_commit = require_string(
        field(provenance, "source_commit", "provenance"),
        "provenance.source_commit",
    )
    if not COMMIT_RE.fullmatch(source_commit):
        fail("provenance.source_commit is not a full lowercase Git commit")
    receipt_clean = require_bool(
        field(provenance, "source_clean", "provenance"),
        "provenance.source_clean",
    )
    live_commit = git_output(
        project_root, "rev-parse", "--verify", "HEAD", label="git rev-parse"
    ).lower()
    if source_commit != live_commit:
        fail("receipt source commit differs from the checked-out Git HEAD")
    status = git_output(
        project_root,
        "status",
        "--porcelain=v1",
        "--untracked-files=all",
        label="git status",
    )
    live_clean = status == ""
    if require_clean_source:
        if not receipt_clean:
            fail("receipt was not produced from a clean source tree")
        if not live_clean:
            fail("checked-out source tree is not clean")
    return live_commit, live_clean, status


def expected_network_anchor(chain_id: int) -> dict[str, Any] | None:
    if chain_id == MAINNET_CHAIN_ID:
        return {
            "block_number": MAINNET_ANCHOR_BLOCK,
            "block_hash": MAINNET_ANCHOR_HASH,
        }
    if chain_id == TESTNET_CHAIN_ID:
        return {
            "block_number": TESTNET_ANCHOR_BLOCK,
            "block_hash": TESTNET_ANCHOR_HASH,
        }
    return None


def validate_network_anchor_value(value: Any, chain_id: int, label: str) -> None:
    expected = expected_network_anchor(chain_id)
    if expected is None:
        if value is not None:
            fail(f"{label} must be null for an unanchored development chain")
        return
    if not isinstance(value, dict):
        fail(f"{label} must be an object for chain {chain_id}")
    require_exact_keys(value, {"block_number", "block_hash"}, label)
    block_number = recorded_integer(
        field(value, "block_number", label), f"{label}.block_number", minimum=1
    )
    block_hash = require_hash(field(value, "block_hash", label), f"{label}.block_hash")
    if block_number != expected["block_number"] or block_hash != expected["block_hash"]:
        fail(f"{label} does not match the pinned PulseChain network anchor")


def validate_release_checkpoint_value(
    provenance: dict[str, Any], chain_id: int
) -> dict[str, Any]:
    checkpoint = object_field(provenance, "release_checkpoint", "provenance")
    require_exact_keys(
        checkpoint,
        {"sha256", "chain_id", "run_id", "network_anchor", "live_reverified"},
        "provenance.release_checkpoint",
    )
    if chain_id != MAINNET_CHAIN_ID:
        if checkpoint != {
            "sha256": None,
            "chain_id": None,
            "run_id": None,
            "network_anchor": None,
            "live_reverified": False,
        }:
            fail("non-mainnet receipt must contain an empty release checkpoint record")
        return checkpoint
    require_sha256(
        field(checkpoint, "sha256", "provenance.release_checkpoint"),
        "provenance.release_checkpoint.sha256",
    )
    checkpoint_chain = recorded_integer(
        field(checkpoint, "chain_id", "provenance.release_checkpoint"),
        "provenance.release_checkpoint.chain_id",
        minimum=1,
    )
    if checkpoint_chain != TESTNET_CHAIN_ID:
        fail("mainnet release checkpoint must be from chain 943")
    checkpoint_run_id = require_string(
        field(checkpoint, "run_id", "provenance.release_checkpoint"),
        "provenance.release_checkpoint.run_id",
    )
    checkpoint_run_match = RUN_ID_RE.fullmatch(checkpoint_run_id)
    if (
        checkpoint_run_match is None
        or int(checkpoint_run_match.group(1)) != TESTNET_CHAIN_ID
    ):
        fail("mainnet release checkpoint run_id must encode chain 943")
    try:
        datetime.strptime(checkpoint_run_match.group(2), "%Y%m%dT%H%M%SZ")
    except ValueError as exc:
        raise VerificationError(
            "mainnet release checkpoint run_id contains an invalid UTC timestamp"
        ) from exc
    validate_network_anchor_value(
        field(checkpoint, "network_anchor", "provenance.release_checkpoint"),
        TESTNET_CHAIN_ID,
        "provenance.release_checkpoint.network_anchor",
    )
    if require_bool(
        field(checkpoint, "live_reverified", "provenance.release_checkpoint"),
        "provenance.release_checkpoint.live_reverified",
    ) is not True:
        fail("mainnet release checkpoint must be marked live-reverified")
    return checkpoint


def validate_recorded_confirmations(
    receipt: dict[str, Any], chain_id: int
) -> tuple[int, int, int, int]:
    """Validate receipt-time confirmation evidence without trusting live state."""

    contracts = object_field(receipt, "contracts", "receipt")
    core = object_field(contracts, "core", "contracts")
    settlement = object_field(contracts, "settlement", "contracts")
    core_block = recorded_integer(
        field(core, "block_number", "contracts.core"),
        "contracts.core.block_number",
        minimum=1,
    )
    settlement_block = recorded_integer(
        field(settlement, "block_number", "contracts.settlement"),
        "contracts.settlement.block_number",
        minimum=1,
    )
    if settlement_block < core_block:
        fail("Settlement deployment block predates the Core deployment block")
    confirmations = object_field(receipt, "confirmations", "receipt")
    required = recorded_integer(
        field(confirmations, "required", "confirmations"),
        "confirmations.required",
        minimum=1,
    )
    confirmed_at = recorded_integer(
        field(confirmations, "confirmed_at_block", "confirmations"),
        "confirmations.confirmed_at_block",
        minimum=1,
    )
    observed = recorded_integer(
        field(confirmations, "observed_at_publication", "confirmations"),
        "confirmations.observed_at_publication",
        minimum=1,
    )
    last_deployment_block = max(core_block, settlement_block)
    anchor = expected_network_anchor(chain_id)
    if anchor is not None and last_deployment_block <= anchor["block_number"]:
        fail("anchored PulseChain deployment must occur after the pinned anchor block")
    if confirmed_at < last_deployment_block:
        fail("recorded confirmation checkpoint predates deployment")
    if observed != confirmed_at - last_deployment_block + 1:
        fail("recorded confirmation count is inconsistent with its checkpoint")
    if observed < required:
        fail("receipt was published before its required confirmations")
    if chain_id == MAINNET_CHAIN_ID and required < MIN_RELEASE_CONFIRMATIONS:
        fail("chain 369 receipt must record at least 12 required confirmations")
    return required, confirmed_at, observed, last_deployment_block


def validate_v4_structure(receipt: dict[str, Any], chain_id: int) -> dict[str, Any]:
    top_level = {
        "schema",
        "generated_at_utc",
        "run_id",
        "chain_id",
        "deployer",
        "deployer_nonce_before",
        "deployer_nonce_after",
        "nonce_policy",
        "contracts",
        "confirmations",
        "provenance",
        "verification",
        "partial_journal",
        "network_anchor",
    }
    if chain_id == MAINNET_CHAIN_ID:
        top_level.add("gas_budget")
    require_exact_keys(receipt, top_level, "receipt")
    if field(receipt, "schema", "receipt") != SCHEMA:
        fail(f"unsupported deployment receipt schema; expected {SCHEMA}")
    if (
        recorded_integer(field(receipt, "chain_id", "receipt"), "chain_id", minimum=1)
        != chain_id
    ):
        fail("receipt chain_id differs from the validated chain ID")

    generated = require_string(
        field(receipt, "generated_at_utc", "receipt"), "generated_at_utc"
    )
    if not GENERATED_AT_RE.fullmatch(generated):
        fail("generated_at_utc is not canonical UTC seconds format")
    try:
        generated_at = datetime.strptime(generated, "%Y-%m-%dT%H:%M:%SZ").replace(
            tzinfo=timezone.utc
        )
    except ValueError as exc:
        raise VerificationError("generated_at_utc is not a valid timestamp") from exc
    run_id = require_string(field(receipt, "run_id", "receipt"), "run_id")
    run_match = RUN_ID_RE.fullmatch(run_id)
    if run_match is None or int(run_match.group(1)) != chain_id:
        fail("run_id does not encode the receipt chain ID")
    try:
        run_started_at = datetime.strptime(
            run_match.group(2), "%Y%m%dT%H%M%SZ"
        ).replace(tzinfo=timezone.utc)
    except ValueError as exc:
        raise VerificationError("run_id contains an invalid UTC timestamp") from exc
    if generated_at < run_started_at:
        fail("generated_at_utc predates the deployment run_id timestamp")
    if generated_at > datetime.now(timezone.utc) + timedelta(minutes=5):
        fail("generated_at_utc is implausibly far in the future")
    partial_journal = require_string(
        field(receipt, "partial_journal", "receipt"), "partial_journal"
    )
    journal_pattern = re.compile(
        rf"^pulsetensor_deploy_{re.escape(run_id)}\.[A-Za-z0-9]{{6}}\.journal\.jsonl$"
    )
    if journal_pattern.fullmatch(partial_journal) is None:
        fail("partial_journal is not the basename for this exact deployment run")

    validate_network_anchor_value(
        field(receipt, "network_anchor", "receipt"), chain_id, "network_anchor"
    )
    contracts = object_field(receipt, "contracts", "receipt")
    require_exact_keys(contracts, {"core", "settlement"}, "contracts")
    core = object_field(contracts, "core", "contracts")
    settlement = object_field(contracts, "settlement", "contracts")
    common_contract_keys = {
        "address",
        "transaction_hash",
        "nonce",
        "gas_estimate",
        "gas_limit",
        "gas_used",
        "effective_gas_price_wei",
        "block_number",
        "block_hash",
        "creation_bytecode_hash",
        "creation_transaction_input_hash",
        "expected_runtime_hash",
        "deployed_runtime_hash",
    }
    require_exact_keys(core, common_contract_keys, "contracts.core")
    require_exact_keys(
        settlement,
        common_contract_keys | {"local_runtime_template_hash", "core_binding"},
        "contracts.settlement",
    )
    confirmations = object_field(receipt, "confirmations", "receipt")
    require_exact_keys(
        confirmations,
        {"required", "confirmed_at_block", "observed_at_publication"},
        "confirmations",
    )
    validate_recorded_confirmations(receipt, chain_id)
    provenance = object_field(receipt, "provenance", "receipt")
    require_exact_keys(
        provenance,
        {
            "source_commit",
            "source_clean",
            "profile_id",
            "foundry_profile",
            "optimizer_runs",
            "compiler_version",
            "forge_version",
            "toolchain",
            "artifacts",
            "release_checkpoint",
        },
        "provenance",
    )
    recorded_source_clean = require_bool(
        field(provenance, "source_clean", "provenance"),
        "provenance.source_clean",
    )
    if chain_id == MAINNET_CHAIN_ID and not recorded_source_clean:
        fail("chain 369 receipt must attest a clean deployment source tree")
    checkpoint = validate_release_checkpoint_value(provenance, chain_id)
    verification = object_field(receipt, "verification", "receipt")
    verification_keys = {
        "passed",
        "chain_id_rechecked",
        "transaction_receipts_rechecked",
        "sender_and_nonce_sequence_checked",
        "exact_runtime_bytecode_checked",
        "immutable_core_binding_checked",
    }
    require_exact_keys(verification, verification_keys, "verification")
    for name in verification_keys:
        if require_bool(verification[name], f"verification.{name}") is not True:
            fail(f"verification.{name} must be true")
    return checkpoint


def verify_live_network_anchor(
    receipt: dict[str, Any], chain_id: int, toolchain: Toolchain
) -> None:
    expected = expected_network_anchor(chain_id)
    if expected is None:
        return
    block = parse_object(
        "network anchor block",
        run_cast(toolchain, "block", "--json", str(expected["block_number"])),
    )
    number = live_integer(
        field(block, "number", "network anchor block"),
        "network_anchor.live_block_number",
        minimum=1,
    )
    block_hash = require_hash(
        field(block, "hash", "network anchor block"),
        "network_anchor.live_block_hash",
    )
    if number != expected["block_number"] or block_hash != expected["block_hash"]:
        fail(f"RPC does not match the pinned PulseChain chain {chain_id} anchor")
    validate_network_anchor_value(
        field(receipt, "network_anchor", "receipt"), chain_id, "network_anchor"
    )


def verify_release_checkpoint_live(
    *,
    checkpoint_path: Path | None,
    recorded_checkpoint: dict[str, Any],
    project_root: Path,
    expected_source_commit: str,
    expected_mainnet_run_id: str,
) -> None:
    if checkpoint_path is None:
        fail("chain 369 verification requires --release-checkpoint")
    open_flags = os.O_RDONLY
    if hasattr(os, "O_NOFOLLOW"):
        open_flags |= os.O_NOFOLLOW
    elif checkpoint_path.is_symlink():
        fail("--release-checkpoint must be a regular, non-symlink file")
    try:
        descriptor = os.open(checkpoint_path, open_flags)
    except OSError as exc:
        raise VerificationError(
            "--release-checkpoint must be a readable regular, non-symlink file"
        ) from exc
    try:
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            fail("--release-checkpoint must be a regular, non-symlink file")
        with os.fdopen(descriptor, "rb", closefd=False) as handle:
            raw = handle.read()
    except OSError as exc:
        raise VerificationError("cannot read supplied release checkpoint") from exc
    finally:
        os.close(descriptor)
    digest = hashlib.sha256(raw).hexdigest()
    if digest != recorded_checkpoint["sha256"]:
        fail("supplied release checkpoint digest differs from the mainnet receipt")
    try:
        checkpoint_text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise VerificationError("release checkpoint receipt is not UTF-8") from exc
    checkpoint_receipt = strict_json_loads(
        checkpoint_text, "release checkpoint receipt"
    )
    if not isinstance(checkpoint_receipt, dict):
        fail("release checkpoint receipt must be a JSON object")
    if checkpoint_receipt.get("schema") != SCHEMA:
        fail("supplied release checkpoint has an unsupported schema")
    checkpoint_chain = recorded_integer(
        field(checkpoint_receipt, "chain_id", "release checkpoint receipt"),
        "release_checkpoint.chain_id",
        minimum=1,
    )
    if checkpoint_chain != TESTNET_CHAIN_ID:
        fail("supplied release checkpoint is not from PulseChain testnet chain 943")
    validate_v4_structure(checkpoint_receipt, checkpoint_chain)
    if checkpoint_receipt["run_id"] != recorded_checkpoint["run_id"]:
        fail("supplied release checkpoint run_id differs from the mainnet receipt")
    if checkpoint_receipt["network_anchor"] != recorded_checkpoint["network_anchor"]:
        fail("supplied release checkpoint network anchor differs from mainnet evidence")
    mainnet_run_match = RUN_ID_RE.fullmatch(expected_mainnet_run_id)
    if mainnet_run_match is None:
        fail("mainnet receipt run_id is invalid during checkpoint verification")
    mainnet_run_started_at = datetime.strptime(
        mainnet_run_match.group(2), "%Y%m%dT%H%M%SZ"
    ).replace(tzinfo=timezone.utc)
    checkpoint_generated_at = datetime.strptime(
        checkpoint_receipt["generated_at_utc"], "%Y-%m-%dT%H:%M:%SZ"
    ).replace(tzinfo=timezone.utc)
    if checkpoint_generated_at >= mainnet_run_started_at:
        fail("release checkpoint must have been generated before the mainnet run")
    checkpoint_provenance = object_field(
        checkpoint_receipt, "provenance", "release checkpoint receipt"
    )
    checkpoint_source_commit = require_string(
        field(checkpoint_provenance, "source_commit", "release checkpoint provenance"),
        "release_checkpoint.provenance.source_commit",
    ).lower()
    if checkpoint_source_commit != expected_source_commit:
        fail("release checkpoint source commit differs from the mainnet receipt")
    if require_bool(
        field(checkpoint_provenance, "source_clean", "release checkpoint provenance"),
        "release_checkpoint.provenance.source_clean",
    ) is not True:
        fail("release checkpoint receipt was not produced from clean source")
    confirmations = object_field(
        checkpoint_receipt, "confirmations", "release checkpoint receipt"
    )
    recorded_required = recorded_integer(
        field(confirmations, "required", "release checkpoint confirmations"),
        "release_checkpoint.confirmations.required",
        minimum=1,
    )
    recorded_observed = recorded_integer(
        field(
            confirmations,
            "observed_at_publication",
            "release checkpoint confirmations",
        ),
        "release_checkpoint.confirmations.observed_at_publication",
        minimum=1,
    )
    if (
        recorded_required < MIN_RELEASE_CONFIRMATIONS
        or recorded_observed < MIN_RELEASE_CONFIRMATIONS
    ):
        fail("release checkpoint receipt does not record at least 12 confirmations")

    checkpoint_rpc = os.environ.get("RELEASE_CHECKPOINT_RPC_URL", "")
    if not checkpoint_rpc:
        fail("chain 369 verification requires RELEASE_CHECKPOINT_RPC_URL")
    if "\n" in checkpoint_rpc or "\r" in checkpoint_rpc:
        fail("RELEASE_CHECKPOINT_RPC_URL must not contain line breaks")
    if checkpoint_rpc == os.environ.get("ETH_RPC_URL"):
        fail("mainnet and release-checkpoint RPC URLs must be distinct")
    checkpoint_env = os.environ.copy()
    checkpoint_env["ETH_RPC_URL"] = checkpoint_rpc
    checkpoint_env.pop("RELEASE_CHECKPOINT_RPC_URL", None)
    with tempfile.TemporaryDirectory(
        prefix="pulsetensor-checkpoint-verification-"
    ) as raw_temp:
        checkpoint_snapshot = Path(raw_temp) / "release-checkpoint.receipt.json"
        descriptor = os.open(
            checkpoint_snapshot, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o400
        )
        try:
            os.fchmod(descriptor, 0o400)
            with os.fdopen(descriptor, "wb", closefd=False) as handle:
                handle.write(raw)
                handle.flush()
                os.fsync(handle.fileno())
        finally:
            os.close(descriptor)
        output = run_command(
            [
                sys.executable,
                str(Path(__file__).resolve()),
                str(checkpoint_snapshot),
                "--project-root",
                str(project_root),
                "--min-confirmations",
                str(MIN_RELEASE_CONFIRMATIONS),
                "--require-clean-source",
            ],
            cwd=project_root,
            env=checkpoint_env,
            label="live release checkpoint verification",
        )
    result = parse_object("live release checkpoint verification", output)
    if result.get("verified") is not True or result.get("chain_id") != TESTNET_CHAIN_ID:
        fail("live release checkpoint verifier returned an invalid result")


def verify_gas_budget(receipt: dict[str, Any], chain_id: int) -> GasBudget | None:
    if chain_id != 369:
        if "gas_budget" in receipt:
            fail("gas_budget must be omitted for non-mainnet receipts")
        return None
    raw = field(receipt, "gas_budget", "receipt")
    if not isinstance(raw, dict):
        fail("chain 369 receipt must include a gas_budget object")
    expected_keys = {
        "max_fee_per_gas_wei",
        "core_estimated_gas",
        "settlement_estimated_gas",
        "margin_bps",
        "maximum_total_cost_wei",
        "deployer_balance_before_wei",
    }
    if set(raw) != expected_keys:
        missing = sorted(expected_keys - set(raw))
        extra = sorted(set(raw) - expected_keys)
        fail(
            "gas_budget keys are not exact"
            + (f"; missing: {', '.join(missing)}" if missing else "")
            + (f"; unexpected: {', '.join(extra)}" if extra else "")
        )
    budget = GasBudget(
        max_fee_per_gas_wei=recorded_integer(
            raw["max_fee_per_gas_wei"],
            "gas_budget.max_fee_per_gas_wei",
            minimum=1,
        ),
        core_estimated_gas=recorded_integer(
            raw["core_estimated_gas"],
            "gas_budget.core_estimated_gas",
            minimum=1,
        ),
        settlement_estimated_gas=recorded_integer(
            raw["settlement_estimated_gas"],
            "gas_budget.settlement_estimated_gas",
            minimum=1,
        ),
        margin_bps=recorded_integer(
            raw["margin_bps"], "gas_budget.margin_bps"
        ),
        maximum_total_cost_wei=recorded_integer(
            raw["maximum_total_cost_wei"],
            "gas_budget.maximum_total_cost_wei",
            minimum=1,
        ),
        deployer_balance_before_wei=recorded_integer(
            raw["deployer_balance_before_wei"],
            "gas_budget.deployer_balance_before_wei",
            minimum=1,
        ),
    )
    if budget.margin_bps != GAS_MARGIN_BPS:
        fail("gas_budget.margin_bps must be exactly 2000")
    core_limit = (
        budget.core_estimated_gas * (10_000 + budget.margin_bps) + 9_999
    ) // 10_000
    settlement_limit = (
        budget.settlement_estimated_gas * (10_000 + budget.margin_bps) + 9_999
    ) // 10_000
    expected_maximum = (
        core_limit + settlement_limit
    ) * budget.max_fee_per_gas_wei
    if budget.maximum_total_cost_wei != expected_maximum:
        fail("gas_budget.maximum_total_cost_wei does not match the exact ceiling formula")
    if budget.deployer_balance_before_wei < budget.maximum_total_cost_wei:
        fail("recorded deployer balance does not cover the maximum gas budget")
    return budget


def verify_contract_budget_alignment(
    core: dict[str, Any], settlement: dict[str, Any], gas_budget: GasBudget | None
) -> None:
    core_estimate = recorded_integer(
        field(core, "gas_estimate", "core"), "core.gas_estimate", minimum=1
    )
    settlement_estimate = recorded_integer(
        field(settlement, "gas_estimate", "settlement"),
        "settlement.gas_estimate",
        minimum=1,
    )
    core_limit = recorded_integer(
        field(core, "gas_limit", "core"), "core.gas_limit", minimum=1
    )
    settlement_limit = recorded_integer(
        field(settlement, "gas_limit", "settlement"),
        "settlement.gas_limit",
        minimum=1,
    )
    expected_core_limit = (
        core_estimate * (10_000 + GAS_MARGIN_BPS) + 9_999
    ) // 10_000
    expected_settlement_limit = (
        settlement_estimate * (10_000 + GAS_MARGIN_BPS) + 9_999
    ) // 10_000
    if core_limit != expected_core_limit:
        fail("core.gas_limit is not the exact 20% individual-ceiling budget")
    if settlement_limit != expected_settlement_limit:
        fail("settlement.gas_limit is not the exact 20% individual-ceiling budget")
    if gas_budget is not None:
        if core_estimate != gas_budget.core_estimated_gas:
            fail("core.gas_estimate differs from gas_budget.core_estimated_gas")
        if settlement_estimate != gas_budget.settlement_estimated_gas:
            fail(
                "settlement.gas_estimate differs from "
                "gas_budget.settlement_estimated_gas"
            )


def verify_nonce_policy(
    receipt: dict[str, Any],
    *,
    nonce_before: int,
    nonce_after: int,
    core: dict[str, Any],
    settlement: dict[str, Any],
) -> None:
    policy = object_field(receipt, "nonce_policy", "receipt")
    expected_keys = {
        "latest_before",
        "pending_before",
        "core_nonce",
        "settlement_nonce",
        "latest_after",
        "pending_after",
        "explicit_nonces_used",
    }
    if set(policy) != expected_keys:
        missing = sorted(expected_keys - set(policy))
        extra = sorted(set(policy) - expected_keys)
        fail(
            "nonce_policy keys are not exact"
            + (f"; missing: {', '.join(missing)}" if missing else "")
            + (f"; unexpected: {', '.join(extra)}" if extra else "")
        )
    numbers = {
        name: recorded_integer(policy[name], f"nonce_policy.{name}")
        for name in expected_keys - {"explicit_nonces_used"}
    }
    if require_bool(
        policy["explicit_nonces_used"], "nonce_policy.explicit_nonces_used"
    ) is not True:
        fail("nonce_policy.explicit_nonces_used must be true")
    expected_numbers = {
        "latest_before": nonce_before,
        "pending_before": nonce_before,
        "core_nonce": nonce_before,
        "settlement_nonce": nonce_before + 1,
        "latest_after": nonce_before + 2,
        "pending_after": nonce_before + 2,
    }
    if numbers != expected_numbers:
        fail("nonce_policy does not record one exact, pending-safe two-nonce sequence")
    if nonce_after != nonce_before + 2:
        fail("receipt deployer nonce sequence is inconsistent with nonce_policy")
    if recorded_integer(field(core, "nonce", "core"), "core.nonce") != numbers[
        "core_nonce"
    ]:
        fail("core.nonce differs from nonce_policy.core_nonce")
    if recorded_integer(
        field(settlement, "nonce", "settlement"), "settlement.nonce"
    ) != numbers["settlement_nonce"]:
        fail("settlement.nonce differs from nonce_policy.settlement_nonce")


def verify_contract(
    *,
    label: str,
    contract: dict[str, Any],
    deployer: str,
    expected_nonce: int,
    chain_id: int,
    expected_creation_input: str,
    expected_runtime: str,
    toolchain: Toolchain,
    max_fee_per_gas_wei: int | None,
) -> tuple[int, str, int]:
    address = require_address(field(contract, "address", label), f"{label}.address")
    tx_hash = require_hash(
        field(contract, "transaction_hash", label), f"{label}.transaction_hash"
    )
    recorded_block = recorded_integer(
        field(contract, "block_number", label), f"{label}.block_number",
        minimum=1,
    )
    recorded_block_hash = require_hash(
        field(contract, "block_hash", label), f"{label}.block_hash"
    )
    recorded_nonce = recorded_integer(
        field(contract, "nonce", label), f"{label}.nonce"
    )
    if recorded_nonce != expected_nonce:
        fail(f"{label} recorded nonce {recorded_nonce}, expected {expected_nonce}")
    recorded_gas_estimate = recorded_integer(
        field(contract, "gas_estimate", label),
        f"{label}.gas_estimate",
        minimum=1,
    )
    recorded_gas_limit = recorded_integer(
        field(contract, "gas_limit", label), f"{label}.gas_limit", minimum=1
    )
    if recorded_gas_limit < recorded_gas_estimate:
        fail(f"{label}.gas_limit is below its pre-broadcast estimate")
    recorded_gas_used = recorded_integer(
        field(contract, "gas_used", label), f"{label}.gas_used", minimum=1
    )
    recorded_effective_price = recorded_integer(
        field(contract, "effective_gas_price_wei", label),
        f"{label}.effective_gas_price_wei",
        minimum=1,
    )

    receipt = parse_object(
        f"{label} receipt", run_cast(toolchain, "receipt", "--json", tx_hash)
    )
    transaction = parse_object(
        f"{label} transaction", run_cast(toolchain, "tx", "--json", tx_hash)
    )
    if live_integer(
        field(receipt, "status", f"{label} receipt"), f"{label}.receipt.status"
    ) != 1:
        fail(f"{label} deployment transaction did not succeed")
    if require_hash(
        field(receipt, "transactionHash", f"{label} receipt"),
        f"{label}.receipt.transactionHash",
    ) != tx_hash:
        fail(f"{label} receipt transaction hash mismatch")
    if require_address(
        field(receipt, "from", f"{label} receipt"), f"{label}.receipt.from"
    ) != deployer:
        fail(f"{label} receipt sender mismatch")
    if require_address(
        field(receipt, "contractAddress", f"{label} receipt"),
        f"{label}.receipt.contractAddress",
    ) != address:
        fail(f"{label} receipt contract address mismatch")

    live_block = live_integer(
        field(receipt, "blockNumber", f"{label} receipt"),
        f"{label}.receipt.blockNumber",
        minimum=1,
    )
    live_block_hash = require_hash(
        field(receipt, "blockHash", f"{label} receipt"),
        f"{label}.receipt.blockHash",
    )
    if live_block != recorded_block or live_block_hash != recorded_block_hash:
        fail(f"{label} receipt moved to a different block")
    block = parse_object(
        f"{label} canonical block",
        run_cast(toolchain, "block", "--json", str(live_block)),
    )
    if require_hash(
        field(block, "hash", f"{label} canonical block"),
        f"{label}.canonical_block.hash",
    ) != live_block_hash:
        fail(f"{label} receipt block is not canonical at its recorded height")

    if require_hash(
        field(transaction, "hash", f"{label} transaction"), f"{label}.tx.hash"
    ) != tx_hash:
        fail(f"{label} transaction hash mismatch")
    if require_address(
        field(transaction, "from", f"{label} transaction"), f"{label}.tx.from"
    ) != deployer:
        fail(f"{label} transaction sender mismatch")
    if live_integer(
        field(transaction, "nonce", f"{label} transaction"), f"{label}.tx.nonce"
    ) != expected_nonce:
        fail(f"{label} transaction nonce mismatch")
    if live_integer(
        field(transaction, "chainId", f"{label} transaction"),
        f"{label}.tx.chainId",
    ) != chain_id:
        fail(f"{label} transaction chain ID mismatch")
    live_gas_limit = live_integer(
        field(transaction, "gas", f"{label} transaction"),
        f"{label}.tx.gas",
        minimum=1,
    )
    if live_gas_limit != recorded_gas_limit:
        fail(f"{label} live transaction gas limit differs from the receipt")
    live_gas_used = live_integer(
        field(receipt, "gasUsed", f"{label} receipt"),
        f"{label}.receipt.gasUsed",
        minimum=1,
    )
    if live_gas_used != recorded_gas_used:
        fail(f"{label} live gas used differs from the receipt")
    if live_gas_used > live_gas_limit:
        fail(f"{label} gas used exceeds its transaction gas limit")
    live_effective_price = live_integer(
        field(receipt, "effectiveGasPrice", f"{label} receipt"),
        f"{label}.receipt.effectiveGasPrice",
        minimum=1,
    )
    if live_effective_price != recorded_effective_price:
        fail(f"{label} live effective gas price differs from the receipt")
    if transaction.get("to") not in (None, "", "0x"):
        fail(f"{label} transaction was not contract creation")
    expected_address_output = run_cast(
        toolchain,
        "compute-address",
        "--nonce",
        str(expected_nonce),
        deployer,
    )
    computed_addresses = re.findall(r"0x[0-9a-fA-F]{40}", expected_address_output)
    if len(computed_addresses) != 1 or computed_addresses[0].lower() != address:
        fail(f"{label} address does not match CREATE(deployer, nonce)")
    live_creation_input = require_hex_bytes(
        field(transaction, "input", f"{label} transaction"),
        f"{label}.tx.input",
    )
    if live_creation_input != expected_creation_input:
        fail(f"{label} transaction input differs from rebuilt creation input")
    expected_creation_input_hash = keccak(
        toolchain, expected_creation_input, f"{label} expected creation input"
    )
    if require_hash(
        field(contract, "creation_transaction_input_hash", label),
        f"{label}.creation_transaction_input_hash",
    ) != expected_creation_input_hash:
        fail(f"{label} recorded creation transaction input hash mismatch")

    expected_runtime_hash = keccak(
        toolchain, expected_runtime, f"{label} expected runtime"
    )
    if require_hash(
        field(contract, "expected_runtime_hash", label),
        f"{label}.expected_runtime_hash",
    ) != expected_runtime_hash:
        fail(f"{label} recorded expected runtime hash mismatch")
    if require_hash(
        field(contract, "deployed_runtime_hash", label),
        f"{label}.deployed_runtime_hash",
    ) != expected_runtime_hash:
        fail(f"{label} recorded deployed runtime hash mismatch")
    code = require_hex_bytes(
        run_cast(toolchain, "code", address).lower(), f"{label} live runtime"
    )
    if code != expected_runtime:
        fail(f"{label} live runtime differs from rebuilt bytecode")
    if keccak(toolchain, code, f"{label} live runtime") != expected_runtime_hash:
        fail(f"{label} live runtime hash mismatch")

    actual_cost = live_gas_used * live_effective_price
    if max_fee_per_gas_wei is not None:
        transaction_price = transaction.get("maxFeePerGas")
        transaction_price_label = "maxFeePerGas"
        if transaction_price is None:
            transaction_price = field(
                transaction, "gasPrice", f"{label} transaction"
            )
            transaction_price_label = "gasPrice"
        transaction_cap = live_integer(
            transaction_price,
            f"{label}.tx.{transaction_price_label}",
            minimum=1,
        )
        if transaction_cap > max_fee_per_gas_wei:
            fail(f"{label} transaction fee cap exceeds recorded mainnet maximum")
        if live_effective_price > transaction_cap:
            fail(f"{label} effective gas price exceeds its transaction fee cap")
        if live_effective_price > max_fee_per_gas_wei:
            fail(f"{label} effective gas price exceeds recorded mainnet maximum")
    return live_block, live_block_hash, actual_cost


def verify_recorded_artifacts(
    *,
    contracts: dict[str, Any],
    artifacts: LocalArtifacts,
    core_address: str,
    expected_settlement_runtime: str,
    expected_settlement_input: str,
    toolchain: Toolchain,
) -> None:
    core = object_field(contracts, "core", "contracts")
    settlement = object_field(contracts, "settlement", "contracts")
    checks = (
        (
            field(core, "creation_bytecode_hash", "core"),
            keccak(toolchain, artifacts.core_creation, "rebuilt Core creation bytecode"),
            "core.creation_bytecode_hash",
        ),
        (
            field(core, "creation_transaction_input_hash", "core"),
            keccak(toolchain, artifacts.core_creation, "rebuilt Core creation input"),
            "core.creation_transaction_input_hash",
        ),
        (
            field(core, "expected_runtime_hash", "core"),
            keccak(toolchain, artifacts.core_runtime, "rebuilt Core runtime"),
            "core.expected_runtime_hash",
        ),
        (
            field(settlement, "creation_bytecode_hash", "settlement"),
            keccak(
                toolchain,
                artifacts.settlement_creation,
                "rebuilt Settlement creation bytecode",
            ),
            "settlement.creation_bytecode_hash",
        ),
        (
            field(settlement, "creation_transaction_input_hash", "settlement"),
            keccak(
                toolchain,
                expected_settlement_input,
                "rebuilt Settlement creation input",
            ),
            "settlement.creation_transaction_input_hash",
        ),
        (
            field(settlement, "local_runtime_template_hash", "settlement"),
            keccak(
                toolchain,
                artifacts.settlement_runtime_template,
                "rebuilt Settlement runtime template",
            ),
            "settlement.local_runtime_template_hash",
        ),
        (
            field(settlement, "expected_runtime_hash", "settlement"),
            keccak(
                toolchain,
                expected_settlement_runtime,
                "rebuilt immutable-linked Settlement runtime",
            ),
            "settlement.expected_runtime_hash",
        ),
    )
    for recorded, expected, label in checks:
        if require_hash(recorded, label) != expected:
            fail(f"{label} differs from the isolated local rebuild")
    binding = require_address(
        field(settlement, "core_binding", "settlement"),
        "settlement.core_binding",
    )
    if binding != core_address:
        fail("recorded Settlement Core binding mismatch")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("receipt", type=Path)
    parser.add_argument(
        "--project-root",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
        help="PulseTensor checkout used for the isolated rebuild (default: script parent)",
    )
    parser.add_argument(
        "--min-confirmations",
        type=int,
        default=None,
        help="Require at least this many confirmations in addition to receipt policy",
    )
    parser.add_argument(
        "--require-current-nonce",
        action="store_true",
        help="Require both latest and pending deployer nonces to equal the post-deployment nonce",
    )
    parser.add_argument(
        "--require-clean-source",
        action="store_true",
        help="Require both deployment-time and current source-clean attestations",
    )
    parser.add_argument(
        "--release-checkpoint",
        type=Path,
        default=None,
        help="Chain-943 v4 receipt required when verifying a chain-369 receipt",
    )
    args = parser.parse_args()

    if not os.environ.get("ETH_RPC_URL"):
        fail("ETH_RPC_URL is required")
    if "\n" in os.environ["ETH_RPC_URL"] or "\r" in os.environ["ETH_RPC_URL"]:
        fail("ETH_RPC_URL must not contain line breaks")
    if args.min_confirmations is not None and args.min_confirmations < 1:
        fail("--min-confirmations must be at least 1")

    project_root = args.project_root.resolve()
    receipt = load_object(args.receipt.resolve(), "receipt")
    if receipt.get("schema") != SCHEMA:
        fail(f"unsupported deployment receipt schema; expected {SCHEMA}")

    chain_id = recorded_integer(
        field(receipt, "chain_id", "receipt"), "chain_id", minimum=1
    )
    recorded_checkpoint = validate_v4_structure(receipt, chain_id)
    if chain_id != MAINNET_CHAIN_ID and args.release_checkpoint is not None:
        fail("--release-checkpoint is valid only for chain-369 verification")
    require_clean_source = args.require_clean_source or chain_id == MAINNET_CHAIN_ID

    provenance = object_field(receipt, "provenance", "receipt")
    source_commit, source_clean_now, source_status = verify_source(
        provenance, project_root, require_clean_source
    )
    toolchain = inspect_toolchain(project_root)
    artifacts = rebuild_artifacts(project_root, toolchain)
    if require_clean_source:
        verify_commit_snapshot_artifacts(
            project_root=project_root,
            source_commit=source_commit,
            toolchain=toolchain,
            live_artifacts=artifacts,
        )
    # Recheck source after compilation to close the local build TOCTOU window.
    source_commit_after, source_clean_after, source_status_after = verify_source(
        provenance, project_root, require_clean_source
    )
    if (
        source_commit_after != source_commit
        or source_clean_after != source_clean_now
        or source_status_after != source_status
    ):
        fail("source state changed during isolated artifact rebuild")
    verify_toolchain_unchanged(project_root, toolchain)
    verify_recorded_toolchain(provenance, toolchain, artifacts)

    live_chain_id = live_integer(run_cast(toolchain, "chain-id"), "live chain ID", minimum=1)
    if live_chain_id != chain_id:
        fail(f"chain ID mismatch: receipt={chain_id} live={live_chain_id}")
    verify_live_network_anchor(receipt, chain_id, toolchain)
    if chain_id == MAINNET_CHAIN_ID:
        verify_release_checkpoint_live(
            checkpoint_path=args.release_checkpoint,
            recorded_checkpoint=recorded_checkpoint,
            project_root=project_root,
            expected_source_commit=source_commit,
            expected_mainnet_run_id=receipt["run_id"],
        )
    gas_budget = verify_gas_budget(receipt, chain_id)

    deployer = require_address(field(receipt, "deployer", "receipt"), "deployer")
    nonce_before = recorded_integer(
        field(receipt, "deployer_nonce_before", "receipt"), "deployer_nonce_before"
    )
    nonce_after = recorded_integer(
        field(receipt, "deployer_nonce_after", "receipt"), "deployer_nonce_after"
    )
    if nonce_after != nonce_before + 2:
        fail("deployment nonce sequence is not exactly two transactions")

    contracts = object_field(receipt, "contracts", "receipt")
    core = object_field(contracts, "core", "contracts")
    settlement = object_field(contracts, "settlement", "contracts")
    verify_nonce_policy(
        receipt,
        nonce_before=nonce_before,
        nonce_after=nonce_after,
        core=core,
        settlement=settlement,
    )
    verify_contract_budget_alignment(core, settlement, gas_budget)
    core_address = require_address(field(core, "address", "core"), "core.address")
    settlement_address = require_address(
        field(settlement, "address", "settlement"), "settlement.address"
    )
    expected_settlement_runtime = patch_settlement_runtime(artifacts, core_address)
    expected_settlement_input = (
        artifacts.settlement_creation + core_address[2:].rjust(64, "0")
    )
    verify_recorded_artifacts(
        contracts=contracts,
        artifacts=artifacts,
        core_address=core_address,
        expected_settlement_runtime=expected_settlement_runtime,
        expected_settlement_input=expected_settlement_input,
        toolchain=toolchain,
    )

    core_block, _, core_actual_gas_cost = verify_contract(
        label="core",
        contract=core,
        deployer=deployer,
        expected_nonce=nonce_before,
        chain_id=chain_id,
        expected_creation_input=artifacts.core_creation,
        expected_runtime=artifacts.core_runtime,
        toolchain=toolchain,
        max_fee_per_gas_wei=(
            gas_budget.max_fee_per_gas_wei if gas_budget is not None else None
        ),
    )
    settlement_block, _, settlement_actual_gas_cost = verify_contract(
        label="settlement",
        contract=settlement,
        deployer=deployer,
        expected_nonce=nonce_before + 1,
        chain_id=chain_id,
        expected_creation_input=expected_settlement_input,
        expected_runtime=expected_settlement_runtime,
        toolchain=toolchain,
        max_fee_per_gas_wei=(
            gas_budget.max_fee_per_gas_wei if gas_budget is not None else None
        ),
    )
    actual_total_gas_cost = core_actual_gas_cost + settlement_actual_gas_cost
    if (
        gas_budget is not None
        and actual_total_gas_cost > gas_budget.maximum_total_cost_wei
    ):
        fail("combined live deployment gas cost exceeds the recorded maximum budget")

    recorded_core_binding = require_address(
        field(settlement, "core_binding", "settlement"), "settlement.core_binding"
    )
    if recorded_core_binding != core_address:
        fail("recorded Settlement Core binding mismatch")
    configured_core = require_address(
        run_cast(toolchain, "call", settlement_address, "CORE()(address)"),
        "settlement.CORE",
    )
    if configured_core != core_address:
        fail("Settlement immutable CORE binding mismatch")

    (
        receipt_required,
        recorded_confirmed_at,
        _,
        recorded_last_deployment_block,
    ) = validate_recorded_confirmations(receipt, chain_id)
    last_deployment_block = max(core_block, settlement_block)
    if last_deployment_block != recorded_last_deployment_block:
        fail("live deployment block heights differ from the recorded confirmation policy")

    chain_minimum = (
        MIN_RELEASE_CONFIRMATIONS if chain_id == MAINNET_CHAIN_ID else 1
    )
    required = max(receipt_required, args.min_confirmations or 1, chain_minimum)
    head = live_integer(run_cast(toolchain, "block-number"), "head block", minimum=1)
    anchor = expected_network_anchor(chain_id)
    if anchor is not None and head < anchor["block_number"]:
        fail("chain head predates the pinned PulseChain network anchor")
    if head < last_deployment_block:
        fail("chain head predates deployment blocks")
    observed = head - last_deployment_block + 1
    if observed < required:
        fail(f"only {observed} confirmations observed; {required} required")
    if recorded_confirmed_at > head:
        fail("recorded confirmation checkpoint is ahead of the current chain head")

    latest_nonce = live_integer(
        run_cast(toolchain, "nonce", "-B", "latest", deployer),
        "latest deployer nonce",
    )
    pending_nonce = live_integer(
        run_cast(toolchain, "nonce", "-B", "pending", deployer),
        "pending deployer nonce",
    )
    if latest_nonce < nonce_after or pending_nonce < nonce_after:
        fail("current deployer nonce predates the deployment receipt")
    if pending_nonce < latest_nonce:
        fail("pending deployer nonce is behind latest nonce")
    if args.require_current_nonce and (
        latest_nonce != nonce_after or pending_nonce != nonce_after
    ):
        fail(
            "deployer nonce changed during verification: "
            f"expected {nonce_after}, latest={latest_nonce}, pending={pending_nonce}"
        )

    final_commit, final_clean, final_status = verify_source(
        provenance, project_root, require_clean_source
    )
    if (
        final_commit != source_commit
        or final_clean != source_clean_now
        or final_status != source_status
    ):
        fail("source state changed during live receipt verification")
    verify_toolchain_unchanged(project_root, toolchain)
    final_live_chain_id = live_integer(
        run_cast(toolchain, "chain-id"), "final live chain ID", minimum=1
    )
    if final_live_chain_id != chain_id:
        fail("RPC chain ID changed during receipt verification")
    verify_live_network_anchor(receipt, chain_id, toolchain)

    result = {
        "chain_id": chain_id,
        "confirmations_observed": observed,
        "core_address": core_address,
        "deployer_nonce_latest": latest_nonce,
        "deployer_nonce_pending": pending_nonce,
        "local_artifacts_rebuilt": True,
        "deployment_gas_cost_wei": actual_total_gas_cost,
        "settlement_address": settlement_address,
        "source_clean_now": source_clean_after,
        "source_commit": source_commit_after,
        "toolchain_lock_sha256": toolchain.lock_sha256,
        "verified": True,
    }
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except VerificationError as exc:
        print(
            f"deployment receipt verification failed: {redact(str(exc))}",
            file=sys.stderr,
        )
        raise SystemExit(1)

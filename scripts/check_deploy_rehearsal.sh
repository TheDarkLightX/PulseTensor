#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${DEPLOY_REHEARSAL_PORT:-18547}"
RPC_ENDPOINT="http://127.0.0.1:${PORT}"
CHAIN_ID=31338
MNEMONIC='test test test test test test test test test test test junk'
PASSWORD='pulsetensor-public-test-password'
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pulsetensor-deploy-rehearsal.XXXXXX")"
EVIDENCE_DIR="${ROOT_DIR}/runs/deploy_rehearsal"
EVIDENCE_REPORT="${EVIDENCE_DIR}/rehearsal_report.json"
OUT_DIR="${WORK_DIR}/receipts"
KEYSTORE_DIR="${WORK_DIR}/keystore"
PASSWORD_FILE="${WORK_DIR}/keystore.password"
ANVIL_LOG="${WORK_DIR}/anvil.log"
DEPLOY_LOG="${WORK_DIR}/deploy.log"
ANVIL_PID=""

fail() {
  echo "[deploy-rehearsal] ERROR: $*" >&2
  exit 1
}

cleanup() {
  local status=$?
  if [[ -n "${ANVIL_PID}" ]] && kill -0 "${ANVIL_PID}" 2>/dev/null; then
    kill "${ANVIL_PID}" 2>/dev/null || true
    wait "${ANVIL_PID}" 2>/dev/null || true
  fi
  if [[ "${status}" != "0" ]]; then
    [[ ! -f "${DEPLOY_LOG}" ]] || { echo "[deploy-rehearsal] deploy log:" >&2; sed -n '1,240p' "${DEPLOY_LOG}" >&2; }
    [[ ! -f "${ANVIL_LOG}" ]] || { echo "[deploy-rehearsal] anvil log:" >&2; sed -n '1,120p' "${ANVIL_LOG}" >&2; }
    echo "[deploy-rehearsal] retained failure workspace: ${WORK_DIR}" >&2
  elif [[ "${KEEP_DEPLOY_REHEARSAL:-0}" != "1" ]]; then
    rm -rf -- "${WORK_DIR}"
  else
    echo "[deploy-rehearsal] retained workspace: ${WORK_DIR}"
  fi
}
trap cleanup EXIT

for command_name in anvil cast forge python3 rg; do
  command -v "${command_name}" >/dev/null 2>&1 || fail "required command not found: ${command_name}"
done
[[ "${PORT}" =~ ^[0-9]+$ ]] || fail "DEPLOY_REHEARSAL_PORT must be an integer"

if ETH_RPC_URL="${RPC_ENDPOINT}" cast block-number >/dev/null 2>&1; then
  fail "port ${PORT} already serves an RPC endpoint"
fi

mkdir -p "${OUT_DIR}" "${KEYSTORE_DIR}"
printf '%s\n' "${PASSWORD}" > "${PASSWORD_FILE}"
chmod 600 "${PASSWORD_FILE}"

anvil \
  --host 127.0.0.1 \
  --port "${PORT}" \
  --chain-id "${CHAIN_ID}" \
  --mnemonic "${MNEMONIC}" >"${ANVIL_LOG}" 2>&1 &
ANVIL_PID=$!
for _ in $(seq 1 100); do
  if ETH_RPC_URL="${RPC_ENDPOINT}" cast block-number >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
ETH_RPC_URL="${RPC_ENDPOINT}" cast block-number >/dev/null 2>&1 || fail "anvil did not start"

OWNER_PK="$(cast wallet private-key --mnemonic "${MNEMONIC}" --mnemonic-index 0)"
OWNER_ADDRESS="$(cast wallet address --private-key "${OWNER_PK}")"
# These are published Anvil fixture credentials. This import step creates the
# encrypted keystore that the production deployment wrapper must consume.
CAST_UNSAFE_PASSWORD="${PASSWORD}" cast wallet import pulsetensor-rehearsal \
  --keystore-dir "${KEYSTORE_DIR}" \
  --private-key "${OWNER_PK}" >/dev/null
KEYSTORE_PATH="$(find "${KEYSTORE_DIR}" -maxdepth 1 -type f -print -quit)"
[[ -n "${KEYSTORE_PATH}" ]] || fail "encrypted keystore fixture was not created"
chmod 600 "${KEYSTORE_PATH}"

(
  cd "${ROOT_DIR}"
  RPC_URL="${RPC_ENDPOINT}" \
  DEPLOY_CONFIRMATIONS=1 \
  DEPLOY_CONFIRMATION_POLL_SECONDS=0.1 \
  FOUNDRY_OPTIMIZER_RUNS=1 \
    bash scripts/deploy_pulsetensor.sh \
      --expected-chain-id "${CHAIN_ID}" \
      --sender "${OWNER_ADDRESS}" \
      --keystore "${KEYSTORE_PATH}" \
      --password-file "${PASSWORD_FILE}" \
      --out-dir "${OUT_DIR}" >"${DEPLOY_LOG}" 2>&1
)

RECEIPT_PATH="$(awk -F': ' '/^  receipt:/ {print $2}' "${DEPLOY_LOG}" | tail -n 1)"
JOURNAL_PATH="$(awk -F': ' '/^  partial_journal:/ {print $2}' "${DEPLOY_LOG}" | tail -n 1)"
[[ -f "${RECEIPT_PATH}" ]] || fail "deployment did not publish a receipt"
[[ -f "${JOURNAL_PATH}" ]] || fail "deployment did not retain its partial journal"
[[ "$(stat -c '%a' "${RECEIPT_PATH}")" == "600" ]] || fail "deployment receipt is not owner-only"
receipt_count="$(find "${OUT_DIR}" -maxdepth 1 -name '*.receipt.json' -type f | awk 'END {print NR}')"
[[ "${receipt_count}" == "1" ]] || fail "unexpected deployment receipt count"

ETH_RPC_URL="${RPC_ENDPOINT}" python3 "${ROOT_DIR}/scripts/verify_deployment_receipt.py" \
  "${RECEIPT_PATH}" --min-confirmations 1 --require-current-nonce >/dev/null

TAMPERED_RECEIPT="${WORK_DIR}/tampered.receipt.json"
python3 - "${RECEIPT_PATH}" "${TAMPERED_RECEIPT}" <<'PY'
import json
import sys

receipt = json.load(open(sys.argv[1], encoding="utf-8"))
receipt["contracts"]["settlement"]["expected_runtime_hash"] = "0x" + "00" * 32
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(receipt, handle)
PY
set +e
ETH_RPC_URL="${RPC_ENDPOINT}" python3 "${ROOT_DIR}/scripts/verify_deployment_receipt.py" \
  "${TAMPERED_RECEIPT}" --min-confirmations 1 --require-current-nonce >/dev/null 2>&1
tampered_status=$?
set -e
[[ "${tampered_status}" != "0" ]] || fail "receipt verifier accepted a tampered runtime hash"

python3 - "${RECEIPT_PATH}" "${RPC_ENDPOINT}" "${KEYSTORE_PATH}" "${PASSWORD_FILE}" "${PASSWORD}" "${OWNER_PK}" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
receipt = json.loads(path.read_text(encoding="utf-8"))
if receipt.get("schema") != "pulsetensor/deployment-receipt/v4":
    raise SystemExit("unexpected deployment receipt schema")
if "signer_mode" in receipt:
    raise SystemExit("public receipt must not disclose signer mode")
if receipt.get("network_anchor") is not None:
    raise SystemExit("local rehearsal must not claim a PulseChain network anchor")
if receipt.get("verification", {}).get("exact_runtime_bytecode_checked") is not True:
    raise SystemExit("exact runtime verification is missing")
nonce_policy = receipt.get("nonce_policy", {})
if nonce_policy.get("explicit_nonces_used") is not True:
    raise SystemExit("explicit nonce evidence is missing")
if nonce_policy.get("latest_before") != nonce_policy.get("pending_before"):
    raise SystemExit("predeployment latest/pending nonces differ")
if nonce_policy.get("latest_after") != nonce_policy.get("pending_after"):
    raise SystemExit("postdeployment latest/pending nonces differ")
toolchain = receipt.get("provenance", {}).get("toolchain", {})
for key in ("toolchain_lock_sha256", "foundry_toml_sha256", "forge_sha256", "cast_sha256", "solc_sha256"):
    value = toolchain.get(key)
    if not isinstance(value, str) or len(value) != 64:
        raise SystemExit(f"exact toolchain evidence is missing: {key}")
for contract in receipt.get("contracts", {}).values():
    for key in ("gas_estimate", "gas_limit", "gas_used", "effective_gas_price_wei"):
        if type(contract.get(key)) is not int or contract[key] <= 0:
            raise SystemExit(f"strict gas evidence is missing: {key}")
serialized = path.read_text(encoding="utf-8")
for forbidden in sys.argv[2:]:
    if forbidden and forbidden in serialized:
        raise SystemExit("receipt contains a forbidden endpoint, path, password, or key")
PY

for event in preflight_complete deployment_intent core_broadcast_intent core_broadcast core_verified settlement_broadcast_intent settlement_broadcast settlement_verified receipt_published; do
  rg -q --fixed-strings -- "\"event\":\"${event}\"" "${JOURNAL_PATH}" || fail "partial journal is missing ${event}"
done

python3 - "${JOURNAL_PATH}" <<'PY'
import json
import sys

events = [json.loads(line)["event"] for line in open(sys.argv[1], encoding="utf-8") if line.strip()]
required = [
    "preflight_complete",
    "deployment_intent",
    "core_broadcast_intent",
    "core_broadcast",
    "core_verified",
    "settlement_broadcast_intent",
    "settlement_broadcast",
    "settlement_verified",
    "receipt_published",
]
positions = [events.index(event) for event in required]
if positions != sorted(positions) or len(set(positions)) != len(positions):
    raise SystemExit("deployment journal events are not in fail-safe order")
PY

python3 - "${ROOT_DIR}/scripts/verify_deployment_receipt.py" <<'PY'
import copy
import hashlib
import importlib.util
import pathlib
import sys
import tempfile

path = pathlib.Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("receipt_verifier", path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)
for invalid in ("943", True, 943.0):
    try:
        module.recorded_integer(invalid, "fault")
    except module.VerificationError:
        continue
    raise SystemExit(f"strict integer checker accepted {invalid!r}")


def expect_rejected(action, label, expected_text=None):
    try:
        action()
    except module.VerificationError as exc:
        if expected_text is not None and expected_text not in str(exc):
            raise SystemExit(
                f"{label} reached the wrong rejection: {exc}"
            ) from exc
        return
    raise SystemExit(f"receipt verifier accepted {label}")


common_contract = {
    "address": "0x" + "11" * 20,
    "transaction_hash": "0x" + "22" * 32,
    "nonce": 0,
    "gas_estimate": 100_000,
    "gas_limit": 120_000,
    "gas_used": 90_000,
    "effective_gas_price_wei": 1,
    "block_number": 100,
    "block_hash": "0x" + "33" * 32,
    "creation_bytecode_hash": "0x" + "44" * 32,
    "creation_transaction_input_hash": "0x" + "55" * 32,
    "expected_runtime_hash": "0x" + "66" * 32,
    "deployed_runtime_hash": "0x" + "66" * 32,
}
run_id = "31338-20260714T120000Z-deadbeef"
receipt = {
    "schema": module.SCHEMA,
    "generated_at_utc": "2026-07-14T12:00:01Z",
    "run_id": run_id,
    "chain_id": 31338,
    "deployer": "0x" + "77" * 20,
    "deployer_nonce_before": 0,
    "deployer_nonce_after": 2,
    "nonce_policy": {},
    "contracts": {
        "core": copy.deepcopy(common_contract),
        "settlement": {
            **copy.deepcopy(common_contract),
            "address": "0x" + "88" * 20,
            "transaction_hash": "0x" + "99" * 32,
            "nonce": 1,
            "block_number": 101,
            "local_runtime_template_hash": "0x" + "aa" * 32,
            "core_binding": "0x" + "11" * 20,
        },
    },
    "confirmations": {
        "required": 1,
        "confirmed_at_block": 101,
        "observed_at_publication": 1,
    },
    "provenance": {
        "source_commit": "b" * 40,
        "source_clean": False,
        "profile_id": module.PROFILE_ID,
        "foundry_profile": module.PROFILE_NAME,
        "optimizer_runs": module.OPTIMIZER_RUNS,
        "compiler_version": "0.8.36+commit.4a455461",
        "forge_version": "forge Version: test",
        "toolchain": {},
        "artifacts": {},
        "release_checkpoint": {
            "sha256": None,
            "chain_id": None,
            "run_id": None,
            "network_anchor": None,
            "live_reverified": False,
        },
    },
    "verification": {
        "passed": True,
        "chain_id_rechecked": True,
        "transaction_receipts_rechecked": True,
        "sender_and_nonce_sequence_checked": True,
        "exact_runtime_bytecode_checked": True,
        "immutable_core_binding_checked": True,
    },
    "partial_journal": f"pulsetensor_deploy_{run_id}.ABC123.journal.jsonl",
    "network_anchor": None,
}
module.validate_v4_structure(receipt, receipt["chain_id"])

expect_rejected(
    lambda: module.strict_json_loads('{"chain_id":369,"chain_id":943}', "fault"),
    "duplicate JSON keys",
    "duplicate JSON key",
)
expect_rejected(
    lambda: module.strict_json_loads('{"chain_id":NaN}', "fault"),
    "a non-finite JSON number",
    "forbidden non-finite number",
)
for location, field_name, field_value in (
    ((), "signer_mode", "keystore"),
    (("provenance",), "source_branch", "private-launch-branch"),
    (("contracts", "core"), "unverified_claim", True),
    (("verification",), "future_unverified_flag", True),
):
    altered = copy.deepcopy(receipt)
    target = altered
    for part in location:
        target = target[part]
    target[field_name] = field_value
    expect_rejected(
        lambda altered=altered: module.validate_v4_structure(altered, 31338),
        f"unknown field {'.'.join((*location, field_name))}",
        "keys are not exact",
    )

altered = copy.deepcopy(receipt)
altered["network_anchor"] = {
    "block_number": module.TESTNET_ANCHOR_BLOCK,
    "block_hash": module.TESTNET_ANCHOR_HASH,
}
expect_rejected(
    lambda: module.validate_v4_structure(altered, 31338),
    "a PulseChain anchor on an unanchored development receipt",
    "must be null",
)

mainnet = copy.deepcopy(receipt)
mainnet_run_id = "369-20260714T120000Z-cafebabe"
mainnet.update(
    {
        "chain_id": module.MAINNET_CHAIN_ID,
        "run_id": mainnet_run_id,
        "partial_journal": (
            f"pulsetensor_deploy_{mainnet_run_id}.ABC123.journal.jsonl"
        ),
        "network_anchor": {
            "block_number": module.MAINNET_ANCHOR_BLOCK,
            "block_hash": module.MAINNET_ANCHOR_HASH,
        },
        "gas_budget": {},
    }
)
mainnet["provenance"]["source_clean"] = True
mainnet["contracts"]["core"]["block_number"] = module.MAINNET_ANCHOR_BLOCK + 1
mainnet["contracts"]["settlement"]["block_number"] = (
    module.MAINNET_ANCHOR_BLOCK + 2
)
mainnet["provenance"]["release_checkpoint"] = {
    "sha256": "cc" * 32,
    "chain_id": module.TESTNET_CHAIN_ID,
    "run_id": "943-20260713T120000Z-acde1234",
    "network_anchor": {
        "block_number": module.TESTNET_ANCHOR_BLOCK,
        "block_hash": module.TESTNET_ANCHOR_HASH,
    },
    "live_reverified": True,
}
mainnet["confirmations"] = {
    "required": module.MIN_RELEASE_CONFIRMATIONS,
    "confirmed_at_block": module.MAINNET_ANCHOR_BLOCK + 13,
    "observed_at_publication": module.MIN_RELEASE_CONFIRMATIONS,
}
module.validate_v4_structure(mainnet, module.MAINNET_CHAIN_ID)

for label, mutate, expected_text in (
    (
        "a dirty mainnet source attestation",
        lambda value: value["provenance"].update(source_clean=False),
        "clean deployment source tree",
    ),
    (
        "fewer than 12 mainnet confirmations",
        lambda value: value["confirmations"].update(
            required=11,
            confirmed_at_block=module.MAINNET_ANCHOR_BLOCK + 12,
            observed_at_publication=11,
        ),
        "at least 12",
    ),
    (
        "a mismatched mainnet anchor",
        lambda value: value["network_anchor"].update(block_hash="0x" + "00" * 32),
        "pinned PulseChain network anchor",
    ),
    (
        "a mismatched checkpoint anchor",
        lambda value: value["provenance"]["release_checkpoint"][
            "network_anchor"
        ].update(block_hash="0x" + "00" * 32),
        "pinned PulseChain network anchor",
    ),
    (
        "an unverified checkpoint claim",
        lambda value: value["provenance"]["release_checkpoint"].update(
            live_reverified=False
        ),
        "must be marked live-reverified",
    ),
):
    altered = copy.deepcopy(mainnet)
    mutate(altered)
    expect_rejected(
        lambda altered=altered: module.validate_v4_structure(
            altered, module.MAINNET_CHAIN_ID
        ),
        label,
        expected_text,
    )

expect_rejected(
    lambda: module.verify_release_checkpoint_live(
        checkpoint_path=None,
        recorded_checkpoint=mainnet["provenance"]["release_checkpoint"],
        project_root=path.parent,
        expected_source_commit=mainnet["provenance"]["source_commit"],
        expected_mainnet_run_id=mainnet["run_id"],
    ),
    "a missing mainnet checkpoint file",
    "requires --release-checkpoint",
)
with tempfile.TemporaryDirectory(prefix="pulsetensor-checkpoint-negative-") as raw:
    checkpoint_path = pathlib.Path(raw) / "checkpoint.json"
    checkpoint_path.write_text("{}\n", encoding="utf-8")
    expected_digest = hashlib.sha256(b"different checkpoint\n").hexdigest()
    recorded_checkpoint = copy.deepcopy(
        mainnet["provenance"]["release_checkpoint"]
    )
    recorded_checkpoint["sha256"] = expected_digest
    expect_rejected(
        lambda: module.verify_release_checkpoint_live(
            checkpoint_path=checkpoint_path,
            recorded_checkpoint=recorded_checkpoint,
            project_root=path.parent,
            expected_source_commit=mainnet["provenance"]["source_commit"],
            expected_mainnet_run_id=mainnet["run_id"],
        ),
        "modified checkpoint bytes",
        "digest differs",
    )
PY

mkdir -p "${EVIDENCE_DIR}"
python3 - "${RECEIPT_PATH}" "${EVIDENCE_REPORT}.tmp" <<'PY'
import datetime
import hashlib
import json
import os
import pathlib
import sys

receipt_path = pathlib.Path(sys.argv[1])
out_path = pathlib.Path(sys.argv[2])
raw = receipt_path.read_bytes()
receipt = json.loads(raw)
contracts = receipt["contracts"]
report = {
    "schema": "pulsetensor/deploy-rehearsal-report/v1",
    "generated_at_utc": datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "chain_id": receipt["chain_id"],
    "signer_mode_exercised": "keystore",
    "receipt_schema": receipt["schema"],
    "receipt_sha256": hashlib.sha256(raw).hexdigest(),
    "contracts": {
        "core": {"address": contracts["core"]["address"], "transaction_hash": contracts["core"]["transaction_hash"]},
        "settlement": {"address": contracts["settlement"]["address"], "transaction_hash": contracts["settlement"]["transaction_hash"]},
    },
    "checks": {
        "encrypted_keystore": True,
        "exact_runtime": True,
        "creation_input": True,
        "exact_initcode_submission": True,
        "chain_and_sender": True,
        "consecutive_nonces": True,
        "explicit_pending_safe_nonces": True,
        "prebroadcast_recovery_intents": True,
        "exact_toolchain": True,
        "strict_gas_accounting": True,
        "confirmation_recheck": True,
        "partial_journal": True,
        "tampered_runtime_rejected": True,
        "strict_receipt_schema": True,
        "duplicate_json_rejected": True,
        "unknown_receipt_fields_rejected": True,
        "mainnet_policy_negatives": True,
        "checkpoint_digest_tamper_rejected": True,
        "privacy_metadata_excluded": True,
    },
}
out_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
os.chmod(out_path, 0o600)
PY
mv -f -- "${EVIDENCE_REPORT}.tmp" "${EVIDENCE_REPORT}"

echo "Encrypted-keystore deployment rehearsal passed"

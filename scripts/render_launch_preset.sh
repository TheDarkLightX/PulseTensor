#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PRESET_PATH="${ROOT_DIR}/configs/presets/launch_presets.json"
PRESET_NAME=""
NETUID=""
MECHID="0"
OUT_PATH=""
CORE_ADDRESS="${CORE_ADDRESS:-<core-address>}"
SETTLEMENT_ADDRESS="${SETTLEMENT_ADDRESS:-<settlement-address>}"
GOVERNANCE_ADDRESS="${GOVERNANCE_ADDRESS:-<governance-contract-address>}"

usage() {
  cat <<'EOF'
Usage: bash scripts/render_launch_preset.sh --preset <name> --netuid <id> [options]

Render a launch parameter preset as:
  - human-readable rollout plan
  - deterministic JSON artifact (optional)

Required:
  --preset <name>         Preset name from configs/presets/launch_presets.json
  --netuid <id>           Target subnet id

Optional:
  --mechid <id>           Mechanism id (default: 0)
  --core <address>        Core contract address for command templates
  --settlement <address>  Settlement contract address for command templates
  --governance <address>  Governance contract address for command templates
  --out <path>            Write JSON rollout artifact
  --help                  Show help

Example:
  bash scripts/render_launch_preset.sh \
    --preset balanced \
    --netuid 1 \
    --mechid 0 \
    --core 0xCore... \
    --settlement 0xSettle... \
    --governance 0xGov... \
    --out runs/deployments/preset_balanced_netuid1.json
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --preset)
      PRESET_NAME="${2:-}"
      shift 2
      ;;
    --netuid)
      NETUID="${2:-}"
      shift 2
      ;;
    --mechid)
      MECHID="${2:-}"
      shift 2
      ;;
    --core)
      CORE_ADDRESS="${2:-}"
      shift 2
      ;;
    --settlement)
      SETTLEMENT_ADDRESS="${2:-}"
      shift 2
      ;;
    --governance)
      GOVERNANCE_ADDRESS="${2:-}"
      shift 2
      ;;
    --out)
      OUT_PATH="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${PRESET_NAME}" ]]; then
  echo "--preset is required"
  usage
  exit 1
fi

if [[ -z "${NETUID}" ]]; then
  echo "--netuid is required"
  usage
  exit 1
fi

if ! [[ "${NETUID}" =~ ^[0-9]+$ ]]; then
  echo "--netuid must be an integer"
  exit 1
fi

if ! [[ "${MECHID}" =~ ^[0-9]+$ ]]; then
  echo "--mechid must be an integer"
  exit 1
fi

if [[ ! -f "${PRESET_PATH}" ]]; then
  echo "Preset config not found: ${PRESET_PATH}"
  exit 1
fi

ROLLBACK_PLAN_JSON="$(
python3 - "${PRESET_PATH}" "${PRESET_NAME}" "${NETUID}" "${MECHID}" "${CORE_ADDRESS}" "${SETTLEMENT_ADDRESS}" "${GOVERNANCE_ADDRESS}" <<'PY'
import json
import sys
from datetime import datetime, timezone
from decimal import Decimal, getcontext

getcontext().prec = 60

preset_path, preset_name, netuid, mechid, core_addr, settlement_addr, governance_addr = sys.argv[1:8]

with open(preset_path, "r", encoding="utf-8") as handle:
    payload = json.load(handle)

presets = payload.get("presets", {})
if preset_name not in presets:
    print(f"Preset not found: {preset_name}", file=sys.stderr)
    print(f"Available presets: {', '.join(sorted(presets.keys()))}", file=sys.stderr)
    sys.exit(1)

preset = presets[preset_name]
subnet = preset["subnet"]
emission = preset["emission"]
settlement = preset["settlement"]
batch_policy = settlement["batch_policy"]
fee_policy = settlement["fee_policy"]

bps_denominator = 10_000
protocol_fee_bps = int(fee_policy["protocol_fee_bps"])
treasury_fee_bps = int(fee_policy["treasury_fee_bps"])
protocol_cut_bps = protocol_fee_bps
treasury_gross_bps = (protocol_fee_bps * treasury_fee_bps) // bps_denominator
miner_gross_bps = protocol_cut_bps - treasury_gross_bps
proposer_gross_bps = bps_denominator - protocol_cut_bps

def wei_to_pls(wei: str) -> str:
    pls = Decimal(wei) / Decimal(10**18)
    text = format(pls, "f")
    if "." in text:
        text = text.rstrip("0").rstrip(".")
    return text

now_utc = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

commands = {
    "owner_direct": [
        {
            "target": "core",
            "address": core_addr,
            "signature": "createSubnet(uint16,uint256,uint16,uint64,uint64)",
            "args": [
                subnet["max_validators"],
                subnet["min_validator_stake_wei"],
                subnet["owner_fee_bps"],
                subnet["reveal_delay_blocks"],
                subnet["epoch_length_blocks"],
            ],
            "note": "Subnet owner call.",
        },
        {
            "target": "core",
            "address": core_addr,
            "signature": "configureSubnetGovernance(uint16,address,uint64)",
            "args": [int(netuid), governance_addr, subnet["owner_action_delay_blocks"]],
            "note": "Subnet owner call; governance must be contract address.",
        },
    ],
    "governance_queue_then_execute": [
        {
            "target": "core",
            "address": core_addr,
            "queue_signature": "queueSubnetEmissionScheduleUpdate(uint16,uint256,uint256,uint64,uint64)",
            "execute_signature": "configureSubnetEmissionSchedule(uint16,uint256,uint256,uint64,uint64)",
            "args": [
                int(netuid),
                emission["subnet_schedule"]["base_per_epoch_wei"],
                emission["subnet_schedule"]["floor_per_epoch_wei"],
                emission["subnet_schedule"]["halving_period_epochs"],
                emission["subnet_schedule"]["start_epoch"],
            ],
            "wait_blocks": subnet["owner_action_delay_blocks"],
        },
        {
            "target": "core",
            "address": core_addr,
            "queue_signature": "queueSubnetEmissionSmoothingUpdate(uint16,bool)",
            "execute_signature": "configureSubnetEmissionSmoothing(uint16,bool)",
            "args": [int(netuid), emission["subnet_schedule"]["smooth_decay_enabled"]],
            "wait_blocks": subnet["owner_action_delay_blocks"],
        },
        {
            "target": "core",
            "address": core_addr,
            "queue_signature": "queueMechanismEmissionScheduleUpdate(uint16,uint16,uint256,uint256,uint64,uint64)",
            "execute_signature": "configureMechanismEmissionSchedule(uint16,uint16,uint256,uint256,uint64,uint64)",
            "args": [
                int(netuid),
                int(mechid),
                emission["mechanism_schedule"]["base_per_epoch_wei"],
                emission["mechanism_schedule"]["floor_per_epoch_wei"],
                emission["mechanism_schedule"]["halving_period_epochs"],
                emission["mechanism_schedule"]["start_epoch"],
            ],
            "wait_blocks": subnet["owner_action_delay_blocks"],
        },
        {
            "target": "core",
            "address": core_addr,
            "queue_signature": "queueMechanismEmissionSmoothingUpdate(uint16,uint16,bool)",
            "execute_signature": "configureMechanismEmissionSmoothing(uint16,uint16,bool)",
            "args": [int(netuid), int(mechid), emission["mechanism_schedule"]["smooth_decay_enabled"]],
            "wait_blocks": subnet["owner_action_delay_blocks"],
        },
        {
            "target": "settlement",
            "address": settlement_addr,
            "queue_signature": "queueBatchPolicyUpdate(uint16,uint16,bool,uint64,uint32,uint256)",
            "execute_signature": "configureBatchPolicy(uint16,uint16,bool,uint64,uint32,uint256)",
            "args": [
                int(netuid),
                int(mechid),
                True,
                batch_policy["challenge_window_blocks"],
                batch_policy["max_batch_items"],
                batch_policy["min_proposer_bond_wei"],
            ],
            "wait_blocks": 2,
        },
        {
            "target": "settlement",
            "address": settlement_addr,
            "queue_signature": "queueFeePolicyUpdate(uint16,uint16,bool,uint16,uint16,address,address)",
            "execute_signature": "configureFeePolicy(uint16,uint16,bool,uint16,uint16,address,address)",
            "args": [
                int(netuid),
                int(mechid),
                True,
                protocol_fee_bps,
                treasury_fee_bps,
                governance_addr,
                governance_addr,
            ],
            "wait_blocks": 2,
            "note": "Replace treasury/miner sink addresses for production payout routing.",
        },
    ],
}

artifact = {
    "generated_at_utc": now_utc,
    "preset_name": preset_name,
    "preset_version": payload.get("version"),
    "netuid": int(netuid),
    "mechid": int(mechid),
    "addresses": {
        "core": core_addr,
        "settlement": settlement_addr,
        "governance": governance_addr,
    },
    "summary": {
        "description": preset["description"],
        "owner_action_delay_blocks": subnet["owner_action_delay_blocks"],
        "protocol_fee_bps": protocol_fee_bps,
        "treasury_fee_bps": treasury_fee_bps,
        "effective_fee_split_bps": {
            "proposer": proposer_gross_bps,
            "miner": miner_gross_bps,
            "treasury": treasury_gross_bps,
        },
    },
    "human": {
        "min_validator_stake_pls": wei_to_pls(subnet["min_validator_stake_wei"]),
        "min_proposer_bond_pls": wei_to_pls(batch_policy["min_proposer_bond_wei"]),
        "subnet_base_emission_pls": wei_to_pls(emission["subnet_schedule"]["base_per_epoch_wei"]),
        "subnet_floor_emission_pls": wei_to_pls(emission["subnet_schedule"]["floor_per_epoch_wei"]),
        "mechanism_base_emission_pls": wei_to_pls(emission["mechanism_schedule"]["base_per_epoch_wei"]),
        "mechanism_floor_emission_pls": wei_to_pls(emission["mechanism_schedule"]["floor_per_epoch_wei"]),
    },
    "parameters": preset,
    "commands": commands,
}

print(json.dumps(artifact, separators=(",", ":"), sort_keys=False))
PY
)"

if [[ -n "${OUT_PATH}" ]]; then
  mkdir -p "$(dirname -- "${OUT_PATH}")"
  python3 - "${ROLLBACK_PLAN_JSON}" "${OUT_PATH}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
out_path = sys.argv[2]
with open(out_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2)
    handle.write("\n")
PY
fi

python3 - "${ROLLBACK_PLAN_JSON}" "${OUT_PATH}" <<'PY'
import json
import shlex
import sys

payload = json.loads(sys.argv[1])
out_path = sys.argv[2]

def fmt_args(values):
    normalized = []
    for value in values:
        if isinstance(value, bool):
            normalized.append("true" if value else "false")
        else:
            normalized.append(str(value))
    return " ".join(shlex.quote(value) for value in normalized)

print(f"Preset: {payload['preset_name']}")
print(f"Description: {payload['summary']['description']}")
print(f"Target: netuid={payload['netuid']}, mechid={payload['mechid']}")
print(
    "Effective fee split (gross bps): "
    f"proposer={payload['summary']['effective_fee_split_bps']['proposer']} "
    f"miner={payload['summary']['effective_fee_split_bps']['miner']} "
    f"treasury={payload['summary']['effective_fee_split_bps']['treasury']}"
)
print(
    "Core Sybil friction: "
    f"min_stake={payload['human']['min_validator_stake_pls']} PLS, "
    f"max_validators={payload['parameters']['subnet']['max_validators']}"
)
print(
    "Settlement anti-fraud: "
    f"challenge_window={payload['parameters']['settlement']['batch_policy']['challenge_window_blocks']} blocks, "
    f"min_bond={payload['human']['min_proposer_bond_pls']} PLS"
)
print("")
print("Owner calls:")
for item in payload["commands"]["owner_direct"]:
    print(
        f"cast send {shlex.quote(item['address'])} "
        f"{shlex.quote(item['signature'])} {fmt_args(item['args'])}"
    )
    print(f"  note: {item['note']}")

print("")
print("Governance queue->execute calls:")
for item in payload["commands"]["governance_queue_then_execute"]:
    print(
        f"queue:   {item['queue_signature']} {fmt_args(item['args'])}"
    )
    print(f"execute: {item['execute_signature']} {fmt_args(item['args'])}")
    print(f"  wait: >= {item['wait_blocks']} blocks")
    if "note" in item:
        print(f"  note: {item['note']}")

if out_path:
    print("")
    print(f"Wrote rollout artifact: {out_path}")
PY

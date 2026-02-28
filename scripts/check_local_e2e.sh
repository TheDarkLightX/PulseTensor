#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT_DIR}/runs/local_e2e"
ANVIL_LOG="${OUT_DIR}/anvil.log"
DEPLOY_LOG="${OUT_DIR}/deploy.log"
CREATE_LOG="${OUT_DIR}/forge_create.log"
REPORT_PATH="${OUT_DIR}/local_e2e_report.json"

LOCAL_E2E_PORT="${LOCAL_E2E_PORT:-8547}"
RPC_URL="${LOCAL_E2E_RPC_URL:-http://127.0.0.1:${LOCAL_E2E_PORT}}"
CHAIN_ID_EXPECTED="${LOCAL_E2E_CHAIN_ID:-31337}"
ANVIL_MNEMONIC="${LOCAL_E2E_MNEMONIC:-test test test test test test test test test test test junk}"

# Optional key overrides. Defaults derive from mnemonic indices 0..3.
OWNER_PK="${LOCAL_E2E_OWNER_PK:-}"
VALIDATOR_PK="${LOCAL_E2E_VALIDATOR_PK:-}"
FUNDER_PK="${LOCAL_E2E_FUNDER_PK:-}"
MINER_PK="${LOCAL_E2E_MINER_PK:-}"

NETUID=1
MECHID=1

log() {
  echo "[local-e2e] $*"
}

fail() {
  echo "[local-e2e] ERROR: $*" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if [[ "${actual}" != "${expected}" ]]; then
    fail "${label}: expected=${expected} actual=${actual}"
  fi
}

assert_true() {
  local actual="$1"
  local label="$2"
  if [[ "${actual}" != "true" ]]; then
    fail "${label}: expected=true actual=${actual}"
  fi
}

normalize_address() {
  local value="$1"
  echo "${value,,}"
}

normalize_uint() {
  local value="$1"
  echo "${value}" | awk '{print $1}'
}

mine_blocks() {
  local blocks="$1"
  local i
  for ((i = 0; i < blocks; i++)); do
    cast rpc --rpc-url "${RPC_URL}" evm_mine >/dev/null
  done
}

deploy_contract() {
  local target="$1"
  local label="$2"
  local output
  output="$(
    forge create "${target}" \
      --rpc-url "${RPC_URL}" \
      --private-key "${OWNER_PK}" \
      --broadcast 2>&1
  )"
  printf '%s\n' "${output}" >> "${CREATE_LOG}"
  local deployed_address
  deployed_address="$(printf '%s\n' "${output}" | awk '/Deployed to:/ {print $3}' | tail -n 1)"
  if [[ -z "${deployed_address}" ]]; then
    fail "unable to parse deployment address for ${label}"
  fi
  echo "${deployed_address}"
}

ANVIL_PID=""
cleanup() {
  if [[ -n "${ANVIL_PID}" ]] && kill -0 "${ANVIL_PID}" 2>/dev/null; then
    kill "${ANVIL_PID}" 2>/dev/null || true
    wait "${ANVIL_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

mkdir -p "${OUT_DIR}"
: > "${CREATE_LOG}"

if cast block-number --rpc-url "${RPC_URL}" >/dev/null 2>&1; then
  fail "RPC endpoint ${RPC_URL} is already in use. Set LOCAL_E2E_PORT or LOCAL_E2E_RPC_URL."
fi

log "starting fresh anvil on ${RPC_URL}"
anvil \
  --host 127.0.0.1 \
  --port "${LOCAL_E2E_PORT}" \
  --chain-id "${CHAIN_ID_EXPECTED}" \
  --mnemonic "${ANVIL_MNEMONIC}" >"${ANVIL_LOG}" 2>&1 &
ANVIL_PID=$!

for _ in $(seq 1 60); do
  if cast block-number --rpc-url "${RPC_URL}" >/dev/null 2>&1; then
    break
  fi
  sleep 0.2
done
if ! cast block-number --rpc-url "${RPC_URL}" >/dev/null 2>&1; then
  fail "anvil failed to start (see ${ANVIL_LOG})"
fi

CHAIN_ID_ACTUAL="$(normalize_uint "$(cast chain-id --rpc-url "${RPC_URL}")")"
assert_eq "${CHAIN_ID_EXPECTED}" "${CHAIN_ID_ACTUAL}" "chain id"

if [[ -z "${OWNER_PK}" ]]; then
  OWNER_PK="$(cast wallet private-key --mnemonic "${ANVIL_MNEMONIC}" --mnemonic-index 0)"
fi
if [[ -z "${VALIDATOR_PK}" ]]; then
  VALIDATOR_PK="$(cast wallet private-key --mnemonic "${ANVIL_MNEMONIC}" --mnemonic-index 1)"
fi
if [[ -z "${FUNDER_PK}" ]]; then
  FUNDER_PK="$(cast wallet private-key --mnemonic "${ANVIL_MNEMONIC}" --mnemonic-index 2)"
fi
if [[ -z "${MINER_PK}" ]]; then
  MINER_PK="$(cast wallet private-key --mnemonic "${ANVIL_MNEMONIC}" --mnemonic-index 3)"
fi

OWNER_ADDR="$(cast wallet address --private-key "${OWNER_PK}")"
VALIDATOR_ADDR="$(cast wallet address --private-key "${VALIDATOR_PK}")"
FUNDER_ADDR="$(cast wallet address --private-key "${FUNDER_PK}")"
MINER_ADDR="$(cast wallet address --private-key "${MINER_PK}")"

log "deploying core and settlement"
FOUNDRY_OPTIMIZER_RUNS="${FOUNDRY_OPTIMIZER_RUNS:-1}" \
RPC_URL="${RPC_URL}" \
PRIVATE_KEY="${OWNER_PK}" \
bash "${ROOT_DIR}/scripts/deploy_pulsetensor.sh" \
  --rpc-url "${RPC_URL}" \
  --private-key "${OWNER_PK}" \
  --out-dir "${OUT_DIR}" >"${DEPLOY_LOG}" 2>&1

RECEIPT_PATH="${OUT_DIR}/pulsetensor_deploy_receipt.json"
if [[ ! -f "${RECEIPT_PATH}" ]]; then
  fail "missing deployment receipt at ${RECEIPT_PATH}"
fi

CORE_ADDR="$(jq -r '.core_address' "${RECEIPT_PATH}")"
SETTLEMENT_ADDR="$(jq -r '.settlement_address' "${RECEIPT_PATH}")"

if [[ -z "${CORE_ADDR}" || "${CORE_ADDR}" == "null" || -z "${SETTLEMENT_ADDR}" || "${SETTLEMENT_ADDR}" == "null" ]]; then
  fail "invalid deploy receipt contents in ${RECEIPT_PATH}"
fi

log "deploying governance feature actor"
GOVERNANCE_ADDR="$(deploy_contract "test/PulseTensorCore.inference_emission.t.sol:FeatureActor" "FeatureActor")"

log "creating subnet and configuring governance"
cast send "${CORE_ADDR}" "createSubnet(uint16,uint256,uint16,uint64,uint64)" \
  64 1000000000000000000 500 2 16 \
  --private-key "${OWNER_PK}" --rpc-url "${RPC_URL}" >/dev/null
cast send "${CORE_ADDR}" "configureSubnetGovernance(uint16,address,uint64)" \
  "${NETUID}" "${GOVERNANCE_ADDR}" 2 \
  --private-key "${OWNER_PK}" --rpc-url "${RPC_URL}" >/dev/null

SUBNET_OWNER="$(cast call "${CORE_ADDR}" "subnetOwner(uint16)(address)" "${NETUID}" --rpc-url "${RPC_URL}")"
SUBNET_GOVERNANCE="$(cast call "${CORE_ADDR}" "subnetGovernance(uint16)(address)" "${NETUID}" --rpc-url "${RPC_URL}")"
assert_eq "$(normalize_address "${OWNER_ADDR}")" "$(normalize_address "${SUBNET_OWNER}")" "subnet owner"
assert_eq "$(normalize_address "${GOVERNANCE_ADDR}")" "$(normalize_address "${SUBNET_GOVERNANCE}")" "subnet governance"

log "staking and validator registration"
cast send "${CORE_ADDR}" "addStake(uint16)" "${NETUID}" \
  --value 2000000000000000000 \
  --private-key "${VALIDATOR_PK}" --rpc-url "${RPC_URL}" >/dev/null
cast send "${CORE_ADDR}" "registerValidator(uint16)" "${NETUID}" \
  --private-key "${VALIDATOR_PK}" --rpc-url "${RPC_URL}" >/dev/null
CAN_VALIDATE="$(cast call "${CORE_ADDR}" "canValidate(uint16,address)(bool)" "${NETUID}" "${VALIDATOR_ADDR}" --rpc-url "${RPC_URL}")"
assert_true "${CAN_VALIDATE}" "validator eligibility"

log "running commit-reveal flow"
COMMIT_EPOCH="$(normalize_uint "$(cast call "${CORE_ADDR}" "currentEpoch(uint16)(uint64)" "${NETUID}" --rpc-url "${RPC_URL}")")"
WEIGHTS_HASH="$(cast keccak "local-e2e-weights")"
SALT="$(cast keccak "local-e2e-salt")"
COMMITMENT_INPUT="$(cast abi-encode "f(bytes32,bytes32,address,uint16,uint64,uint256,address,uint32)" \
  "${WEIGHTS_HASH}" "${SALT}" "${VALIDATOR_ADDR}" "${NETUID}" "${COMMIT_EPOCH}" "${CHAIN_ID_ACTUAL}" "${CORE_ADDR}" 1)"
COMMITMENT="$(cast keccak "${COMMITMENT_INPUT}")"
cast send "${CORE_ADDR}" "commitWeights(uint16,bytes32)" "${NETUID}" "${COMMITMENT}" \
  --private-key "${VALIDATOR_PK}" --rpc-url "${RPC_URL}" >/dev/null
mine_blocks 3
cast send "${CORE_ADDR}" "revealWeights(uint16,uint64,bytes32,bytes32)" \
  "${NETUID}" "${COMMIT_EPOCH}" "${WEIGHTS_HASH}" "${SALT}" \
  --private-key "${VALIDATOR_PK}" --rpc-url "${RPC_URL}" >/dev/null
REVEALED="$(cast call "${CORE_ADDR}" "epochRevealed(uint16,uint64,address)(bool)" \
  "${NETUID}" "${COMMIT_EPOCH}" "${VALIDATOR_ADDR}" --rpc-url "${RPC_URL}")"
REVEALED_HASH="$(cast call "${CORE_ADDR}" "epochRevealedWeightsHash(uint16,uint64,address)(bytes32)" \
  "${NETUID}" "${COMMIT_EPOCH}" "${VALIDATOR_ADDR}" --rpc-url "${RPC_URL}")"
assert_true "${REVEALED}" "weights reveal status"
assert_eq "${WEIGHTS_HASH}" "${REVEALED_HASH}" "revealed weights hash"

log "configuring emission schedule and smoothing through governance delay"
cast send "${GOVERNANCE_ADDR}" \
  "queueSubnetEmissionScheduleUpdate(address,uint16,uint256,uint256,uint64,uint64)" \
  "${CORE_ADDR}" "${NETUID}" 1000000000000000000 125000000000000000 4 0 \
  --private-key "${OWNER_PK}" --rpc-url "${RPC_URL}" >/dev/null
cast send "${GOVERNANCE_ADDR}" \
  "queueSubnetEmissionSmoothingUpdate(address,uint16,bool)" \
  "${CORE_ADDR}" "${NETUID}" true \
  --private-key "${OWNER_PK}" --rpc-url "${RPC_URL}" >/dev/null
mine_blocks 3
cast send "${GOVERNANCE_ADDR}" \
  "configureSubnetEmissionSchedule(address,uint16,uint256,uint256,uint64,uint64)" \
  "${CORE_ADDR}" "${NETUID}" 1000000000000000000 125000000000000000 4 0 \
  --private-key "${OWNER_PK}" --rpc-url "${RPC_URL}" >/dev/null
cast send "${GOVERNANCE_ADDR}" \
  "configureSubnetEmissionSmoothing(address,uint16,bool)" \
  "${CORE_ADDR}" "${NETUID}" true \
  --private-key "${OWNER_PK}" --rpc-url "${RPC_URL}" >/dev/null
QUOTE_EPOCH_1="$(normalize_uint "$(cast call "${CORE_ADDR}" "quoteSubnetEpochEmission(uint16,uint64)(uint256)" "${NETUID}" 1 --rpc-url "${RPC_URL}")")"
assert_eq "875000000000000000" "${QUOTE_EPOCH_1}" "smoothed subnet epoch quote"

log "configuring inference batch and fee policies through governance delay"
cast send "${GOVERNANCE_ADDR}" \
  "queueInferenceBatchPolicyUpdate(address,uint16,uint16,bool,uint64,uint32,uint256)" \
  "${SETTLEMENT_ADDR}" "${NETUID}" "${MECHID}" true 5 8 100000000000000000 \
  --private-key "${OWNER_PK}" --rpc-url "${RPC_URL}" >/dev/null
cast send "${GOVERNANCE_ADDR}" \
  "queueInferenceFeePolicyUpdate(address,uint16,uint16,bool,uint16,uint16,address,address)" \
  "${SETTLEMENT_ADDR}" "${NETUID}" "${MECHID}" true 1200 3500 "${FUNDER_ADDR}" "${MINER_ADDR}" \
  --private-key "${OWNER_PK}" --rpc-url "${RPC_URL}" >/dev/null
mine_blocks 3
cast send "${GOVERNANCE_ADDR}" \
  "configureInferenceBatchPolicy(address,uint16,uint16,bool,uint64,uint32,uint256)" \
  "${SETTLEMENT_ADDR}" "${NETUID}" "${MECHID}" true 5 8 100000000000000000 \
  --private-key "${OWNER_PK}" --rpc-url "${RPC_URL}" >/dev/null
cast send "${GOVERNANCE_ADDR}" \
  "configureInferenceFeePolicy(address,uint16,uint16,bool,uint16,uint16,address,address)" \
  "${SETTLEMENT_ADDR}" "${NETUID}" "${MECHID}" true 1200 3500 "${FUNDER_ADDR}" "${MINER_ADDR}" \
  --private-key "${OWNER_PK}" --rpc-url "${RPC_URL}" >/dev/null

log "committing, funding, finalizing, and settling inference batch"
INFER_EPOCH="$(normalize_uint "$(cast call "${CORE_ADDR}" "currentEpoch(uint16)(uint64)" "${NETUID}" --rpc-url "${RPC_URL}")")"
REQUEST_ID="$(cast keccak "local-e2e-request-1")"
RESULT_HASH="$(cast keccak "local-e2e-result-1")"
LEAF_HASH="$(cast call "${SETTLEMENT_ADDR}" \
  "computeInferenceLeaf(uint16,uint16,uint64,bytes32,bytes32)(bytes32)" \
  "${NETUID}" "${MECHID}" "${INFER_EPOCH}" "${REQUEST_ID}" "${RESULT_HASH}" --rpc-url "${RPC_URL}")"
cast send "${SETTLEMENT_ADDR}" \
  "commitInferenceBatchRoot(uint16,uint16,uint64,bytes32,uint32,uint256)" \
  "${NETUID}" "${MECHID}" "${INFER_EPOCH}" "${LEAF_HASH}" 1 1000000000000000000 \
  --value 200000000000000000 \
  --private-key "${VALIDATOR_PK}" --rpc-url "${RPC_URL}" >/dev/null
cast send "${SETTLEMENT_ADDR}" "fundInferenceBatchFees(uint16,uint16,uint64)" \
  "${NETUID}" "${MECHID}" "${INFER_EPOCH}" \
  --value 1000000000000000000 \
  --private-key "${FUNDER_PK}" --rpc-url "${RPC_URL}" >/dev/null
mine_blocks 7
cast send "${SETTLEMENT_ADDR}" "finalizeInferenceBatch(uint16,uint16,uint64)" \
  "${NETUID}" "${MECHID}" "${INFER_EPOCH}" \
  --private-key "${OWNER_PK}" --rpc-url "${RPC_URL}" >/dev/null
cast send "${SETTLEMENT_ADDR}" \
  "settleFinalizedInferenceLeaf(uint16,uint16,uint64,bytes32,uint256,bytes32[])" \
  "${NETUID}" "${MECHID}" "${INFER_EPOCH}" "${LEAF_HASH}" 0 "[]" \
  --private-key "${OWNER_PK}" --rpc-url "${RPC_URL}" >/dev/null
LEAF_SETTLED="$(cast call "${SETTLEMENT_ADDR}" "settledLeaves(uint16,uint16,bytes32)(bool)" \
  "${NETUID}" "${MECHID}" "${LEAF_HASH}" --rpc-url "${RPC_URL}")"
assert_true "${LEAF_SETTLED}" "settled leaf"

log "verifying and claiming proposer bond + fee distribution"
BOND_REFUND="$(normalize_uint "$(cast call "${SETTLEMENT_ADDR}" "proposerBondRefundOf(uint16,address)(uint256)" \
  "${NETUID}" "${VALIDATOR_ADDR}" --rpc-url "${RPC_URL}")")"
assert_eq "200000000000000000" "${BOND_REFUND}" "proposer bond refund balance"

VALIDATOR_FEE_CLAIM="$(normalize_uint "$(cast call "${SETTLEMENT_ADDR}" "inferenceFeeClaimOf(uint16,address)(uint256)" \
  "${NETUID}" "${VALIDATOR_ADDR}" --rpc-url "${RPC_URL}")")"
TREASURY_FEE_CLAIM="$(normalize_uint "$(cast call "${SETTLEMENT_ADDR}" "inferenceFeeClaimOf(uint16,address)(uint256)" \
  "${NETUID}" "${FUNDER_ADDR}" --rpc-url "${RPC_URL}")")"
MINER_FEE_CLAIM="$(normalize_uint "$(cast call "${SETTLEMENT_ADDR}" "inferenceFeeClaimOf(uint16,address)(uint256)" \
  "${NETUID}" "${MINER_ADDR}" --rpc-url "${RPC_URL}")")"

assert_eq "880000000000000000" "${VALIDATOR_FEE_CLAIM}" "validator inference fee claim"
assert_eq "42000000000000000" "${TREASURY_FEE_CLAIM}" "treasury inference fee claim"
assert_eq "78000000000000000" "${MINER_FEE_CLAIM}" "miner inference fee claim"

cast send "${SETTLEMENT_ADDR}" "claimProposerBondRefund(uint16,uint256)" \
  "${NETUID}" "${BOND_REFUND}" --private-key "${VALIDATOR_PK}" --rpc-url "${RPC_URL}" >/dev/null
cast send "${SETTLEMENT_ADDR}" "claimInferenceFee(uint16,uint256)" \
  "${NETUID}" "${VALIDATOR_FEE_CLAIM}" --private-key "${VALIDATOR_PK}" --rpc-url "${RPC_URL}" >/dev/null
cast send "${SETTLEMENT_ADDR}" "claimInferenceFee(uint16,uint256)" \
  "${NETUID}" "${TREASURY_FEE_CLAIM}" --private-key "${FUNDER_PK}" --rpc-url "${RPC_URL}" >/dev/null
cast send "${SETTLEMENT_ADDR}" "claimInferenceFee(uint16,uint256)" \
  "${NETUID}" "${MINER_FEE_CLAIM}" --private-key "${MINER_PK}" --rpc-url "${RPC_URL}" >/dev/null

POST_BOND_REFUND="$(normalize_uint "$(cast call "${SETTLEMENT_ADDR}" "proposerBondRefundOf(uint16,address)(uint256)" \
  "${NETUID}" "${VALIDATOR_ADDR}" --rpc-url "${RPC_URL}")")"
POST_VALIDATOR_FEE_CLAIM="$(normalize_uint "$(cast call "${SETTLEMENT_ADDR}" "inferenceFeeClaimOf(uint16,address)(uint256)" \
  "${NETUID}" "${VALIDATOR_ADDR}" --rpc-url "${RPC_URL}")")"
POST_TREASURY_FEE_CLAIM="$(normalize_uint "$(cast call "${SETTLEMENT_ADDR}" "inferenceFeeClaimOf(uint16,address)(uint256)" \
  "${NETUID}" "${FUNDER_ADDR}" --rpc-url "${RPC_URL}")")"
POST_MINER_FEE_CLAIM="$(normalize_uint "$(cast call "${SETTLEMENT_ADDR}" "inferenceFeeClaimOf(uint16,address)(uint256)" \
  "${NETUID}" "${MINER_ADDR}" --rpc-url "${RPC_URL}")")"

assert_eq "0" "${POST_BOND_REFUND}" "post-claim proposer bond refund"
assert_eq "0" "${POST_VALIDATOR_FEE_CLAIM}" "post-claim validator fee"
assert_eq "0" "${POST_TREASURY_FEE_CLAIM}" "post-claim treasury fee"
assert_eq "0" "${POST_MINER_FEE_CLAIM}" "post-claim miner fee"

FINAL_BLOCK="$(normalize_uint "$(cast block-number --rpc-url "${RPC_URL}")")"
GENERATED_AT_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat > "${REPORT_PATH}" <<EOF
{
  "schema": "pulsetensor/local-e2e-report/v1",
  "generated_at_utc": "${GENERATED_AT_UTC}",
  "rpc_url": "${RPC_URL}",
  "chain_id": ${CHAIN_ID_ACTUAL},
  "final_block": ${FINAL_BLOCK},
  "core_address": "${CORE_ADDR}",
  "settlement_address": "${SETTLEMENT_ADDR}",
  "governance_actor_address": "${GOVERNANCE_ADDR}",
  "netuid": ${NETUID},
  "mechid": ${MECHID},
  "commit_epoch": ${COMMIT_EPOCH},
  "inference_epoch": ${INFER_EPOCH},
  "leaf_hash": "${LEAF_HASH}",
  "fee_distribution_wei": {
    "validator": ${VALIDATOR_FEE_CLAIM},
    "treasury": ${TREASURY_FEE_CLAIM},
    "miner": ${MINER_FEE_CLAIM}
  },
  "checks": {
    "can_validate": true,
    "commit_reveal": true,
    "governance_delay_paths": true,
    "inference_finalize_and_settle": true,
    "claims_zero_after_withdraw": true
  }
}
EOF

log "local E2E passed; report written to ${REPORT_PATH}"

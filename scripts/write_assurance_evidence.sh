#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT_DIR}/runs/assurance"
OUT_PATH="${OUT_DIR}/evidence.json"

for command_name in forge cast jq git sha256sum; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    echo "required command not found: ${command_name}"
    exit 1
  }
done

pushd "${ROOT_DIR}" >/dev/null
FOUNDRY_OPTIMIZER_RUNS=1 forge build >/dev/null
mkdir -p "${OUT_DIR}"

tracked_digest="$({
  git ls-files -z \
    | LC_ALL=C sort -z \
    | xargs -0 sha256sum
} | sha256sum | awk '{print $1}')"
source scripts/toolchain.lock
solc_path="${HOME}/.svm/${SOLC_VERSION}/solc-${SOLC_VERSION}"
[[ -x "${solc_path}" ]] || {
  echo "pinned solc binary not found: ${solc_path}"
  exit 1
}
core_runtime="$(jq -r '.deployedBytecode.object' out/PulseTensorCore.sol/PulseTensorCore.json)"
settlement_runtime="$(jq -r '.deployedBytecode.object' out/PulseTensorInferenceSettlement.sol/PulseTensorInferenceSettlement.json)"

jq -n \
  --arg schema "pulsetensor-assurance-evidence-v1" \
  --arg commit "$(git rev-parse HEAD)" \
  --arg tree_state "$(test -z "$(git status --porcelain --untracked-files=no)" && echo clean || echo dirty)" \
  --arg forge "$(forge --version | head -n 1)" \
  --arg solc "$("${solc_path}" --version | tail -n 1)" \
  --arg solc_sha256 "$(sha256sum "${solc_path}" | awk '{print $1}')" \
  --arg python "$(python3 --version | head -n 1)" \
  --arg docker "$(docker --version 2>/dev/null | head -n 1 || echo unavailable)" \
  --arg solhint "$(solhint --version 2>/dev/null | head -n 1 || echo unavailable)" \
  --arg tracked_digest "${tracked_digest}" \
  --arg foundry_config_sha256 "$(sha256sum foundry.toml | awk '{print $1}')" \
  --arg toolchain_lock_sha256 "$(sha256sum scripts/toolchain.lock | awk '{print $1}')" \
  --arg core_runtime_keccak256 "$(cast keccak "${core_runtime}")" \
  --arg settlement_runtime_keccak256 "$(cast keccak "${settlement_runtime}")" \
  '{
    schema: $schema,
    commit: $commit,
    tree_state: $tree_state,
    profile: {solc: "0.8.36", optimizer: true, optimizer_runs: 1, via_ir: true, evm: "paris"},
    tools: {forge: $forge, solc: $solc, solc_sha256: $solc_sha256, python: $python, docker: $docker, solhint: $solhint},
    inputs: {
      tracked_files_sha256: $tracked_digest,
      foundry_config_sha256: $foundry_config_sha256,
      toolchain_lock_sha256: $toolchain_lock_sha256
    },
    deploy_profile_runtime: {
      core_keccak256: $core_runtime_keccak256,
      settlement_template_keccak256: $settlement_runtime_keccak256
    }
  }' >"${OUT_PATH}.tmp"
mv "${OUT_PATH}.tmp" "${OUT_PATH}"
popd >/dev/null

echo "Assurance evidence written: ${OUT_PATH}"

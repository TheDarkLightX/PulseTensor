#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT_DIR}/runs/assurance"
OUT_PATH="${OUT_DIR}/evidence.json"

for command_name in forge cast jq git sha256sum python3; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    echo "required command not found: ${command_name}"
    exit 1
  }
done

pushd "${ROOT_DIR}" >/dev/null
if ! git diff --quiet -- || ! git diff --cached --quiet --; then
  echo "refusing to attest a dirty tracked worktree"
  exit 1
fi

source scripts/toolchain.lock
while IFS= read -r foundry_env_name; do
  if [[ "${foundry_env_name}" == "FOUNDRY_OPTIMIZER_RUNS" && "${!foundry_env_name}" == "1" ]]; then
    continue
  fi
  echo "refusing unapproved Foundry environment override: ${foundry_env_name}"
  exit 1
done < <(compgen -A variable FOUNDRY_)

export FOUNDRY_OPTIMIZER_RUNS=1
profile_json="$(forge config --json | jq -c '{
  src,
  test,
  out,
  libs,
  remappings,
  ffi,
  fs_permissions,
  script,
  cache_path,
  broadcast,
  allow_paths,
  include_paths,
  solc,
  optimizer,
  optimizer_runs,
  via_ir,
  evm: .evm_version,
  bytecode_hash,
  cbor_metadata
}')"
if ! jq -e \
  --arg solc "${SOLC_VERSION}" \
  '.src == "src" and
   .test == "test" and
   .out == "out" and
   .libs == ["lib"] and
   .remappings == ["forge-std/=lib/forge-std/src/"] and
   .ffi == false and
   .fs_permissions == [{"access":"read","path":"./"}] and
   .script == "script" and
   .cache_path == "cache" and
   .broadcast == "broadcast" and
   .allow_paths == [] and
   .include_paths == [] and
   .solc == $solc and
   .optimizer == true and
   .optimizer_runs == 1 and
   .via_ir == true and
   .evm == "paris" and
   .bytecode_hash == "ipfs" and
   .cbor_metadata == true' \
  <<<"${profile_json}" >/dev/null; then
  echo "deployment profile does not match the attested release profile"
  echo "${profile_json}"
  exit 1
fi

bash scripts/verify_ci_toolchain.sh >/dev/null
forge clean
forge build >/dev/null
mkdir -p "${OUT_DIR}"

tracked_digest="$({
  git ls-files -z \
    | LC_ALL=C sort -z \
    | xargs -0 sha256sum
} | sha256sum | awk '{print $1}')"
solc_path="${HOME}/.svm/${SOLC_VERSION}/solc-${SOLC_VERSION}"
[[ -x "${solc_path}" ]] || {
  echo "pinned solc binary not found: ${solc_path}"
  exit 1
}
core_runtime="$(jq -r '.deployedBytecode.object' out/PulseTensorCore.sol/PulseTensorCore.json)"
settlement_runtime="$(jq -r '.deployedBytecode.object' out/PulseTensorInferenceSettlement.sol/PulseTensorInferenceSettlement.json)"
forge_std_content_sha256="$(
  cd lib/forge-std
  find . -type f -not -path './.git/*' -print0 \
    | LC_ALL=C sort -z \
    | xargs -0 sha256sum \
    | sha256sum \
    | awk '{print $1}'
)"

artifact_hashes="$(python3 - "${ROOT_DIR}" <<'PY'
import hashlib
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
manifest = root / "docs/security/artifact_manifest.release.txt"
paths: list[str] = []
for raw_line in manifest.read_text(encoding="utf-8").splitlines():
    line = raw_line.split("#", 1)[0].strip()
    if line:
        paths.append(line)
paths.extend(
    [
        "runs/security/deploy_code_size_report.json",
        "runs/security/artifact_freshness_report.txt",
        "runs/local_e2e/local_e2e_report.json",
        "runs/local_e2e/pulsetensor_deploy_receipt.json",
        "runs/formal/pulsetensor_emergency_mode_goal_frontier.report.json",
        "runs/formal/pulsetensor_tokenomics_goal_frontier.report.json",
        "runs/formal/pulsetensor_participant_regret_goal_frontier.report.json",
    ]
)

hashes: dict[str, str] = {}
for relative in paths:
    path = root / relative
    if not path.is_file():
        raise SystemExit(f"required assurance artifact missing: {relative}")
    hashes[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
print(json.dumps(hashes, sort_keys=True))
PY
)"

jq -n \
  --arg schema "pulsetensor-assurance-evidence-v2" \
  --arg commit "$(git rev-parse HEAD)" \
  --arg generated_at_utc "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg forge "$(forge --version | head -n 1)" \
  --arg solc "$("${solc_path}" --version | tail -n 1)" \
  --arg solc_sha256 "$(sha256sum "${solc_path}" | awk '{print $1}')" \
  --arg python "$(python3 --version | head -n 1)" \
  --arg docker "$(docker --version 2>/dev/null | head -n 1 || echo unavailable)" \
  --arg solhint "$(solhint --version 2>/dev/null | head -n 1 || echo unavailable)" \
  --arg tracked_digest "${tracked_digest}" \
  --arg foundry_config_sha256 "$(sha256sum foundry.toml | awk '{print $1}')" \
  --arg toolchain_lock_sha256 "$(sha256sum scripts/toolchain.lock | awk '{print $1}')" \
  --arg forge_sha256 "$(sha256sum "$(command -v forge)" | awk '{print $1}')" \
  --arg cast_sha256 "$(sha256sum "$(command -v cast)" | awk '{print $1}')" \
  --arg anvil_sha256 "$(sha256sum "$(command -v anvil)" | awk '{print $1}')" \
  --arg forge_std_content_sha256 "${forge_std_content_sha256}" \
  --arg slither "$("${ROOT_DIR}/.venv/bin/python" -c 'import importlib.metadata; print(importlib.metadata.version("slither-analyzer"))')" \
  --arg slither_environment_sha256 "$("${ROOT_DIR}/.venv/bin/pip" freeze --all | LC_ALL=C sort | sha256sum | awk '{print $1}')" \
  --arg core_runtime_keccak256 "$(cast keccak "${core_runtime}")" \
  --arg settlement_runtime_keccak256 "$(cast keccak "${settlement_runtime}")" \
  --argjson profile "${profile_json}" \
  --argjson artifact_hashes "${artifact_hashes}" \
  '{
    schema: $schema,
    commit: $commit,
    generated_at_utc: $generated_at_utc,
    tree_state: "clean",
    profile: $profile,
    tools: {
      forge: $forge,
      forge_sha256: $forge_sha256,
      cast_sha256: $cast_sha256,
      anvil_sha256: $anvil_sha256,
      solc: $solc,
      solc_sha256: $solc_sha256,
      forge_std_content_sha256: $forge_std_content_sha256,
      slither: $slither,
      slither_environment_sha256: $slither_environment_sha256,
      python: $python,
      docker: $docker,
      solhint: $solhint
    },
    inputs: {
      tracked_files_sha256: $tracked_digest,
      foundry_config_sha256: $foundry_config_sha256,
      toolchain_lock_sha256: $toolchain_lock_sha256
    },
    artifacts_sha256: $artifact_hashes,
    deploy_profile_runtime: {
      core_keccak256: $core_runtime_keccak256,
      settlement_template_keccak256: $settlement_runtime_keccak256
    }
  }' >"${OUT_PATH}.tmp"
mv "${OUT_PATH}.tmp" "${OUT_PATH}"
popd >/dev/null

echo "Assurance evidence written: ${OUT_PATH}"

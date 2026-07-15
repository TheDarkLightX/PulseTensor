#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/toolchain.lock"
CONTRACT_PATH="."
CONTRACT_NAME="PulseTensorCoreEchidna"
CONFIG_PATH="test/echidna/echidna.yaml"
OUT_DIR="${ROOT_DIR}/runs/security"
ECHIDNA_LOG_PATH="${OUT_DIR}/echidna.log"
ECHIDNA_SEED="1"
ECHIDNA_WORKERS="1"
ECHIDNA_DOCKER_NETWORK="none"

run_docker() {
  local solc_path="${HOME}/.svm/${SOLC_VERSION}/solc-${SOLC_VERSION}"
  [[ -x "${solc_path}" ]] || {
    echo "pinned solc binary not found: ${solc_path}"
    exit 1
  }
  if [[ "$(sha256sum "${solc_path}" | awk '{print $1}')" != "${SOLC_RELEASE_SHA256}" ]]; then
    echo "pinned solc binary digest mismatch"
    exit 1
  fi

  docker run --rm \
    --network "${ECHIDNA_DOCKER_NETWORK}" \
    --env HOME=/root \
    --env FOUNDRY_OPTIMIZER_RUNS=1 \
    --env FOUNDRY_SRC=echidna \
    --env ECHIDNA_SEED="${ECHIDNA_SEED}" \
    --env ECHIDNA_WORKERS="${ECHIDNA_WORKERS}" \
    --mount "type=bind,src=${ROOT_DIR},dst=/src,readonly" \
    --mount "type=bind,src=$(dirname "${solc_path}"),dst=/root/.svm/${SOLC_VERSION},readonly" \
    "${ECHIDNA_IMAGE}" \
      bash -lc '
        set -euo pipefail
        mkdir -p /tmp/work
        cp -a /src/src /src/test /src/echidna /src/lib /tmp/work/
        cp -a /src/foundry.toml /tmp/work/
        cd /tmp/work
        echidna --version
        forge config --json | python3 -c '\''import json,sys; c=json.load(sys.stdin); print("echidna_compile_profile=" + json.dumps({k:c[k] for k in ("src","solc","optimizer","optimizer_runs","via_ir","evm_version")}, sort_keys=True))'\''
        sha256sum "/root/.svm/'"${SOLC_VERSION}"'/solc-'"${SOLC_VERSION}"'"
        forge build --build-info --skip ./test/** ./script/** --force >/dev/null
        echidna "." \
          --contract "PulseTensorCoreEchidna" \
          --config "test/echidna/echidna.yaml" \
          --seed "${ECHIDNA_SEED}" \
          --workers "${ECHIDNA_WORKERS}"
      ' 2>&1 \
    | tee -a "${ECHIDNA_LOG_PATH}"
}

pushd "${ROOT_DIR}" >/dev/null
mkdir -p "${OUT_DIR}"
bash "${ROOT_DIR}/scripts/check_echidna_harness.sh"
if ! command -v docker >/dev/null 2>&1; then
  echo "digest-pinned Docker Echidna is required for the assurance gate"
  exit 1
fi
{
  echo "echidna_image=${ECHIDNA_IMAGE}"
  echo "echidna_config_sha256=$(sha256sum "${ROOT_DIR}/${CONFIG_PATH}" | awk '{print $1}')"
  echo "echidna_seed=${ECHIDNA_SEED}"
  echo "echidna_workers=${ECHIDNA_WORKERS}"
} >"${ECHIDNA_LOG_PATH}"
run_docker
popd >/dev/null

echo "Echidna checks passed (seed=${ECHIDNA_SEED}, workers=${ECHIDNA_WORKERS}, log=${ECHIDNA_LOG_PATH})" \
  | tee -a "${ECHIDNA_LOG_PATH}"

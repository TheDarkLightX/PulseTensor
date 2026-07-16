#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/toolchain.lock"
CONTRACT_PATH="."
CONTRACT_NAME="PulseTensorCoreEchidna"
CONFIG_PATH="test/echidna/echidna.yaml"
NEGATIVE_CONFIG_PATH="test/echidna/negative-control.yaml"
OUT_DIR="${ROOT_DIR}/runs/security"
ECHIDNA_LOG_PATH="${OUT_DIR}/echidna.log"
ECHIDNA_SUMMARY_PATH="${OUT_DIR}/echidna_summary.json"
ECHIDNA_SEED="1"
ECHIDNA_WORKERS="1"
ECHIDNA_DOCKER_NETWORK="none"

run_docker() {
  local solc_path="${HOME}/.svm/${SOLC_VERSION}/solc-${SOLC_VERSION}"
  local forge_path
  forge_path="$(command -v forge)"
  [[ -x "${solc_path}" ]] || {
    echo "pinned solc binary not found: ${solc_path}"
    exit 1
  }
  if [[ "$(sha256sum "${solc_path}" | awk '{print $1}')" != "${SOLC_RELEASE_SHA256}" ]]; then
    echo "pinned solc binary digest mismatch"
    exit 1
  fi
  if [[ "$(sha256sum "${forge_path}" | awk '{print $1}')" != "${FORGE_RELEASE_SHA256}" ]]; then
    echo "pinned Forge binary digest mismatch"
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
    --mount "type=bind,src=${forge_path},dst=/usr/local/bin/forge,readonly" \
    "${ECHIDNA_IMAGE}" \
      bash -lc '
        set -euo pipefail
        mkdir -p /tmp/work
        cp -a /src/src /src/test /src/echidna /src/lib /tmp/work/
        cp -a /src/foundry.toml /tmp/work/
        cd /tmp/work
        [[ "$(echidna --version)" == "'"${ECHIDNA_VERSION}"'" ]]
        [[ "$(forge --version | head -n 1)" == "'"${FORGE_RELEASE_VERSION}"'" ]]
        echidna --version
        forge --version | head -n 1
        sha256sum /usr/local/bin/forge
        forge config --json | python3 -c '\''import json,sys; c=json.load(sys.stdin); print("echidna_compile_profile=" + json.dumps({k:c[k] for k in ("src","solc","optimizer","optimizer_runs","via_ir","evm_version")}, sort_keys=True))'\''
        sha256sum "/root/.svm/'"${SOLC_VERSION}"'/solc-'"${SOLC_VERSION}"'"
        forge build --build-info --skip ./test/** ./script/** --force >/dev/null
        set +e
        echidna "." \
          --contract "PulseTensorCoreEchidna" \
          --config "test/echidna/echidna.yaml" \
          --seed "${ECHIDNA_SEED}" \
          --workers "${ECHIDNA_WORKERS}" \
          --format text
        primary_status=$?
        set -e
        echo "--- PULSETENSOR ECHIDNA PRIMARY END status=${primary_status} ---"
        if [[ "${primary_status}" != "0" ]]; then
          exit "${primary_status}"
        fi

        set +e
        echidna "." \
          --contract "PulseTensorCoreEchidnaKnownFailure" \
          --config "test/echidna/negative-control.yaml" \
          --seed "${ECHIDNA_SEED}" \
          --workers "${ECHIDNA_WORKERS}" \
          --format text
        negative_status=$?
        set -e
        echo "--- PULSETENSOR ECHIDNA NEGATIVE END status=${negative_status} ---"
        if [[ "${negative_status}" != "1" ]]; then
          echo "negative-control campaign must exit exactly 1; found ${negative_status}"
          exit 1
        fi
      ' 2>&1 \
    | tee -a "${ECHIDNA_LOG_PATH}"
}

pushd "${ROOT_DIR}" >/dev/null
mkdir -p "${OUT_DIR}"
if [[ -f "${ECHIDNA_SUMMARY_PATH}" ]]; then
  mv "${ECHIDNA_SUMMARY_PATH}" "${ECHIDNA_SUMMARY_PATH}.previous.$(date +%s%N)"
fi
bash "${ROOT_DIR}/scripts/check_echidna_harness.sh"
if ! command -v docker >/dev/null 2>&1; then
  echo "digest-pinned Docker Echidna is required for the assurance gate"
  exit 1
fi
{
  echo "echidna_image=${ECHIDNA_IMAGE}"
  echo "echidna_config_sha256=$(sha256sum "${ROOT_DIR}/${CONFIG_PATH}" | awk '{print $1}')"
  echo "echidna_negative_config_sha256=$(sha256sum "${ROOT_DIR}/${NEGATIVE_CONFIG_PATH}" | awk '{print $1}')"
  echo "echidna_seed=${ECHIDNA_SEED}"
  echo "echidna_workers=${ECHIDNA_WORKERS}"
} >"${ECHIDNA_LOG_PATH}"
run_docker
python3 "${ROOT_DIR}/scripts/check_echidna_campaign.py" "${ECHIDNA_LOG_PATH}" "${ECHIDNA_SUMMARY_PATH}"
popd >/dev/null

echo "Echidna checks passed (seed=${ECHIDNA_SEED}, workers=${ECHIDNA_WORKERS}, log=${ECHIDNA_LOG_PATH})" \
  | tee -a "${ECHIDNA_LOG_PATH}"

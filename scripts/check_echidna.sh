#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT_PATH="test/echidna/PulseTensorCoreEchidna.sol"
CONTRACT_NAME="PulseTensorCoreEchidna"
CONFIG_PATH="test/echidna/echidna.yaml"
OUT_DIR="${ROOT_DIR}/runs/security"
ECHIDNA_LOG_PATH="${OUT_DIR}/echidna.log"
ECHIDNA_SEED="${ECHIDNA_SEED:-1}"
ECHIDNA_WORKERS="${ECHIDNA_WORKERS:-1}"
ECHIDNA_IMAGE="${ECHIDNA_IMAGE:-ghcr.io/crytic/echidna/echidna:latest}"
ECHIDNA_DOCKER_NETWORK="${ECHIDNA_DOCKER_NETWORK:-bridge}"

run_local() {
  echidna "${CONTRACT_PATH}" \
    --contract "${CONTRACT_NAME}" \
    --config "${CONFIG_PATH}" \
    --seed "${ECHIDNA_SEED}" \
    --workers "${ECHIDNA_WORKERS}" \
    | tee "${ECHIDNA_LOG_PATH}"
}

run_docker() {
  docker run --rm \
    --user "$(id -u):$(id -g)" \
    --network "${ECHIDNA_DOCKER_NETWORK}" \
    -v "${ROOT_DIR}:/src" \
    -w /src \
    "${ECHIDNA_IMAGE}" \
      echidna \
      "${CONTRACT_PATH}" \
      --contract "${CONTRACT_NAME}" \
      --config "${CONFIG_PATH}" \
      --seed "${ECHIDNA_SEED}" \
      --workers "${ECHIDNA_WORKERS}" \
      | tee "${ECHIDNA_LOG_PATH}"
}

pushd "${ROOT_DIR}" >/dev/null
mkdir -p "${OUT_DIR}"
if command -v echidna >/dev/null 2>&1; then
  run_local
elif command -v docker >/dev/null 2>&1; then
  run_docker
else
  echo "echidna check requires local echidna binary or docker"
  exit 1
fi
popd >/dev/null

echo "Echidna checks passed (seed=${ECHIDNA_SEED}, workers=${ECHIDNA_WORKERS}, log=${ECHIDNA_LOG_PATH})"

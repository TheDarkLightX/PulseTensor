#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ORCH_DIR="${ROOT_DIR}/external/Orchestration-Unit"
PYTHON_BIN="${ROOT_DIR}/.venv/bin/python"
TASKS_DIR="${TASKS_DIR:-${ROOT_DIR}/runs/orch_tasks_pulsetensor_algo_innovation_swarm_v2}"
PAD_DIR="${PAD_DIR:-${ROOT_DIR}/runs/orch_popperpad_algo_swarm_v2}"
RUN_LABEL="${RUN_LABEL:-pulsetensor_algo_innovation_v2_$(date -u +%Y%m%dT%H%M%S)}"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/runs/orch_swarm_${RUN_LABEL}}"
AGENT_COUNT="${AGENT_COUNT:-6}"
AGENT_TIMEOUT_S="${AGENT_TIMEOUT_S:-7200}"
IDLE_EXIT_S="${IDLE_EXIT_S:-900}"

if [[ ! -d "${ORCH_DIR}" ]]; then
  echo "Orchestration-Unit repo not found at ${ORCH_DIR}"
  exit 1
fi

if [[ ! -d "${TASKS_DIR}" ]]; then
  echo "Tasks directory not found at ${TASKS_DIR}"
  exit 1
fi

if [[ ! -x "${PYTHON_BIN}" ]]; then
  PYTHON_BIN="python3"
fi

mkdir -p "${PAD_DIR}"

echo "Launching swarm"
echo "  tasks: ${TASKS_DIR}"
echo "  out:   ${OUT_DIR}"
echo "  pad:   ${PAD_DIR}"

pushd "${ORCH_DIR}" >/dev/null
"${PYTHON_BIN}" -m orch_unit.cli popperpad-swarm \
  --tasks-dir "${TASKS_DIR}" \
  --pad "${PAD_DIR}" \
  --project-root "${ROOT_DIR}" \
  --out-dir "${OUT_DIR}" \
  --agent-count "${AGENT_COUNT}" \
  --providers codex \
  --mode subprocess \
  --sandbox danger-full-access \
  --agent-timeout-s "${AGENT_TIMEOUT_S}" \
  --max-runtime-s 0 \
  --idle-exit-s "${IDLE_EXIT_S}"
popd >/dev/null

echo "Swarm run complete: ${OUT_DIR}"

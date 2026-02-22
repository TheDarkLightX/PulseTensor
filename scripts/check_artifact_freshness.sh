#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_PATH="${1:-}"
SINCE_EPOCH="${2:-${RUN_START_EPOCH:-0}}"
REPORT_DIR="${ROOT_DIR}/runs/security"

if [[ -z "${MANIFEST_PATH}" ]]; then
  echo "Usage: bash scripts/check_artifact_freshness.sh <manifest-path> [since-epoch]"
  exit 1
fi

if [[ "${MANIFEST_PATH}" != /* ]]; then
  MANIFEST_PATH="${ROOT_DIR}/${MANIFEST_PATH}"
fi

if [[ ! -f "${MANIFEST_PATH}" ]]; then
  echo "Artifact manifest not found: ${MANIFEST_PATH}"
  exit 1
fi

if [[ ! "${SINCE_EPOCH}" =~ ^[0-9]+$ ]]; then
  echo "since-epoch must be an integer unix timestamp"
  exit 1
fi

mkdir -p "${REPORT_DIR}"
REPORT_FILE="${REPORT_DIR}/artifact_freshness_report.txt"

missing=0
stale=0
checked=0

{
  echo "manifest=${MANIFEST_PATH}"
  echo "since_epoch=${SINCE_EPOCH}"
  while IFS= read -r raw_line || [[ -n "${raw_line}" ]]; do
    line="${raw_line}"
    line="${line%%#*}"
    line="$(echo "${line}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    if [[ -z "${line}" ]]; then
      continue
    fi

    checked=$((checked + 1))
    artifact_path="${ROOT_DIR}/${line}"

    if [[ ! -f "${artifact_path}" ]]; then
      missing=$((missing + 1))
      echo "${line}|exists=0|mtime=0|fresh=0"
      continue
    fi

    mtime="$(stat -c %Y "${artifact_path}")"
    if (( mtime < SINCE_EPOCH )); then
      stale=$((stale + 1))
      echo "${line}|exists=1|mtime=${mtime}|fresh=0"
    else
      echo "${line}|exists=1|mtime=${mtime}|fresh=1"
    fi
  done <"${MANIFEST_PATH}"
  echo "checked=${checked}"
  echo "missing=${missing}"
  echo "stale=${stale}"
} >"${REPORT_FILE}"

if (( checked == 0 )); then
  echo "Artifact manifest has no entries: ${MANIFEST_PATH}"
  exit 1
fi

if (( missing > 0 || stale > 0 )); then
  echo "Artifact freshness check failed (missing=${missing}, stale=${stale}; report=${REPORT_FILE})"
  exit 1
fi

echo "Artifact freshness check passed (checked=${checked}; report=${REPORT_FILE})"

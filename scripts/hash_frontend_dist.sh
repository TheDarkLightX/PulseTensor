#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
FRONTEND_DIR="${ROOT_DIR}/frontend"
DIST_DIR="${FRONTEND_DIR}/dist"
OUTPUT_DIR="${1:-${ROOT_DIR}/runs/frontend_release}"

if [[ $# -gt 1 ]]; then
  echo "Usage: bash scripts/hash_frontend_dist.sh [fresh-output-directory]" >&2
  exit 1
fi

source "${ROOT_DIR}/scripts/frontend_release_lib.sh"

ROOT_DIR="$(realpath -e -- "${ROOT_DIR}")"
FRONTEND_DIR="$(realpath -e -- "${FRONTEND_DIR}")"
OUTPUT_DIR="$(frontend_release_claim_output_dir "${ROOT_DIR}" "${FRONTEND_DIR}" "${OUTPUT_DIR}")"
frontend_release_acquire_output_lock "${OUTPUT_DIR}"

WORK_DIR=""
cleanup() {
  local status=$?
  trap - EXIT
  if [[ -n "${WORK_DIR}" ]]; then
    rm -rf -- "${WORK_DIR}"
  fi
  frontend_release_release_output_lock
  exit "${status}"
}
trap cleanup EXIT
WORK_DIR="$(mktemp -d)"

if [[ ! -d "${DIST_DIR}" ]]; then
  frontend_release_fail "frontend dist directory not found: ${DIST_DIR}; run npm --prefix frontend run build"
  exit 1
fi

SNAPSHOT_DIST="${WORK_DIR}/snapshot/dist"
frontend_release_create_dist_snapshot "${DIST_DIR}" "${SNAPSHOT_DIST}"
bash "${ROOT_DIR}/scripts/check_frontend_dist_portable.sh" "${SNAPSHOT_DIST}"
frontend_release_write_hash_evidence "${SNAPSHOT_DIST}" "${OUTPUT_DIR}"
frontend_release_verify_manifest "${SNAPSHOT_DIST}" "${OUTPUT_DIR}/frontend_dist.sha256.txt"

tree_hash="$(frontend_release_read_named_sha256 "${OUTPUT_DIR}/frontend_dist.tree.sha256" frontend_dist.sha256.txt)"
file_count="$(wc -l < "${OUTPUT_DIR}/frontend_dist.sha256.txt" | tr -d ' ')"
total_bytes="$(awk -F '\t' '{sum += $1} END {print sum + 0}' "${OUTPUT_DIR}/frontend_dist.stats.tsv")"

echo "Frontend artifact hash manifest written from one private snapshot:"
echo "  manifest: ${OUTPUT_DIR}/frontend_dist.sha256.txt"
echo "  tree-hash: ${OUTPUT_DIR}/frontend_dist.tree.sha256"
echo "  stats: ${OUTPUT_DIR}/frontend_dist.stats.tsv"
echo "FRONTEND_DIST_TREE_SHA256=${tree_hash}"
echo "FRONTEND_DIST_FILE_COUNT=${file_count}"
echo "FRONTEND_DIST_TOTAL_BYTES=${total_bytes}"

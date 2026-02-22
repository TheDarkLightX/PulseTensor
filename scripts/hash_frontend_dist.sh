#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/frontend/dist"
OUTPUT_DIR="${1:-${ROOT_DIR}/runs/frontend_release}"

if [[ ! -d "${DIST_DIR}" ]]; then
  echo "Frontend dist directory not found: ${DIST_DIR}"
  echo "Run: npm --prefix frontend run build"
  exit 1
fi

mkdir -p "${OUTPUT_DIR}"

MANIFEST_FILE="${OUTPUT_DIR}/frontend_dist.sha256.txt"
TREE_HASH_FILE="${OUTPUT_DIR}/frontend_dist.tree.sha256"
STATS_FILE="${OUTPUT_DIR}/frontend_dist.stats.tsv"

manifest_tmp="$(mktemp)"
stats_tmp="$(mktemp)"
trap 'rm -f "${manifest_tmp}" "${stats_tmp}"' EXIT

while IFS= read -r -d '' artifact_file; do
  rel_path="${artifact_file#${DIST_DIR}/}"
  artifact_hash="$(sha256sum "${artifact_file}" | awk '{print $1}')"
  artifact_size="$(stat -c %s "${artifact_file}")"

  printf '%s  %s\n' "${artifact_hash}" "${rel_path}" >> "${manifest_tmp}"
  printf '%s\t%s\n' "${artifact_size}" "${rel_path}" >> "${stats_tmp}"
done < <(find "${DIST_DIR}" -type f -print0 | LC_ALL=C sort -z)

if [[ ! -s "${manifest_tmp}" ]]; then
  echo "No frontend artifacts found under: ${DIST_DIR}"
  exit 1
fi

mv "${manifest_tmp}" "${MANIFEST_FILE}"
sort -n "${stats_tmp}" > "${STATS_FILE}"

tree_hash="$(sha256sum "${MANIFEST_FILE}" | awk '{print $1}')"
printf '%s  frontend_dist.sha256.txt\n' "${tree_hash}" > "${TREE_HASH_FILE}"

file_count="$(wc -l < "${MANIFEST_FILE}" | tr -d ' ')"
total_bytes="$(awk -F '\t' '{sum += $1} END {print sum + 0}' "${STATS_FILE}")"

echo "Frontend artifact hash manifest written:"
echo "  manifest: ${MANIFEST_FILE}"
echo "  tree-hash: ${TREE_HASH_FILE}"
echo "  stats: ${STATS_FILE}"
echo "FRONTEND_DIST_TREE_SHA256=${tree_hash}"
echo "FRONTEND_DIST_FILE_COUNT=${file_count}"
echo "FRONTEND_DIST_TOTAL_BYTES=${total_bytes}"

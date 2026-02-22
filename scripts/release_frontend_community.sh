#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${ROOT_DIR}/runs/frontend_release"
SKIP_BUILD=0

usage() {
  cat <<'EOF'
Usage: bash scripts/release_frontend_community.sh [--skip-build] [--out-dir <path>]

Builds and packages a deterministic frontend release kit:
  - frontend/dist build
  - sorted per-file sha256 manifest
  - tree hash over manifest
  - deterministic tarball + sha256
  - machine-readable release receipt
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    --out-dir)
      if [[ $# -lt 2 ]]; then
        echo "--out-dir requires a value"
        exit 1
      fi
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

mkdir -p "${OUTPUT_DIR}"

if [[ "${SKIP_BUILD}" != "1" ]]; then
  npm --prefix "${ROOT_DIR}/frontend" ci
  npm --prefix "${ROOT_DIR}/frontend" run build
fi

bash "${ROOT_DIR}/scripts/hash_frontend_dist.sh" "${OUTPUT_DIR}"

DIST_TARBALL="${OUTPUT_DIR}/frontend_dist.tar.gz"
DIST_TARBALL_SHA_FILE="${OUTPUT_DIR}/frontend_dist.tar.gz.sha256"
RECEIPT_JSON="${OUTPUT_DIR}/frontend_release_receipt.json"

tar \
  --sort=name \
  --owner=0 \
  --group=0 \
  --numeric-owner \
  --mtime='UTC 1970-01-01' \
  -czf "${DIST_TARBALL}" \
  -C "${ROOT_DIR}/frontend" \
  dist

dist_tarball_sha256="$(sha256sum "${DIST_TARBALL}" | awk '{print $1}')"
printf '%s  %s\n' "${dist_tarball_sha256}" "frontend_dist.tar.gz" > "${DIST_TARBALL_SHA_FILE}"

manifest_file="${OUTPUT_DIR}/frontend_dist.sha256.txt"
tree_hash_file="${OUTPUT_DIR}/frontend_dist.tree.sha256"
tree_sha256="$(awk 'NR==1 {print $1}' "${tree_hash_file}")"
file_count="$(wc -l < "${manifest_file}" | tr -d ' ')"
total_bytes="$(awk -F '\t' '{sum += $1} END {print sum + 0}' "${OUTPUT_DIR}/frontend_dist.stats.tsv")"
generated_at_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat > "${RECEIPT_JSON}" <<EOF
{
  "generated_at_utc": "${generated_at_utc}",
  "frontend_dist_tree_sha256": "${tree_sha256}",
  "frontend_dist_file_count": ${file_count},
  "frontend_dist_total_bytes": ${total_bytes},
  "frontend_dist_tarball_sha256": "${dist_tarball_sha256}",
  "artifacts": {
    "manifest": "frontend_dist.sha256.txt",
    "tree_hash": "frontend_dist.tree.sha256",
    "stats": "frontend_dist.stats.tsv",
    "tarball": "frontend_dist.tar.gz",
    "tarball_sha256": "frontend_dist.tar.gz.sha256"
  }
}
EOF

echo "Frontend community release kit generated:"
echo "  output_dir: ${OUTPUT_DIR}"
echo "  tree_sha256: ${tree_sha256}"
echo "  tarball_sha256: ${dist_tarball_sha256}"
echo "  receipt: ${RECEIPT_JSON}"

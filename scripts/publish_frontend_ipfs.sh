#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${ROOT_DIR}/runs/frontend_release"
SKIP_BUILD=0

usage() {
  cat <<'EOF'
Usage: bash scripts/publish_frontend_ipfs.sh [--skip-build] [--out-dir <path>]

Generates the frontend release kit and publishes artifacts to IPFS:
  - Publishes frontend/dist directory (root CID)
  - Publishes frontend_dist.tar.gz (tarball CID)
  - Writes IPFS publish receipt with CIDs + hashes
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

if ! command -v ipfs >/dev/null 2>&1; then
  echo "ipfs CLI not found. Install Kubo/IPFS first."
  echo "You can still prepare release artifacts with:"
  echo "  bash scripts/release_frontend_community.sh"
  exit 1
fi

release_args=(--out-dir "${OUTPUT_DIR}")
if [[ "${SKIP_BUILD}" == "1" ]]; then
  release_args=(--skip-build --out-dir "${OUTPUT_DIR}")
fi
bash "${ROOT_DIR}/scripts/release_frontend_community.sh" "${release_args[@]}"

DIST_DIR="${ROOT_DIR}/frontend/dist"
TARBALL_PATH="${OUTPUT_DIR}/frontend_dist.tar.gz"
RECEIPT_JSON="${OUTPUT_DIR}/frontend_ipfs_publish_receipt.json"
RECEIPT_TXT="${OUTPUT_DIR}/frontend_ipfs_publish_receipt.txt"

if [[ ! -d "${DIST_DIR}" ]]; then
  echo "Missing dist directory: ${DIST_DIR}"
  exit 1
fi
if [[ ! -f "${TARBALL_PATH}" ]]; then
  echo "Missing tarball: ${TARBALL_PATH}"
  exit 1
fi

add_help="$(ipfs add --help 2>&1 || true)"
add_args=(add -r -Q --cid-version=1 --raw-leaves=true --hash=sha2-256 --chunker=size-262144 --pin=true)
if grep -q -- "--preserve-mode" <<<"${add_help}"; then
  add_args+=(--preserve-mode=false)
fi
if grep -q -- "--preserve-mtime" <<<"${add_help}"; then
  add_args+=(--preserve-mtime=false)
fi

dist_cid="$(ipfs "${add_args[@]}" "${DIST_DIR}")"
tarball_cid="$(ipfs add -Q --cid-version=1 --hash=sha2-256 --pin=true "${TARBALL_PATH}")"

tree_sha256="$(awk 'NR==1 {print $1}' "${OUTPUT_DIR}/frontend_dist.tree.sha256")"
tarball_sha256="$(awk 'NR==1 {print $1}' "${OUTPUT_DIR}/frontend_dist.tar.gz.sha256")"
generated_at_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat > "${RECEIPT_JSON}" <<EOF
{
  "generated_at_utc": "${generated_at_utc}",
  "frontend_dist_tree_sha256": "${tree_sha256}",
  "frontend_dist_tarball_sha256": "${tarball_sha256}",
  "ipfs": {
    "dist_root_cid": "${dist_cid}",
    "tarball_cid": "${tarball_cid}",
    "dist_gateway_url": "https://ipfs.io/ipfs/${dist_cid}",
    "tarball_gateway_url": "https://ipfs.io/ipfs/${tarball_cid}"
  }
}
EOF

cat > "${RECEIPT_TXT}" <<EOF
PulseTensor Frontend IPFS Publish Receipt
generated_at_utc: ${generated_at_utc}

frontend_dist_tree_sha256: ${tree_sha256}
frontend_dist_tarball_sha256: ${tarball_sha256}

dist_root_cid: ${dist_cid}
tarball_cid: ${tarball_cid}

dist_gateway_url: https://ipfs.io/ipfs/${dist_cid}
tarball_gateway_url: https://ipfs.io/ipfs/${tarball_cid}
EOF

echo "Frontend published to IPFS:"
echo "  dist_root_cid: ${dist_cid}"
echo "  tarball_cid: ${tarball_cid}"
echo "  receipt_json: ${RECEIPT_JSON}"
echo "  receipt_txt: ${RECEIPT_TXT}"

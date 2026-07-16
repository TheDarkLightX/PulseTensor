#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
FRONTEND_DIR="${ROOT_DIR}/frontend"
OUTPUT_DIR="${ROOT_DIR}/runs/frontend_release"
SKIP_BUILD=0
SUBDOMAIN_GATEWAY_SUFFIX="${IPFS_SUBDOMAIN_GATEWAY_SUFFIX:-ipfs.dweb.link}"

source "${ROOT_DIR}/scripts/frontend_release_lib.sh"

usage() {
  cat <<'EOF'
Usage: bash scripts/publish_frontend_ipfs.sh [--skip-build] [--out-dir <path>]

Generates a frontend release kit and publishes artifacts derived from its one
verified snapshot to IPFS. It independently parses returned CIDs, reads the
tarball back by CID, retrieves the directory by CID, and verifies both.
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

ROOT_DIR="$(realpath -e -- "${ROOT_DIR}")"
FRONTEND_DIR="$(realpath -e -- "${FRONTEND_DIR}")"

if ! command -v ipfs >/dev/null 2>&1; then
  echo "ipfs CLI not found. Install Kubo/IPFS first."
  echo "You can still prepare release artifacts with:"
  echo "  bash scripts/release_frontend_community.sh"
  exit 1
fi

validate_gateway_suffix() {
  local suffix label
  suffix="$1"
  if [[ ${#suffix} -gt 253 || "${suffix}" != *.* || "${suffix}" == .* || "${suffix}" == *. || "${suffix}" == *..* ]]; then
    return 1
  fi
  IFS='.' read -r -a labels <<<"${suffix}"
  for label in "${labels[@]}"; do
    if [[ ${#label} -lt 1 || ${#label} -gt 63 || ! "${label}" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]]; then
      return 1
    fi
  done
}

if ! validate_gateway_suffix "${SUBDOMAIN_GATEWAY_SUFFIX}"; then
  echo "IPFS_SUBDOMAIN_GATEWAY_SUFFIX must be a canonical DNS suffix without a scheme, path, port, or credentials."
  exit 1
fi

release_args=(--out-dir "${OUTPUT_DIR}")
if [[ "${SKIP_BUILD}" == "1" ]]; then
  release_args=(--skip-build --out-dir "${OUTPUT_DIR}")
fi
bash "${ROOT_DIR}/scripts/release_frontend_community.sh" "${release_args[@]}"

OUTPUT_DIR="$(frontend_release_assert_output_dir "${ROOT_DIR}" "${FRONTEND_DIR}" "${OUTPUT_DIR}")"
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

TARBALL_PATH="${OUTPUT_DIR}/frontend_dist.tar.gz"
MANIFEST_PATH="${OUTPUT_DIR}/frontend_dist.sha256.txt"
RELEASE_RECEIPT_PATH="${OUTPUT_DIR}/frontend_release_receipt.json"
RECEIPT_JSON="${OUTPUT_DIR}/frontend_ipfs_publish_receipt.json"
RECEIPT_TXT="${OUTPUT_DIR}/frontend_ipfs_publish_receipt.txt"

tarball_sha256="$(frontend_release_read_named_sha256 "${OUTPUT_DIR}/frontend_dist.tar.gz.sha256" frontend_dist.tar.gz)"
actual_tarball_sha256="$(sha256sum "${TARBALL_PATH}" | awk '{print $1}')"
if [[ "${actual_tarball_sha256}" != "${tarball_sha256}" ]]; then
  frontend_release_fail "release tarball does not match its checksum file"
  exit 1
fi
tree_sha256="$(frontend_release_read_named_sha256 "${OUTPUT_DIR}/frontend_dist.tree.sha256" frontend_dist.sha256.txt)"
[[ -f "${RELEASE_RECEIPT_PATH}" && ! -L "${RELEASE_RECEIPT_PATH}" ]] || {
  frontend_release_fail "release receipt is missing or unsafe"
  exit 1
}
release_receipt_sha256="$(sha256sum "${RELEASE_RECEIPT_PATH}" | awk '{print $1}')"
node - "${RELEASE_RECEIPT_PATH}" "${tree_sha256}" "${tarball_sha256}" <<'NODE'
const { readFileSync } = require("node:fs");
const [receiptPath, treeSha256, tarballSha256] = process.argv.slice(2);
const receipt = JSON.parse(readFileSync(receiptPath, "utf8"));
if (receipt.schema !== "pulsetensor/frontend-release-receipt/v2" ||
    receipt.status !== "candidate-release-kit" ||
    receipt.artifacts?.frontend_dist_tree_sha256 !== treeSha256 ||
    receipt.artifacts?.frontend_dist_tarball_sha256 !== tarballSha256) {
  throw new Error("release receipt does not bind the manifest and tarball selected for IPFS publication");
}
NODE

PUBLISH_DIST="${WORK_DIR}/release-snapshot/dist"
frontend_release_extract_verified_tar "${TARBALL_PATH}" "${MANIFEST_PATH}" "${WORK_DIR}/release-snapshot"

add_help="$(ipfs add --help 2>&1 || true)"
directory_add_args=(add -r -Q --cid-version=1 --raw-leaves=true --hash=sha2-256 --chunker=size-262144 --pin=true)
file_add_args=(add -Q --cid-version=1 --raw-leaves=true --hash=sha2-256 --chunker=size-262144 --pin=true)
preserve_mode_setting="default-false"
preserve_mtime_setting="default-false"
if grep -q -- "--preserve-mode" <<<"${add_help}"; then
  directory_add_args+=(--preserve-mode=false)
  file_add_args+=(--preserve-mode=false)
  preserve_mode_setting="explicit-false"
fi
if grep -q -- "--preserve-mtime" <<<"${add_help}"; then
  directory_add_args+=(--preserve-mtime=false)
  file_add_args+=(--preserve-mtime=false)
  preserve_mtime_setting="explicit-false"
fi

dist_cid="$(ipfs "${directory_add_args[@]}" "${PUBLISH_DIST}")"
tarball_cid="$(ipfs "${file_add_args[@]}" "${TARBALL_PATH}")"
node "${ROOT_DIR}/scripts/validate_ipfs_cid.mjs" --kind directory --cid "${dist_cid}" >/dev/null
node "${ROOT_DIR}/scripts/validate_ipfs_cid.mjs" --kind file --cid "${tarball_cid}" >/dev/null

retrieved_tarball="${WORK_DIR}/retrieved-frontend-dist.tar.gz"
ipfs cat "${tarball_cid}" > "${retrieved_tarball}"
retrieved_tarball_sha256="$(sha256sum "${retrieved_tarball}" | awk '{print $1}')"
if [[ "${retrieved_tarball_sha256}" != "${tarball_sha256}" ]]; then
  frontend_release_fail "tarball read back from Kubo does not match the release SHA-256"
  exit 1
fi

retrieved_dist="${WORK_DIR}/retrieved-dist"
ipfs get --progress=false -o "${retrieved_dist}" "${dist_cid}" >/dev/null
frontend_release_assert_safe_dist "${retrieved_dist}"
frontend_release_verify_manifest "${retrieved_dist}" "${MANIFEST_PATH}"

kubo_version="$(ipfs version --number 2>/dev/null || ipfs version | awk 'NR==1 {print $NF}')"
if [[ ! "${kubo_version}" =~ ^[0-9A-Za-z.+-]+$ ]]; then
  frontend_release_fail "IPFS returned an unsafe version string"
  exit 1
fi
generated_at_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
dist_gateway_url="https://${dist_cid}.${SUBDOMAIN_GATEWAY_SUFFIX}/"
tarball_gateway_url="https://${tarball_cid}.${SUBDOMAIN_GATEWAY_SUFFIX}/"

receipt_json_content="$(cat <<EOF
{
  "schema": "pulsetensor/frontend-ipfs-publish-receipt/v2",
  "status": "candidate-publication-receipt",
  "generated_at_utc": "${generated_at_utc}",
  "publication_source": "verified-extraction-of-release-tarball",
  "frontend_dist_tree_sha256": "${tree_sha256}",
  "frontend_dist_tarball_sha256": "${tarball_sha256}",
  "frontend_release_receipt_sha256": "${release_receipt_sha256}",
  "ipfs": {
    "kubo_version": "${kubo_version}",
    "cid_version": 1,
    "hash": "sha2-256",
    "raw_leaves": true,
    "chunker": "size-262144",
    "preserve_mode": "${preserve_mode_setting}",
    "preserve_mtime": "${preserve_mtime_setting}",
    "dist_root_cid": "${dist_cid}",
    "tarball_cid": "${tarball_cid}",
    "independent_cid_decode": true,
    "tarball_readback_sha256_verified": true,
    "directory_readback_manifest_verified": true,
    "origin_isolation": "cid-subdomain",
    "dist_gateway_url": "${dist_gateway_url}",
    "tarball_gateway_url": "${tarball_gateway_url}"
  },
  "warning": "This candidate receipt is not a signature or durability guarantee; independently authenticate and pin the CIDs."
}
EOF
)"
frontend_release_write_text_exclusive "${RECEIPT_JSON}" 0644 "${receipt_json_content}"$'\n'

receipt_text_content="$(cat <<EOF
PulseTensor Frontend IPFS Candidate Publish Receipt
generated_at_utc: ${generated_at_utc}
publication_source: verified-extraction-of-release-tarball

frontend_dist_tree_sha256: ${tree_sha256}
frontend_dist_tarball_sha256: ${tarball_sha256}
frontend_release_receipt_sha256: ${release_receipt_sha256}

kubo_version: ${kubo_version}
cid_version: 1
hash: sha2-256
raw_leaves: true
chunker: size-262144
preserve_mode: ${preserve_mode_setting}
preserve_mtime: ${preserve_mtime_setting}

dist_root_cid: ${dist_cid}
tarball_cid: ${tarball_cid}
independent_cid_decode: true
tarball_readback_sha256_verified: true
directory_readback_manifest_verified: true

origin_isolation: cid-subdomain
dist_gateway_url: ${dist_gateway_url}
tarball_gateway_url: ${tarball_gateway_url}
EOF
)"
frontend_release_write_text_exclusive "${RECEIPT_TXT}" 0644 "${receipt_text_content}"$'\n'

echo "Frontend published to IPFS from the verified release snapshot:"
echo "  dist_root_cid: ${dist_cid}"
echo "  tarball_cid: ${tarball_cid}"
echo "  tarball_readback: verified"
echo "  directory_readback: verified"
echo "  receipt_json: ${RECEIPT_JSON}"
echo "  receipt_txt: ${RECEIPT_TXT}"

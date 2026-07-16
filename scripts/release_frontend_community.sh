#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
FRONTEND_DIR="${ROOT_DIR}/frontend"
DIST_DIR="${FRONTEND_DIR}/dist"
OUTPUT_DIR="${ROOT_DIR}/runs/frontend_release"
SKIP_BUILD=0

source "${ROOT_DIR}/scripts/frontend_release_lib.sh"

usage() {
  cat <<'EOF'
Usage: bash scripts/release_frontend_community.sh [--skip-build] [--out-dir <path>]

Builds and packages a frontend release kit from one private dist snapshot:
  - optional fresh frontend/dist build with validated, frozen public inputs
  - sorted per-file SHA-256 manifest and tree hash from the snapshot
  - deterministic tarball from that same snapshot
  - machine-readable candidate release receipt

--skip-build packages an existing dist but deliberately records its build inputs,
source, and build toolchain as unknown. It does not infer them from the current shell.
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
BUILD_INPUTS_FILE="${WORK_DIR}/build-inputs.json"

release_tooling_hash() {
  frontend_release_hash_named_files \
    "${ROOT_DIR}" \
    Makefile \
    .github/workflows/frontend-assurance.yml \
    scripts/frontend_release_lib.sh \
    scripts/capture_frontend_build_inputs.mjs \
    scripts/validate_ipfs_cid.mjs \
    scripts/hash_frontend_dist.sh \
    scripts/check_frontend_dist_portable.sh \
    scripts/check_frontend_reproducible.sh \
    scripts/release_frontend_community.sh \
    scripts/publish_frontend_ipfs.sh \
    scripts/test_frontend_release_hardening.sh \
    scripts/write_frontend_release_receipt.mjs
}

if [[ "${SKIP_BUILD}" != "1" ]]; then
  npm --prefix "${FRONTEND_DIR}" ci
  node "${ROOT_DIR}/scripts/capture_frontend_build_inputs.mjs" \
    --frontend-dir "${FRONTEND_DIR}" \
    --output "${BUILD_INPUTS_FILE}" \
    --mode fresh-build

  read_build_input() {
    node -e 'const r=require(process.argv[1]); process.stdout.write(r.public_vite_inputs[process.argv[2]])' "$1" "$2"
  }
  frozen_core_address="$(read_build_input "${BUILD_INPUTS_FILE}" VITE_DEFAULT_CORE_ADDRESS)"
  frozen_settlement_address="$(read_build_input "${BUILD_INPUTS_FILE}" VITE_DEFAULT_SETTLEMENT_ADDRESS)"
  frozen_manifest_sha256="$(read_build_input "${BUILD_INPUTS_FILE}" VITE_EXACT_MANIFEST_SHA256)"
  frozen_manifest_url="$(read_build_input "${BUILD_INPUTS_FILE}" VITE_EXACT_MANIFEST_URL)"

  frontend_source_tree_sha256="$(frontend_release_hash_source_tree "${FRONTEND_DIR}")"
  release_tooling_sha256="$(release_tooling_hash)"
  env \
    VITE_DEFAULT_CORE_ADDRESS="${frozen_core_address}" \
    VITE_DEFAULT_SETTLEMENT_ADDRESS="${frozen_settlement_address}" \
    VITE_EXACT_MANIFEST_SHA256="${frozen_manifest_sha256}" \
    VITE_EXACT_MANIFEST_URL="${frozen_manifest_url}" \
    npm --prefix "${FRONTEND_DIR}" run build

  source_hash_after_build="$(frontend_release_hash_source_tree "${FRONTEND_DIR}")"
  tooling_hash_after_build="$(release_tooling_hash)"
  if [[ "${source_hash_after_build}" != "${frontend_source_tree_sha256}" ]]; then
    frontend_release_fail "frontend source changed while the fresh build was running"
    exit 1
  fi
  if [[ "${tooling_hash_after_build}" != "${release_tooling_sha256}" ]]; then
    frontend_release_fail "release or assurance tooling changed while the fresh build was running"
    exit 1
  fi
  build_mode="fresh-build"
  source_stability="matched-before-and-after-build"
  vite_version="$(node -e 'const {createRequire}=require("node:module"); const r=createRequire(process.argv[1]+"/package.json"); process.stdout.write(require(r.resolve("vite/package.json")).version)' "${FRONTEND_DIR}")"
else
  node "${ROOT_DIR}/scripts/capture_frontend_build_inputs.mjs" \
    --frontend-dir "${FRONTEND_DIR}" \
    --output "${BUILD_INPUTS_FILE}" \
    --mode prebuilt-unknown
  frontend_source_tree_sha256="$(frontend_release_hash_source_tree "${FRONTEND_DIR}")"
  release_tooling_sha256="$(release_tooling_hash)"
  build_mode="prebuilt-dist"
  source_stability="captured-at-packaging-only"
  vite_version="not-used-for-prebuilt-packaging"
fi

if [[ ! -d "${DIST_DIR}" ]]; then
  frontend_release_fail "frontend dist directory not found: ${DIST_DIR}"
  exit 1
fi

SNAPSHOT_DIST="${WORK_DIR}/snapshot/dist"
frontend_release_create_dist_snapshot "${DIST_DIR}" "${SNAPSHOT_DIST}"
bash "${ROOT_DIR}/scripts/check_frontend_dist_portable.sh" "${SNAPSHOT_DIST}"
frontend_release_write_hash_evidence "${SNAPSHOT_DIST}" "${OUTPUT_DIR}"

DIST_TARBALL="${OUTPUT_DIR}/frontend_dist.tar.gz"
DIST_TARBALL_SHA_FILE="${OUTPUT_DIR}/frontend_dist.tar.gz.sha256"
RECEIPT_JSON="${OUTPUT_DIR}/frontend_release_receipt.json"
frontend_release_write_deterministic_tar "${SNAPSHOT_DIST}" "${DIST_TARBALL}"
frontend_release_extract_verified_tar \
  "${DIST_TARBALL}" \
  "${OUTPUT_DIR}/frontend_dist.sha256.txt" \
  "${WORK_DIR}/archive-self-check"

dist_tarball_sha256="$(sha256sum "${DIST_TARBALL}" | awk '{print $1}')"
frontend_release_write_text_exclusive \
  "${DIST_TARBALL_SHA_FILE}" \
  0644 \
  "${dist_tarball_sha256}  frontend_dist.tar.gz"$'\n'

manifest_file="${OUTPUT_DIR}/frontend_dist.sha256.txt"
tree_hash_file="${OUTPUT_DIR}/frontend_dist.tree.sha256"
tree_sha256="$(frontend_release_read_named_sha256 "${tree_hash_file}" frontend_dist.sha256.txt)"
file_count="$(wc -l < "${manifest_file}" | tr -d ' ')"
total_bytes="$(awk -F '\t' '{sum += $1} END {print sum + 0}' "${OUTPUT_DIR}/frontend_dist.stats.tsv")"
generated_at_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
git_commit="$(git -C "${ROOT_DIR}" rev-parse --verify HEAD)"
if [[ -n "$(git -C "${ROOT_DIR}" status --porcelain --untracked-files=all)" ]]; then
  git_tree_state="dirty"
else
  git_tree_state="clean"
fi

for provenance_file in package.json package-lock.json vite.config.ts; do
  if [[ ! -f "${FRONTEND_DIR}/${provenance_file}" || -L "${FRONTEND_DIR}/${provenance_file}" ]]; then
    frontend_release_fail "packaging provenance file is missing or unsafe: frontend/${provenance_file}"
    exit 1
  fi
done
package_json_sha256="$(sha256sum "${FRONTEND_DIR}/package.json" | awk '{print $1}')"
package_lock_sha256="$(sha256sum "${FRONTEND_DIR}/package-lock.json" | awk '{print $1}')"
vite_config_sha256="$(sha256sum "${FRONTEND_DIR}/vite.config.ts" | awk '{print $1}')"
node_version="$(node --version)"
npm_version="$(npm --version)"
tar_version="$(tar --version | sed -n '1p')"
gzip_version="$(gzip --version | sed -n '1p')"
assurance_context="${PULSETENSOR_FRONTEND_ASSURANCE_CONTEXT:-not-run-by-release-script}"

node "${ROOT_DIR}/scripts/write_frontend_release_receipt.mjs" \
  --output "${RECEIPT_JSON}" \
  --build-inputs-file "${BUILD_INPUTS_FILE}" \
  --generated-at-utc "${generated_at_utc}" \
  --git-commit "${git_commit}" \
  --git-tree-state "${git_tree_state}" \
  --frontend-source-tree-sha256 "${frontend_source_tree_sha256}" \
  --release-tooling-sha256 "${release_tooling_sha256}" \
  --package-json-sha256 "${package_json_sha256}" \
  --package-lock-sha256 "${package_lock_sha256}" \
  --vite-config-sha256 "${vite_config_sha256}" \
  --build-mode "${build_mode}" \
  --source-stability "${source_stability}" \
  --assurance-context "${assurance_context}" \
  --node-version "${node_version}" \
  --npm-version "${npm_version}" \
  --vite-version "${vite_version}" \
  --tar-version "${tar_version}" \
  --gzip-version "${gzip_version}" \
  --tree-sha256 "${tree_sha256}" \
  --file-count "${file_count}" \
  --total-bytes "${total_bytes}" \
  --tarball-sha256 "${dist_tarball_sha256}"

echo "Frontend community release kit generated:"
echo "  output_dir: ${OUTPUT_DIR}"
echo "  snapshot_source: single private validated dist snapshot"
echo "  tree_sha256: ${tree_sha256}"
echo "  tarball_sha256: ${dist_tarball_sha256}"
echo "  receipt: ${RECEIPT_JSON}"

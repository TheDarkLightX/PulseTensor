#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "${ROOT_DIR}/scripts/frontend_release_lib.sh"

TMP_DIR="$(mktemp -d)"
DEFAULT_PATH_FIXTURE="${ROOT_DIR}/runs/frontend_release_claim_test_$$"
cleanup_test() {
  rm -rf -- "${TMP_DIR}" "${DEFAULT_PATH_FIXTURE}"
}
trap cleanup_test EXIT

fail() {
  printf 'frontend release regression: %s\n' "$*" >&2
  exit 1
}

expect_failure() {
  if "$@" >"${TMP_DIR}/unexpected.stdout" 2>"${TMP_DIR}/unexpected.stderr"; then
    fail "command unexpectedly succeeded: $*"
  fi
}

FAKE_ROOT="${TMP_DIR}/repo"
FAKE_FRONTEND="${FAKE_ROOT}/frontend"
mkdir -p "${FAKE_FRONTEND}/dist" "${FAKE_FRONTEND}/src"

safe_output="$(frontend_release_claim_output_dir \
  "${FAKE_ROOT}" \
  "${FAKE_FRONTEND}" \
  "${FAKE_ROOT}/runs/release-a"
)"
[[ "${safe_output}" == "${FAKE_ROOT}/runs/release-a" ]] || fail "safe output was not canonicalized"
[[ "$(stat -c %a "${safe_output}")" == "700" ]] || fail "claimed output mode is not 0700"
[[ "$(stat -c %u "${safe_output}")" == "$(id -u)" ]] || fail "claimed output owner is wrong"
expect_failure frontend_release_claim_output_dir "${FAKE_ROOT}" "${FAKE_FRONTEND}" "${safe_output}"

# Exercise the repository-default ancestry. This workspace intentionally has a
# world-writable ancestor above a current-user 0700 trust boundary.
default_claim="$(frontend_release_claim_output_dir "${ROOT_DIR}" "${ROOT_DIR}/frontend" "${DEFAULT_PATH_FIXTURE}")"
[[ "${default_claim}" == "${DEFAULT_PATH_FIXTURE}" ]] || fail "default-path claim failed"
frontend_release_acquire_output_lock "${default_claim}"
expect_failure frontend_release_acquire_output_lock "${default_claim}"
frontend_release_release_output_lock
[[ ! -e "${default_claim}/.frontend-release.lock" ]] || fail "output lock was not cleaned up"

expect_failure \
  frontend_release_claim_output_dir \
  "${FAKE_ROOT}" \
  "${FAKE_FRONTEND}" \
  "${FAKE_FRONTEND}/dist/release"

mkdir -p "${TMP_DIR}/safe-target"
ln -s "${TMP_DIR}/safe-target" "${TMP_DIR}/linked-output"
expect_failure \
  frontend_release_claim_output_dir \
  "${FAKE_ROOT}" \
  "${FAKE_FRONTEND}" \
  "${TMP_DIR}/linked-output"

ln -s "${FAKE_FRONTEND}" "${TMP_DIR}/linked-parent"
expect_failure \
  frontend_release_claim_output_dir \
  "${FAKE_ROOT}" \
  "${FAKE_FRONTEND}" \
  "${TMP_DIR}/linked-parent/dist/release"

printf 'not-a-directory\n' > "${TMP_DIR}/output-file"
expect_failure \
  frontend_release_claim_output_dir \
  "${FAKE_ROOT}" \
  "${FAKE_FRONTEND}" \
  "${TMP_DIR}/output-file"

mkdir "${TMP_DIR}/shared-output"
chmod 0777 "${TMP_DIR}/shared-output"
expect_failure \
  frontend_release_assert_output_dir \
  "${FAKE_ROOT}" \
  "${FAKE_FRONTEND}" \
  "${TMP_DIR}/shared-output"

unsafe_dist="${TMP_DIR}/unsafe-dist"
mkdir -p "${unsafe_dist}"
ln -s /etc/passwd "${unsafe_dist}/linked-artifact"
expect_failure frontend_release_assert_safe_dist "${unsafe_dist}"
rm -f "${unsafe_dist}/linked-artifact"
printf 'bad\n' > "${unsafe_dist}/bad"$'\n'"name"
expect_failure frontend_release_assert_safe_dist "${unsafe_dist}"
rm -f "${unsafe_dist}/bad"$'\n'"name"
printf 'bad\n' > "${unsafe_dist}/bad\\name"
expect_failure frontend_release_assert_safe_dist "${unsafe_dist}"

printf 'outside version 1\n' > "${TMP_DIR}/outside.ts"
ln -s "${TMP_DIR}/outside.ts" "${FAKE_FRONTEND}/src/input.ts"
expect_failure frontend_release_assert_safe_source_tree "${FAKE_FRONTEND}"
expect_failure frontend_release_hash_source_tree "${FAKE_FRONTEND}"
rm -f "${FAKE_FRONTEND}/src/input.ts"

DIST_A="${TMP_DIR}/mode-a/dist"
DIST_B="${TMP_DIR}/mode-b/dist"
mkdir -p "${DIST_A}/assets" "${DIST_B}/assets"
printf '<!doctype html><script type="module" src="./assets/app.js"></script>\n' > "${DIST_A}/index.html"
printf 'console.log("deterministic");\n' > "${DIST_A}/assets/app.js"
cp "${DIST_A}/index.html" "${DIST_B}/index.html"
cp "${DIST_A}/assets/app.js" "${DIST_B}/assets/app.js"
chmod 0755 "${DIST_A}" "${DIST_A}/assets"
chmod 0644 "${DIST_A}/index.html" "${DIST_A}/assets/app.js"
chmod 0700 "${DIST_B}" "${DIST_B}/assets"
chmod 0600 "${DIST_B}/index.html" "${DIST_B}/assets/app.js"

SNAPSHOT_A="${TMP_DIR}/snapshot-a/dist"
SNAPSHOT_B="${TMP_DIR}/snapshot-b/dist"
frontend_release_create_dist_snapshot "${DIST_A}" "${SNAPSHOT_A}"
frontend_release_create_dist_snapshot "${DIST_B}" "${SNAPSHOT_B}"
[[ "$(stat -c %a "${SNAPSHOT_B}")" == "755" ]] || fail "snapshot directory mode is not 0755"
[[ "$(stat -c %a "${SNAPSHOT_B}/index.html")" == "644" ]] || fail "snapshot file mode is not 0644"

snapshot_manifest_before="${TMP_DIR}/snapshot-before.manifest"
snapshot_stats_before="${TMP_DIR}/snapshot-before.stats"
snapshot_manifest_after="${TMP_DIR}/snapshot-after.manifest"
snapshot_stats_after="${TMP_DIR}/snapshot-after.stats"
frontend_release_compute_manifest "${SNAPSHOT_A}" "${snapshot_manifest_before}" "${snapshot_stats_before}"
printf 'live dist changed after snapshot\n' > "${DIST_A}/assets/app.js"
frontend_release_compute_manifest "${SNAPSHOT_A}" "${snapshot_manifest_after}" "${snapshot_stats_after}"
cmp "${snapshot_manifest_before}" "${snapshot_manifest_after}" || fail "private snapshot followed a live-dist mutation"

HASH_OUTPUT="$(frontend_release_claim_output_dir "${FAKE_ROOT}" "${FAKE_FRONTEND}" "${TMP_DIR}/hash-output")"
frontend_release_acquire_output_lock "${HASH_OUTPUT}"
frontend_release_write_hash_evidence "${SNAPSHOT_A}" "${HASH_OUTPUT}"
frontend_release_verify_manifest "${SNAPSHOT_A}" "${HASH_OUTPUT}/frontend_dist.sha256.txt"
frontend_release_release_output_lock
for evidence_file in frontend_dist.sha256.txt frontend_dist.stats.tsv frontend_dist.tree.sha256; do
  [[ "$(stat -c %a "${HASH_OUTPUT}/${evidence_file}")" == "644" ]] || fail "evidence mode is not 0644"
done

TAR_A="${TMP_DIR}/mode-a.tar.gz"
TAR_B="${TMP_DIR}/mode-b.tar.gz"
(umask 0022; frontend_release_write_deterministic_tar "${SNAPSHOT_A}" "${TAR_A}")
(umask 0077; frontend_release_write_deterministic_tar "${SNAPSHOT_B}" "${TAR_B}")
cmp "${TAR_A}" "${TAR_B}" || fail "normalized snapshot tarballs differ across source modes or umasks"
expect_failure frontend_release_write_deterministic_tar "${SNAPSHOT_A}" "${TAR_A}"

EXTRACTED="${TMP_DIR}/extracted"
frontend_release_extract_verified_tar "${TAR_A}" "${HASH_OUTPUT}/frontend_dist.sha256.txt" "${EXTRACTED}"
[[ "$(stat -c %a "${EXTRACTED}/dist")" == "755" ]] || fail "archive directory mode is not 0755"

exclusive_file="${HASH_OUTPUT}/exclusive.txt"
frontend_release_write_text_exclusive "${exclusive_file}" 0644 $'first\n'
expect_failure frontend_release_write_text_exclusive "${exclusive_file}" 0644 $'second\n'
[[ "$(cat "${exclusive_file}")" == "first" ]] || fail "exclusive writer overwrote an artifact"

VALID_BUILD_INPUTS="${TMP_DIR}/valid-build-inputs.json"
VALID_DIGEST="$(printf 'a%.0s' {1..64})"
VITE_DEFAULT_CORE_ADDRESS="0x0000000000000000000000000000000000001001" \
VITE_DEFAULT_SETTLEMENT_ADDRESS="0x0000000000000000000000000000000000001002" \
VITE_EXACT_MANIFEST_SHA256="${VALID_DIGEST}" \
VITE_EXACT_MANIFEST_URL="https://example.test/manifest.json" \
node "${ROOT_DIR}/scripts/capture_frontend_build_inputs.mjs" \
  --frontend-dir "${ROOT_DIR}/frontend" \
  --output "${VALID_BUILD_INPUTS}" \
  --mode fresh-build

expect_failure env \
  VITE_DEFAULT_CORE_ADDRESS=0x0000000000000000000000000000000000000000 \
  VITE_DEFAULT_SETTLEMENT_ADDRESS=0x0000000000000000000000000000000000001002 \
  node "${ROOT_DIR}/scripts/capture_frontend_build_inputs.mjs" \
  --frontend-dir "${ROOT_DIR}/frontend" --output "${TMP_DIR}/zero-address.json" --mode fresh-build
expect_failure env \
  VITE_DEFAULT_CORE_ADDRESS=0x0000000000000000000000000000000000001001 \
  node "${ROOT_DIR}/scripts/capture_frontend_build_inputs.mjs" \
  --frontend-dir "${ROOT_DIR}/frontend" --output "${TMP_DIR}/unpaired-address.json" --mode fresh-build
expect_failure env \
  VITE_EXACT_MANIFEST_SHA256="${VALID_DIGEST}" \
  VITE_EXACT_MANIFEST_URL='https://example.test/manifest.json?token=EXPOSED' \
  node "${ROOT_DIR}/scripts/capture_frontend_build_inputs.mjs" \
  --frontend-dir "${ROOT_DIR}/frontend" --output "${TMP_DIR}/query-secret.json" --mode fresh-build
expect_failure env \
  VITE_EXACT_MANIFEST_SHA256="${VALID_DIGEST}" \
  VITE_EXACT_MANIFEST_URL='https://user:password@example.test/manifest.json' \
  node "${ROOT_DIR}/scripts/capture_frontend_build_inputs.mjs" \
  --frontend-dir "${ROOT_DIR}/frontend" --output "${TMP_DIR}/userinfo.json" --mode fresh-build
expect_failure env \
  VITE_EXACT_MANIFEST_SHA256="${VALID_DIGEST}" \
  VITE_EXACT_MANIFEST_URL='https://example.test/manifest.json#reviewed' \
  node "${ROOT_DIR}/scripts/capture_frontend_build_inputs.mjs" \
  --frontend-dir "${ROOT_DIR}/frontend" --output "${TMP_DIR}/fragment.json" --mode fresh-build
expect_failure env \
  VITE_EXACT_MANIFEST_SHA256="${VALID_DIGEST}" \
  VITE_EXACT_MANIFEST_URL='https://example.test/access_token/ghp_abcdefghijklmnopqrstuvwxyz123456' \
  node "${ROOT_DIR}/scripts/capture_frontend_build_inputs.mjs" \
  --frontend-dir "${ROOT_DIR}/frontend" --output "${TMP_DIR}/secret-like.json" --mode fresh-build

UNKNOWN_BUILD_INPUTS="${TMP_DIR}/unknown-build-inputs.json"
node "${ROOT_DIR}/scripts/capture_frontend_build_inputs.mjs" \
  --frontend-dir "${ROOT_DIR}/frontend" \
  --output "${UNKNOWN_BUILD_INPUTS}" \
  --mode prebuilt-unknown

HASH_1="$(printf '1%.0s' {1..64})"
HASH_2="$(printf '2%.0s' {1..64})"
HASH_3="$(printf '3%.0s' {1..64})"
HASH_4="$(printf '4%.0s' {1..64})"
HASH_5="$(printf '5%.0s' {1..64})"
HASH_6="$(printf '6%.0s' {1..64})"
HASH_7="$(printf '7%.0s' {1..64})"

write_receipt() {
  local output="$1" build_inputs="$2" build_mode="$3" source_stability="$4" vite_version="$5"
  node "${ROOT_DIR}/scripts/write_frontend_release_receipt.mjs" \
    --output "${output}" \
    --build-inputs-file "${build_inputs}" \
    --generated-at-utc "2026-07-16T12:00:00Z" \
    --git-commit "$(printf 'a%.0s' {1..40})" \
    --git-tree-state clean \
    --frontend-source-tree-sha256 "${HASH_1}" \
    --release-tooling-sha256 "${HASH_2}" \
    --package-json-sha256 "${HASH_3}" \
    --package-lock-sha256 "${HASH_4}" \
    --vite-config-sha256 "${HASH_5}" \
    --build-mode "${build_mode}" \
    --source-stability "${source_stability}" \
    --assurance-context not-run-by-release-script \
    --node-version v22.17.0 \
    --npm-version 11.4.2 \
    --vite-version "${vite_version}" \
    --tar-version "tar (GNU tar) test" \
    --gzip-version "gzip test" \
    --tree-sha256 "${HASH_6}" \
    --file-count 2 \
    --total-bytes 42 \
    --tarball-sha256 "${HASH_7}"
}

FRESH_RECEIPT="${TMP_DIR}/fresh-receipt.json"
write_receipt "${FRESH_RECEIPT}" "${VALID_BUILD_INPUTS}" fresh-build matched-before-and-after-build 5.4.21
expect_failure write_receipt "${FRESH_RECEIPT}" "${VALID_BUILD_INPUTS}" fresh-build matched-before-and-after-build 5.4.21
PREBUILT_RECEIPT="${TMP_DIR}/prebuilt-receipt.json"
write_receipt "${PREBUILT_RECEIPT}" "${UNKNOWN_BUILD_INPUTS}" prebuilt-dist captured-at-packaging-only not-used-for-prebuilt-packaging

node --input-type=module - "${FRESH_RECEIPT}" "${PREBUILT_RECEIPT}" <<'NODE'
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const fresh = JSON.parse(readFileSync(process.argv[2], "utf8"));
const prebuilt = JSON.parse(readFileSync(process.argv[3], "utf8"));
assert.equal(fresh.schema, "pulsetensor/frontend-release-receipt/v2");
assert.equal(fresh.build.provenance, "captured-and-frozen-before-fresh-build");
assert.equal(fresh.build.assurance_context_is_attestation, false);
assert.equal(fresh.build.public_vite_inputs.VITE_EXACT_MANIFEST_URL, "https://example.test/manifest.json");
assert.match(fresh.build.public_vite_inputs_sha256, /^[0-9a-f]{64}$/);
assert.equal(fresh.packaging_environment.role, "same-process-build-and-packaging-toolchain");
assert.equal(prebuilt.build.provenance, "unknown-prebuilt-artifact");
assert.equal(prebuilt.build.public_vite_inputs, null);
assert.equal(prebuilt.build.public_vite_inputs_sha256, null);
assert.equal(prebuilt.packaging_environment.vite_version, null);
assert.equal(prebuilt.packaging_environment.role, "packaging-only-not-claimed-as-build-toolchain");
NODE

VALID_DIRECTORY_CID="bafybeiaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
VALID_FILE_CID="bafkreiabaeaqcaibaeaqcaibaeaqcaibaeaqcaibaeaqcaibaeaqcaibae"
node "${ROOT_DIR}/scripts/validate_ipfs_cid.mjs" --kind directory --cid "${VALID_DIRECTORY_CID}" >/dev/null
node "${ROOT_DIR}/scripts/validate_ipfs_cid.mjs" --kind file --cid "${VALID_FILE_CID}" >/dev/null
expect_failure node "${ROOT_DIR}/scripts/validate_ipfs_cid.mjs" --kind directory --cid baaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
expect_failure node "${ROOT_DIR}/scripts/validate_ipfs_cid.mjs" --kind directory --cid "${VALID_FILE_CID}"
expect_failure node "${ROOT_DIR}/scripts/validate_ipfs_cid.mjs" --kind file --cid "${VALID_FILE_CID}a"

export MOCK_IPFS_STATE="${TMP_DIR}/mock-ipfs-state"
export MOCK_DIRECTORY_CID="${VALID_DIRECTORY_CID}"
export MOCK_FILE_CID="${VALID_FILE_CID}"
export MOCK_LIVE_DIST="${ROOT_DIR}/frontend/dist"
mkdir -p "${MOCK_IPFS_STATE}"
ipfs() {
  if [[ "${1:-}" == "add" && "${2:-}" == "--help" ]]; then
    printf '%s\n' 'Options: --preserve-mode --preserve-mtime'
    return 0
  fi
  if [[ "${1:-}" == "add" ]]; then
    local source_path="${@: -1}" argument
    for argument in "$@"; do
      if [[ "${argument}" == "-r" ]]; then
        [[ "${source_path}" != "${MOCK_LIVE_DIST}" ]] || return 91
        printf '%s' "${source_path}" > "${MOCK_IPFS_STATE}/dist-path"
        printf '%s\n' "${MOCK_DIRECTORY_CID}"
        return 0
      fi
    done
    printf '%s' "${source_path}" > "${MOCK_IPFS_STATE}/tar-path"
    printf '%s\n' "${MOCK_FILE_CID}"
    return 0
  fi
  if [[ "${1:-}" == "cat" ]]; then
    command cat "$(command cat "${MOCK_IPFS_STATE}/tar-path")"
    return 0
  fi
  if [[ "${1:-}" == "get" ]]; then
    local output_path="" previous="" argument
    for argument in "$@"; do
      if [[ "${previous}" == "-o" ]]; then
        output_path="${argument}"
        break
      fi
      previous="${argument}"
    done
    [[ -n "${output_path}" ]] || return 92
    command mkdir -p "${output_path}"
    command cp -R "$(command cat "${MOCK_IPFS_STATE}/dist-path")/." "${output_path}/"
    return 0
  fi
  if [[ "${1:-}" == "version" ]]; then
    printf '%s\n' '0.42.0'
    return 0
  fi
  return 93
}
export -f ipfs

PUBLISH_OUTPUT="${TMP_DIR}/publish-output"
bash "${ROOT_DIR}/scripts/publish_frontend_ipfs.sh" --skip-build --out-dir "${PUBLISH_OUTPUT}" >/dev/null
node --input-type=module - "${PUBLISH_OUTPUT}/frontend_ipfs_publish_receipt.json" <<'NODE'
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
const receipt = JSON.parse(readFileSync(process.argv[2], "utf8"));
assert.equal(receipt.schema, "pulsetensor/frontend-ipfs-publish-receipt/v2");
assert.equal(receipt.publication_source, "verified-extraction-of-release-tarball");
assert.equal(receipt.ipfs.independent_cid_decode, true);
assert.equal(receipt.ipfs.tarball_readback_sha256_verified, true);
assert.equal(receipt.ipfs.directory_readback_manifest_verified, true);
NODE
[[ ! -e "${PUBLISH_OUTPUT}/.frontend-release.lock" ]] || fail "publish lock was not cleaned up"

printf 'Frontend release hardening regressions passed.\n'

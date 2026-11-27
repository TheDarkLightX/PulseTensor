#!/usr/bin/env bash

# Shared fail-closed primitives for frontend release scripts. Callers are
# expected to enable `set -euo pipefail` before sourcing this file.

frontend_release_fail() {
  printf 'Frontend release: %s\n' "$*" >&2
  return 1
}

frontend_release_assert_no_symlink_components() {
  local lexical_path cursor
  lexical_path="$(realpath -ms -- "$1")" || return 1
  cursor="${lexical_path}"
  while [[ "${cursor}" != "/" ]]; do
    if [[ -L "${cursor}" ]]; then
      frontend_release_fail "path must not contain symbolic links: ${cursor}"
      return 1
    fi
    cursor="$(dirname -- "${cursor}")"
  done
}

frontend_release_resolve_output_dir() {
  if [[ $# -ne 3 ]]; then
    frontend_release_fail "internal error: expected root, frontend, and output paths"
    return 1
  fi

  local root_dir frontend_dir raw_output lexical_output resolved_output
  root_dir="$(realpath -e -- "$1")" || return 1
  frontend_dir="$(realpath -e -- "$2")" || return 1
  raw_output="$3"
  [[ -n "${raw_output}" ]] || {
    frontend_release_fail "output directory cannot be empty"
    return 1
  }

  lexical_output="$(realpath -ms -- "${raw_output}")" || return 1
  frontend_release_assert_no_symlink_components "${lexical_output}" || return 1
  resolved_output="$(realpath -m -- "${raw_output}")" || return 1
  case "${resolved_output}" in
    "${frontend_dir}"|"${frontend_dir}"/*)
      frontend_release_fail "output directory must be outside the frontend source and dist trees: ${resolved_output}"
      return 1
      ;;
    "${root_dir}"|"${root_dir}/.git"|"${root_dir}/.git"/*)
      frontend_release_fail "output directory cannot be the repository root or Git metadata: ${resolved_output}"
      return 1
      ;;
  esac

  printf '%s\n' "${resolved_output}"
}

frontend_release_assert_secure_ancestry() {
  local cursor owner_uid mode_text mode current_uid
  cursor="$(realpath -e -- "$1")" || return 1
  current_uid="$(id -u)"
  while :; do
    owner_uid="$(stat -c %u -- "${cursor}")" || return 1
    mode_text="$(stat -c %a -- "${cursor}")" || return 1
    mode=$((8#${mode_text}))
    if [[ "${owner_uid}" == "${current_uid}" && $((mode & 0022)) -eq 0 ]]; then
      # Once this process owns a directory that no group/other user can even
      # traverse, higher ancestors cannot be used to replace descendants.
      if [[ $((mode & 0077)) -eq 0 ]]; then
        break
      fi
    elif [[ "${owner_uid}" == "0" && $((mode & 0022)) -eq 0 ]]; then
      :
    elif [[ "${owner_uid}" == "0" && $((mode & 01000)) -ne 0 && $((mode & 0002)) -ne 0 ]]; then
      # Root-owned sticky directories such as /tmp are safe claim points: another
      # unprivileged user cannot replace entries owned by this process.
      :
    else
      frontend_release_fail "output ancestry is writable or controlled by another user: ${cursor}"
      return 1
    fi
    [[ "${cursor}" == "/" ]] && break
    cursor="$(dirname -- "${cursor}")"
  done
}

frontend_release_assert_output_dir() {
  local resolved_output actual_output owner_uid mode_text
  resolved_output="$(frontend_release_resolve_output_dir "$@")" || return 1
  if [[ ! -d "${resolved_output}" || -L "${resolved_output}" ]]; then
    frontend_release_fail "output directory is missing or unsafe: ${resolved_output}"
    return 1
  fi
  actual_output="$(realpath -e -- "${resolved_output}")" || return 1
  if [[ "${actual_output}" != "${resolved_output}" ]]; then
    frontend_release_fail "output directory changed during validation: ${resolved_output}"
    return 1
  fi
  owner_uid="$(stat -c %u -- "${resolved_output}")" || return 1
  mode_text="$(stat -c %a -- "${resolved_output}")" || return 1
  if [[ "${owner_uid}" != "$(id -u)" || "${mode_text}" != "700" ]]; then
    frontend_release_fail "output directory must be owned by the current user with mode 0700: ${resolved_output}"
    return 1
  fi
  frontend_release_assert_secure_ancestry "$(dirname -- "${resolved_output}")" || return 1
  printf '%s\n' "${resolved_output}"
}

frontend_release_claim_output_dir() {
  local resolved_output output_parent confirmed_output
  resolved_output="$(frontend_release_resolve_output_dir "$@")" || return 1
  output_parent="$(dirname -- "${resolved_output}")"

  (umask 077; mkdir -p -- "${output_parent}") || return 1
  frontend_release_assert_no_symlink_components "${output_parent}" || return 1
  output_parent="$(realpath -e -- "${output_parent}")" || return 1
  frontend_release_assert_secure_ancestry "${output_parent}" || return 1

  if [[ -e "${resolved_output}" || -L "${resolved_output}" ]]; then
    frontend_release_fail "output path already exists; preserve it and choose a fresh path: ${resolved_output}"
    return 1
  fi
  if ! (umask 077; mkdir -m 0700 -- "${resolved_output}"); then
    frontend_release_fail "could not atomically claim fresh output directory: ${resolved_output}"
    return 1
  fi
  confirmed_output="$(frontend_release_assert_output_dir "$@")" || return 1
  printf '%s\n' "${confirmed_output}"
}

frontend_release_acquire_output_lock() {
  if [[ $# -ne 1 ]]; then
    frontend_release_fail "internal error: expected an output path to lock"
    return 1
  fi
  local output_dir lock_path
  output_dir="$1"
  lock_path="${output_dir}/.frontend-release.lock"
  if [[ -e "${lock_path}" || -L "${lock_path}" ]]; then
    frontend_release_fail "output directory is already locked or contains a stale lock: ${lock_path}"
    return 1
  fi
  if ! (umask 077; set -o noclobber; : > "${lock_path}") 2>/dev/null; then
    frontend_release_fail "could not exclusively create output lock: ${lock_path}"
    return 1
  fi
  chmod 0600 -- "${lock_path}"
  exec {FRONTEND_RELEASE_LOCK_FD}<>"${lock_path}"
  if ! flock -n "${FRONTEND_RELEASE_LOCK_FD}"; then
    exec {FRONTEND_RELEASE_LOCK_FD}>&-
    rm -f -- "${lock_path}"
    frontend_release_fail "another release process holds the output lock: ${output_dir}"
    return 1
  fi
  FRONTEND_RELEASE_LOCK_PATH="${lock_path}"
}

frontend_release_release_output_lock() {
  if [[ -n "${FRONTEND_RELEASE_LOCK_FD:-}" ]]; then
    flock -u "${FRONTEND_RELEASE_LOCK_FD}" || true
    exec {FRONTEND_RELEASE_LOCK_FD}>&- || true
    unset FRONTEND_RELEASE_LOCK_FD
  fi
  if [[ -n "${FRONTEND_RELEASE_LOCK_PATH:-}" ]]; then
    rm -f -- "${FRONTEND_RELEASE_LOCK_PATH}"
    unset FRONTEND_RELEASE_LOCK_PATH
  fi
}

frontend_release_assert_safe_relative_path() {
  if [[ $# -ne 1 ]]; then
    frontend_release_fail "internal error: expected a relative artifact path"
    return 1
  fi
  local relative_path LC_ALL=C
  relative_path="$1"
  if [[ -z "${relative_path}" || "${relative_path}" == /* || "${relative_path}" == *\\* || "${relative_path}" =~ [[:cntrl:]] ]]; then
    frontend_release_fail "artifact path contains an unsafe absolute, backslash, or control-character form"
    return 1
  fi
}

frontend_release_assert_safe_dist() {
  if [[ $# -ne 1 ]]; then
    frontend_release_fail "internal error: expected a dist path"
    return 1
  fi
  local dist_dir entry relative_path
  dist_dir="$1"
  if [[ ! -d "${dist_dir}" || -L "${dist_dir}" ]]; then
    frontend_release_fail "frontend dist must be a real directory: ${dist_dir}"
    return 1
  fi
  while IFS= read -r -d '' entry; do
    if [[ -L "${entry}" || ( ! -d "${entry}" && ! -f "${entry}" ) ]]; then
      frontend_release_fail "frontend dist contains a symbolic link or special file: ${entry}"
      return 1
    fi
    relative_path="${entry#${dist_dir}/}"
    frontend_release_assert_safe_relative_path "${relative_path}" || return 1
  done < <(find "${dist_dir}" -mindepth 1 -print0)
}

frontend_release_assert_safe_source_tree() {
  if [[ $# -ne 1 ]]; then
    frontend_release_fail "internal error: expected a frontend source path"
    return 1
  fi
  local frontend_dir entry relative_path
  frontend_dir="$1"
  if [[ ! -d "${frontend_dir}" || -L "${frontend_dir}" ]]; then
    frontend_release_fail "frontend source must be a real directory: ${frontend_dir}"
    return 1
  fi
  while IFS= read -r -d '' entry; do
    if [[ -L "${entry}" || ( ! -d "${entry}" && ! -f "${entry}" ) ]]; then
      frontend_release_fail "frontend source contains a symbolic link or special file: ${entry}"
      return 1
    fi
    relative_path="${entry#${frontend_dir}/}"
    frontend_release_assert_safe_relative_path "${relative_path}" || return 1
  done < <(
    find "${frontend_dir}" -mindepth 1 \
      \( -path "${frontend_dir}/node_modules" -o -path "${frontend_dir}/dist" \) -prune -o \
      -print0
  )
}

frontend_release_create_dist_snapshot() {
  if [[ $# -ne 2 ]]; then
    frontend_release_fail "internal error: expected live dist and snapshot paths"
    return 1
  fi
  local dist_dir snapshot_dir
  dist_dir="$1"
  snapshot_dir="$2"
  frontend_release_assert_safe_dist "${dist_dir}" || return 1
  if [[ -e "${snapshot_dir}" || -L "${snapshot_dir}" ]]; then
    frontend_release_fail "snapshot path already exists: ${snapshot_dir}"
    return 1
  fi
  (umask 077; mkdir -p -- "${snapshot_dir}") || return 1
  cp -R --no-dereference --no-preserve=mode,ownership,timestamps -- "${dist_dir}/." "${snapshot_dir}/"
  frontend_release_assert_safe_dist "${snapshot_dir}" || return 1
  find "${snapshot_dir}" -type d -exec chmod 0755 {} +
  find "${snapshot_dir}" -type f -exec chmod 0644 {} +
  frontend_release_assert_safe_dist "${snapshot_dir}" || return 1
  frontend_release_assert_normalized_dist_modes "${snapshot_dir}" || return 1
}

frontend_release_assert_normalized_dist_modes() {
  if [[ $# -ne 1 ]]; then
    frontend_release_fail "internal error: expected a normalized dist path"
    return 1
  fi
  local dist_dir entry expected_mode actual_mode
  dist_dir="$1"
  while IFS= read -r -d '' entry; do
    if [[ -d "${entry}" && ! -L "${entry}" ]]; then
      expected_mode="755"
    elif [[ -f "${entry}" && ! -L "${entry}" ]]; then
      expected_mode="644"
    else
      frontend_release_fail "normalized dist contains an unsafe entry: ${entry}"
      return 1
    fi
    actual_mode="$(stat -c %a -- "${entry}")" || return 1
    if [[ "${actual_mode}" != "${expected_mode}" ]]; then
      frontend_release_fail "snapshot mode is not normalized (${actual_mode}, expected ${expected_mode}): ${entry}"
      return 1
    fi
  done < <(find "${dist_dir}" -print0)
}

frontend_release_commit_temp_file() {
  if [[ $# -ne 3 ]]; then
    frontend_release_fail "internal error: expected temporary path, destination, and mode"
    return 1
  fi
  local temporary_path destination_path file_mode destination_parent
  temporary_path="$1"
  destination_path="$2"
  file_mode="$3"
  destination_parent="$(dirname -- "${destination_path}")"
  if [[ ! -f "${temporary_path}" || -L "${temporary_path}" || "$(dirname -- "${temporary_path}")" != "${destination_parent}" ]]; then
    frontend_release_fail "temporary release file is missing, unsafe, or on another directory: ${temporary_path}"
    return 1
  fi
  if [[ -e "${destination_path}" || -L "${destination_path}" ]]; then
    frontend_release_fail "refusing to overwrite release artifact: ${destination_path}"
    return 1
  fi
  chmod "${file_mode}" -- "${temporary_path}"
  if ! ln -- "${temporary_path}" "${destination_path}"; then
    frontend_release_fail "could not atomically publish release artifact without overwrite: ${destination_path}"
    return 1
  fi
  rm -f -- "${temporary_path}"
}

frontend_release_write_text_exclusive() (
  set -euo pipefail
  if [[ $# -ne 3 ]]; then
    frontend_release_fail "internal error: expected destination, mode, and content"
    exit 1
  fi
  local destination_path file_mode content temporary_path
  destination_path="$1"
  file_mode="$2"
  content="$3"
  temporary_path="$(mktemp "$(dirname -- "${destination_path}")/.release-text.XXXXXX")"
  trap 'rm -f -- "${temporary_path}"' EXIT
  printf '%s' "${content}" > "${temporary_path}"
  frontend_release_commit_temp_file "${temporary_path}" "${destination_path}" "${file_mode}" || exit 1
)

frontend_release_compute_manifest() {
  if [[ $# -ne 3 ]]; then
    frontend_release_fail "internal error: expected dist, manifest, and stats paths"
    return 1
  fi
  local dist_dir manifest_file stats_file artifact_file relative_path artifact_hash artifact_size
  dist_dir="$1"
  manifest_file="$2"
  stats_file="$3"
  frontend_release_assert_safe_dist "${dist_dir}" || return 1
  : > "${manifest_file}"
  : > "${stats_file}"
  while IFS= read -r -d '' artifact_file; do
    relative_path="${artifact_file#${dist_dir}/}"
    artifact_hash="$(sha256sum "${artifact_file}" | awk '{print $1}')"
    artifact_size="$(stat -c %s -- "${artifact_file}")"
    printf '%s  %s\n' "${artifact_hash}" "${relative_path}" >> "${manifest_file}"
    printf '%s\t%s\n' "${artifact_size}" "${relative_path}" >> "${stats_file}"
  done < <(find "${dist_dir}" -type f -print0 | LC_ALL=C sort -z)
  [[ -s "${manifest_file}" ]] || {
    frontend_release_fail "no frontend artifacts found under: ${dist_dir}"
    return 1
  }
  LC_ALL=C sort -n -o "${stats_file}" "${stats_file}"
}

frontend_release_write_hash_evidence() (
  set -euo pipefail
  if [[ $# -ne 2 ]]; then
    frontend_release_fail "internal error: expected dist and output paths"
    exit 1
  fi
  local dist_dir output_dir manifest_file stats_file tree_hash_file manifest_tmp stats_tmp tree_tmp tree_hash
  dist_dir="$1"
  output_dir="$2"
  manifest_file="${output_dir}/frontend_dist.sha256.txt"
  stats_file="${output_dir}/frontend_dist.stats.tsv"
  tree_hash_file="${output_dir}/frontend_dist.tree.sha256"
  manifest_tmp="$(mktemp "${output_dir}/.manifest.XXXXXX")"
  stats_tmp="$(mktemp "${output_dir}/.stats.XXXXXX")"
  tree_tmp="$(mktemp "${output_dir}/.tree-hash.XXXXXX")"
  trap 'rm -f -- "${manifest_tmp}" "${stats_tmp}" "${tree_tmp}"' EXIT

  frontend_release_compute_manifest "${dist_dir}" "${manifest_tmp}" "${stats_tmp}" || exit 1
  tree_hash="$(sha256sum "${manifest_tmp}" | awk '{print $1}')"
  printf '%s  frontend_dist.sha256.txt\n' "${tree_hash}" > "${tree_tmp}"
  frontend_release_commit_temp_file "${manifest_tmp}" "${manifest_file}" 0644 || exit 1
  frontend_release_commit_temp_file "${stats_tmp}" "${stats_file}" 0644 || exit 1
  frontend_release_commit_temp_file "${tree_tmp}" "${tree_hash_file}" 0644 || exit 1
)

frontend_release_verify_manifest() (
  set -euo pipefail
  if [[ $# -ne 2 ]]; then
    frontend_release_fail "internal error: expected dist and manifest paths"
    exit 1
  fi
  local dist_dir expected_manifest temporary_dir computed_manifest computed_stats
  dist_dir="$1"
  expected_manifest="$2"
  [[ -f "${expected_manifest}" && ! -L "${expected_manifest}" ]] || {
    frontend_release_fail "expected manifest is missing or unsafe: ${expected_manifest}"
    exit 1
  }
  temporary_dir="$(mktemp -d)"
  trap 'rm -rf -- "${temporary_dir}"' EXIT
  computed_manifest="${temporary_dir}/manifest"
  computed_stats="${temporary_dir}/stats"
  frontend_release_compute_manifest "${dist_dir}" "${computed_manifest}" "${computed_stats}" || exit 1
  if ! cmp -s -- "${expected_manifest}" "${computed_manifest}"; then
    frontend_release_fail "directory contents do not match the release manifest: ${dist_dir}"
    exit 1
  fi
)

frontend_release_write_deterministic_tar() (
  set -euo pipefail
  if [[ $# -ne 2 ]]; then
    frontend_release_fail "internal error: expected dist and tarball paths"
    exit 1
  fi

  local dist_dir tarball_path tarball_parent dist_parent tarball_tmp
  dist_dir="$1"
  tarball_path="$2"
  frontend_release_assert_safe_dist "${dist_dir}" || exit 1
  frontend_release_assert_normalized_dist_modes "${dist_dir}" || exit 1
  [[ "$(basename -- "${dist_dir}")" == "dist" ]] || {
    frontend_release_fail "snapshot directory archived as the release root must be named dist"
    exit 1
  }
  dist_parent="$(dirname -- "${dist_dir}")"
  tarball_parent="$(dirname -- "${tarball_path}")"
  [[ -d "${tarball_parent}" && ! -L "${tarball_parent}" ]] || {
    frontend_release_fail "tarball parent is missing or unsafe: ${tarball_parent}"
    exit 1
  }
  if [[ -e "${tarball_path}" || -L "${tarball_path}" ]]; then
    frontend_release_fail "refusing to overwrite release tarball: ${tarball_path}"
    exit 1
  fi

  tarball_tmp="$(mktemp "${tarball_parent}/.frontend-dist.tar.XXXXXX")"
  trap 'rm -f -- "${tarball_tmp}"' EXIT
  TZ=UTC LC_ALL=C tar \
    --format=ustar \
    --sort=name \
    --owner=0 \
    --group=0 \
    --numeric-owner \
    --mtime='UTC 1970-01-01' \
    -C "${dist_parent}" \
    -cf - \
    dist \
    | gzip -n -9 > "${tarball_tmp}"
  frontend_release_commit_temp_file "${tarball_tmp}" "${tarball_path}" 0644 || exit 1
)

frontend_release_extract_verified_tar() {
  if [[ $# -ne 3 ]]; then
    frontend_release_fail "internal error: expected tarball, manifest, and extraction root"
    return 1
  fi
  local tarball_path manifest_path extraction_root first_entry second_entry
  tarball_path="$1"
  manifest_path="$2"
  extraction_root="$3"
  if [[ ! -f "${tarball_path}" || -L "${tarball_path}" || -e "${extraction_root}" || -L "${extraction_root}" ]]; then
    frontend_release_fail "tarball or extraction target is missing or unsafe"
    return 1
  fi
  (umask 077; mkdir -m 0700 -- "${extraction_root}") || return 1
  tar --extract --gzip --file="${tarball_path}" --directory="${extraction_root}" \
    --no-same-owner --no-same-permissions
  first_entry="$(find "${extraction_root}" -mindepth 1 -maxdepth 1 -print -quit)"
  second_entry="$(find "${extraction_root}" -mindepth 1 -maxdepth 1 -print | sed -n '2p')"
  if [[ "${first_entry}" != "${extraction_root}/dist" || -n "${second_entry}" ]]; then
    frontend_release_fail "release tarball must contain exactly one top-level dist directory"
    return 1
  fi
  frontend_release_assert_safe_dist "${extraction_root}/dist" || return 1
  frontend_release_verify_manifest "${extraction_root}/dist" "${manifest_path}"
}

frontend_release_read_named_sha256() {
  if [[ $# -ne 2 ]]; then
    frontend_release_fail "internal error: expected checksum file and artifact name"
    return 1
  fi
  local checksum_file expected_name checksum name extra line_count
  checksum_file="$1"
  expected_name="$2"
  [[ -f "${checksum_file}" && ! -L "${checksum_file}" ]] || {
    frontend_release_fail "checksum file is missing or unsafe: ${checksum_file}"
    return 1
  }
  line_count="$(wc -l < "${checksum_file}" | tr -d ' ')"
  IFS=$' \t' read -r checksum name extra < "${checksum_file}" || true
  if [[ "${line_count}" != "1" || ! "${checksum}" =~ ^[0-9a-f]{64}$ || "${name}" != "${expected_name}" || -n "${extra:-}" ]]; then
    frontend_release_fail "checksum file has an invalid canonical form: ${checksum_file}"
    return 1
  fi
  printf '%s\n' "${checksum}"
}

frontend_release_hash_source_tree() (
  set -euo pipefail
  if [[ $# -ne 1 ]]; then
    frontend_release_fail "internal error: expected a frontend source path"
    exit 1
  fi
  local frontend_dir file_path relative_path file_sha256
  frontend_dir="$(realpath -e -- "$1")"
  frontend_release_assert_safe_source_tree "${frontend_dir}" || exit 1
  cd "${frontend_dir}"
  while IFS= read -r -d '' file_path; do
    relative_path="${file_path#./}"
    file_sha256="$(sha256sum "${file_path}" | awk '{print $1}')"
    printf '%s\0%s\0' "${relative_path}" "${file_sha256}"
  done < <(
    find . \
      \( -path './node_modules' -o -path './dist' \) -prune -o \
      -type f \
      ! -name '*.tsbuildinfo' \
      ! -name '.env' \
      ! -name '.env.*' \
      -print0 \
      | LC_ALL=C sort -z
  ) | sha256sum | awk '{print $1}'
)

frontend_release_hash_named_files() (
  set -euo pipefail
  if [[ $# -lt 2 ]]; then
    frontend_release_fail "internal error: expected a root and named files"
    exit 1
  fi
  local root_dir relative_path file_sha256
  root_dir="$(realpath -e -- "$1")"
  shift
  cd "${root_dir}"
  for relative_path in "$@"; do
    if [[ ! -f "${relative_path}" || -L "${relative_path}" ]]; then
      frontend_release_fail "provenance input is missing or unsafe: ${relative_path}"
      exit 1
    fi
    frontend_release_assert_safe_relative_path "${relative_path}" || exit 1
    file_sha256="$(sha256sum "${relative_path}" | awk '{print $1}')"
    printf '%s\0%s\0' "${relative_path}" "${file_sha256}"
  done | sha256sum | awk '{print $1}'
)

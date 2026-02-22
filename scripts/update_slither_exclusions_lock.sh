#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ALLOWLIST_PATH="${ROOT_DIR}/docs/security/slither_exclusions.allowlist"
LOCK_PATH="${ROOT_DIR}/docs/security/slither_exclusions.lock"

if [[ ! -f "${ALLOWLIST_PATH}" ]]; then
  echo "Slither exclusion allowlist not found: ${ALLOWLIST_PATH}"
  exit 1
fi

hash_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
    return
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
    return
  fi
  echo "Neither sha256sum nor shasum is available" >&2
  exit 1
}

mapfile -t EXCLUSIONS < <(awk '
  {
    line=$0
    sub(/#.*/, "", line)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
    if (line != "") print line
  }
' "${ALLOWLIST_PATH}")

if [[ ${#EXCLUSIONS[@]} -eq 0 ]]; then
  echo "Slither exclusion allowlist is empty: ${ALLOWLIST_PATH}"
  exit 1
fi

HASH_VALUE="$(printf '%s\n' "${EXCLUSIONS[@]}" | hash_stdin)"
{
  echo "${HASH_VALUE}"
  echo "# sha256(canonical detector ids, one per line, comments/blank lines stripped)"
  echo "# update via: bash scripts/update_slither_exclusions_lock.sh"
} >"${LOCK_PATH}"

echo "Updated ${LOCK_PATH} (${HASH_VALUE})"

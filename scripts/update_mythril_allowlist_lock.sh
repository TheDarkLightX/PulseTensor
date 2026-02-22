#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ALLOWLIST_PATH="${ROOT_DIR}/docs/security/mythril_ignored_swc.allowlist"
LOCK_PATH="${ROOT_DIR}/docs/security/mythril_ignored_swc.lock"

if [[ ! -f "${ALLOWLIST_PATH}" ]]; then
  echo "Mythril SWC allowlist not found: ${ALLOWLIST_PATH}"
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

mapfile -t SWC_IDS < <(awk '
  {
    line=$0
    sub(/#.*/, "", line)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
    if (line != "") print line
  }
' "${ALLOWLIST_PATH}")

if [[ ${#SWC_IDS[@]} -eq 0 ]]; then
  echo "Mythril SWC allowlist is empty: ${ALLOWLIST_PATH}"
  exit 1
fi

HASH_VALUE="$(printf '%s\n' "${SWC_IDS[@]}" | hash_stdin)"
{
  echo "${HASH_VALUE}"
  echo "# sha256(canonical SWC ids, one per line, comments/blank lines stripped)"
  echo "# update via: bash scripts/update_mythril_allowlist_lock.sh"
} >"${LOCK_PATH}"

echo "Updated ${LOCK_PATH} (${HASH_VALUE})"

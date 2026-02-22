#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ALLOWLIST_PATH="${ROOT_DIR}/docs/security/mythril_ignored_swc.allowlist"
LOCK_PATH="${ROOT_DIR}/docs/security/mythril_ignored_swc.lock"

if [[ ! -f "${ALLOWLIST_PATH}" ]]; then
  echo "Mythril SWC allowlist not found: ${ALLOWLIST_PATH}"
  exit 1
fi

if [[ ! -f "${LOCK_PATH}" ]]; then
  echo "Mythril SWC allowlist lock not found: ${LOCK_PATH}"
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

for swc_id in "${SWC_IDS[@]}"; do
  if [[ ! "${swc_id}" =~ ^SWC-[0-9]{3}$ ]]; then
    echo "Invalid SWC id in Mythril allowlist: ${swc_id}"
    exit 1
  fi
done

DUPLICATES="$(printf '%s\n' "${SWC_IDS[@]}" | sort | uniq -d)"
if [[ -n "${DUPLICATES}" ]]; then
  echo "Duplicate SWC ids in Mythril allowlist:"
  echo "${DUPLICATES}"
  exit 1
fi

EXPECTED_HASH="$(awk 'NR==1 {print $1}' "${LOCK_PATH}")"
if [[ -z "${EXPECTED_HASH}" ]]; then
  echo "Mythril allowlist lock is malformed: ${LOCK_PATH}"
  exit 1
fi

ACTUAL_HASH="$(printf '%s\n' "${SWC_IDS[@]}" | hash_stdin)"
if [[ "${ACTUAL_HASH}" != "${EXPECTED_HASH}" ]]; then
  echo "Mythril allowlist changed without lock refresh."
  echo "Expected hash: ${EXPECTED_HASH}"
  echo "Actual hash:   ${ACTUAL_HASH}"
  echo "If intentional, run: bash scripts/update_mythril_allowlist_lock.sh"
  exit 1
fi

echo "Mythril SWC allowlist lock passed (ids=${#SWC_IDS[@]})"

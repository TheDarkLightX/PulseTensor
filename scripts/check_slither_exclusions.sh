#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ALLOWLIST_PATH="${ROOT_DIR}/docs/security/slither_exclusions.allowlist"
LOCK_PATH="${ROOT_DIR}/docs/security/slither_exclusions.lock"

if [[ ! -f "${ALLOWLIST_PATH}" ]]; then
  echo "Slither exclusion allowlist not found: ${ALLOWLIST_PATH}"
  exit 1
fi

if [[ ! -f "${LOCK_PATH}" ]]; then
  echo "Slither exclusion lock not found: ${LOCK_PATH}"
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

for detector in "${EXCLUSIONS[@]}"; do
  if [[ ! "${detector}" =~ ^[a-z0-9-]+$ ]]; then
    echo "Invalid Slither detector id in allowlist: ${detector}"
    exit 1
  fi
done

DUPLICATES="$(printf '%s\n' "${EXCLUSIONS[@]}" | sort | uniq -d)"
if [[ -n "${DUPLICATES}" ]]; then
  echo "Duplicate detector ids in Slither allowlist:"
  echo "${DUPLICATES}"
  exit 1
fi

EXPECTED_HASH="$(awk 'NR==1 {print $1}' "${LOCK_PATH}")"
if [[ -z "${EXPECTED_HASH}" ]]; then
  echo "Slither exclusion lock is malformed: ${LOCK_PATH}"
  exit 1
fi

ACTUAL_HASH="$(printf '%s\n' "${EXCLUSIONS[@]}" | hash_stdin)"
if [[ "${ACTUAL_HASH}" != "${EXPECTED_HASH}" ]]; then
  echo "Slither exclusion allowlist changed without lock refresh."
  echo "Expected hash: ${EXPECTED_HASH}"
  echo "Actual hash:   ${ACTUAL_HASH}"
  echo "If intentional, run: bash scripts/update_slither_exclusions_lock.sh"
  exit 1
fi

echo "Slither exclusion allowlist lock passed (detectors=${#EXCLUSIONS[@]})"

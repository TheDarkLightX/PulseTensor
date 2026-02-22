#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

require_no_pattern() {
  local description="$1"
  local pattern="$2"
  local tmp_output
  tmp_output="$(mktemp)"
  set +e
  rg -n --hidden --glob '!out/**' --glob '!cache/**' --glob '!external/**' "${pattern}" "${ROOT_DIR}/src" >"${tmp_output}" 2>/dev/null
  local rg_status=$?
  set -e
  if [[ ${rg_status} -eq 0 ]]; then
    echo "Security anti-pattern found: ${description}"
    cat "${tmp_output}"
    rm -f "${tmp_output}"
    exit 1
  fi
  if [[ ${rg_status} -ne 1 ]]; then
    rm -f "${tmp_output}"
    echo "Security anti-pattern scan failed for ${description} (rg exit=${rg_status})"
    exit 1
  fi
  rm -f "${tmp_output}"
}

require_no_pattern "tx.origin authorization usage" 'tx\.origin'
require_no_pattern "delegatecall usage" 'delegatecall'
require_no_pattern "selfdestruct/suicide usage" 'selfdestruct|suicide\('
require_no_pattern "block.timestamp usage in protocol logic" 'block\.timestamp'

echo "Security anti-pattern checks passed"

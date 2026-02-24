#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

require_file() {
  local path="$1"
  if [[ ! -f "${ROOT_DIR}/${path}" ]]; then
    echo "Missing required security readiness doc: ${path}"
    exit 1
  fi
}

require_pattern() {
  local path="$1"
  local pattern="$2"
  local description="$3"
  if ! rg -q "${pattern}" "${ROOT_DIR}/${path}"; then
    echo "Missing ${description} in ${path}"
    exit 1
  fi
}

require_file "docs/security/external_audit_plan.md"
require_file "docs/security/governance_queue_runbook.md"
require_file "docs/security/launch_controls.md"

require_pattern "docs/security/external_audit_plan.md" "^Last updated: [0-9]{4}-[0-9]{2}-[0-9]{2}$" "update stamp"
require_pattern "docs/security/external_audit_plan.md" "^## Scope$" "scope section"
require_pattern "docs/security/external_audit_plan.md" "^## Deliverables$" "deliverables section"

require_pattern "docs/security/governance_queue_runbook.md" "^Last updated: [0-9]{4}-[0-9]{2}-[0-9]{2}$" "update stamp"
require_pattern "docs/security/governance_queue_runbook.md" "^## Alert Conditions$" "alert conditions section"
require_pattern "docs/security/governance_queue_runbook.md" "^## Response Steps$" "response steps section"

require_pattern "docs/security/launch_controls.md" "^Last updated: [0-9]{4}-[0-9]{2}-[0-9]{2}$" "update stamp"
require_pattern "docs/security/launch_controls.md" "^## Phase 0: Pre-Launch Gate$" "phase 0 section"
require_pattern "docs/security/launch_controls.md" "^## Bug Bounty$" "bug bounty section"

echo "Security readiness docs gate passed"

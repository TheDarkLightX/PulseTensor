#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# Retained as a compatibility alias so the two release entry points cannot
# silently diverge in scope.
exec bash "${ROOT_DIR}/scripts/verify_release.sh"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# Compatibility alias: there is one canonical assurance/release pipeline.
exec bash "${ROOT_DIR}/scripts/verify_release.sh"

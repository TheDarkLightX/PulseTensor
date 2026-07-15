#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# There is one exact release-toolchain verifier for both local and CI use.
# Keeping a second, prefix-only path previously allowed local release evidence
# to attest a different toolchain from the required workflow.
exec bash "${ROOT_DIR}/scripts/verify_ci_toolchain.sh"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

if ! rg -q --line-regexp "(external/|/external/)" "${ROOT_DIR}/.gitignore"; then
  echo ".gitignore must include external/ to keep private tools out of version control"
  exit 1
fi

tracked_external="$(git -C "${ROOT_DIR}" ls-files | rg '^external/' || true)"
if [[ -n "${tracked_external}" ]]; then
  echo "Tracked files detected under external/. This must remain untracked:"
  echo "${tracked_external}"
  exit 1
fi

ssh_url_hits="$(
  rg -n \
    --hidden \
    --glob '!.git/**' \
    --glob '!external/**' \
    --glob '!scripts/check_private_boundaries.sh' \
    '(git@|ssh://git@)[^[:space:]]+' \
    "${ROOT_DIR}" \
    || true
)"
if [[ -n "${ssh_url_hits}" ]]; then
  echo "Public-tree files contain SSH-style repository URLs. Keep private repository locations out of tracked files:"
  echo "${ssh_url_hits}"
  exit 1
fi

external_ref_hits="$(
  rg -n \
    --glob 'README.md' \
    --glob 'Makefile' \
    --glob 'docs/**' \
    --glob '!scripts/check_private_boundaries.sh' \
    '\bexternal/' \
    "${ROOT_DIR}" \
    || true
)"
if [[ -n "${external_ref_hits}" ]]; then
  echo "Public-tree files should not depend on local external/ paths:"
  echo "${external_ref_hits}"
  exit 1
fi

echo "Private boundary checks passed"

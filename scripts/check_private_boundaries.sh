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

private_url_hits="$(
  rg -n \
    --hidden \
    --glob '!.git/**' \
    --glob '!external/**' \
    'github\.com[:/](TheDarkLightX/(ESSO|Morph|ZAG|Orchestration-Unit)|opentensor/bittensor)(\.git)?' \
    "${ROOT_DIR}" \
    | rg -v '/scripts/check_private_boundaries.sh:' || true
)"
if [[ -n "${private_url_hits}" ]]; then
  echo "Public-tree files contain upstream/private repo URLs. Use local-path references instead:"
  echo "${private_url_hits}"
  exit 1
fi

require_ssh_origin() {
  local label="$1"
  local repo_dir="$2"
  local expected="$3"

  if [[ ! -d "${repo_dir}/.git" ]]; then
    echo "Skipping ${label} origin check (repo not present): ${repo_dir}"
    return 0
  fi

  local actual
  actual="$(git -C "${repo_dir}" remote get-url origin)"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "${label} origin mismatch"
    echo "  expected: ${expected}"
    echo "  actual:   ${actual}"
    exit 1
  fi
}

require_ssh_origin "ESSO" "${ROOT_DIR}/external/ESSO" "git@github.com:TheDarkLightX/ESSO.git"
require_ssh_origin "Morph" "${ROOT_DIR}/external/Morph" "git@github.com:TheDarkLightX/Morph.git"
require_ssh_origin "ZAG" "${ROOT_DIR}/external/ZAG" "git@github.com:TheDarkLightX/ZAG.git"
require_ssh_origin "Orchestration-Unit" "${ROOT_DIR}/external/Orchestration-Unit" "git@github.com:TheDarkLightX/Orchestration-Unit.git"
require_ssh_origin "Bittensor" "${ROOT_DIR}/external/bittensor" "git@github.com:opentensor/bittensor.git"

echo "Private tooling boundaries verified"

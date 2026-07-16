#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRONTEND_DIR="${ROOT_DIR}/frontend"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

hash_tree() {
  local directory="$1"
  (
    cd "${directory}"
    LC_ALL=C find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum
  )
}

cd "${FRONTEND_DIR}"
npx --no-install vite build --emptyOutDir --outDir "${TMP_DIR}/first" >/dev/null
npx --no-install vite build --emptyOutDir --outDir "${TMP_DIR}/second" >/dev/null

bash "${ROOT_DIR}/scripts/check_frontend_dist_portable.sh" "${TMP_DIR}/first"
bash "${ROOT_DIR}/scripts/check_frontend_dist_portable.sh" "${TMP_DIR}/second"
hash_tree "${TMP_DIR}/first" > "${TMP_DIR}/first.sha256"
hash_tree "${TMP_DIR}/second" > "${TMP_DIR}/second.sha256"

if ! diff -u "${TMP_DIR}/first.sha256" "${TMP_DIR}/second.sha256"; then
  echo "Frontend production builds are not byte-for-byte reproducible." >&2
  exit 1
fi

echo "Frontend reproducibility check passed: two clean Vite builds are byte-identical."

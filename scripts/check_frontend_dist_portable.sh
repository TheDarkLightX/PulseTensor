#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${1:-${ROOT_DIR}/frontend/dist}"
INDEX_HTML="${DIST_DIR}/index.html"

if [[ ! -f "${INDEX_HTML}" ]]; then
  echo "Frontend entry point not found: ${INDEX_HTML}"
  echo "Run: npm --prefix frontend run build"
  exit 1
fi

if grep -nE '(src|href)="/' "${INDEX_HTML}"; then
  echo "Root-relative frontend asset reference found in ${INDEX_HTML}."
  echo "Static releases must use ./ paths so they work below an IPFS gateway CID path."
  exit 1
fi

if ! grep -qE '<script[^>]+type="module"[^>]+src="\./assets/[^\"]+\.js"' "${INDEX_HTML}"; then
  echo "No relative Vite module entry was found in ${INDEX_HTML}."
  exit 1
fi

while IFS= read -r asset_ref; do
  asset_path="${DIST_DIR}/${asset_ref#./}"
  if [[ ! -f "${asset_path}" ]]; then
    echo "Referenced frontend asset is missing: ${asset_ref}"
    exit 1
  fi
done < <(grep -oE '(src|href)="\./[^\"]+"' "${INDEX_HTML}" | sed -E 's/^(src|href)="(.*)"$/\2/' | LC_ALL=C sort -u)

while IFS= read -r stylesheet; do
  if grep -nE "url\((/|\"/|'/)" "${stylesheet}"; then
    echo "Root-relative CSS URL found in ${stylesheet#${DIST_DIR}/}."
    exit 1
  fi
done < <(find "${DIST_DIR}" -type f -name '*.css' | LC_ALL=C sort)

echo "Frontend dist portability check passed: all generated entry assets are relative."

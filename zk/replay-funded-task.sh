#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: bash zk/replay-funded-task.sh RISC0_ETHEREUM_CHECKOUT [NEW_JOURNAL_OUTPUT]" >&2
  exit 2
fi
upstream="$1"
fixtures="${root}/zk/tests/fixtures"

[[ "$(git -C "$upstream" rev-parse HEAD)" == ff30da77ba4afdd496290ebebedb205348b15d83 ]]
git -C "$upstream" diff --quiet HEAD -- contracts/src
openzeppelin="${upstream}/lib/openzeppelin-contracts"
[[ "$(git -C "$openzeppelin" rev-parse HEAD)" == acd4ff74de833399287ed6b31b4debf6b2b35527 ]]
git -C "$openzeppelin" diff --quiet HEAD -- contracts

stage="$(mktemp -d)"
trap 'rm -rf -- "$stage"' EXIT
mkdir -p "$stage"/{src,test,fixtures,lib/risc0,lib/openzeppelin,lib/forge-std}
cp "$root/zk/evm/foundry.toml" "$stage/"
cp "$root/zk/evm/FundedTask.t.sol" "$stage/test/"
cp -R "$root/src/." "$stage/src/"
cp -R "$upstream/contracts/src/." "$stage/lib/risc0/"
cp -R "$openzeppelin/contracts" "$stage/lib/openzeppelin/"
cp -R "$root/lib/forge-std/src/." "$stage/lib/forge-std/"
cp "$fixtures/journal.hex" "$fixtures/image_id.txt" "$stage/fixtures/"

if [[ $# -eq 2 ]]; then
  (cd "$stage" && forge test --match-test testWriteRealTaskJournal)
  (set -o noclobber; cat "$stage/fixtures/funded_task_journal.bin" > "$2")
  exit
fi

python3 - "$fixtures" "$stage/fixtures" <<'PY'
import sys
from pathlib import Path

source, output = map(Path, sys.argv[1:])
for name in ("funded_task_journal", "funded_task_receipt"):
    data = bytes.fromhex((source / f"{name}.hex").read_text())
    (output / f"{name}.bin").write_bytes(data)
PY
(
  cd "$root/zk"
  cargo run --quiet --locked --features receipt --bin check-receipt -- \
    "$(cat "$fixtures/image_id.txt")" "$stage/fixtures/funded_task_journal.bin" \
    "$stage/fixtures/funded_task_receipt.bin" > "$stage/fixtures/funded_task_seal.hex"
)
(cd "$stage" && forge test --match-test testSettleFundedTaskWithRealProof -vv)

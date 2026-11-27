# PulseTensor exact inference guest

This Rust package implements `PT_Q8_LINEAR_V1`. The same deterministic relation runs in the native CLI and in the
RISC Zero guest. The guest emits the exact 736-byte ABI journal only after checking the input commitment, model
commitment, all four scores, the lowest-index tie break, and the output commitment. Settlement reconstructs the
journal from the on-chain task and proof submission before verifying it.

## Run the local fixture

From the repository root, with Rustup and Python 3 installed:

```bash
mkdir -p runs/exact_guest
python3 - <<'PY'
from pathlib import Path

fixtures = Path("zk/tests/fixtures")
out = Path("runs/exact_guest")
for name in ("witness", "journal"):
    (out / f"{name}.bin").write_bytes(bytes.fromhex((fixtures / f"{name}.hex").read_text()))
PY
(
  cd zk
  cargo test --locked
  cargo run --locked -- evaluate ../runs/exact_guest/witness.bin
  cargo run --locked -- prepare ../runs/exact_guest/witness.bin \
    ../runs/exact_guest/journal.bin ../runs/exact_guest/job.bin
)
```

`prepare` creates a new file. Use a new output path on a rerun. For an actual task, use `evaluate` before posting
commitments. A provider can obtain the journal bytes with a read-only call to
`encodeExactInferencePublicValues(taskId, provider, beneficiary, classIndex, scores)` on the intended settlement
contract after the task is posted. Decode the returned `bytes` to a binary file before invoking `prepare`.

The 208-byte witness has 32 signed 16-bit little-endian inputs, four contiguous rows of 32 signed 8-bit weights,
and four signed 32-bit little-endian biases, in that order. The 944-byte guest input is the raw ABI journal followed
by that witness. A job file contains the private witness. Store it locally or share it only with the chosen prover.

The fixture tests signed limits, scores outside the `int32` range, and a tie for first place. The Foundry test
`testRustGuestJournalMatchesSolidityAbi` and frontend test `exactRustVector.test.ts` independently reproduce the
commitments and shared journal. The Rust tests compare 2,048 cases with an `i128` reference.

## Build and prove locally

Install `cargo-risczero` and `r0vm` version `3.1.0` and select the RISC Zero guest Rust toolchain with
`rzup install rust 1.88.0`. The upstream [3.1.0 release](https://github.com/risc0/risc0/releases/tag/v3.1.0) includes
both Linux tools in one archive. The local fixture requires no wallet or paid proving service.

```bash
(cd zk && RISC0_BUILD_LOCKED=1 cargo risczero bake -p pt-q8-linear-v1)
guest=zk/guest/elfs/pt-q8-linear-v1.elf
image_id=$(r0vm --elf "$guest" --id)
env -u RISC0_DEV_MODE r0vm -v --elf "$guest" \
  --initial-input runs/exact_guest/job.bin \
  --receipt runs/exact_guest/composite.receipt --receipt-kind composite
(
  cd zk
  cargo run --locked --features receipt --bin check-receipt -- "$image_id" \
    ../runs/exact_guest/journal.bin ../runs/exact_guest/composite.receipt
)
```

The composite receipt is for local verification. The checker verifies both the image ID and the full expected
journal with development mode disabled at compile time. For an authentic receipt generated with `--receipt-kind
groth16`, it also prints the 260-byte settlement seal as hex. The settlement adapter expects the RISC Zero 3.1.0
Groth16 seal with selector `0xe71e6620`. Local CPU Groth16 proving requires Docker. A deployable release requires a
reproducible build, a genuine Groth16 receipt checked through the pinned direct verifier, and a testnet canary. See
the [settlement specification](../docs/zk_exact_inference_v1.md) for the remaining release obligations.

## Local build evidence

Two clean builds under different directories on x86-64 Linux produced byte-identical program binaries and image
IDs with the toolchain above and the committed lockfile. The program SHA-256 was
`fdb75f647fb2b93140dac3d309ec896de04c4f793f23835b7b8f176f82c0b8e8`. The RISC Zero image ID was
`cc1901d9d3244317e6b4bfd9b248e8ab560d8880775258b6c99521cd4d4604bd`.

The fixture produced a genuine composite receipt in 3m27s of local wall time. With development mode disabled,
the checker accepted the receipt against the 736-byte fixture and rejected both a changed expected journal and a
changed image ID. This benchmark covers the fixed Q8 relation and local composite proving.

The same fixture produced a genuine Groth16 receipt in 6m10s on that CPU. The patched direct verifier and
PulseTensor adapter accepted its seal on a local EVM, using 237,185 gas for the verifier call in the test. An
altered image ID and an altered journal were both rejected. This is a local measurement of verification only.

## Replay a funded task locally

Use the pinned Foundry and Solidity versions in `scripts/toolchain.lock`. Install the project’s `forge-std`
dependency and use the upstream RISC Zero Ethereum checkout at `ff30da77ba4afdd496290ebebedb205348b15d83`
with its OpenZeppelin submodule initialized. From the repository root:

```bash
bash zk/replay-funded-task.sh /path/to/risc0-ethereum
```

The replay verifies the checked-in Groth16 receipt against the pinned image and journal. It then creates a local
task with fake native currency, rebuilds its settlement journal, submits the extracted seal, and checks both
withdrawals. This uses the real Core, settlement, adapter, and direct Groth16 verifier contracts. It is independent
of PulseChain RPCs and public testnet balances.

The local fixture funded 10,001 wei, credited 8,801 wei to the beneficiary and 1,200 wei to the treasury, and
withdrew both amounts. The proof took 5m57s of CPU wall time. The proof submission used 412,884 gas before
transaction and calldata charges. Deploying the four contracts in the local fixture used about 9.52 million gas
before transaction overhead or governance setup. These measurements are for the pinned local test profile.

To generate a new journal from the same local scenario, give the replay script a second argument with a new binary
output path. Pass that file to `prepare` with the committed witness, then prove the resulting job with `--receipt-kind
groth16` and verify the receipt with `check-receipt`.

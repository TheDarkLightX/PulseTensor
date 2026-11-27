use std::{env, fs::File, io::Read, process::ExitCode};

use bincode::Options;
use hex::FromHex;
use pulsetensor_exact::JOURNAL_BYTES;
use risc0_zkvm::{Digest, Receipt};

const RECEIPT_LIMIT: u64 = 64 * 1024 * 1024;
const GROTH16_SELECTOR: [u8; 4] = [0xe7, 0x1e, 0x66, 0x20];

fn run() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<_> = env::args().skip(1).collect();
    let [id, journal, receipt] = args.as_slice() else {
        return Err("usage: check-receipt IMAGE_ID JOURNAL.bin RECEIPT.bin".into());
    };
    let id = Digest::from_hex(id.trim_start_matches("0x"))?;
    let mut expected_journal = Vec::with_capacity(JOURNAL_BYTES + 1);
    File::open(journal)?
        .take((JOURNAL_BYTES + 1) as u64)
        .read_to_end(&mut expected_journal)?;
    if expected_journal.len() != JOURNAL_BYTES {
        return Err("expected journal must contain exactly 736 bytes".into());
    }
    let mut encoded = Vec::new();
    File::open(receipt)?
        .take(RECEIPT_LIMIT + 1)
        .read_to_end(&mut encoded)?;
    if encoded.len() as u64 > RECEIPT_LIMIT {
        return Err("receipt exceeds 64 MiB".into());
    }
    let receipt: Receipt = bincode::DefaultOptions::new()
        .with_fixint_encoding()
        .with_limit(RECEIPT_LIMIT)
        .reject_trailing_bytes()
        .deserialize(&encoded)?;
    receipt.verify(id)?;
    if receipt.journal.bytes != expected_journal {
        return Err("verified receipt journal differs from the expected journal".into());
    }

    if let Ok(groth16) = receipt.inner.groth16() {
        if groth16.verifier_parameters.as_bytes()[..4] != GROTH16_SELECTOR
            || groth16.seal.len() != 256
        {
            return Err(
                "receipt does not match the supported Groth16 selector and seal length".into(),
            );
        }
        println!(
            "0x{}{}",
            hex::encode(GROTH16_SELECTOR),
            hex::encode(&groth16.seal)
        );
    }
    eprintln!("Verified image ID and exact 736-byte journal.");
    Ok(())
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("{error}");
            ExitCode::FAILURE
        }
    }
}

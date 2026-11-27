use std::io::Read;

use pulsetensor_exact::{verify_job, JOB_BYTES, JOURNAL_BYTES};
use risc0_zkvm::guest::env;

fn main() {
    let mut input = [0; JOB_BYTES];
    let mut stdin = env::stdin();
    stdin.read_exact(&mut input).expect("incomplete job");
    assert_eq!(
        stdin.read(&mut [0]).expect("read stdin"),
        0,
        "trailing input"
    );
    verify_job(&input).expect("PT_Q8_LINEAR_V1 rejected job");
    env::commit_slice(&input[..JOURNAL_BYTES]);
}

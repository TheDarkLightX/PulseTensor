use std::{
    env,
    fs::File,
    io::{self, Read, Write},
    process::ExitCode,
};

use pulsetensor_exact::{evaluate, verify_journal, Inference, JOURNAL_BYTES, WITNESS_BYTES};

fn read_bounded(path: &str, size: usize) -> io::Result<Vec<u8>> {
    let mut bytes = Vec::with_capacity(size + 1);
    File::open(path)?
        .take((size + 1) as u64)
        .read_to_end(&mut bytes)?;
    if bytes.len() != size {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            format!("{path} must be {size} bytes"),
        ));
    }
    Ok(bytes)
}

fn print_result(result: &Inference) {
    println!(
        "input_commitment=0x{}",
        hex::encode(result.input_commitment)
    );
    println!(
        "model_commitment=0x{}",
        hex::encode(result.model_commitment)
    );
    println!("class_index={}", result.class_index);
    println!("scores={:?}", result.scores);
    println!(
        "output_commitment=0x{}",
        hex::encode(result.output_commitment)
    );
}

fn run() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<_> = env::args().skip(1).collect();
    match args.as_slice() {
        [command, witness] if command == "evaluate" => {
            let witness = read_bounded(witness, WITNESS_BYTES)?;
            let result = evaluate(&witness).map_err(|error| format!("{error:?}"))?;
            print_result(&result);
        }
        [command, witness, journal, job] if command == "prepare" => {
            let witness = read_bounded(witness, WITNESS_BYTES)?;
            let journal = read_bounded(journal, JOURNAL_BYTES)?;
            let result = verify_journal(&journal, &witness).map_err(|error| format!("{error:?}"))?;
            let mut output = File::create_new(job)?;
            output.write_all(&journal)?;
            output.write_all(&witness)?;
            print_result(&result);
        }
        _ => return Err("usage: pulsetensor-exact evaluate WITNESS.bin | prepare WITNESS.bin JOURNAL.bin JOB.bin".into()),
    }
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

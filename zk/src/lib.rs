use hex_literal::hex;
use sha2::{Digest, Sha256};

pub const FEATURES: usize = 32;
pub const CLASSES: usize = 4;
pub const WORD_BYTES: usize = 32;
pub const WITNESS_BYTES: usize = 2 * FEATURES + CLASSES * FEATURES + 4 * CLASSES;
pub const JOURNAL_BYTES: usize = 23 * WORD_BYTES;
pub const JOB_BYTES: usize = JOURNAL_BYTES + WITNESS_BYTES;

type Word = [u8; WORD_BYTES];

// Keccak-256 domains and the SHA-256 relation identifier from the V1 wire spec.
const INPUT_DOMAIN: Word = hex!("f382693f0ad193d4c7b9759c75a65bc866ec3a170c9ca80b66cb0165c8cbf722");
const MODEL_DOMAIN: Word = hex!("6d312c910fc3d92604a1443b0db94b12f2362e1c6054471301051477dae54f18");
const OUTPUT_DOMAIN: Word =
    hex!("b519cb2fd1de10558a2fb5a800edd48b08f0dde5e55498cdd40a9857e311bffb");
const JOURNAL_DOMAIN: Word =
    hex!("4dbb238f363195ab8cfb4cef81c91a886c788ff98991ecde4840fa58f3f43b51");
const RELATION_ID: Word = hex!("48a3045b928f9e95b25747a674941e3c55668f2bdb53cf4cf4822bc924feed44");

#[derive(Debug, PartialEq, Eq)]
pub enum Error {
    JournalLength,
    WitnessLength,
    JobLength,
    NoncanonicalJournal,
    InputCommitment,
    ModelCommitment,
    Output,
    Overflow,
}

#[derive(Debug, PartialEq, Eq)]
pub struct Inference {
    pub input_commitment: Word,
    pub model_commitment: Word,
    pub class_index: u8,
    pub scores: [i64; CLASSES],
    pub output_commitment: Word,
}

fn integer_word(value: i64) -> Word {
    let mut word = [if value < 0 { 0xff } else { 0 }; WORD_BYTES];
    word[24..].copy_from_slice(&value.to_be_bytes());
    word
}

fn commitment(domain: Word, values: impl IntoIterator<Item = i64>) -> Word {
    let mut hash = Sha256::new();
    hash.update(domain);
    hash.update(integer_word(1));
    for value in values {
        hash.update(integer_word(value));
    }
    hash.finalize().into()
}

/// Decodes 32 little-endian i16s, 128 row-major i8s, then four little-endian i32s.
pub fn evaluate(witness: &[u8]) -> Result<Inference, Error> {
    if witness.len() != WITNESS_BYTES {
        return Err(Error::WitnessLength);
    }
    let (input_bytes, model) = witness.split_at(2 * FEATURES);
    let (weight_bytes, bias_bytes) = model.split_at(CLASSES * FEATURES);
    let mut input = [0i16; FEATURES];
    for (value, bytes) in input.iter_mut().zip(input_bytes.chunks_exact(2)) {
        *value = i16::from_le_bytes([bytes[0], bytes[1]]);
    }
    let mut biases = [0i32; CLASSES];
    for (value, bytes) in biases.iter_mut().zip(bias_bytes.chunks_exact(4)) {
        *value = i32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]);
    }

    let mut scores = [0i64; CLASSES];
    let mut class_index = 0;
    for (row, weights) in weight_bytes.chunks_exact(FEATURES).enumerate() {
        let mut score = i64::from(biases[row]);
        for (x, weight) in input.iter().zip(weights) {
            let product = i64::from(*x)
                .checked_mul(i64::from(*weight as i8))
                .ok_or(Error::Overflow)?;
            score = score.checked_add(product).ok_or(Error::Overflow)?;
        }
        scores[row] = score;
        if score > scores[class_index] {
            class_index = row;
        }
    }

    Ok(Inference {
        input_commitment: commitment(INPUT_DOMAIN, input.map(i64::from)),
        model_commitment: commitment(
            MODEL_DOMAIN,
            weight_bytes
                .iter()
                .map(|&weight| i64::from(weight as i8))
                .chain(biases.map(i64::from)),
        ),
        class_index: class_index as u8,
        scores,
        output_commitment: commitment(
            OUTPUT_DOMAIN,
            core::iter::once(class_index as i64).chain(scores),
        ),
    })
}

fn word(journal: &[u8], index: usize) -> &[u8] {
    &journal[index * WORD_BYTES..(index + 1) * WORD_BYTES]
}

pub fn verify_journal(journal: &[u8], witness: &[u8]) -> Result<Inference, Error> {
    if journal.len() != JOURNAL_BYTES {
        return Err(Error::JournalLength);
    }

    let treasury = word(journal, 14);
    let fee_bps = word(journal, 13);
    let fee = u16::from_be_bytes([fee_bps[30], fee_bps[31]]);
    let mechanism = word(journal, 7);
    let mechanism_id = u16::from_be_bytes([mechanism[30], mechanism[31]]);
    if word(journal, 0) != JOURNAL_DOMAIN
        || word(journal, 1) != integer_word(1)
        || word(journal, 9) != RELATION_ID
        || word(journal, 6)[..30] != [0; 30]
        || mechanism != integer_word(i64::from(mechanism_id))
        || mechanism_id > 1_023
        || word(journal, 8)[..24] != [0; 24]
        || fee_bps != integer_word(i64::from(fee))
        || fee > 3_000
        || treasury[..12] != [0; 12]
        || (fee == 0) != (treasury == [0; WORD_BYTES])
        || [3, 21, 22].iter().any(|&index| {
            let address = word(journal, index);
            address[..12] != [0; 12] || address[12..] == [0; 20]
        })
    {
        return Err(Error::NoncanonicalJournal);
    }

    // Chain, settlement, task and payee identity are authenticated by the contract
    // when it reconstructs the whole journal, not by the untrusted prover input.
    let result = evaluate(witness)?;
    if word(journal, 11) != result.input_commitment {
        return Err(Error::InputCommitment);
    }
    if word(journal, 12) != result.model_commitment {
        return Err(Error::ModelCommitment);
    }
    if word(journal, 15) != integer_word(i64::from(result.class_index))
        || word(journal, 20) != result.output_commitment
        || result
            .scores
            .iter()
            .enumerate()
            .any(|(index, &score)| word(journal, 16 + index) != integer_word(score))
    {
        return Err(Error::Output);
    }
    Ok(result)
}

pub fn verify_job(job: &[u8]) -> Result<Inference, Error> {
    if job.len() != JOB_BYTES {
        return Err(Error::JobLength);
    }
    let (journal, witness) = job.split_at(JOURNAL_BYTES);
    verify_journal(journal, witness)
}

use pulsetensor_exact::{evaluate, verify_job, verify_journal, Error, JOB_BYTES, JOURNAL_BYTES};

fn fixture(content: &str) -> Vec<u8> {
    hex::decode(content.trim()).expect("hex fixture")
}

#[test]
fn verifies_the_cross_language_fixture() {
    let journal = fixture(include_str!("fixtures/journal.hex"));
    let witness = fixture(include_str!("fixtures/witness.hex"));
    let job = [journal, witness].concat();
    let result = verify_job(&job).unwrap();
    assert_eq!(job.len(), JOB_BYTES);
    assert_eq!(result.class_index, 2);
    assert_eq!(result.scores[2], result.scores[3]);
    assert!(result.scores[0] < i64::from(i32::MIN));
    assert!(result.scores[2] > i64::from(i32::MAX));
}

#[test]
fn rejects_invalid_relation_fields_and_noncanonical_sizes() {
    let journal = fixture(include_str!("fixtures/journal.hex"));
    let witness = fixture(include_str!("fixtures/witness.hex"));
    for (word, expected) in [
        (0, Error::NoncanonicalJournal),
        (1, Error::NoncanonicalJournal),
        (6, Error::NoncanonicalJournal),
        (7, Error::NoncanonicalJournal),
        (8, Error::NoncanonicalJournal),
        (9, Error::NoncanonicalJournal),
        (11, Error::InputCommitment),
        (12, Error::ModelCommitment),
        (13, Error::NoncanonicalJournal),
        (14, Error::NoncanonicalJournal),
        (15, Error::Output),
        (16, Error::Output),
        (17, Error::Output),
        (18, Error::Output),
        (19, Error::Output),
        (20, Error::Output),
        (21, Error::NoncanonicalJournal),
        (22, Error::NoncanonicalJournal),
    ] {
        let mut corrupt = journal.clone();
        corrupt[32 * word] ^= 1;
        assert_eq!(
            verify_journal(&corrupt, &witness),
            Err(expected),
            "word {word}"
        );
    }
    for (index, expected) in [
        (0, Error::InputCommitment),
        (64, Error::ModelCommitment),
        (192, Error::ModelCommitment),
    ] {
        let mut corrupt = witness.clone();
        corrupt[index] ^= 1;
        assert_eq!(verify_journal(&journal, &corrupt), Err(expected));
    }
    assert_eq!(
        verify_journal(&journal[..JOURNAL_BYTES - 1], &witness),
        Err(Error::JournalLength)
    );
    assert_eq!(
        verify_journal(&journal, &witness[..witness.len() - 1]),
        Err(Error::WitnessLength)
    );
    let mut oversized = [journal, witness].concat();
    oversized.push(0);
    assert_eq!(verify_job(&oversized), Err(Error::JobLength));
}

#[test]
fn agrees_with_an_i128_reference_over_signed_boundary_and_seeded_cases() {
    let mut random = 0x37a2_6d8b_u32;
    for case in 0..2048 {
        let mut witness = fixture(include_str!("fixtures/witness.hex"));
        if case > 0 {
            for byte in &mut witness {
                random ^= random << 13;
                random ^= random >> 17;
                random ^= random << 5;
                *byte = random as u8;
            }
        }
        let scores: [i128; 4] = std::array::from_fn(|row| {
            let bias =
                i32::from_le_bytes(witness[192 + row * 4..196 + row * 4].try_into().unwrap());
            i128::from(bias)
                + (0..32)
                    .map(|column| {
                        let x = i16::from_le_bytes(
                            witness[2 * column..2 * column + 2].try_into().unwrap(),
                        );
                        let weight = witness[64 + row * 32 + column] as i8;
                        i128::from(x) * i128::from(weight)
                    })
                    .sum::<i128>()
        });
        let max = scores.iter().max().unwrap();
        let expected_class = scores.iter().position(|value| value == max).unwrap();
        let actual = evaluate(&witness).unwrap();
        assert_eq!(actual.scores.map(i128::from), scores, "case {case}");
        assert_eq!(
            usize::from(actual.class_index),
            expected_class,
            "case {case}"
        );
    }
}

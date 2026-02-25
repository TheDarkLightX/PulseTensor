# Signer Selection Checklist

Last updated: 2026-02-25

## Eligibility

- Demonstrated record of operational reliability in production systems.
- Ability to respond during incident windows within agreed SLA.
- No unresolved conflicts of interest that create unilateral influence risk.
- Willingness to publish role category and governance participation record.

## Security Controls

- Uses a dedicated hardware wallet for PulseTensor governance only.
- Uses passphrase/PIN protection and offline seed backup.
- Does not store seed phrase in cloud notes, chats, or password managers.
- Uses isolated device profile for transaction review/signing.
- Commits to mandatory transaction simulation before signature.

## Independence and Distribution

- Signer is not controlled by founder legal entity (for independent seats).
- Signer shares no custody infrastructure with another signer.
- Signer is in a distinct failure domain:
  - different operator organization,
  - different geographic location,
  - different network/provider profile where possible.

## Operational Readiness

- Completed governance runbook walkthrough.
- Completed queue/cancel/execute dry run against test deployment.
- Completed key-loss and compromised-key rotation drill.
- Can verify contract target/function arguments before signing.

## Policy Acceptance

- Accepts committee charter: `docs/security/governance_committee_charter.md`.
- Accepts launch controls: `docs/security/launch_controls.md`.
- Accepts governance queue runbook: `docs/security/governance_queue_runbook.md`.
- Accepts public disclosure requirements for governance actions.

## Minimum Bar to Activate

- At least 7 approved signers.
- At least 3 independent non-founder signers.
- 4-of-7 threshold configured and validated via test transaction.
- Emergency signer replacement playbook tested once before mainnet activation.

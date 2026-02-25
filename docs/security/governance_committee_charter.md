# Governance Committee Charter

Last updated: 2026-02-25

## Purpose

- Define who controls privileged PulseTensor governance actions.
- Prevent founder-single-key control while preserving founder participation.
- Establish auditable operating rules for signer behavior, key custody, and incident response.

## Scope

- Applies to governance actions executed against:
  - `PulseTensorCore` subnet governance queues.
  - `PulseTensorInferenceSettlement` policy governance queues.
- Applies to treasury sink and miner-sink address updates that affect fee flows.

## Committee Composition

- Target size: 7 signers.
- Threshold: 4-of-7 for standard operations.
- Seat allocation baseline:
  - 1 founder seat.
  - 2 core engineering seats.
  - 2 independent ecosystem/community seats.
  - 1 external security seat.
  - 1 foundation/operations seat.

## Independence Rules

- Founder must not control more than 1 active signer key.
- At least 3 signers must be operationally independent from founder-controlled entities.
- No signer may share a seed phrase, hardware wallet, or backup secret with another signer.
- Every signer must maintain a dedicated hardware wallet used only for governance signing.

## Authority Boundary

- Committee controls only governed contract actions through the governance contract address.
- Committee does not bypass on-chain queue delay, queue-origin binding, or expiry semantics.
- Committee cannot violate protocol hard caps encoded in contracts (for example fee caps).

## Decision Classes

- Routine parameter tuning:
  - Follow published change request template.
  - Minimum review: 2 reviewers before execution.
- High-impact changes (treasury sink changes, pause/unpause, fee policy updates):
  - Require explicit rationale and rollback condition in public notes.
  - Require at least one independent (non-core) signer approval.
- Emergency actions:
  - Allowed only for active security incidents.
  - Post-incident report required within 72 hours.

## Signer Lifecycle

- Onboarding:
  - Must pass `docs/security/signer_selection_checklist.md`.
  - Must complete dry-run signing and recovery drill.
- Rotation:
  - Planned rotation at least every 12 months, or immediately on compromise risk.
  - Queue entries created by prior governance identity must be canceled/requeued after governance changes.
- Removal:
  - Immediate removal for key compromise, policy breach, or prolonged non-responsiveness.

## Transparency and Records

- Publish:
  - Current signer set and role categories.
  - Threshold configuration.
  - Governance change log (queued, executed, canceled, expired).
- Retain deterministic evidence artifacts for governance actions under `runs/`.

## Emergency Response

- If signer key compromise is suspected:
  - Freeze new high-impact actions.
  - Rotate compromised signer key.
  - Revalidate pending queued actions before execution.
- If governance operation repeatedly fails queue-origin checks:
  - Cancel stale queue entries.
  - Requeue under current governance identity.

## Review Cadence

- Quarterly review:
  - Signer activity and independence.
  - Incident metrics and near misses.
  - Threshold suitability and liveness.

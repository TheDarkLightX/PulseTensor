# Multisig Operations Standard

Last updated: 2026-02-25

## Objective

- Operate PulseTensor governance through a production-grade multisig comparable to Safe (formerly Gnosis Safe).
- Keep policy control human-accountable and deterministic.
- Keep signer actions bounded by on-chain protocol and queue controls.

## Recommended Stack

- Governance account: Safe smart account style multisig.
- Signer set: 7 owners.
- Threshold: 4 signatures.
- PulseTensor wiring:
  - Configure the multisig contract as `subnetGovernance`.
  - Execute queue/cancel/configure calls from the same multisig identity.

## Chain Support and Deployment Policy

- Prefer official Safe deployments and verified addresses when available.
- If chain support is unavailable or unofficial:
  - deploy Safe contracts from official Safe smart account sources,
  - verify deployed bytecode and initialization parameters,
  - document addresses and deployment receipts under `runs/deployments/`.
- Do not trust unverified third-party "Safe" deployments.

## Required Signer OPSEC

- Hardware-wallet-only signing.
- Human-readable transaction decoding before signature.
- Independent verification of destination, calldata, and value.
- No blind signing of opaque payloads.

## Transaction Policy

- Routine updates:
  - Require simulation prior to final signature.
  - Require change log entry with reason, expected effect, rollback condition.
- High-impact updates:
  - Require an extra review checkpoint (at least one independent signer notes review in writing).
  - Avoid batching unrelated high-impact actions in one transaction.

## Queue Discipline for PulseTensor

- Core and settlement queues bind execution to `queuedBy` governance identity.
- Any governance identity rotation requires:
  - cancel stale queued entries,
  - requeue under new governance identity.
- Do not execute near-expiry queue entries without revalidating parameters.

## Optional Hardening Add-Ons

- Safe guard/module policies to restrict unsafe call patterns.
- Additional timelock layer outside protocol queues for meta-governance actions.
- Separate treasury sink multisig from protocol-parameter multisig if operational capacity allows.

## Incident Handling

- Key compromise suspected:
  - pause new high-impact actions,
  - rotate signer,
  - review all queued actions for stale assumptions.
- Signing outage:
  - invoke replacement plan from charter,
  - validate threshold liveness after replacement.

## Evidence and Auditability

- Archive:
  - multisig transaction IDs/hashes,
  - simulation artifacts,
  - signer review notes,
  - executed action receipts.
- Keep artifacts deterministic and stored under `runs/` for audit packet reuse.

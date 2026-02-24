# Governance Queue Runbook

Last updated: 2026-02-23

## Scope

- Core owner-action queue in `PulseTensorCore`.
- Settlement policy queues in `PulseTensorInferenceSettlement`.

## Alert Conditions

- `queued=true && expired=true` for any privileged action for more than 1 monitoring interval.
- Repeated cancel/requeue loops for the same logical action in a short window.
- Execution attempt failures for `OwnerActionQueuedByMismatch`, `OwnerActionExpired`, or `GovernanceActionQueuedByMismatch`.
- Sudden increase in queued privileged actions per subnet.

## Monitoring Signals

- Queue depth per subnet.
- Oldest queued action age and time-to-expiry.
- Count of expired queued actions.
- Count of queue-origin mismatch execution failures.

## Response Steps

1. Identify affected `netuid`, `actionId`, and current governance identity.
2. Confirm whether queued action origin (`queuedBy`) still matches intended governance operator.
3. If stale or mismatched, cancel and requeue under current governance.
4. Re-verify target parameters before re-execution.
5. Record incident details and operator decisions.

## Escalation

- Escalate immediately if:
  - repeated expiry/mismatch events occur across multiple subnets, or
  - privileged action execution repeatedly fails after requeue.
- Require two-person review for emergency governance changes under incident conditions.

## Postmortem Template

- Incident window (start/end UTC).
- Affected subnets/actions.
- Root cause category (stale queue, governance rotation mismatch, operator error, other).
- Corrective actions and test coverage updates.

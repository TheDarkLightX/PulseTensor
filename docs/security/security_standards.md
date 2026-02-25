# Security Standards Baseline

As of February 25, 2026, PulseTensor hardening tracks the following primary standards:

- OWASP SCSVS (control verification standard): `https://scs.owasp.org/SCSVS/`
- OWASP Smart Contract Top 10 (risk taxonomy, 2026): `https://scs.owasp.org/sctop10/`
- OWASP SCWE (weakness enumeration): `https://scs.owasp.org/SCWE/`
- EEA EthTrust Security Levels v3 (specification baseline): `https://entethalliance.org/groups/ethtrust/`
- Solidity known compiler bugs (official bug feed): `https://docs.soliditylang.org/en/latest/bugs.html`
- OpenZeppelin Contracts governance/time-delay patterns: `https://docs.openzeppelin.com/contracts/5.x/api/governance#TimelockController`
- Compound Timelock grace-period pattern (reference implementation): `https://raw.githubusercontent.com/compound-finance/compound-protocol/master/contracts/Timelock.sol`
- Safe smart account (multisig baseline): `https://docs.safe.global/home/safe-smart-account`
- Safe advanced setup patterns (guards/modules): `https://docs.safe.global/advanced/smart-account-guards`
- SWC registry (legacy taxonomy; not primary due maintenance status): `https://github.com/SmartContractSecurity/SWC-registry`

## Operational policy

- Control mapping is stored in `docs/security/control_matrix.json`.
- Security pipeline is fail-closed:
  - compiler bug gate,
  - control-matrix coverage gate,
  - anti-pattern gate,
  - locked Slither exclusion gate,
  - locked Mythril SWC allowlist gate,
  - static analysis + deterministic fuzz + deterministic invariants,
  - artifact freshness gate against explicit manifests.
- Solidity compiler policy requires a version with no active known compiler bugs for the configured build profile.
- Slither exclusions are allowlisted in `docs/security/slither_exclusions.allowlist` and hash-locked in `docs/security/slither_exclusions.lock`.
- Mythril SWC ignores are allowlisted in `docs/security/mythril_ignored_swc.allowlist` and hash-locked in `docs/security/mythril_ignored_swc.lock`.
- Deterministic evidence artifacts are listed in:
  - `docs/security/artifact_manifest.security.txt`
  - `docs/security/artifact_manifest.release.txt`
- Security readiness docs are mandatory and validated by gate:
  - `docs/security/external_audit_plan.md`
  - `docs/security/governance_queue_runbook.md`
  - `docs/security/launch_controls.md`
  - `docs/security/governance_committee_charter.md`
  - `docs/security/signer_selection_checklist.md`
  - `docs/security/multisig_operations.md`
- Governance queue policy requires explicit queue lifecycle controls for privileged updates (queue/cancel/readiness/expiry).
- Governance queue policy requires bounded action expiry and requeue-on-stale semantics for both core owner-action queues and settlement policy queues.
- Governance queue policy requires queue-origin binding: execution must be authorized by the same governance identity that queued the action, and governance rotations must explicitly cancel/requeue stale entries.
- Governance queue policy requires queue-state observability (`readyAt`, `queuedBy`, readiness/expiry flags) for deterministic operator monitoring.
- Governance committee policy requires founder-balanced multisig controls with explicit signer independence and hardware-key custody requirements.
- Multisig operations policy requires production-grade multisig controls, deterministic review/simulation discipline, and documented signer rotation/incident procedures.
- Pause policy requires resolution liveness: paused mode must not block reveal/challenge settlement for already pending commitments.

## Practical interpretation

- OWASP Top 10 drives threat prioritization.
- OWASP SCSVS drives verification control families and evidence.
- EthTrust drives audit-readiness level targeting (S/M now, Q tracked for mainnet-candidate hardening).

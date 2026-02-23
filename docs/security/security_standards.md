# Security Standards Baseline

As of February 22, 2026, PulseTensor hardening tracks the following primary standards:

- OWASP SCSVS (control verification standard): `https://scs.owasp.org/SCSVS/`
- OWASP Smart Contract Top 10 (risk taxonomy, 2026): `https://scs.owasp.org/sctop10/`
- EEA EthTrust Security Levels v3 (specification baseline): `https://entethalliance.org/groups/ethtrust/`
- Solidity known compiler bugs (official bug feed): `https://docs.soliditylang.org/en/latest/bugs.html`
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
  - `docs/security/artifact_manifest.esso.txt`
  - `docs/security/artifact_manifest.release.txt`
- Governance queue policy requires explicit queue lifecycle controls for privileged updates (queue/cancel/readiness/expiry).
- Governance queue policy requires queue-origin binding: execution must be authorized by the same governance identity that queued the action, and governance rotations must explicitly cancel/requeue stale entries.
- Governance queue policy requires queue-state observability (`readyAt`, `queuedBy`, readiness/expiry flags) for deterministic operator monitoring.
- Pause policy requires resolution liveness: paused mode must not block reveal/challenge settlement for already pending commitments.

## Practical interpretation

- OWASP Top 10 drives threat prioritization.
- OWASP SCSVS drives verification control families and evidence.
- EthTrust drives audit-readiness level targeting (S/M now, Q tracked for mainnet-candidate hardening).

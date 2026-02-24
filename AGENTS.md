# PulseTensor Agent Instructions

## Mission

- Build PulseTensor for Pulsechain by reusing proven Bittensor mechanisms where low-risk.
- Improve algorithm design and security with deterministic, fail-closed evidence.
- Treat correctness as fail-closed: no unverifiable claims.

## Non-Negotiable Rules

- Never claim "verified/proved" without successful deterministic checks.
- Prefer deterministic local commands, fixed seeds, and captured artifacts under `runs/`.
- Counterexamples override hypotheses.
- Keep protocol runtime independent from optional research tooling.

## Required Check Surface Before Promotion

- Canonical release gate: `make verify-release`
- Equivalent explicit checks:
  - `forge test`
  - `bash scripts/check_security.sh`
  - `bash scripts/verify_toolchain.sh`
  - `bash scripts/check_private_boundaries.sh`

If any check fails, treat the candidate as not ready.

## Swarm Output Discipline

- For each hypothesis: include at least one support recipe and one refute recipe.
- Support recipe passes when hypothesis holds.
- Refute recipe passes only when a counterexample is found.
- Include concrete command argv and expected artifact capture paths.

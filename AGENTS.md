# PulseTensor Agent Instructions

## Mission

- Build PulseTensor for Pulsechain by reusing proven Bittensor mechanisms where low-risk.
- Improve algorithm design and security with Morph, ESSO, and ZAG.
- Treat correctness as fail-closed: no unverifiable claims.

## Non-Negotiable Rules

- Never claim "verified/proved" without successful deterministic checks.
- Prefer deterministic local commands, fixed seeds, and captured artifacts under `runs/`.
- Counterexamples override hypotheses.
- Keep protocol runtime independent from external research tools (Morph/ESSO/ZAG are offline tooling only).

## Required Check Surface Before Promotion

- Canonical release gate: `make verify-release`
- Equivalent explicit checks:
  - `forge test`
  - `bash scripts/check_security.sh`
  - `bash scripts/check_esso.sh`
  - `bash scripts/check_morph.sh`
  - `bash scripts/check_zag.sh quick`
  - `bash scripts/check_orch_unit.sh`

If any check fails, treat the candidate as not ready.

## Skills To Prefer

- `morph-orch-unit` for Morph discovery/evidence bundles.
- `esso-best-practices` for ESSO model/verify workflows.
- `reformulation-innovation-lab` for novelty-first hypothesis loops.
- `rlm-subagent-collab` for multi-agent orchestration with folded context.

## Swarm Output Discipline

- For each hypothesis: include at least one support recipe and one refute recipe.
- Support recipe passes when hypothesis holds.
- Refute recipe passes only when a counterexample is found.
- Include concrete command argv and expected artifact capture paths.

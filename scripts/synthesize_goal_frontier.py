#!/usr/bin/env python3
"""Deterministic multi-goal safety frontier synthesis over finite turn-based games.

This tool is intentionally lightweight and public-facing:
- no private/internal toolchain dependency
- deterministic enumeration order and strategy tie-breaking
- JSON input/output suitable for CI artifacts under runs/
"""

from __future__ import annotations

import argparse
import hashlib
import json
from dataclasses import dataclass
from itertools import combinations
from pathlib import Path
from typing import Dict, List, Sequence, Set, Tuple

SCHEMA = "pulsetensor/goal-frontier-model/v1"
REPORT_SCHEMA = "pulsetensor/goal-frontier-report/v1"
SCRIPT_VERSION = "v1"


class ModelError(ValueError):
    """Raised when the frontier model is invalid."""


@dataclass(frozen=True)
class Transition:
    action: str
    to_state: str


@dataclass(frozen=True)
class State:
    controller: str
    labels: Tuple[str, ...]
    transitions: Tuple[Transition, ...]


@dataclass(frozen=True)
class Goal:
    goal_id: str
    description: str
    forbidden_labels: Tuple[str, ...]


@dataclass(frozen=True)
class ParsedModel:
    initial_state: str
    states: Dict[str, State]
    goals: Tuple[Goal, ...]


def _sorted_unique_strings(items: Sequence[str], *, field: str) -> Tuple[str, ...]:
    out: List[str] = []
    seen: Set[str] = set()
    for raw in items:
        if not isinstance(raw, str) or raw.strip() == "":
            raise ModelError(f"{field} entries must be non-empty strings")
        value = raw.strip()
        if value in seen:
            continue
        seen.add(value)
        out.append(value)
    out.sort()
    return tuple(out)


def _parse_state(state_name: str, payload: object) -> State:
    if not isinstance(payload, dict):
        raise ModelError(f"state '{state_name}' must be an object")

    controller = payload.get("controller")
    if controller not in {"system", "environment"}:
        raise ModelError(
            f"state '{state_name}' has invalid controller {controller!r}; "
            "expected 'system' or 'environment'"
        )

    raw_labels = payload.get("labels", [])
    if not isinstance(raw_labels, list):
        raise ModelError(f"state '{state_name}' labels must be a list")
    labels = _sorted_unique_strings(raw_labels, field=f"state '{state_name}' labels")

    raw_transitions = payload.get("transitions")
    if not isinstance(raw_transitions, list) or len(raw_transitions) == 0:
        raise ModelError(
            f"state '{state_name}' must define at least one transition"
        )

    transitions: List[Transition] = []
    seen_pairs: Set[Tuple[str, str]] = set()
    for index, raw_transition in enumerate(raw_transitions):
        if not isinstance(raw_transition, dict):
            raise ModelError(
                f"state '{state_name}' transition[{index}] must be an object"
            )
        action = raw_transition.get("action")
        to_state = raw_transition.get("to")
        if not isinstance(action, str) or action.strip() == "":
            raise ModelError(
                f"state '{state_name}' transition[{index}] action must be non-empty string"
            )
        if not isinstance(to_state, str) or to_state.strip() == "":
            raise ModelError(
                f"state '{state_name}' transition[{index}] to must be non-empty string"
            )
        key = (action.strip(), to_state.strip())
        if key in seen_pairs:
            continue
        seen_pairs.add(key)
        transitions.append(Transition(action=key[0], to_state=key[1]))

    transitions.sort(key=lambda t: (t.action, t.to_state))
    return State(
        controller=controller,
        labels=labels,
        transitions=tuple(transitions),
    )


def _parse_goal(index: int, payload: object) -> Goal:
    if not isinstance(payload, dict):
        raise ModelError(f"goals[{index}] must be an object")

    goal_id = payload.get("id")
    if not isinstance(goal_id, str) or goal_id.strip() == "":
        raise ModelError(f"goals[{index}] missing non-empty id")

    description = payload.get("description")
    if not isinstance(description, str) or description.strip() == "":
        raise ModelError(f"goal '{goal_id}' missing non-empty description")

    raw_forbidden = payload.get("forbidden_labels")
    if not isinstance(raw_forbidden, list) or len(raw_forbidden) == 0:
        raise ModelError(
            f"goal '{goal_id}' must include non-empty forbidden_labels list"
        )
    forbidden = _sorted_unique_strings(
        raw_forbidden, field=f"goal '{goal_id}' forbidden_labels"
    )

    return Goal(
        goal_id=goal_id.strip(),
        description=description.strip(),
        forbidden_labels=forbidden,
    )


def parse_model(model_path: Path, *, max_goals: int) -> ParsedModel:
    payload = json.loads(model_path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ModelError("model root must be an object")

    schema = payload.get("schema")
    if schema != SCHEMA:
        raise ModelError(f"unsupported schema {schema!r}; expected {SCHEMA!r}")

    initial_state = payload.get("initial_state")
    if not isinstance(initial_state, str) or initial_state.strip() == "":
        raise ModelError("initial_state must be a non-empty string")
    initial_state = initial_state.strip()

    raw_states = payload.get("states")
    if not isinstance(raw_states, dict) or len(raw_states) == 0:
        raise ModelError("states must be a non-empty object")

    states: Dict[str, State] = {}
    for state_name in sorted(raw_states.keys()):
        if not isinstance(state_name, str) or state_name.strip() == "":
            raise ModelError("state names must be non-empty strings")
        normalized = state_name.strip()
        states[normalized] = _parse_state(normalized, raw_states[state_name])

    if initial_state not in states:
        raise ModelError(f"initial_state '{initial_state}' is not a known state")

    # Ensure all transition targets exist.
    for state_name, state in states.items():
        for transition in state.transitions:
            if transition.to_state not in states:
                raise ModelError(
                    f"state '{state_name}' transition target '{transition.to_state}' does not exist"
                )

    raw_goals = payload.get("goals")
    if not isinstance(raw_goals, list) or len(raw_goals) == 0:
        raise ModelError("goals must be a non-empty list")
    if len(raw_goals) > max_goals:
        raise ModelError(
            f"goal count {len(raw_goals)} exceeds --max-goals={max_goals}"
        )

    goals = tuple(_parse_goal(i, raw_goals[i]) for i in range(len(raw_goals)))
    goal_ids = [goal.goal_id for goal in goals]
    if len(set(goal_ids)) != len(goal_ids):
        raise ModelError("goal ids must be unique")

    return ParsedModel(initial_state=initial_state, states=states, goals=goals)


def _unsafe_states_for_labels(states: Dict[str, State], forbidden: Set[str]) -> List[str]:
    unsafe: List[str] = []
    for state_name in sorted(states.keys()):
        labels = set(states[state_name].labels)
        if labels.intersection(forbidden):
            unsafe.append(state_name)
    return unsafe


def solve_safety_game(
    *,
    states: Dict[str, State],
    initial_state: str,
    unsafe_states: Set[str],
) -> Tuple[bool, List[str], Dict[str, Dict[str, str]], int]:
    winning: Set[str] = set(states.keys()) - unsafe_states
    iterations = 0

    while True:
        iterations += 1
        next_winning: Set[str] = set()

        for state_name in sorted(winning):
            state = states[state_name]
            successors = [t.to_state for t in state.transitions]

            if state.controller == "system":
                # System can keep safety if at least one controllable successor stays winning.
                keep = any(target in winning for target in successors)
            else:
                # Environment state is winning only if every environment move keeps safety.
                keep = all(target in winning for target in successors)

            if keep:
                next_winning.add(state_name)

        if next_winning == winning:
            break
        winning = next_winning

    realizable = initial_state in winning
    strategy: Dict[str, Dict[str, str]] = {}

    if realizable:
        for state_name in sorted(winning):
            state = states[state_name]
            if state.controller != "system":
                continue
            admissible = [
                t for t in state.transitions if t.to_state in winning
            ]
            if not admissible:
                # Should not happen due winning-state characterization.
                continue
            chosen = sorted(admissible, key=lambda t: (t.action, t.to_state))[0]
            strategy[state_name] = {
                "action": chosen.action,
                "to": chosen.to_state,
            }

    return realizable, sorted(winning), strategy, iterations


def _goal_set_key(goal_ids: Sequence[str], subset: Set[str]) -> Tuple[int, Tuple[str, ...]]:
    canonical = tuple(g for g in goal_ids if g in subset)
    return (-len(canonical), canonical)


def synthesize_frontier(model: ParsedModel, model_path: Path) -> Dict[str, object]:
    goals_by_id = {goal.goal_id: goal for goal in model.goals}
    goal_ids = [goal.goal_id for goal in model.goals]

    subset_results: List[Dict[str, object]] = []
    realizable_sets: List[Set[str]] = []

    for subset_size in range(0, len(goal_ids) + 1):
        for subset_tuple in combinations(goal_ids, subset_size):
            subset_set = set(subset_tuple)
            forbidden_labels: Set[str] = set()
            for goal_id in subset_tuple:
                forbidden_labels.update(goals_by_id[goal_id].forbidden_labels)

            unsafe_states = _unsafe_states_for_labels(model.states, forbidden_labels)
            realizable, winning_states, strategy, iterations = solve_safety_game(
                states=model.states,
                initial_state=model.initial_state,
                unsafe_states=set(unsafe_states),
            )

            if realizable:
                realizable_sets.append(subset_set)

            subset_results.append(
                {
                    "goals": list(subset_tuple),
                    "forbidden_labels": sorted(forbidden_labels),
                    "unsafe_states": unsafe_states,
                    "realizable": realizable,
                    "winning_state_count": len(winning_states),
                    "winning_states": winning_states,
                    "strategy": strategy,
                    "fixpoint_iterations": iterations,
                }
            )

    maximal_sets: List[Set[str]] = []
    for candidate in realizable_sets:
        if not any(candidate < other for other in realizable_sets):
            maximal_sets.append(candidate)

    maximal_sets_sorted = sorted(
        maximal_sets,
        key=lambda subset: _goal_set_key(goal_ids, subset),
    )

    full_set = set(goal_ids)
    full_set_realizable = any(subset == full_set for subset in realizable_sets)

    minimal_relaxations_from_full: List[List[str]] = []
    if not full_set_realizable and realizable_sets:
        max_cardinality = max(len(subset) for subset in realizable_sets)
        best_subsets = [subset for subset in realizable_sets if len(subset) == max_cardinality]
        dropped_variants = {
            tuple(goal_id for goal_id in goal_ids if goal_id not in subset)
            for subset in best_subsets
        }
        minimal_relaxations_from_full = [list(item) for item in sorted(dropped_variants)]

    incompatible_pairs: List[List[str]] = []
    for i in range(len(goal_ids)):
        for j in range(i + 1, len(goal_ids)):
            g1 = goal_ids[i]
            g2 = goal_ids[j]
            if not any({g1, g2}.issubset(subset) for subset in realizable_sets):
                incompatible_pairs.append([g1, g2])

    realizable_count_by_goal = {
        goal_id: sum(1 for subset in realizable_sets if goal_id in subset)
        for goal_id in goal_ids
    }

    model_bytes = model_path.read_bytes()
    model_sha256 = hashlib.sha256(model_bytes).hexdigest()

    report: Dict[str, object] = {
        "schema": REPORT_SCHEMA,
        "script_version": SCRIPT_VERSION,
        "model_path": str(model_path),
        "model_sha256": model_sha256,
        "initial_state": model.initial_state,
        "goals": [
            {
                "id": goal.goal_id,
                "description": goal.description,
                "forbidden_labels": list(goal.forbidden_labels),
            }
            for goal in model.goals
        ],
        "summary": {
            "goal_count": len(goal_ids),
            "state_count": len(model.states),
            "total_subsets": len(subset_results),
            "realizable_subset_count": len(realizable_sets),
            "full_goal_set_realizable": full_set_realizable,
            "maximal_realizable_goal_sets": [
                [goal_id for goal_id in goal_ids if goal_id in subset]
                for subset in maximal_sets_sorted
            ],
            "minimal_relaxations_from_full": minimal_relaxations_from_full,
            "incompatible_goal_pairs": incompatible_pairs,
            "realizable_subset_count_by_goal": realizable_count_by_goal,
        },
        "subset_results": subset_results,
    }

    return report


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Compute realizable multi-goal frontier for a finite turn-based safety model"
    )
    parser.add_argument(
        "--model",
        required=True,
        help="Path to model JSON (schema pulsetensor/goal-frontier-model/v1)",
    )
    parser.add_argument(
        "--out",
        help="Optional output JSON path. If omitted, report is printed to stdout.",
    )
    parser.add_argument(
        "--max-goals",
        type=int,
        default=16,
        help="Fail if model goal count exceeds this limit (default: 16)",
    )
    args = parser.parse_args()

    model_path = Path(args.model)
    if not model_path.is_file():
        raise SystemExit(f"model file not found: {model_path}")

    try:
        model = parse_model(model_path, max_goals=args.max_goals)
        report = synthesize_frontier(model, model_path)
    except ModelError as exc:
        raise SystemExit(f"invalid model: {exc}") from exc

    payload = json.dumps(report, indent=2)
    if args.out:
        out_path = Path(args.out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(payload + "\n", encoding="utf-8")
        print(
            f"Goal frontier synthesis complete: {out_path} "
            f"(maximal_sets={len(report['summary']['maximal_realizable_goal_sets'])})"
        )
    else:
        print(payload)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

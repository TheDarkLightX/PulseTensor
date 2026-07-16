#!/usr/bin/env python3
"""Exhaust the bounded ExactInference V1 accounting/state model.

This is deliberately a small, dependency-free model checker. It proves the
listed invariants only for one configuration, one task, the enumerated escrow
and fee boundary values, and the transitions below. It is not a Solidity/EVM
refinement proof.
"""

from __future__ import annotations

import argparse
import dataclasses
import hashlib
import json
from collections import deque
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable


CONFIG_MISSING = 0
CONFIG_ACTIVE = 1
CONFIG_DEPRECATED = 2
CONFIG_REVOKED = 3

TASK_NONE = 0
TASK_OPEN = 1
TASK_PROOF_SETTLED = 2
TASK_EXPIRED_REFUND = 3
TASK_REVOKED_REFUND = 4
TASK_UNAVAILABLE_REFUND = 5

ESCROW_BOUNDARIES = (1, 2, 7, 100)
FEE_BPS_BOUNDARIES = (0, 1, 999, 1_000, 2_999, 3_000)
EXPECTED_SPEC_SHA256 = "34beea9ec70632a7e0f4c57bbcdf96afc89a84cef9d0f454282cef965b2a2b07"


@dataclasses.dataclass(frozen=True, slots=True)
class State:
    config: int = CONFIG_MISSING
    verifier_code_available: bool = True
    task: int = TASK_NONE
    deadline_passed: bool = False
    proof_valid: bool = False
    open_escrow: int = 0
    beneficiary_claimable: int = 0
    treasury_claimable: int = 0
    refund_claimable: int = 0
    contract_balance: int = 0
    protocol_fee_bps: int = 0

    @property
    def total_claimable(self) -> int:
        return self.beneficiary_claimable + self.treasury_claimable + self.refund_claimable

    @property
    def liabilities(self) -> int:
        return self.open_escrow + self.total_claimable


def check_invariants(state: State) -> None:
    if not 0 <= state.protocol_fee_bps <= 3_000:
        raise AssertionError("protocol fee escaped the [0, 3000] bps bound")
    if min(
        state.open_escrow,
        state.beneficiary_claimable,
        state.treasury_claimable,
        state.refund_claimable,
        state.contract_balance,
    ) < 0:
        raise AssertionError("negative value liability")
    if state.contract_balance < state.liabilities:
        raise AssertionError("insolvent: balance is below open escrow plus claims")
    if state.task == TASK_NONE:
        if state.open_escrow != 0 or state.total_claimable != 0:
            raise AssertionError("missing task owns value")
    elif state.task == TASK_OPEN:
        if state.open_escrow <= 0:
            raise AssertionError("open task has no escrow")
        if state.total_claimable != 0:
            raise AssertionError("open task already created a pull claim")
    elif state.task in (
        TASK_PROOF_SETTLED,
        TASK_EXPIRED_REFUND,
        TASK_REVOKED_REFUND,
        TASK_UNAVAILABLE_REFUND,
    ):
        if state.open_escrow != 0:
            raise AssertionError("terminal task retained open escrow")
    else:
        raise AssertionError("unknown task state")

    if state.task == TASK_PROOF_SETTLED and state.refund_claimable != 0:
        raise AssertionError("settled task created a refund claim")
    if state.task in (TASK_EXPIRED_REFUND, TASK_REVOKED_REFUND, TASK_UNAVAILABLE_REFUND):
        if state.beneficiary_claimable != 0 or state.treasury_claimable != 0:
            raise AssertionError("refund path charged a fee or paid a provider")


def require_expected_spec_digest(spec_bytes: bytes) -> str:
    digest = hashlib.sha256(spec_bytes).hexdigest()
    if digest != EXPECTED_SPEC_SHA256:
        raise AssertionError(
            "exact-inference descriptive spec digest mismatch: "
            f"expected {EXPECTED_SPEC_SHA256}, received {digest}"
        )
    return digest


def claim_amounts(amount: int) -> tuple[int, ...]:
    if amount <= 0:
        return ()
    return (amount,) if amount == 1 else (1, amount)


def transitions(state: State) -> Iterable[tuple[str, State]]:
    if state.config == CONFIG_MISSING:
        yield "add_config_after_delay", dataclasses.replace(state, config=CONFIG_ACTIVE)
    if state.config == CONFIG_ACTIVE:
        yield "deprecate_config_after_delay", dataclasses.replace(state, config=CONFIG_DEPRECATED)
    if state.config in (CONFIG_ACTIVE, CONFIG_DEPRECATED):
        yield "revoke_config", dataclasses.replace(state, config=CONFIG_REVOKED)

    if state.verifier_code_available:
        yield "make_verifier_unavailable", dataclasses.replace(state, verifier_code_available=False)
    if not state.deadline_passed:
        yield "advance_past_deadline", dataclasses.replace(state, deadline_passed=True)
    if not state.proof_valid:
        yield "make_proof_valid", dataclasses.replace(state, proof_valid=True)

    if (
        state.config == CONFIG_ACTIVE
        and state.verifier_code_available
        and state.task == TASK_NONE
        and not state.deadline_passed
    ):
        for value in ESCROW_BOUNDARIES:
            for fee_bps in FEE_BPS_BOUNDARIES:
                yield (
                    f"create_task(value={value},fee_bps={fee_bps})",
                    dataclasses.replace(
                        state,
                        task=TASK_OPEN,
                        open_escrow=value,
                        contract_balance=state.contract_balance + value,
                        protocol_fee_bps=fee_bps,
                    ),
                )

    if (
        state.task == TASK_OPEN
        and not state.deadline_passed
        and state.config != CONFIG_REVOKED
        and state.verifier_code_available
        and state.proof_valid
    ):
        fee = state.open_escrow * state.protocol_fee_bps // 10_000
        beneficiary = state.open_escrow - fee
        yield (
            "submit_valid_proof",
            dataclasses.replace(
                state,
                task=TASK_PROOF_SETTLED,
                open_escrow=0,
                beneficiary_claimable=beneficiary,
                treasury_claimable=fee,
            ),
        )

    if state.task == TASK_OPEN and state.deadline_passed:
        yield (
            "refund_expired",
            dataclasses.replace(
                state,
                task=TASK_EXPIRED_REFUND,
                refund_claimable=state.open_escrow,
                open_escrow=0,
            ),
        )
    if state.task == TASK_OPEN and state.config == CONFIG_REVOKED:
        yield (
            "refund_revoked",
            dataclasses.replace(
                state,
                task=TASK_REVOKED_REFUND,
                refund_claimable=state.open_escrow,
                open_escrow=0,
            ),
        )
    if state.task == TASK_OPEN and not state.verifier_code_available:
        yield (
            "refund_unavailable",
            dataclasses.replace(
                state,
                task=TASK_UNAVAILABLE_REFUND,
                refund_claimable=state.open_escrow,
                open_escrow=0,
            ),
        )

    for amount in claim_amounts(state.beneficiary_claimable):
        yield (
            f"claim_beneficiary({amount})",
            dataclasses.replace(
                state,
                beneficiary_claimable=state.beneficiary_claimable - amount,
                contract_balance=state.contract_balance - amount,
            ),
        )
    for amount in claim_amounts(state.treasury_claimable):
        yield (
            f"claim_treasury({amount})",
            dataclasses.replace(
                state,
                treasury_claimable=state.treasury_claimable - amount,
                contract_balance=state.contract_balance - amount,
            ),
        )
    for amount in claim_amounts(state.refund_claimable):
        yield (
            f"claim_refund({amount})",
            dataclasses.replace(
                state,
                refund_claimable=state.refund_claimable - amount,
                contract_balance=state.contract_balance - amount,
            ),
        )


def check_transition_policy(action: str, before: State, after: State) -> None:
    """Independently validate every emitted transition and its exact state delta."""
    if action == "add_config_after_delay":
        if before.config != CONFIG_MISSING:
            raise AssertionError("add_config_after_delay requires a missing configuration")
        expected = dataclasses.replace(before, config=CONFIG_ACTIVE)
    elif action == "deprecate_config_after_delay":
        if before.config != CONFIG_ACTIVE:
            raise AssertionError("deprecate_config_after_delay requires an active configuration")
        expected = dataclasses.replace(before, config=CONFIG_DEPRECATED)
    elif action == "revoke_config":
        if before.config not in (CONFIG_ACTIVE, CONFIG_DEPRECATED):
            raise AssertionError("revoke_config requires an active or deprecated configuration")
        expected = dataclasses.replace(before, config=CONFIG_REVOKED)
    elif action == "make_verifier_unavailable":
        if not before.verifier_code_available:
            raise AssertionError("make_verifier_unavailable requires available verifier code")
        expected = dataclasses.replace(before, verifier_code_available=False)
    elif action == "advance_past_deadline":
        if before.deadline_passed:
            raise AssertionError("advance_past_deadline cannot repeat")
        expected = dataclasses.replace(before, deadline_passed=True)
    elif action == "make_proof_valid":
        if before.proof_valid:
            raise AssertionError("make_proof_valid cannot repeat")
        expected = dataclasses.replace(before, proof_valid=True)
    elif action.startswith("create_task("):
        if (
            before.config != CONFIG_ACTIVE
            or not before.verifier_code_available
            or before.task != TASK_NONE
            or before.deadline_passed
        ):
            raise AssertionError("create_task admission preconditions are not satisfied")
        value = after.open_escrow
        if value not in ESCROW_BOUNDARIES or after.protocol_fee_bps not in FEE_BPS_BOUNDARIES:
            raise AssertionError("create_task escaped the disclosed boundary set")
        expected = dataclasses.replace(
            before,
            task=TASK_OPEN,
            open_escrow=value,
            contract_balance=before.contract_balance + value,
            protocol_fee_bps=after.protocol_fee_bps,
        )
    elif action == "submit_valid_proof":
        if (
            before.task != TASK_OPEN
            or before.deadline_passed
            or before.config not in (CONFIG_ACTIVE, CONFIG_DEPRECATED)
            or not before.verifier_code_available
            or not before.proof_valid
        ):
            raise AssertionError("submit_valid_proof admission preconditions are not satisfied")
        fee = before.open_escrow * before.protocol_fee_bps // 10_000
        expected = dataclasses.replace(
            before,
            task=TASK_PROOF_SETTLED,
            open_escrow=0,
            beneficiary_claimable=before.open_escrow - fee,
            treasury_claimable=fee,
        )
    elif action == "refund_expired":
        if before.task != TASK_OPEN or not before.deadline_passed:
            raise AssertionError("refund_expired admission preconditions are not satisfied")
        expected = dataclasses.replace(
            before,
            task=TASK_EXPIRED_REFUND,
            refund_claimable=before.open_escrow,
            open_escrow=0,
        )
    elif action == "refund_revoked":
        if before.task != TASK_OPEN or before.config != CONFIG_REVOKED:
            raise AssertionError("refund_revoked admission preconditions are not satisfied")
        expected = dataclasses.replace(
            before,
            task=TASK_REVOKED_REFUND,
            refund_claimable=before.open_escrow,
            open_escrow=0,
        )
    elif action == "refund_unavailable":
        if before.task != TASK_OPEN or before.verifier_code_available:
            raise AssertionError("refund_unavailable admission preconditions are not satisfied")
        expected = dataclasses.replace(
            before,
            task=TASK_UNAVAILABLE_REFUND,
            refund_claimable=before.open_escrow,
            open_escrow=0,
        )
    elif action.startswith("claim_beneficiary("):
        amount = before.beneficiary_claimable - after.beneficiary_claimable
        if amount not in claim_amounts(before.beneficiary_claimable):
            raise AssertionError("claim_beneficiary amount is outside the transition boundary set")
        expected = dataclasses.replace(
            before,
            beneficiary_claimable=before.beneficiary_claimable - amount,
            contract_balance=before.contract_balance - amount,
        )
    elif action.startswith("claim_treasury("):
        amount = before.treasury_claimable - after.treasury_claimable
        if amount not in claim_amounts(before.treasury_claimable):
            raise AssertionError("claim_treasury amount is outside the transition boundary set")
        expected = dataclasses.replace(
            before,
            treasury_claimable=before.treasury_claimable - amount,
            contract_balance=before.contract_balance - amount,
        )
    elif action.startswith("claim_refund("):
        amount = before.refund_claimable - after.refund_claimable
        if amount not in claim_amounts(before.refund_claimable):
            raise AssertionError("claim_refund amount is outside the transition boundary set")
        expected = dataclasses.replace(
            before,
            refund_claimable=before.refund_claimable - amount,
            contract_balance=before.contract_balance - amount,
        )
    else:
        raise AssertionError(f"unknown transition action: {action}")

    if after != expected:
        raise AssertionError(f"{action} changed fields outside its exact transition policy")


def trace_for(
    state: State,
    predecessor: dict[State, tuple[State, str] | None],
) -> list[str]:
    trace: list[str] = []
    cursor = state
    while predecessor[cursor] is not None:
        previous, action = predecessor[cursor]  # type: ignore[misc]
        trace.append(action)
        cursor = previous
    trace.reverse()
    return trace


def select_shortest_state(
    states: set[State],
    predecessor: dict[State, tuple[State, str] | None],
    predicate,
) -> State | None:
    candidates = [state for state in states if predicate(state)]
    if not candidates:
        return None
    return min(candidates, key=lambda state: (len(trace_for(state, predecessor)), dataclasses.astuple(state)))


def detect_mutants(states: set[State], predecessor: dict[State, tuple[State, str] | None]) -> dict[str, dict]:
    open_revoked = select_shortest_state(
        states,
        predecessor,
        lambda state: state.task == TASK_OPEN
        and state.config == CONFIG_REVOKED
        and not state.deadline_passed
        and state.verifier_code_available
        and state.proof_valid,
    )
    if open_revoked is None:
        raise AssertionError("negative control unreachable: no open task under a revoked config")

    revoked_fee = open_revoked.open_escrow * open_revoked.protocol_fee_bps // 10_000
    mutant_revoked_settlement = dataclasses.replace(
        open_revoked,
        task=TASK_PROOF_SETTLED,
        open_escrow=0,
        beneficiary_claimable=open_revoked.open_escrow - revoked_fee,
        treasury_claimable=revoked_fee,
    )
    # The state invariants alone intentionally accept this accounting-correct mutant;
    # the independently checked transition admission policy must reject it.
    check_invariants(mutant_revoked_settlement)
    revoked_detected = False
    revoked_reason = ""
    try:
        check_transition_policy("submit_valid_proof", open_revoked, mutant_revoked_settlement)
    except AssertionError as error:
        revoked_detected = True
        revoked_reason = str(error)
    if not revoked_detected:
        raise AssertionError("negative control survived: proof settlement under a revoked configuration")

    refundable = select_shortest_state(
        states,
        predecessor,
        lambda state: state.task == TASK_OPEN
        and state.deadline_passed
        and (state.open_escrow * state.protocol_fee_bps // 10_000) > 0,
    )
    if refundable is None:
        raise AssertionError("negative control unreachable: no fee-bearing expired task")
    fee = refundable.open_escrow * refundable.protocol_fee_bps // 10_000
    mutant_refund = dataclasses.replace(
        refundable,
        task=TASK_EXPIRED_REFUND,
        open_escrow=0,
        refund_claimable=refundable.open_escrow - fee,
        treasury_claimable=fee,
    )
    refund_detected = False
    try:
        check_invariants(mutant_refund)
    except AssertionError:
        refund_detected = True
    if not refund_detected:
        raise AssertionError("negative control survived: fee charged on a refund")

    settled = select_shortest_state(
        states,
        predecessor,
        lambda state: state.task == TASK_PROOF_SETTLED
        and state.total_claimable > 0
        and state.total_claimable == state.contract_balance,
    )
    if settled is None:
        raise AssertionError("negative control unreachable: no settled task")
    mutant_double_credit = dataclasses.replace(
        settled,
        beneficiary_claimable=settled.beneficiary_claimable + settled.contract_balance,
    )
    double_detected = False
    try:
        check_invariants(mutant_double_credit)
    except AssertionError:
        double_detected = True
    if not double_detected:
        raise AssertionError("negative control survived: double settlement credit")

    return {
        "settle_revoked_config": {
            "detected": revoked_detected,
            "reason": revoked_reason,
            "counterexample_prefix": trace_for(open_revoked, predecessor),
        },
        "charge_fee_on_refund": {
            "detected": refund_detected,
            "counterexample_prefix": trace_for(refundable, predecessor),
        },
        "double_credit_settlement": {
            "detected": double_detected,
            "counterexample_prefix": trace_for(settled, predecessor),
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--out",
        default="runs/formal/pulsetensor_exact_inference_settlement_v1.report.json",
    )
    parser.add_argument(
        "--spec",
        default="specs/formal/pulsetensor_exact_inference_settlement_v1.yaml",
    )
    parser.add_argument("--self-test-spec-binding", action="store_true")
    args = parser.parse_args()

    spec_path = Path(args.spec)
    spec_bytes = spec_path.read_bytes()
    spec_sha256 = require_expected_spec_digest(spec_bytes)
    if args.self_test_spec_binding:
        mutated = spec_bytes.replace(b'id: "Solvent"', b'id: "Solvent_MUTANT"', 1)
        if mutated == spec_bytes:
            raise AssertionError("spec-binding negative control could not mutate the Solvent invariant")
        mutation_detected = False
        try:
            require_expected_spec_digest(mutated)
        except AssertionError:
            mutation_detected = True
        if not mutation_detected:
            raise AssertionError("spec-binding negative control survived an invariant mutation")
        print("Exact-inference spec-binding negative control passed")
        return 0

    initial = State()
    queue: deque[State] = deque([initial])
    predecessor: dict[State, tuple[State, str] | None] = {initial: None}
    transition_count = 0
    max_trace_depth = 0

    while queue:
        state = queue.popleft()
        check_invariants(state)
        max_trace_depth = max(max_trace_depth, len(trace_for(state, predecessor)))
        for action, next_state in transitions(state):
            transition_count += 1
            check_transition_policy(action, state, next_state)
            check_invariants(next_state)
            if next_state not in predecessor:
                predecessor[next_state] = (state, action)
                queue.append(next_state)

    states = set(predecessor)
    mutants = detect_mutants(states, predecessor)
    reached_task_states = sorted({state.task for state in states})
    expected_task_states = list(range(TASK_NONE, TASK_UNAVAILABLE_REFUND + 1))
    if reached_task_states != expected_task_states:
        raise AssertionError(
            f"state coverage incomplete: reached={reached_task_states}, expected={expected_task_states}"
        )

    report = {
        "schema": "pulsetensor/exact-inference-bounded-model-report/v1",
        "generated_at_utc": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "model_scope": {
            "configurations": 1,
            "tasks": 1,
            "escrow_boundaries": list(ESCROW_BOUNDARIES),
            "fee_bps_boundaries": list(FEE_BPS_BOUNDARIES),
            "refinement_proof_to_solidity": False,
            "yaml_interpreted": False,
        },
        "descriptive_spec": {
            "path": str(spec_path),
            "sha256": spec_sha256,
            "binding": "exact SHA-256; executable transition logic is implemented in this checker",
        },
        "states_explored": len(states),
        "transitions_checked": transition_count,
        "max_shortest_trace_depth": max_trace_depth,
        "reached_task_states": reached_task_states,
        "invariants": [
            "balance >= openEscrow + beneficiaryClaims + treasuryClaims + refundClaims",
            "open tasks have positive escrow and no claims",
            "terminal tasks retain no open escrow",
            "proof settlement creates no refund liability",
            "refund transitions create neither provider nor treasury liability",
            "protocol fee remains within [0, 3000] bps",
        ],
        "transition_policy": [
            "every emitted action satisfies its admission preconditions",
            "every emitted action changes exactly its authorized state fields",
            "proof settlement is forbidden after deadline, revocation, or verifier unavailability",
        ],
        "negative_controls": mutants,
        "ok": True,
    }
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(
        "Exact-inference bounded model passed "
        f"(states={len(states)}, transitions={transition_count}, mutants={len(mutants)})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

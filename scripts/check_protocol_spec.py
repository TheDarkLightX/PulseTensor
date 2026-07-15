#!/usr/bin/env python3
"""Validate the PulseTensor target protocol using only the Python standard library.

This checker establishes structural consistency of a target design. It is not a
model checker, Solidity verifier, economic proof, or source-to-bytecode
refinement proof.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import pathlib
import re
import sys
from collections import Counter, deque
from dataclasses import dataclass
from typing import Any, Callable


EXPECTED_SCHEMA = "pulsetensor/target-protocol/v1"
REPORT_SCHEMA = "pulsetensor/target-protocol-report/v1"
JSON_SCHEMA_DIALECT = "https://json-schema.org/draft/2020-12/schema"
ALLOWED_STATUSES = {"target_unimplemented", "partial", "implemented"}
ALLOWED_PROOF_STATUSES = {
    "unproved_target",
    "structurally_checked_target",
    "bounded_checked",
    "proved",
}
ASSURANCE_MODES = {
    "EXACT",
    "OPTIMISTIC",
    "STATISTICAL",
    "ATTESTED",
    "REQUESTER_ACCEPTED",
}
ASSET_ID_DERIVATION = "keccak256(abi.encode(uint256(chainId), uint8(assetKindCode), address(tokenAddress)))"
ASSET_ID_ABI_TYPES = ["uint256", "uint8", "address"]
ASSET_KIND_CODES = {
    "NATIVE_PLS": 0,
    "EXACT_ERC20": 1,
}
SPECIAL_PAYOUT_ROLES = {
    "CONTRIBUTOR_REFUND",
    "CONTRIBUTOR_COMPENSATION",
    "NON_SELF_RESOLVER",
    "PROVIDER_BOND_REFUND",
    "EVALUATOR_BOND_REFUND",
    "HONEST_EVALUATORS",
}
NORMATIVE_SCHEMA_FIELDS = {
    "TaskSpecV1": frozenset(
        {
            "schema",
            "taskVersion",
            "chainId",
            "settlementContract",
            "taskId",
            "payer",
            "requester",
            "requesterRefundRecipient",
            "provider",
            "netuid",
            "mechid",
            "mechanismVersion",
            "taskType",
            "inputCommitment",
            "inputAvailabilityPolicyHash",
            "canonicalSemanticsId",
            "outputSchemaHash",
            "assuranceMode",
            "verifierPolicyHash",
            "evaluationPolicyHash",
            "evaluatorCommitteeRoot",
            "paymentAsset",
            "contributionRoot",
            "fundedAmount",
            "providerBondAmount",
            "evaluatorBondAmount",
            "feeScheduleHash",
            "deadlines",
            "payerNonce",
            "payerAuthorization",
        }
    ),
    "WorkReceiptV1": frozenset(
        {
            "schema",
            "receiptVersion",
            "chainId",
            "settlementContract",
            "taskId",
            "attemptId",
            "taskSpecHash",
            "provider",
            "inputCommitment",
            "outputCommitment",
            "evidenceRoot",
            "availabilityAttestationRoot",
            "canonicalSemanticsId",
            "assuranceMode",
            "proofSystemId",
            "verifierId",
            "modelArtifactHash",
            "runtimeArtifactHash",
            "tcbManifestHash",
            "startedAtBlock",
            "submittedAtBlock",
            "providerNonce",
            "providerSignature",
        }
    ),
    "EvaluationRevealV1": frozenset(
        {
            "schema",
            "evaluationVersion",
            "chainId",
            "evaluationContract",
            "taskId",
            "receiptHash",
            "evaluationPolicyHash",
            "evaluator",
            "scoreVector",
            "evidenceRoot",
            "salt",
            "evaluatorNonce",
            "evaluatorSignature",
        }
    ),
    "DecisionRecordV1": frozenset(
        {
            "schema",
            "decisionVersion",
            "chainId",
            "taskMarket",
            "taskId",
            "taskSpecHash",
            "receiptHash",
            "assuranceMode",
            "outcome",
            "reasonCode",
            "bountyVectorId",
            "providerBondVectorId",
            "providerBondDispositionEvidenceHash",
            "evaluatorBondDispositionRoot",
            "resolverAuthority",
            "resolverPolicyHash",
            "resolverEvidenceHash",
            "challengeRecordHash",
            "decidedAtBlock",
        }
    ),
    "NodeDescriptorV1": frozenset(
        {
            "schema",
            "descriptorVersion",
            "chainId",
            "nodeRegistry",
            "netuid",
            "mechid",
            "controller",
            "operator",
            "roleBitmap",
            "sequence",
            "validFromBlock",
            "validUntilBlock",
            "endpointSet",
            "tlsCertificateHash",
            "capabilityManifestHash",
            "supportedTaskVersions",
            "supportedReceiptVersions",
            "supportedAssuranceModes",
            "acceptedAssetSetHash",
            "availabilityModes",
            "maxRequestBytes",
            "maxConcurrentTasks",
            "softwareArtifactHash",
            "operatorSignature",
        }
    ),
    "PTAuthEnvelopeV1": frozenset(
        {
            "schema",
            "protocolVersion",
            "chainId",
            "nodeRegistry",
            "netuid",
            "mechid",
            "senderOperator",
            "receiverOperator",
            "messageType",
            "methodHash",
            "requestTargetHash",
            "rawBodyHash",
            "taskId",
            "attemptId",
            "nonce",
            "referenceBlockNumber",
            "referenceBlockHash",
            "expiresAtBlock",
            "signature",
        }
    ),
}
NORMATIVE_NESTED_SCHEMA_FIELDS = {
    ("TaskSpecV1", "paymentAsset", "object"): frozenset({"assetId", "kind", "chainId", "token"}),
    ("TaskSpecV1", "deadlines", "object"): frozenset(
        {"assignment", "submission", "evaluationCommit", "evaluationReveal", "challenge", "claim"}
    ),
    ("EvaluationRevealV1", "scoreVector", "array_items"): frozenset({"criterionId", "scoreBps"}),
    ("NodeDescriptorV1", "endpointSet", "array_items"): frozenset({"transport", "uri"}),
}
REQUIRED_UINT_DEFS = {
    "TaskSpecV1": frozenset({"uintString", "quantizedAmount"}),
    "WorkReceiptV1": frozenset({"uintString"}),
    "EvaluationRevealV1": frozenset({"uintString"}),
    "DecisionRecordV1": frozenset({"uintString"}),
    "NodeDescriptorV1": frozenset({"uintString"}),
    "PTAuthEnvelopeV1": frozenset({"uintString"}),
}
DOMAIN_OBJECTS = {
    "TASK_SPEC_DOMAIN": "TaskSpecV1",
    "WORK_RECEIPT_DOMAIN": "WorkReceiptV1",
    "EVALUATION_DOMAIN": "EvaluationRevealV1",
    "DECISION_RECORD_DOMAIN": "DecisionRecordV1",
    "NODE_DESCRIPTOR_DOMAIN": "NodeDescriptorV1",
    "PTAUTH_DOMAIN": "PTAuthEnvelopeV1",
}
DOMAIN_EXCLUDED_FIELDS = {
    "TaskSpecV1": {"schema", "payerAuthorization"},
    "WorkReceiptV1": {"schema", "providerSignature"},
    "EvaluationRevealV1": {"schema", "evaluatorSignature"},
    "DecisionRecordV1": {"schema"},
    "NodeDescriptorV1": {"schema", "operatorSignature"},
    "PTAuthEnvelopeV1": {"schema", "signature"},
}
REQUIRED_DOMAIN_FIELDS = {
    domain_id: set(NORMATIVE_SCHEMA_FIELDS[object_id]) - DOMAIN_EXCLUDED_FIELDS[object_id]
    for domain_id, object_id in DOMAIN_OBJECTS.items()
}
IMPLEMENTATION_STATUS_BOUNDARY = {
    "CURRENT_COMMIT_REVEAL": "implemented",
    "CURRENT_NATIVE_BATCH_SHELL": "partial",
    "TARGET_NODE_REGISTRY": "target_unimplemented",
    "TARGET_TASK_MARKET": "target_unimplemented",
    "TARGET_QUALITY_CONSENSUS": "target_unimplemented",
    "TARGET_VERIFIER_REGISTRY": "target_unimplemented",
    "TARGET_PULSEGRAPH": "target_unimplemented",
}
PAYOUT_ROLE_RULES = {
    "PROVIDER": {"default_bps": 7200, "min_bps": 6500, "max_bps": 8500},
    "EVALUATORS": {"default_bps": 1200, "min_bps": 0, "max_bps": 2500},
    "SUBNET_BUILDER": {"default_bps": 500, "min_bps": 0, "max_bps": 750},
    "CORE_MAINTAINER": {"default_bps": 500, "min_bps": 0, "max_bps": 750},
    "SECURITY_RESERVE": {"default_bps": 300, "min_bps": 100, "max_bps": 500},
    "ECOSYSTEM": {"default_bps": 300, "min_bps": 0, "max_bps": 500},
}
COUPLED_BOUND_RULES = {
    "BUILDER_PLUS_CORE_CAP": {"roles": ("SUBNET_BUILDER", "CORE_MAINTAINER"), "max_bps": 1200}
}
BOND_POLICY_BOUNDS = {
    "provider_min_bps": 1000,
    "provider_max_bps": 30000,
    "evaluator_min_bps": 100,
    "evaluator_max_bps": 10000,
}
BOND_OBJECTIVE_FAULTS = {
    "equivocation",
    "committed non-reveal",
    "invalid reveal",
    "provider deadline default",
    "unavailable evidence promised by the snapshotted policy",
    "fraud established by the snapshotted verifier",
}
PAYOUT_VECTOR_RULES = {
    "ACCEPTED_BOUNTY": {
        "principal": "BOUNTY",
        "allocations": {role: rule["default_bps"] for role, rule in PAYOUT_ROLE_RULES.items()},
    },
    "REJECTED_REVIEWED_BOUNTY": {
        "principal": "BOUNTY",
        "allocations": {"CONTRIBUTOR_REFUND": 8800, "EVALUATORS": 1200},
    },
    "FULL_REFUND_BOUNTY": {
        "principal": "BOUNTY",
        "allocations": {"CONTRIBUTOR_REFUND": 10000},
    },
    "VALID_PROVIDER_BOND": {
        "principal": "PROVIDER_BOND",
        "allocations": {"PROVIDER_BOND_REFUND": 10000},
    },
    "PROVABLE_PROVIDER_FAULT_BOND": {
        "principal": "PROVIDER_BOND",
        "allocations": {"CONTRIBUTOR_COMPENSATION": 6000, "NON_SELF_RESOLVER": 2000, "SECURITY_RESERVE": 2000},
    },
    "VALID_EVALUATOR_BOND": {
        "principal": "EVALUATOR_BOND_EACH",
        "allocations": {"EVALUATOR_BOND_REFUND": 10000},
    },
    "PROVABLE_EVALUATOR_DEFAULT_BOND": {
        "principal": "EVALUATOR_BOND_EACH",
        "allocations": {"CONTRIBUTOR_COMPENSATION": 6000, "HONEST_EVALUATORS": 2000, "SECURITY_RESERVE": 2000},
    },
}
LIFECYCLE_STATES = frozenset(
    {
        "FUNDED_OPEN",
        "ASSIGNED",
        "SUBMITTED",
        "EVALUATION_COMMIT",
        "EVALUATION_REVEAL",
        "PROVISIONAL_ACCEPT",
        "PROVISIONAL_REJECT",
        "CHALLENGED",
        "FINAL_ACCEPT",
        "FINAL_REJECT",
        "FINAL_PROVIDER_FAULT",
        "CANCELLED_REFUND",
        "ASSIGNMENT_EXPIRED_REFUND",
        "PROVIDER_DEFAULT_REFUND",
        "EVALUATION_FAILED_REFUND",
        "CHALLENGE_EXPIRED_REFUND",
        "SETTLED",
    }
)
LIFECYCLE_TRANSITION_EDGES = {
    "ASSIGN": ("FUNDED_OPEN", "ASSIGNED"),
    "CANCEL_OPEN": ("FUNDED_OPEN", "CANCELLED_REFUND"),
    "EXPIRE_ASSIGNMENT": ("FUNDED_OPEN", "ASSIGNMENT_EXPIRED_REFUND"),
    "SUBMIT": ("ASSIGNED", "SUBMITTED"),
    "DEFAULT_PROVIDER": ("ASSIGNED", "PROVIDER_DEFAULT_REFUND"),
    "START_EVALUATION": ("SUBMITTED", "EVALUATION_COMMIT"),
    "DIRECT_PROVISIONAL_ACCEPT": ("SUBMITTED", "PROVISIONAL_ACCEPT"),
    "DIRECT_PROVISIONAL_REJECT": ("SUBMITTED", "PROVISIONAL_REJECT"),
    "VERIFY_PROVIDER_FAULT": ("SUBMITTED", "FINAL_PROVIDER_FAULT"),
    "TIMEOUT_SUBMITTED": ("SUBMITTED", "EVALUATION_FAILED_REFUND"),
    "OPEN_REVEAL": ("EVALUATION_COMMIT", "EVALUATION_REVEAL"),
    "FAIL_COMMIT_QUORUM": ("EVALUATION_COMMIT", "EVALUATION_FAILED_REFUND"),
    "AGGREGATE_ACCEPT": ("EVALUATION_REVEAL", "PROVISIONAL_ACCEPT"),
    "AGGREGATE_REJECT": ("EVALUATION_REVEAL", "PROVISIONAL_REJECT"),
    "FAIL_REVEAL_QUORUM": ("EVALUATION_REVEAL", "EVALUATION_FAILED_REFUND"),
    "CHALLENGE_ACCEPT": ("PROVISIONAL_ACCEPT", "CHALLENGED"),
    "FINALIZE_ACCEPT": ("PROVISIONAL_ACCEPT", "FINAL_ACCEPT"),
    "CHALLENGE_REJECT": ("PROVISIONAL_REJECT", "CHALLENGED"),
    "FINALIZE_REJECT": ("PROVISIONAL_REJECT", "FINAL_REJECT"),
    "RESOLVE_CHALLENGE_ACCEPT": ("CHALLENGED", "FINAL_ACCEPT"),
    "RESOLVE_CHALLENGE_REJECT": ("CHALLENGED", "FINAL_REJECT"),
    "RESOLVE_CHALLENGE_PROVIDER_FAULT": ("CHALLENGED", "FINAL_PROVIDER_FAULT"),
    "TIMEOUT_CHALLENGE_RESOLUTION": ("CHALLENGED", "CHALLENGE_EXPIRED_REFUND"),
    "SETTLE_ACCEPT": ("FINAL_ACCEPT", "SETTLED"),
    "SETTLE_REJECT": ("FINAL_REJECT", "SETTLED"),
    "SETTLE_PROVIDER_FAULT": ("FINAL_PROVIDER_FAULT", "SETTLED"),
    "SETTLE_CANCEL": ("CANCELLED_REFUND", "SETTLED"),
    "SETTLE_ASSIGNMENT_EXPIRY": ("ASSIGNMENT_EXPIRED_REFUND", "SETTLED"),
    "SETTLE_PROVIDER_DEFAULT": ("PROVIDER_DEFAULT_REFUND", "SETTLED"),
    "SETTLE_EVALUATION_FAILURE": ("EVALUATION_FAILED_REFUND", "SETTLED"),
    "SETTLE_CHALLENGE_EXPIRY": ("CHALLENGE_EXPIRED_REFUND", "SETTLED"),
}
SETTLEMENT_DECISION_RULES = {
    "SETTLE_ACCEPT": {
        "outcome": "FINAL_ACCEPT",
        "reason": "ACCEPTED_BY_SNAPSHOTTED_POLICY",
        "dispositions": {
            "BOUNTY": ("EXACT", ("ACCEPTED_BOUNTY",)),
            "PROVIDER_BOND": ("EXACT", ("VALID_PROVIDER_BOND",)),
            "EVALUATOR_BOND_EACH": (
                "PER_LOCKED_BOND_OBJECTIVE_EVIDENCE",
                ("VALID_EVALUATOR_BOND", "PROVABLE_EVALUATOR_DEFAULT_BOND"),
            ),
        },
    },
    "SETTLE_REJECT": {
        "outcome": "FINAL_REJECT",
        "reason": "REJECTED_BY_SNAPSHOTTED_POLICY",
        "dispositions": {
            "BOUNTY": ("EXACT", ("REJECTED_REVIEWED_BOUNTY",)),
            "PROVIDER_BOND": ("EXACT", ("VALID_PROVIDER_BOND",)),
            "EVALUATOR_BOND_EACH": (
                "PER_LOCKED_BOND_OBJECTIVE_EVIDENCE",
                ("VALID_EVALUATOR_BOND", "PROVABLE_EVALUATOR_DEFAULT_BOND"),
            ),
        },
    },
    "SETTLE_PROVIDER_FAULT": {
        "outcome": "FINAL_REJECT",
        "reason": "OBJECTIVE_PROVIDER_FAULT_PROVED",
        "dispositions": {
            "BOUNTY": ("EXACT", ("REJECTED_REVIEWED_BOUNTY",)),
            "PROVIDER_BOND": ("EXACT", ("PROVABLE_PROVIDER_FAULT_BOND",)),
            "EVALUATOR_BOND_EACH": (
                "PER_LOCKED_BOND_OBJECTIVE_EVIDENCE",
                ("VALID_EVALUATOR_BOND", "PROVABLE_EVALUATOR_DEFAULT_BOND"),
            ),
        },
    },
    "SETTLE_CANCEL": {
        "outcome": "FULL_REFUND",
        "reason": "CANCELLED_BEFORE_ASSIGNMENT",
        "dispositions": {
            "BOUNTY": ("EXACT", ("FULL_REFUND_BOUNTY",)),
            "PROVIDER_BOND": ("NONE_LOCKED", ()),
            "EVALUATOR_BOND_EACH": ("NONE_LOCKED", ()),
        },
    },
    "SETTLE_ASSIGNMENT_EXPIRY": {
        "outcome": "FULL_REFUND",
        "reason": "ASSIGNMENT_EXPIRED",
        "dispositions": {
            "BOUNTY": ("EXACT", ("FULL_REFUND_BOUNTY",)),
            "PROVIDER_BOND": ("NONE_LOCKED", ()),
            "EVALUATOR_BOND_EACH": ("NONE_LOCKED", ()),
        },
    },
    "SETTLE_PROVIDER_DEFAULT": {
        "outcome": "FULL_REFUND",
        "reason": "PROVIDER_SUBMISSION_DEFAULT",
        "dispositions": {
            "BOUNTY": ("EXACT", ("FULL_REFUND_BOUNTY",)),
            "PROVIDER_BOND": ("EXACT", ("PROVABLE_PROVIDER_FAULT_BOND",)),
            "EVALUATOR_BOND_EACH": ("EXACT", ("VALID_EVALUATOR_BOND",)),
        },
    },
    "SETTLE_EVALUATION_FAILURE": {
        "outcome": "FULL_REFUND",
        "reason": "EVALUATION_OR_DIRECT_RESOLUTION_TIMEOUT",
        "dispositions": {
            "BOUNTY": ("EXACT", ("FULL_REFUND_BOUNTY",)),
            "PROVIDER_BOND": ("EXACT", ("VALID_PROVIDER_BOND",)),
            "EVALUATOR_BOND_EACH": (
                "PER_LOCKED_BOND_OBJECTIVE_EVIDENCE",
                ("VALID_EVALUATOR_BOND", "PROVABLE_EVALUATOR_DEFAULT_BOND"),
            ),
        },
    },
    "SETTLE_CHALLENGE_EXPIRY": {
        "outcome": "FULL_REFUND",
        "reason": "CHALLENGE_RESOLUTION_TIMEOUT",
        "dispositions": {
            "BOUNTY": ("EXACT", ("FULL_REFUND_BOUNTY",)),
            "PROVIDER_BOND": ("EXACT", ("VALID_PROVIDER_BOND",)),
            "EVALUATOR_BOND_EACH": (
                "PER_LOCKED_BOND_OBJECTIVE_EVIDENCE",
                ("VALID_EVALUATOR_BOND", "PROVABLE_EVALUATOR_DEFAULT_BOND"),
            ),
        },
    },
}
SETTLEMENT_NULLIFIER_RULES = {
    "PULSETENSOR_TASK_SETTLEMENT_NULLIFIER_V1": {
        "derivation": (
            'keccak256(abi.encode(keccak256("PULSETENSOR_TASK_SETTLEMENT_NULLIFIER_V1"), '
            "uint256(chainId), address(settlementContract), bytes32(taskId), bytes32(taskSpecHash)))"
        ),
        "abi_types": ("bytes32", "uint256", "address", "bytes32", "bytes32"),
        "required_fields": ("chainId", "settlementContract", "taskId", "taskSpecHash"),
        "consumed_key": "consumedTaskNullifier",
    },
    "PULSETENSOR_RECEIPT_SETTLEMENT_NULLIFIER_V1": {
        "derivation": (
            'keccak256(abi.encode(keccak256("PULSETENSOR_RECEIPT_SETTLEMENT_NULLIFIER_V1"), '
            "uint256(chainId), address(settlementContract), bytes32(taskId), bytes32(attemptId), bytes32(receiptHash)))"
        ),
        "abi_types": ("bytes32", "uint256", "address", "bytes32", "bytes32", "bytes32"),
        "required_fields": ("chainId", "settlementContract", "taskId", "attemptId", "receiptHash"),
        "consumed_key": "consumedReceiptNullifier",
    },
}


class SpecError(ValueError):
    """A deterministic target-spec validation failure."""


def fail(message: str) -> None:
    raise SpecError(message)


def canonical_json(value: Any) -> bytes:
    return (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True) + "\n").encode()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


_KECCAK_ROUND_CONSTANTS = (
    0x0000000000000001,
    0x0000000000008082,
    0x800000000000808A,
    0x8000000080008000,
    0x000000000000808B,
    0x0000000080000001,
    0x8000000080008081,
    0x8000000000008009,
    0x000000000000008A,
    0x0000000000000088,
    0x0000000080008009,
    0x000000008000000A,
    0x000000008000808B,
    0x800000000000008B,
    0x8000000000008089,
    0x8000000000008003,
    0x8000000000008002,
    0x8000000000000080,
    0x000000000000800A,
    0x800000008000000A,
    0x8000000080008081,
    0x8000000000008080,
    0x0000000080000001,
    0x8000000080008008,
)
_KECCAK_ROTATIONS = (
    (0, 36, 3, 41, 18),
    (1, 44, 10, 45, 2),
    (62, 6, 43, 15, 61),
    (28, 55, 25, 21, 56),
    (27, 20, 39, 8, 14),
)
_UINT64_MASK = (1 << 64) - 1


def rotate_left_64(value: int, shift: int) -> int:
    if shift == 0:
        return value & _UINT64_MASK
    return ((value << shift) | (value >> (64 - shift))) & _UINT64_MASK


def keccak_f1600(state: list[int]) -> None:
    for round_constant in _KECCAK_ROUND_CONSTANTS:
        columns = [state[x] ^ state[x + 5] ^ state[x + 10] ^ state[x + 15] ^ state[x + 20] for x in range(5)]
        deltas = [columns[(x - 1) % 5] ^ rotate_left_64(columns[(x + 1) % 5], 1) for x in range(5)]
        for y in range(5):
            for x in range(5):
                state[x + 5 * y] ^= deltas[x]

        rotated = [0] * 25
        for y in range(5):
            for x in range(5):
                rotated[y + 5 * ((2 * x + 3 * y) % 5)] = rotate_left_64(
                    state[x + 5 * y], _KECCAK_ROTATIONS[x][y]
                )

        for y in range(5):
            row = rotated[5 * y : 5 * y + 5]
            for x in range(5):
                state[x + 5 * y] = row[x] ^ ((~row[(x + 1) % 5]) & row[(x + 2) % 5])
                state[x + 5 * y] &= _UINT64_MASK
        state[0] ^= round_constant


def keccak256(value: bytes) -> bytes:
    rate = 136
    padded = bytearray(value)
    padded.append(0x01)
    padded.extend(b"\x00" * ((rate - len(padded) % rate - 1) % rate))
    padded.append(0x80)
    state = [0] * 25
    for offset in range(0, len(padded), rate):
        block = padded[offset : offset + rate]
        for lane_index in range(rate // 8):
            lane = int.from_bytes(block[lane_index * 8 : lane_index * 8 + 8], "little")
            state[lane_index] ^= lane
        keccak_f1600(state)
    output = b"".join(lane.to_bytes(8, "little") for lane in state[: rate // 8])
    return output[:32]


def encode_asset_id_preimage(chain_id: int, asset_kind: str, token_address: str) -> bytes:
    if isinstance(chain_id, bool) or not isinstance(chain_id, int) or not 0 <= chain_id < 1 << 256:
        fail("asset chainId must fit uint256")
    if asset_kind not in ASSET_KIND_CODES:
        fail(f"unsupported asset kind {asset_kind!r}")
    if not re.fullmatch(r"0x[0-9a-fA-F]{40}", token_address):
        fail("asset token address must be 20-byte hex")
    return (
        chain_id.to_bytes(32, "big")
        + ASSET_KIND_CODES[asset_kind].to_bytes(32, "big")
        + bytes.fromhex(token_address[2:]).rjust(32, b"\x00")
    )


def derive_asset_id(chain_id: int, asset_kind: str, token_address: str) -> str:
    return "0x" + keccak256(encode_asset_id_preimage(chain_id, asset_kind, token_address)).hex()


def read_json(path: pathlib.Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        fail(f"missing JSON file: {path}")
    except json.JSONDecodeError as exc:
        fail(f"invalid JSON in {path}: {exc}")


def require_dict(value: Any, field: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        fail(f"{field} must be an object")
    return value


def require_list(value: Any, field: str, *, nonempty: bool = True) -> list[Any]:
    if not isinstance(value, list):
        fail(f"{field} must be a list")
    if nonempty and not value:
        fail(f"{field} must be non-empty")
    return value


def require_string(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        fail(f"{field} must be a non-empty string")
    return value


def require_bool(value: Any, field: str) -> bool:
    if not isinstance(value, bool):
        fail(f"{field} must be boolean")
    return value


def require_int(value: Any, field: str, *, minimum: int | None = None) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        fail(f"{field} must be an integer")
    if minimum is not None and value < minimum:
        fail(f"{field} must be at least {minimum}")
    return value


def unique_strings(value: Any, field: str, *, nonempty: bool = True) -> list[str]:
    raw = require_list(value, field, nonempty=nonempty)
    out: list[str] = []
    seen: set[str] = set()
    for index, item in enumerate(raw):
        text = require_string(item, f"{field}[{index}]")
        if text in seen:
            fail(f"{field} contains duplicate value {text!r}")
        seen.add(text)
        out.append(text)
    return out


def unique_object_ids(value: Any, field: str) -> list[dict[str, Any]]:
    raw = require_list(value, field)
    out: list[dict[str, Any]] = []
    seen: set[str] = set()
    for index, item in enumerate(raw):
        obj = require_dict(item, f"{field}[{index}]")
        item_id = require_string(obj.get("id"), f"{field}[{index}].id")
        if item_id in seen:
            fail(f"{field} contains duplicate id {item_id!r}")
        seen.add(item_id)
        out.append(obj)
    return out


def safe_path(root: pathlib.Path, relative: Any, field: str) -> pathlib.Path:
    text = require_string(relative, field)
    candidate = (root / text).resolve()
    try:
        candidate.relative_to(root.resolve())
    except ValueError:
        fail(f"{field} escapes repository root: {text}")
    if not candidate.is_file():
        fail(f"{field} does not exist: {text}")
    return candidate


def resolve_ref(schema_root: dict[str, Any], ref: str, field: str) -> dict[str, Any]:
    if not ref.startswith("#/"):
        fail(f"{field} uses unsupported non-local $ref {ref!r}")
    current: Any = schema_root
    for segment in ref[2:].split("/"):
        segment = segment.replace("~1", "/").replace("~0", "~")
        if not isinstance(current, dict) or segment not in current:
            fail(f"{field} has unresolved $ref {ref!r}")
        current = current[segment]
    return require_dict(current, f"resolved {field}")


def validate_json_value(value: Any, schema: dict[str, Any], root: dict[str, Any], field: str) -> None:
    if "$ref" in schema:
        ref = require_string(schema["$ref"], f"{field}.$ref")
        validate_json_value(value, resolve_ref(root, ref, field), root, field)
        return

    if "const" in schema and value != schema["const"]:
        fail(f"{field} must equal {schema['const']!r}")
    if "enum" in schema:
        enum = require_list(schema["enum"], f"{field}.enum")
        if value not in enum:
            fail(f"{field} must be one of {enum!r}")

    declared_type = schema.get("type")
    if declared_type == "object":
        obj = require_dict(value, field)
        properties = require_dict(schema.get("properties", {}), f"{field}.schema.properties")
        required = unique_strings(schema.get("required", []), f"{field}.schema.required", nonempty=False)
        for key in required:
            if key not in obj:
                fail(f"{field} is missing required property {key!r}")
        if schema.get("additionalProperties") is False:
            unknown = sorted(set(obj) - set(properties))
            if unknown:
                fail(f"{field} has unknown properties {unknown!r}")
        for key, child in obj.items():
            if key in properties:
                validate_json_value(child, require_dict(properties[key], f"{field}.schema.properties.{key}"), root, f"{field}.{key}")
        return

    if declared_type == "array":
        if not isinstance(value, list):
            fail(f"{field} must be an array")
        minimum = schema.get("minItems")
        maximum = schema.get("maxItems")
        if isinstance(minimum, int) and len(value) < minimum:
            fail(f"{field} must contain at least {minimum} items")
        if isinstance(maximum, int) and len(value) > maximum:
            fail(f"{field} must contain at most {maximum} items")
        if schema.get("uniqueItems") is True:
            encoded = [canonical_json(item) for item in value]
            if len(encoded) != len(set(encoded)):
                fail(f"{field} items must be unique")
        item_schema = schema.get("items")
        if item_schema is not None:
            item_schema = require_dict(item_schema, f"{field}.schema.items")
            for index, item in enumerate(value):
                validate_json_value(item, item_schema, root, f"{field}[{index}]")
        return

    if declared_type == "string":
        if not isinstance(value, str):
            fail(f"{field} must be a string")
        minimum = schema.get("minLength")
        maximum = schema.get("maxLength")
        if isinstance(minimum, int) and len(value) < minimum:
            fail(f"{field} length must be at least {minimum}")
        if isinstance(maximum, int) and len(value) > maximum:
            fail(f"{field} length must be at most {maximum}")
        pattern = schema.get("pattern")
        if pattern is not None and re.search(require_string(pattern, f"{field}.schema.pattern"), value) is None:
            fail(f"{field} does not match {pattern!r}")
        quantum = schema.get("x-pulsetensor-multipleOfBaseUnits")
        if quantum is not None:
            quantum = require_int(quantum, f"{field}.schema.quantum", minimum=1)
            if not value.isdigit() or int(value) % quantum != 0:
                fail(f"{field} must be a multiple of {quantum} base units")
        uint_bits = schema.get("x-pulsetensor-uintBits")
        if uint_bits is not None:
            uint_bits = require_int(uint_bits, f"{field}.schema.uintBits", minimum=1)
            if not value.isdigit() or int(value) >= 1 << uint_bits:
                fail(f"{field} must fit uint{uint_bits}")
        return

    if declared_type == "integer":
        number = require_int(value, field)
        minimum = schema.get("minimum")
        maximum = schema.get("maximum")
        if isinstance(minimum, int) and number < minimum:
            fail(f"{field} must be at least {minimum}")
        if isinstance(maximum, int) and number > maximum:
            fail(f"{field} must be at most {maximum}")
        return

    if declared_type == "boolean":
        require_bool(value, field)
        return

    if declared_type is not None:
        fail(f"{field} uses unsupported JSON Schema type {declared_type!r}")


@dataclass
class SchemaRecord:
    object_id: str
    schema_path: str
    example_path: str
    canonical_sha256: str
    schema: dict[str, Any]
    example: dict[str, Any]
    schema_bytes: bytes
    example_bytes: bytes


@dataclass
class Bundle:
    root: pathlib.Path
    spec_path: str
    spec: dict[str, Any]
    spec_bytes: bytes
    schemas: dict[str, SchemaRecord]


def load_bundle(root: pathlib.Path, spec_relative: str) -> Bundle:
    spec_path = safe_path(root, spec_relative, "spec path")
    spec_bytes = spec_path.read_bytes()
    spec = require_dict(read_json(spec_path), "protocol spec")
    records: dict[str, SchemaRecord] = {}
    for index, item in enumerate(require_list(spec.get("schemas"), "schemas")):
        obj = require_dict(item, f"schemas[{index}]")
        object_id = require_string(obj.get("id"), f"schemas[{index}].id")
        if object_id in records:
            fail(f"schemas contains duplicate id {object_id!r}")
        schema_path_text = require_string(obj.get("path"), f"schemas[{index}].path")
        example_path_text = require_string(obj.get("example"), f"schemas[{index}].example")
        canonical_sha256 = require_string(obj.get("canonical_sha256"), f"schemas[{index}].canonical_sha256")
        if re.fullmatch(r"[0-9a-f]{64}", canonical_sha256) is None:
            fail(f"schemas[{index}].canonical_sha256 must be a lowercase SHA-256 digest")
        schema_path = safe_path(root, schema_path_text, f"schemas[{index}].path")
        example_path = safe_path(root, example_path_text, f"schemas[{index}].example")
        schema_bytes = schema_path.read_bytes()
        example_bytes = example_path.read_bytes()
        records[object_id] = SchemaRecord(
            object_id=object_id,
            schema_path=schema_path_text,
            example_path=example_path_text,
            canonical_sha256=canonical_sha256,
            schema=require_dict(read_json(schema_path), f"schema {object_id}"),
            example=require_dict(read_json(example_path), f"example {object_id}"),
            schema_bytes=schema_bytes,
            example_bytes=example_bytes,
        )
    return Bundle(root.resolve(), spec_relative, spec, spec_bytes, records)


def validate_normative_object_schema(schema: dict[str, Any], expected_fields: set[str] | frozenset[str], field: str) -> None:
    if schema.get("type") != "object":
        fail(f"{field} must be an object schema")
    if schema.get("additionalProperties") is not False:
        fail(f"{field} must set additionalProperties=false")
    properties = set(require_dict(schema.get("properties"), f"{field}.properties"))
    required = set(unique_strings(schema.get("required"), f"{field}.required"))
    expected = set(expected_fields)
    if properties != expected:
        fail(f"{field} property inventory mismatch: missing={sorted(expected - properties)!r} extra={sorted(properties - expected)!r}")
    if required != expected:
        fail(f"{field} required inventory mismatch: missing={sorted(expected - required)!r} extra={sorted(required - expected)!r}")


def validate_schema_record(record: SchemaRecord) -> None:
    schema = record.schema
    if sha256_bytes(canonical_json(schema)) != record.canonical_sha256:
        fail(f"schema {record.object_id} differs from its declared canonical SHA-256 digest")
    if schema.get("$schema") != JSON_SCHEMA_DIALECT:
        fail(f"schema {record.object_id} must use JSON Schema Draft 2020-12")
    require_string(schema.get("$id"), f"schema {record.object_id}.$id")
    expected_fields = NORMATIVE_SCHEMA_FIELDS.get(record.object_id)
    if expected_fields is None:
        fail(f"schema {record.object_id} has no normative field inventory")
    validate_normative_object_schema(schema, expected_fields, f"schema {record.object_id}")
    properties = require_dict(schema["properties"], f"schema {record.object_id}.properties")
    for (object_id, property_name, shape), nested_fields in NORMATIVE_NESTED_SCHEMA_FIELDS.items():
        if object_id != record.object_id:
            continue
        nested = require_dict(properties.get(property_name), f"schema {record.object_id}.{property_name}")
        if shape == "array_items":
            if nested.get("type") != "array":
                fail(f"schema {record.object_id}.{property_name} must be an array schema")
            nested = require_dict(nested.get("items"), f"schema {record.object_id}.{property_name}.items")
        validate_normative_object_schema(nested, nested_fields, f"schema {record.object_id}.{property_name}")
    definitions = require_dict(schema.get("$defs"), f"schema {record.object_id}.$defs")
    for definition_name in REQUIRED_UINT_DEFS[record.object_id]:
        definition = require_dict(definitions.get(definition_name), f"schema {record.object_id}.$defs.{definition_name}")
        if definition.get("x-pulsetensor-uintBits") != 256:
            fail(f"schema {record.object_id}.$defs.{definition_name} must declare x-pulsetensor-uintBits=256")
    validate_json_value(record.example, schema, schema, f"example {record.object_id}")


def validate_documents(bundle: Bundle) -> list[pathlib.Path]:
    documents = unique_strings(bundle.spec.get("normative_documents"), "normative_documents")
    return [safe_path(bundle.root, path, f"normative_documents[{index}]") for index, path in enumerate(documents)]


def validate_implementation_map(bundle: Bundle) -> Counter[str]:
    status_counts: Counter[str] = Counter()
    requirement_matrix = read_json(bundle.root / "specs/formal/requirements_traceability.json")
    known_requirements = {
        require_string(item.get("id"), "requirements_traceability.requirement.id")
        for item in require_list(require_dict(requirement_matrix, "requirements traceability").get("requirements"), "requirements traceability.requirements")
        if isinstance(item, dict)
    }
    items = unique_object_ids(bundle.spec.get("implementation_map"), "implementation_map")
    actual_ids = {item["id"] for item in items}
    expected_ids = set(IMPLEMENTATION_STATUS_BOUNDARY)
    if actual_ids != expected_ids:
        fail(f"implementation_map inventory mismatch: missing={sorted(expected_ids - actual_ids)!r} extra={sorted(actual_ids - expected_ids)!r}")
    for index, item in enumerate(items):
        require_string(item.get("summary"), f"implementation_map[{index}].summary")
        status = require_string(item.get("status"), f"implementation_map[{index}].status")
        if status not in ALLOWED_STATUSES:
            fail(f"implementation_map[{index}] has unsupported status {status!r}")
        expected_status = IMPLEMENTATION_STATUS_BOUNDARY[item["id"]]
        if status != expected_status:
            fail(f"implementation_map item {item['id']!r} must remain {expected_status!r}, got {status!r}")
        status_counts[status] += 1
        source = unique_strings(item.get("source"), f"implementation_map[{index}].source", nonempty=False)
        tests = unique_strings(item.get("tests"), f"implementation_map[{index}].tests", nonempty=False)
        requirements = unique_strings(item.get("requirements"), f"implementation_map[{index}].requirements", nonempty=False)
        if status in {"implemented", "partial"} and (not source or not tests or not requirements):
            fail(f"{status} item {item['id']!r} must cite source, tests, and requirements")
        if status == "target_unimplemented" and (source or tests or requirements):
            fail(f"target_unimplemented item {item['id']!r} must not masquerade as implementation evidence")
        for path_index, path in enumerate(source):
            safe_path(bundle.root, path, f"implementation_map[{index}].source[{path_index}]")
        for path_index, path in enumerate(tests):
            safe_path(bundle.root, path, f"implementation_map[{index}].tests[{path_index}]")
        unknown_requirements = sorted(set(requirements) - known_requirements)
        if unknown_requirements:
            fail(f"implementation_map[{index}] references unknown requirements {unknown_requirements!r}")
    if status_counts["target_unimplemented"] == 0:
        fail("implementation_map must identify target_unimplemented modules")
    return status_counts


def validate_asset_model(spec: dict[str, Any]) -> None:
    model = require_dict(spec.get("asset_model"), "asset_model")
    derivation = require_string(model.get("asset_id_derivation"), "asset_model.asset_id_derivation")
    if derivation != ASSET_ID_DERIVATION:
        fail(f"asset_model.asset_id_derivation must equal {ASSET_ID_DERIVATION!r}")
    abi_types = unique_strings(model.get("asset_id_abi_types"), "asset_model.asset_id_abi_types")
    if abi_types != ASSET_ID_ABI_TYPES:
        fail(f"asset_model.asset_id_abi_types must equal {ASSET_ID_ABI_TYPES!r}")
    kind_codes = require_dict(model.get("asset_kind_codes"), "asset_model.asset_kind_codes")
    if set(kind_codes) != set(ASSET_KIND_CODES):
        fail("asset_model.asset_kind_codes must define exactly NATIVE_PLS and EXACT_ERC20")
    for asset_kind, expected_code in ASSET_KIND_CODES.items():
        actual_code = require_int(kind_codes.get(asset_kind), f"asset_model.asset_kind_codes.{asset_kind}", minimum=0)
        if actual_code != expected_code:
            fail(f"asset_model.asset_kind_codes.{asset_kind} must equal {expected_code}")
    golden_vectors = require_list(model.get("asset_id_golden_vectors"), "asset_model.asset_id_golden_vectors")
    seen_vectors: set[tuple[int, str, str]] = set()
    for index, raw_vector in enumerate(golden_vectors):
        vector = require_dict(raw_vector, f"asset_model.asset_id_golden_vectors[{index}]")
        expected_keys = {"chainId", "assetKind", "assetKindCode", "tokenAddress", "abiEncoded", "assetId"}
        if set(vector) != expected_keys:
            fail(f"asset_model.asset_id_golden_vectors[{index}] must contain exactly {sorted(expected_keys)!r}")
        chain_id = require_int(vector.get("chainId"), f"asset_model.asset_id_golden_vectors[{index}].chainId", minimum=1)
        asset_kind = require_string(vector.get("assetKind"), f"asset_model.asset_id_golden_vectors[{index}].assetKind")
        if asset_kind not in ASSET_KIND_CODES:
            fail(f"asset_model.asset_id_golden_vectors[{index}] uses unsupported asset kind {asset_kind!r}")
        asset_kind_code = require_int(
            vector.get("assetKindCode"), f"asset_model.asset_id_golden_vectors[{index}].assetKindCode", minimum=0
        )
        if asset_kind_code != ASSET_KIND_CODES[asset_kind]:
            fail(f"asset_model.asset_id_golden_vectors[{index}] has the wrong assetKindCode")
        token_address = require_string(
            vector.get("tokenAddress"), f"asset_model.asset_id_golden_vectors[{index}].tokenAddress"
        )
        identity = (chain_id, asset_kind, token_address.lower())
        if identity in seen_vectors:
            fail(f"asset_model.asset_id_golden_vectors contains duplicate identity {identity!r}")
        seen_vectors.add(identity)
        encoded = "0x" + encode_asset_id_preimage(chain_id, asset_kind, token_address).hex()
        if vector.get("abiEncoded") != encoded:
            fail(f"asset_model.asset_id_golden_vectors[{index}].abiEncoded does not match the typed ABI encoding")
        if vector.get("assetId") != derive_asset_id(chain_id, asset_kind, token_address):
            fail(f"asset_model.asset_id_golden_vectors[{index}].assetId does not match keccak256(abi.encode(...))")
    if require_int(model.get("max_assets_per_task"), "asset_model.max_assets_per_task") != 1:
        fail("asset_model.max_assets_per_task must equal 1 in target v1")
    if not require_bool(
        model.get("task_asset_chain_must_equal_task_chain"), "asset_model.task_asset_chain_must_equal_task_chain"
    ):
        fail("asset_model.task_asset_chain_must_equal_task_chain must be true")
    if require_int(model.get("funding_quantum_base_units"), "asset_model.funding_quantum_base_units") != 10000:
        fail("asset_model.funding_quantum_base_units must equal 10000")
    if require_bool(model.get("base_kernel_price_oracle"), "asset_model.base_kernel_price_oracle"):
        fail("asset_model.base_kernel_price_oracle must be false")
    if require_bool(model.get("cross_asset_netting"), "asset_model.cross_asset_netting"):
        fail("asset_model.cross_asset_netting must be false")
    if require_bool(model.get("cross_asset_conversion"), "asset_model.cross_asset_conversion"):
        fail("asset_model.cross_asset_conversion must be false")
    if not require_bool(model.get("same_asset_bond_required"), "asset_model.same_asset_bond_required"):
        fail("asset_model.same_asset_bond_required must be true")
    if not require_bool(model.get("native_pls_and_wpls_are_distinct_assets"), "asset_model.native_pls_and_wpls_are_distinct_assets"):
        fail("native PLS and WPLS must remain distinct ledger assets")
    launch_kinds = unique_strings(model.get("base_launch_asset_kinds"), "asset_model.base_launch_asset_kinds")
    if launch_kinds != ["NATIVE_PLS"]:
        fail("target v1 base launch must be native PLS only")
    semantics = unique_object_ids(model.get("asset_semantics"), "asset_model.asset_semantics")
    if {item["id"] for item in semantics} != set(ASSET_KIND_CODES):
        fail("asset_model asset semantics must exactly match the typed asset-kind mapping")
    rejected = set(unique_strings(model.get("rejected_semantics"), "asset_model.rejected_semantics"))
    required_rejections = {"fee-on-transfer", "rebasing", "reflection", "receiver hooks"}
    if not required_rejections <= rejected:
        fail(f"asset_model.rejected_semantics is missing {sorted(required_rejections - rejected)!r}")


def validate_economics(spec: dict[str, Any]) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    economics = require_dict(spec.get("economics"), "economics")
    sources = set(unique_strings(economics.get("funding_sources"), "economics.funding_sources"))
    if not {"REQUESTER_DEPOSIT", "SPONSOR_DEPOSIT"} <= sources:
        fail("economics.funding_sources must include requester and sponsor deposits")
    if require_bool(economics.get("unfunded_credit_allowed"), "economics.unfunded_credit_allowed"):
        fail("economics.unfunded_credit_allowed must be false")
    if require_bool(economics.get("minted_protocol_rewards"), "economics.minted_protocol_rewards"):
        fail("economics.minted_protocol_rewards must be false")
    if require_bool(economics.get("fee_mutable_after_assignment"), "economics.fee_mutable_after_assignment"):
        fail("economics.fee_mutable_after_assignment must be false")
    denominator = require_int(economics.get("bps_denominator"), "economics.bps_denominator", minimum=1)
    if denominator != 10000:
        fail("economics.bps_denominator must equal 10000")
    if require_string(economics.get("allocation_unit"), "economics.allocation_unit") != "EACH_ORIGINAL_CONTRIBUTION":
        fail("economics must allocate each original contribution independently")
    if require_string(economics.get("refund_recipient_source"), "economics.refund_recipient_source") != "CONTRIBUTION.refundRecipient":
        fail("economics refunds must use the original contribution refund recipient")
    if not require_bool(economics.get("contributor_ownership_preserved"), "economics.contributor_ownership_preserved"):
        fail("economics must preserve contributor ownership on refunds")
    if require_string(economics.get("empty_recipient_fallback"), "economics.empty_recipient_fallback") != "CONTRIBUTOR_COMPENSATION":
        fail("empty payout recipients must fall back to contributor compensation")

    roles = unique_object_ids(economics.get("payout_roles"), "economics.payout_roles")
    actual_role_ids = {role["id"] for role in roles}
    if actual_role_ids != set(PAYOUT_ROLE_RULES):
        fail(
            f"economics payout-role inventory mismatch: missing={sorted(set(PAYOUT_ROLE_RULES) - actual_role_ids)!r} "
            f"extra={sorted(actual_role_ids - set(PAYOUT_ROLE_RULES))!r}"
        )
    role_by_id: dict[str, dict[str, Any]] = {}
    for index, role in enumerate(roles):
        default = require_int(role.get("default_bps"), f"economics.payout_roles[{index}].default_bps", minimum=0)
        minimum = require_int(role.get("min_bps"), f"economics.payout_roles[{index}].min_bps", minimum=0)
        maximum = require_int(role.get("max_bps"), f"economics.payout_roles[{index}].max_bps", minimum=0)
        if not minimum <= default <= maximum <= denominator:
            fail(f"economics payout role {role['id']!r} has inconsistent bounds")
        actual_rule = {"default_bps": default, "min_bps": minimum, "max_bps": maximum}
        if actual_rule != PAYOUT_ROLE_RULES[role["id"]]:
            fail(f"economics payout role {role['id']!r} differs from the version-1 launch policy")
        role_by_id[role["id"]] = role
    if sum(require_int(role["default_bps"], f"role {role['id']}.default_bps") for role in roles) != denominator:
        fail("economics default payout roles must sum to 10000 bps")

    coupled_bounds = unique_object_ids(economics.get("coupled_bounds"), "economics.coupled_bounds")
    actual_bound_ids = {bound["id"] for bound in coupled_bounds}
    if actual_bound_ids != set(COUPLED_BOUND_RULES):
        fail("economics coupled-bound inventory differs from the version-1 launch policy")
    for index, bound in enumerate(coupled_bounds):
        bounded_roles = unique_strings(bound.get("roles"), f"economics.coupled_bounds[{index}].roles")
        if not set(bounded_roles) <= set(role_by_id):
            fail(f"economics coupled bound {bound['id']!r} references unknown roles")
        cap = require_int(bound.get("max_bps"), f"economics.coupled_bounds[{index}].max_bps", minimum=0)
        expected_bound = COUPLED_BOUND_RULES[bound["id"]]
        if tuple(bounded_roles) != expected_bound["roles"] or cap != expected_bound["max_bps"]:
            fail(f"economics coupled bound {bound['id']!r} differs from the version-1 launch policy")
        default_total = sum(require_int(role_by_id[item]["default_bps"], f"role {item}.default_bps") for item in bounded_roles)
        if default_total > cap:
            fail(f"economics coupled bound {bound['id']!r} is violated by defaults")

    vectors = unique_object_ids(economics.get("payout_vectors"), "economics.payout_vectors")
    vector_by_id: dict[str, dict[str, Any]] = {}
    allowed_roles = set(role_by_id) | SPECIAL_PAYOUT_ROLES
    for index, vector in enumerate(vectors):
        require_string(vector.get("principal"), f"economics.payout_vectors[{index}].principal")
        allocations = require_list(vector.get("allocations"), f"economics.payout_vectors[{index}].allocations")
        allocation_roles: set[str] = set()
        total = 0
        for allocation_index, allocation_value in enumerate(allocations):
            allocation = require_dict(allocation_value, f"economics.payout_vectors[{index}].allocations[{allocation_index}]")
            role = require_string(allocation.get("role"), f"economics.payout_vectors[{index}].allocations[{allocation_index}].role")
            if role not in allowed_roles:
                fail(f"payout vector {vector['id']!r} references unknown role {role!r}")
            if role in allocation_roles:
                fail(f"payout vector {vector['id']!r} repeats role {role!r}")
            allocation_roles.add(role)
            total += require_int(allocation.get("bps"), f"economics.payout_vectors[{index}].allocations[{allocation_index}].bps", minimum=0)
        if total != denominator:
            fail(f"payout vector {vector['id']!r} must sum to 10000 bps, got {total}")
        vector_by_id[vector["id"]] = vector

    accepted = vector_by_id.get("ACCEPTED_BOUNTY")
    if accepted is None:
        fail("economics must define ACCEPTED_BOUNTY")
    accepted_map = {item["role"]: item["bps"] for item in accepted["allocations"]}
    default_map = {item["id"]: item["default_bps"] for item in roles}
    if accepted_map != default_map:
        fail("ACCEPTED_BOUNTY must exactly match the default payout-role vector")
    expected_vector_ids = set(PAYOUT_VECTOR_RULES)
    actual_vector_ids = set(vector_by_id)
    if actual_vector_ids != expected_vector_ids:
        fail(
            f"economics payout-vector inventory mismatch: missing={sorted(expected_vector_ids - actual_vector_ids)!r} "
            f"extra={sorted(actual_vector_ids - expected_vector_ids)!r}"
        )
    for vector_id, rule in PAYOUT_VECTOR_RULES.items():
        vector = vector_by_id[vector_id]
        if vector["principal"] != rule["principal"]:
            fail(f"payout vector {vector_id!r} must dispose principal {rule['principal']!r}")
        required_map = rule["allocations"]
        if required_map is None:
            continue
        actual_map = {item["role"]: item["bps"] for item in vector["allocations"]}
        if actual_map != required_map:
            fail(f"payout vector {vector_id!r} must preserve its normative allocation")

    bond_policy = require_dict(economics.get("bond_policy"), "economics.bond_policy")
    for field, expected in BOND_POLICY_BOUNDS.items():
        if require_int(bond_policy.get(field), f"economics.bond_policy.{field}", minimum=0) != expected:
            fail(f"economics.bond_policy.{field} differs from the version-1 launch policy")
    if require_bool(bond_policy.get("subjective_disagreement_is_slashable"), "economics.bond_policy.subjective_disagreement_is_slashable"):
        fail("subjective disagreement must not be slashable")
    objective_faults = set(unique_strings(bond_policy.get("objective_faults"), "economics.bond_policy.objective_faults"))
    if objective_faults != BOND_OBJECTIVE_FAULTS:
        fail("economics.bond_policy.objective_faults differs from the version-1 objective-fault inventory")
    maintenance = require_dict(economics.get("maintenance_flow"), "economics.maintenance_flow")
    if require_bool(maintenance.get("guaranteed"), "economics.maintenance_flow.guaranteed"):
        fail("economics must not guarantee maintenance income")
    if not require_bool(
        maintenance.get("zero_external_funding_implies_zero_maintenance_flow"),
        "economics.maintenance_flow.zero_external_funding_implies_zero_maintenance_flow",
    ):
        fail("zero external funding must imply zero maintenance flow")
    return roles, vectors


def schema_property_enum(bundle: Bundle, schema_id: str, property_name: str) -> set[str]:
    schema = bundle.schemas[schema_id].schema
    properties = require_dict(schema.get("properties"), f"schema {schema_id}.properties")
    property_schema = require_dict(properties.get(property_name), f"schema {schema_id}.{property_name}")
    if "$ref" in property_schema:
        property_schema = resolve_ref(
            schema,
            require_string(property_schema["$ref"], f"schema {schema_id}.{property_name}.$ref"),
            f"schema {schema_id}.{property_name}",
        )
    return set(unique_strings(property_schema.get("enum"), f"schema {schema_id}.{property_name}.enum"))


def validate_lifecycle(spec: dict[str, Any], vectors: list[dict[str, Any]], bundle: Bundle) -> list[dict[str, Any]]:
    lifecycle = require_dict(spec.get("lifecycle"), "lifecycle")
    states = unique_strings(lifecycle.get("states"), "lifecycle.states")
    state_set = set(states)
    if state_set != LIFECYCLE_STATES:
        fail(f"lifecycle state inventory mismatch: missing={sorted(LIFECYCLE_STATES - state_set)!r} extra={sorted(state_set - LIFECYCLE_STATES)!r}")
    initial = require_string(lifecycle.get("initial_state"), "lifecycle.initial_state")
    terminals = set(unique_strings(lifecycle.get("terminal_states"), "lifecycle.terminal_states"))
    if initial not in state_set:
        fail("lifecycle.initial_state must exist in lifecycle.states")
    if not terminals <= state_set:
        fail("lifecycle.terminal_states must exist in lifecycle.states")
    if terminals != {"SETTLED"}:
        fail("target v1 lifecycle must use SETTLED as its only terminal state")

    transitions = unique_object_ids(lifecycle.get("transitions"), "lifecycle.transitions")
    transition_ids = {item["id"] for item in transitions}
    expected_transition_ids = set(LIFECYCLE_TRANSITION_EDGES)
    if transition_ids != expected_transition_ids:
        fail(
            f"lifecycle transition inventory mismatch: missing={sorted(expected_transition_ids - transition_ids)!r} "
            f"extra={sorted(transition_ids - expected_transition_ids)!r}"
        )
    vector_by_id = {item["id"]: item for item in vectors}
    outcome_enum = schema_property_enum(bundle, "DecisionRecordV1", "outcome")
    reason_enum = schema_property_enum(bundle, "DecisionRecordV1", "reasonCode")
    bounty_vector_enum = schema_property_enum(bundle, "DecisionRecordV1", "bountyVectorId")
    provider_vector_enum = schema_property_enum(bundle, "DecisionRecordV1", "providerBondVectorId") - {"NONE"}
    forward: dict[str, set[str]] = {state: set() for state in states}
    reverse: dict[str, set[str]] = {state: set() for state in states}
    seen_edges: set[tuple[str, str]] = set()
    for index, transition in enumerate(transitions):
        source = require_string(transition.get("from"), f"lifecycle.transitions[{index}].from")
        target = require_string(transition.get("to"), f"lifecycle.transitions[{index}].to")
        expected_edge = LIFECYCLE_TRANSITION_EDGES[transition["id"]]
        if (source, target) != expected_edge:
            fail(f"lifecycle transition {transition['id']!r} must remain {expected_edge[0]!r}->{expected_edge[1]!r}")
        if source not in state_set or target not in state_set:
            fail(f"lifecycle transition {transition['id']!r} references an unknown state")
        if source in terminals:
            fail(f"terminal state {source!r} must have no outgoing transition")
        if (source, target) in seen_edges:
            fail(f"lifecycle contains duplicate edge {source!r}->{target!r}")
        seen_edges.add((source, target))
        forward[source].add(target)
        reverse[target].add(source)
        if target != "SETTLED":
            if set(transition) != {"id", "from", "to"}:
                fail(f"non-settlement transition {transition['id']!r} must contain only id, from, and to")
            continue

        expected_transition_keys = {
            "id",
            "from",
            "to",
            "decision_outcome",
            "decision_reason",
            "principal_dispositions",
        }
        if set(transition) != expected_transition_keys:
            fail(f"settlement transition {transition['id']!r} must contain exactly {sorted(expected_transition_keys)!r}")
        rule = SETTLEMENT_DECISION_RULES[transition["id"]]
        outcome = require_string(transition.get("decision_outcome"), f"lifecycle.transitions[{index}].decision_outcome")
        reason = require_string(transition.get("decision_reason"), f"lifecycle.transitions[{index}].decision_reason")
        if outcome not in outcome_enum or reason not in reason_enum:
            fail(f"settlement transition {transition['id']!r} uses an unknown decision outcome or reason")
        if outcome != rule["outcome"] or reason != rule["reason"]:
            fail(f"settlement transition {transition['id']!r} has an invalid decision outcome/reason mapping")

        raw_dispositions = require_list(
            transition.get("principal_dispositions"), f"lifecycle.transitions[{index}].principal_dispositions"
        )
        dispositions: dict[str, tuple[str, tuple[str, ...]]] = {}
        for disposition_index, raw_disposition in enumerate(raw_dispositions):
            disposition = require_dict(
                raw_disposition, f"lifecycle.transitions[{index}].principal_dispositions[{disposition_index}]"
            )
            if set(disposition) != {"principal", "selection", "allowed_vectors"}:
                fail(f"settlement transition {transition['id']!r} has a malformed principal disposition")
            principal = require_string(
                disposition.get("principal"),
                f"lifecycle.transitions[{index}].principal_dispositions[{disposition_index}].principal",
            )
            if principal in dispositions:
                fail(f"settlement transition {transition['id']!r} repeats principal {principal!r}")
            selection = require_string(
                disposition.get("selection"),
                f"lifecycle.transitions[{index}].principal_dispositions[{disposition_index}].selection",
            )
            allowed_vectors = tuple(
                unique_strings(
                    disposition.get("allowed_vectors"),
                    f"lifecycle.transitions[{index}].principal_dispositions[{disposition_index}].allowed_vectors",
                    nonempty=False,
                )
            )
            dispositions[principal] = (selection, allowed_vectors)
            for vector_id in allowed_vectors:
                vector = vector_by_id.get(vector_id)
                if vector is None:
                    fail(f"settlement transition {transition['id']!r} references unknown payout vector {vector_id!r}")
                if vector["principal"] != principal:
                    fail(
                        f"settlement transition {transition['id']!r} applies {vector_id!r} to the wrong principal {principal!r}"
                    )
                if principal == "BOUNTY" and vector_id not in bounty_vector_enum:
                    fail(f"settlement transition {transition['id']!r} uses a bounty vector absent from DecisionRecordV1")
                if principal == "PROVIDER_BOND" and vector_id not in provider_vector_enum:
                    fail(f"settlement transition {transition['id']!r} uses a provider vector absent from DecisionRecordV1")
        if set(dispositions) != {"BOUNTY", "PROVIDER_BOND", "EVALUATOR_BOND_EACH"}:
            fail(f"settlement transition {transition['id']!r} must dispose all three principals exactly once")
        if dispositions != rule["dispositions"]:
            fail(f"settlement transition {transition['id']!r} does not match its normative principal dispositions")

    reachable: set[str] = set()
    queue = deque([initial])
    while queue:
        state = queue.popleft()
        if state in reachable:
            continue
        reachable.add(state)
        queue.extend(sorted(forward[state] - reachable))
    unreachable = sorted(state_set - reachable)
    if unreachable:
        fail(f"lifecycle contains unreachable states {unreachable!r}")

    can_reach_terminal: set[str] = set(terminals)
    queue = deque(sorted(terminals))
    while queue:
        state = queue.popleft()
        for prior in sorted(reverse[state]):
            if prior not in can_reach_terminal:
                can_reach_terminal.add(prior)
                queue.append(prior)
    stranded = sorted(state_set - can_reach_terminal)
    if stranded:
        fail(f"lifecycle contains states with no terminal path {stranded!r}")

    required_refund_states = {
        "CANCELLED_REFUND",
        "ASSIGNMENT_EXPIRED_REFUND",
        "PROVIDER_DEFAULT_REFUND",
        "EVALUATION_FAILED_REFUND",
        "CHALLENGE_EXPIRED_REFUND",
    }
    for state in required_refund_states:
        matching = [item for item in transitions if item.get("from") == state and item.get("to") == "SETTLED"]
        if len(matching) != 1:
            fail(f"refund state {state!r} must have exactly one settlement edge")
        bounty = next(item for item in matching[0]["principal_dispositions"] if item["principal"] == "BOUNTY")
        if matching[0]["decision_outcome"] != "FULL_REFUND" or bounty["allowed_vectors"] != ["FULL_REFUND_BOUNTY"]:
            fail(f"refund state {state!r} must settle with FULL_REFUND_BOUNTY")

    never_blocks = set(unique_strings(lifecycle.get("pause_never_blocks"), "lifecycle.pause_never_blocks"))
    required_unblocked = {
        "challenge",
        "timeout resolution",
        "refund conversion",
        "claim withdrawal",
    }
    if not required_unblocked <= never_blocks:
        fail(f"pause_never_blocks is missing {sorted(required_unblocked - never_blocks)!r}")
    if not require_bool(lifecycle.get("claims_are_separate_liabilities"), "lifecycle.claims_are_separate_liabilities"):
        fail("claims must remain separate liabilities after task settlement")
    return transitions


def validate_modes_and_consensus(spec: dict[str, Any], bundle: Bundle) -> None:
    modes = unique_object_ids(spec.get("assurance_modes"), "assurance_modes")
    mode_ids = {item["id"] for item in modes}
    if mode_ids != ASSURANCE_MODES:
        fail(f"assurance_modes must equal {sorted(ASSURANCE_MODES)!r}")
    receipt_properties = set(require_dict(bundle.schemas["WorkReceiptV1"].schema.get("properties"), "WorkReceiptV1.properties"))
    receipt_domain_fields = REQUIRED_DOMAIN_FIELDS["WORK_RECEIPT_DOMAIN"]
    for index, mode in enumerate(modes):
        require_string(mode.get("claim"), f"assurance_modes[{index}].claim")
        require_string(mode.get("decision_rule"), f"assurance_modes[{index}].decision_rule")
        fields = set(unique_strings(mode.get("required_receipt_fields"), f"assurance_modes[{index}].required_receipt_fields"))
        if not fields <= receipt_properties:
            fail(f"assurance mode {mode['id']!r} references unknown receipt fields")
        if not fields <= receipt_domain_fields:
            fail(f"assurance mode {mode['id']!r} requires unsigned receipt fields {sorted(fields - receipt_domain_fields)!r}")
        require_string(mode.get("challenge_behavior"), f"assurance_modes[{index}].challenge_behavior")
        exclusion = require_string(mode.get("excluded_guarantee"), f"assurance_modes[{index}].excluded_guarantee")
        if mode["id"] == "REQUESTER_ACCEPTED" and "not a correctness proof" not in exclusion:
            fail("REQUESTER_ACCEPTED must explicitly exclude a correctness proof")

    for schema_id in ("TaskSpecV1", "WorkReceiptV1"):
        schema = bundle.schemas[schema_id].schema
        enum = set(resolve_ref(schema, "#/$defs/assuranceMode", schema_id).get("enum", []))
        if enum != ASSURANCE_MODES:
            fail(f"{schema_id} assuranceMode enum must match the target assurance modes")
    if schema_property_enum(bundle, "DecisionRecordV1", "assuranceMode") != ASSURANCE_MODES:
        fail("DecisionRecordV1 assuranceMode enum must match the target assurance modes")
    expected_outcomes = {rule["outcome"] for rule in SETTLEMENT_DECISION_RULES.values()}
    expected_reasons = {rule["reason"] for rule in SETTLEMENT_DECISION_RULES.values()}
    expected_bounty_vectors = {
        vector_id for vector_id, rule in PAYOUT_VECTOR_RULES.items() if rule["principal"] == "BOUNTY"
    }
    expected_provider_vectors = {"NONE"} | {
        vector_id for vector_id, rule in PAYOUT_VECTOR_RULES.items() if rule["principal"] == "PROVIDER_BOND"
    }
    decision_enums = {
        "outcome": expected_outcomes,
        "reasonCode": expected_reasons,
        "bountyVectorId": expected_bounty_vectors,
        "providerBondVectorId": expected_provider_vectors,
    }
    for property_name, expected in decision_enums.items():
        if schema_property_enum(bundle, "DecisionRecordV1", property_name) != expected:
            fail(f"DecisionRecordV1 {property_name} enum differs from the settlement inventory")

    consensus = require_dict(spec.get("quality_consensus"), "quality_consensus")
    minimum = require_int(consensus.get("committee_min"), "quality_consensus.committee_min", minimum=1)
    default = require_int(consensus.get("committee_default"), "quality_consensus.committee_default", minimum=1)
    maximum = require_int(consensus.get("committee_max"), "quality_consensus.committee_max", minimum=1)
    if not (minimum <= default <= maximum <= 7 and minimum >= 3 and default % 2 == 1):
        fail("quality_consensus committee bounds must be odd-default 3..7")
    if require_bool(consensus.get("stake_only_selection"), "quality_consensus.stake_only_selection"):
        fail("quality_consensus.stake_only_selection must be false")
    if not require_bool(consensus.get("selection_snapshot_before_output"), "quality_consensus.selection_snapshot_before_output"):
        fail("quality committee selection must be snapshotted before output")
    if not require_bool(consensus.get("commit_reveal"), "quality_consensus.commit_reveal"):
        fail("quality consensus must use commit/reveal")
    if require_int(consensus.get("score_min"), "quality_consensus.score_min") != 0:
        fail("quality score minimum must equal 0")
    if require_int(consensus.get("score_max"), "quality_consensus.score_max") != 10000:
        fail("quality score maximum must equal 10000")
    if require_int(consensus.get("criterion_weight_sum"), "quality_consensus.criterion_weight_sum") != 10000:
        fail("quality criterion weights must sum to 10000")
    if consensus.get("no_quorum_result") != "EVALUATION_FAILED_REFUND":
        fail("quality no-quorum result must refund")
    if consensus.get("payout_curve") != "BINARY_ACCEPT_OR_REFUND":
        fail("target v1 quality payout curve must be binary")
    unique_strings(consensus.get("non_guarantees"), "quality_consensus.non_guarantees")


def validate_network(spec: dict[str, Any], bundle: Bundle) -> None:
    network = require_dict(spec.get("network"), "network")
    if not require_bool(network.get("controller_operator_separation"), "network.controller_operator_separation"):
        fail("network must separate controller and operator authority")
    if require_bool(network.get("indexer_has_settlement_authority"), "network.indexer_has_settlement_authority"):
        fail("network indexer must not have settlement authority")
    if network.get("wire_protocol") != "ptauth/1":
        fail("network.wire_protocol must equal ptauth/1")
    if not require_bool(network.get("request_receiver_required"), "network.request_receiver_required"):
        fail("ptauth receiver binding must be mandatory")
    if not require_bool(network.get("raw_body_hash_required"), "network.raw_body_hash_required"):
        fail("ptauth raw body binding must be mandatory")
    if not require_bool(network.get("shared_replay_store_required"), "network.shared_replay_store_required"):
        fail("ptauth replay store must be shared across server processes")
    message_types = set(unique_strings(network.get("message_types"), "network.message_types"))
    auth_schema = bundle.schemas["PTAuthEnvelopeV1"].schema
    schema_message_types = set(
        require_list(
            require_dict(auth_schema["properties"]["messageType"], "PTAuth messageType schema").get("enum"),
            "PTAuth messageType enum",
        )
    )
    if message_types != schema_message_types:
        fail("network message types must exactly match PTAuthEnvelopeV1")


def validate_hash_domains(spec: dict[str, Any], bundle: Bundle) -> None:
    domains = unique_object_ids(spec.get("hash_domains"), "hash_domains")
    domain_ids = {item["id"] for item in domains}
    if domain_ids != set(REQUIRED_DOMAIN_FIELDS):
        fail(f"hash_domains must equal {sorted(REQUIRED_DOMAIN_FIELDS)!r}")
    for index, domain in enumerate(domains):
        object_id = require_string(domain.get("object"), f"hash_domains[{index}].object")
        expected_object_id = DOMAIN_OBJECTS[domain["id"]]
        if object_id != expected_object_id:
            fail(f"hash domain {domain['id']!r} must bind {expected_object_id!r}, got {object_id!r}")
        field_order = unique_strings(domain.get("required_fields"), f"hash_domains[{index}].required_fields")
        fields = set(field_order)
        required = REQUIRED_DOMAIN_FIELDS[domain["id"]]
        if fields != required:
            fail(
                f"hash domain {domain['id']!r} field inventory mismatch: "
                f"missing={sorted(required - fields)!r} extra={sorted(fields - required)!r}"
            )
        schema_fields = set(require_dict(bundle.schemas[object_id].schema.get("properties"), f"schema {object_id}.properties"))
        schema_required = set(
            unique_strings(bundle.schemas[object_id].schema.get("required"), f"schema {object_id}.required")
        )
        if not fields <= schema_fields & schema_required:
            fail(f"hash domain {domain['id']!r} contains fields that are not required by {object_id}")
        schema_required_order = unique_strings(
            bundle.schemas[object_id].schema.get("required"), f"schema {object_id}.required"
        )
        expected_order = [field for field in schema_required_order if field not in DOMAIN_EXCLUDED_FIELDS[object_id]]
        if field_order != expected_order:
            fail(f"hash domain {domain['id']!r} field order must match the normative typed-struct order")


def validate_settlement_nullifiers(spec: dict[str, Any]) -> None:
    nullifiers = unique_object_ids(spec.get("settlement_nullifiers"), "settlement_nullifiers")
    actual_ids = {item["id"] for item in nullifiers}
    expected_ids = set(SETTLEMENT_NULLIFIER_RULES)
    if actual_ids != expected_ids:
        fail(f"settlement nullifier inventory mismatch: missing={sorted(expected_ids - actual_ids)!r} extra={sorted(actual_ids - expected_ids)!r}")
    consumed_keys: set[str] = set()
    expected_keys = {"id", "derivation", "abi_types", "required_fields", "consumed_key", "includes_signature_bytes"}
    for index, nullifier in enumerate(nullifiers):
        if set(nullifier) != expected_keys:
            fail(f"settlement_nullifiers[{index}] must contain exactly {sorted(expected_keys)!r}")
        rule = SETTLEMENT_NULLIFIER_RULES[nullifier["id"]]
        if require_string(nullifier.get("derivation"), f"settlement_nullifiers[{index}].derivation") != rule["derivation"]:
            fail(f"settlement nullifier {nullifier['id']!r} has a non-normative derivation")
        abi_types = tuple(
            require_string(value, f"settlement_nullifiers[{index}].abi_types[{type_index}]")
            for type_index, value in enumerate(
                require_list(nullifier.get("abi_types"), f"settlement_nullifiers[{index}].abi_types")
            )
        )
        if abi_types != rule["abi_types"]:
            fail(f"settlement nullifier {nullifier['id']!r} has non-normative ABI types")
        fields = tuple(unique_strings(nullifier.get("required_fields"), f"settlement_nullifiers[{index}].required_fields"))
        if fields != rule["required_fields"]:
            fail(f"settlement nullifier {nullifier['id']!r} has non-normative required fields")
        consumed_key = require_string(nullifier.get("consumed_key"), f"settlement_nullifiers[{index}].consumed_key")
        if consumed_key != rule["consumed_key"]:
            fail(f"settlement nullifier {nullifier['id']!r} has the wrong consumed key")
        if consumed_key in consumed_keys:
            fail(f"settlement nullifiers collapse onto consumed key {consumed_key!r}")
        consumed_keys.add(consumed_key)
        if require_bool(
            nullifier.get("includes_signature_bytes"), f"settlement_nullifiers[{index}].includes_signature_bytes"
        ):
            fail(f"settlement nullifier {nullifier['id']!r} must exclude raw signature bytes")
    if not require_bool(
        spec.get("settlement_requires_all_nullifiers_unconsumed"), "settlement_requires_all_nullifiers_unconsumed"
    ):
        fail("settlement must require all nullifiers to be unconsumed")


def validate_governance(spec: dict[str, Any]) -> None:
    governance = require_dict(spec.get("governance"), "governance")
    require_int(governance.get("minimum_policy_delay_blocks"), "governance.minimum_policy_delay_blocks", minimum=1)
    required_true = {
        "live_task_policy_is_immutable",
        "live_task_asset_adapter_is_immutable",
        "emergency_pause_refund_liveness",
        "upgrade_migration_requires_each_payer_opt_in",
    }
    for field in required_true:
        if not require_bool(governance.get(field), f"governance.{field}"):
            fail(f"governance.{field} must be true")
    if require_bool(governance.get("governance_can_seize_liabilities"), "governance.governance_can_seize_liabilities"):
        fail("governance cannot seize liabilities")
    if require_bool(governance.get("governance_can_cross_asset_net"), "governance.governance_can_cross_asset_net"):
        fail("governance cannot cross-asset net")


def validate_invariants(spec: dict[str, Any]) -> list[dict[str, Any]]:
    invariants = unique_object_ids(spec.get("invariants"), "invariants")
    required_ids = {
        "INV-ASSET-001",
        "INV-ASSET-002",
        "INV-FUND-001",
        "INV-SETTLE-001",
        "INV-BOND-001",
        "INV-AUTH-001",
        "INV-LIFE-001",
        "INV-PAUSE-001",
        "INV-GOV-001",
        "INV-EVAL-001",
        "INV-EVAL-002",
        "INV-NET-001",
    }
    actual_ids = {item["id"] for item in invariants}
    if actual_ids != required_ids:
        fail(f"invariant inventory mismatch: missing={sorted(required_ids - actual_ids)!r} extra={sorted(actual_ids - required_ids)!r}")
    for index, invariant in enumerate(invariants):
        require_string(invariant.get("statement"), f"invariants[{index}].statement")
        status = require_string(invariant.get("proof_status"), f"invariants[{index}].proof_status")
        if status not in ALLOWED_PROOF_STATUSES:
            fail(f"invariant {invariant['id']!r} has unsupported proof status {status!r}")
        unique_strings(invariant.get("assumptions"), f"invariants[{index}].assumptions", nonempty=False)
        require_string(invariant.get("support_recipe"), f"invariants[{index}].support_recipe")
        require_string(invariant.get("refute_recipe"), f"invariants[{index}].refute_recipe")
        if status == "proved" and not invariant.get("proof_evidence"):
            fail(f"proved invariant {invariant['id']!r} must cite proof_evidence")
    return invariants


def validate_examples(bundle: Bundle) -> None:
    task = bundle.schemas["TaskSpecV1"].example
    receipt = bundle.schemas["WorkReceiptV1"].example
    evaluation = bundle.schemas["EvaluationRevealV1"].example
    decision = bundle.schemas["DecisionRecordV1"].example
    node = bundle.schemas["NodeDescriptorV1"].example
    auth = bundle.schemas["PTAuthEnvelopeV1"].example
    quantum = bundle.spec["asset_model"]["funding_quantum_base_units"]

    for field in ("chainId", "settlementContract", "taskId", "provider", "inputCommitment", "canonicalSemanticsId", "assuranceMode"):
        if receipt[field] != task[field]:
            fail(f"TaskSpecV1 and WorkReceiptV1 examples disagree on {field}")
    for field in ("fundedAmount", "providerBondAmount", "evaluatorBondAmount"):
        if int(task[field]) % quantum != 0:
            fail(f"TaskSpecV1 example {field} must be a multiple of the funding quantum")
    if task["paymentAsset"]["chainId"] != task["chainId"]:
        fail("TaskSpecV1 example asset chain must match task chain")
    if task["paymentAsset"]["kind"] == "NATIVE_PLS" and task["paymentAsset"]["token"] != "0x" + "0" * 40:
        fail("TaskSpecV1 native PLS token address must be zero")
    expected_asset_id = derive_asset_id(
        task["paymentAsset"]["chainId"], task["paymentAsset"]["kind"], task["paymentAsset"]["token"]
    )
    if task["paymentAsset"]["assetId"] != expected_asset_id:
        fail("TaskSpecV1 example assetId must match the typed asset-id derivation")
    deadlines = [int(task["deadlines"][key]) for key in ("assignment", "submission", "evaluationCommit", "evaluationReveal", "challenge", "claim")]
    if any(left >= right for left, right in zip(deadlines, deadlines[1:])):
        fail("TaskSpecV1 deadlines must be strictly increasing")
    if not deadlines[0] <= int(receipt["startedAtBlock"]) <= int(receipt["submittedAtBlock"]) <= deadlines[1]:
        fail("WorkReceiptV1 example execution blocks must fit the task window")

    if evaluation["chainId"] != task["chainId"] or evaluation["taskId"] != task["taskId"]:
        fail("EvaluationRevealV1 example must match the task chain and taskId")
    if evaluation["evaluationPolicyHash"] != task["evaluationPolicyHash"]:
        fail("EvaluationRevealV1 example must match the task evaluation policy")
    criteria = [item["criterionId"] for item in evaluation["scoreVector"]]
    if len(criteria) != len(set(criteria)):
        fail("EvaluationRevealV1 example criterion IDs must be unique")

    for field in ("chainId", "taskId", "assuranceMode"):
        if decision[field] != task[field]:
            fail(f"DecisionRecordV1 and TaskSpecV1 examples disagree on {field}")
    if decision["taskMarket"] != task["settlementContract"]:
        fail("DecisionRecordV1 example taskMarket must match the task settlement contract")
    if decision["taskSpecHash"] != receipt["taskSpecHash"]:
        fail("DecisionRecordV1 example must bind the example task-spec hash")
    if decision["receiptHash"] != evaluation["receiptHash"]:
        fail("DecisionRecordV1 example must bind the example receipt hash")
    matching_decision_rules = [
        rule
        for rule in SETTLEMENT_DECISION_RULES.values()
        if rule["outcome"] == decision["outcome"] and rule["reason"] == decision["reasonCode"]
    ]
    if len(matching_decision_rules) != 1:
        fail("DecisionRecordV1 example must match exactly one settlement decision rule")
    decision_rule = matching_decision_rules[0]
    if decision["bountyVectorId"] not in decision_rule["dispositions"]["BOUNTY"][1]:
        fail("DecisionRecordV1 example bounty vector is inconsistent with its outcome and reason")
    provider_vectors = decision_rule["dispositions"]["PROVIDER_BOND"][1]
    expected_provider_vector = "NONE" if not provider_vectors else provider_vectors[0]
    if decision["providerBondVectorId"] != expected_provider_vector:
        fail("DecisionRecordV1 example provider-bond vector is inconsistent with its outcome and reason")

    if int(node["validFromBlock"]) >= int(node["validUntilBlock"]):
        fail("NodeDescriptorV1 example validity window must be increasing")
    for field in ("chainId", "netuid", "mechid", "nodeRegistry"):
        if auth[field] != node[field]:
            fail(f"PTAuthEnvelopeV1 and NodeDescriptorV1 examples disagree on {field}")
    if auth["receiverOperator"] != node["operator"]:
        fail("PTAuthEnvelopeV1 example receiver must match the node operator")
    if auth["taskId"] != task["taskId"] or auth["attemptId"] != receipt["attemptId"]:
        fail("PTAuthEnvelopeV1 example must bind the example task and attempt")
    for field in ("chainId", "netuid", "mechid"):
        if node[field] != task[field]:
            fail(f"NodeDescriptorV1 and TaskSpecV1 examples disagree on {field}")
    if node["operator"] != task["provider"]:
        fail("NodeDescriptorV1 example operator must match the task provider")
    if task["taskVersion"] not in node["supportedTaskVersions"]:
        fail("NodeDescriptorV1 example must support the example task version")
    if receipt["receiptVersion"] not in node["supportedReceiptVersions"]:
        fail("NodeDescriptorV1 example must support the example receipt version")
    if task["assuranceMode"] not in node["supportedAssuranceModes"]:
        fail("NodeDescriptorV1 example must support the example task assurance mode")
    reference = int(auth["referenceBlockNumber"])
    expiry = int(auth["expiresAtBlock"])
    if not int(node["validFromBlock"]) <= reference < expiry <= int(node["validUntilBlock"]):
        fail("PTAuthEnvelopeV1 example checkpoint and expiry must fit the descriptor validity window")


def validate_bundle(bundle: Bundle) -> dict[str, Any]:
    spec = bundle.spec
    if spec.get("schema") != EXPECTED_SCHEMA:
        fail(f"unexpected protocol schema {spec.get('schema')!r}; expected {EXPECTED_SCHEMA!r}")
    require_string(spec.get("spec_id"), "spec_id")
    require_string(spec.get("version"), "version")
    if spec.get("status") != "target_unimplemented":
        fail("top-level target protocol status must remain target_unimplemented")
    documents = validate_documents(bundle)
    if set(bundle.schemas) != set(NORMATIVE_SCHEMA_FIELDS):
        fail(f"protocol target must define exactly the version-1 schemas {sorted(NORMATIVE_SCHEMA_FIELDS)!r}")
    for record in bundle.schemas.values():
        validate_schema_record(record)
    status_counts = validate_implementation_map(bundle)
    validate_asset_model(spec)
    roles, vectors = validate_economics(spec)
    transitions = validate_lifecycle(spec, vectors, bundle)
    validate_modes_and_consensus(spec, bundle)
    validate_network(spec, bundle)
    validate_hash_domains(spec, bundle)
    validate_settlement_nullifiers(spec)
    validate_governance(spec)
    invariants = validate_invariants(spec)
    validate_examples(bundle)
    unique_strings(spec.get("primary_references"), "primary_references")
    return {
        "documents": documents,
        "status_counts": status_counts,
        "roles": roles,
        "vectors": vectors,
        "transitions": transitions,
        "invariants": invariants,
    }


def build_report(bundle: Bundle, result: dict[str, Any]) -> dict[str, Any]:
    files: dict[str, str] = {bundle.spec_path: sha256_bytes(bundle.spec_bytes)}
    for path in result["documents"]:
        relative = str(path.relative_to(bundle.root))
        files[relative] = sha256_bytes(path.read_bytes())
    for record in bundle.schemas.values():
        files[record.schema_path] = sha256_bytes(record.schema_bytes)
        files[record.example_path] = sha256_bytes(record.example_bytes)
    evidence_paths = {"specs/formal/requirements_traceability.json"}
    for item in bundle.spec["implementation_map"]:
        evidence_paths.update(item["source"])
        evidence_paths.update(item["tests"])
    for relative in sorted(evidence_paths):
        path = safe_path(bundle.root, relative, "report evidence path")
        files[relative] = sha256_bytes(path.read_bytes())
    return {
        "schema": REPORT_SCHEMA,
        "spec_id": bundle.spec["spec_id"],
        "spec_version": bundle.spec["version"],
        "target_status": bundle.spec["status"],
        "source_sha256": sha256_bytes(bundle.spec_bytes),
        "file_sha256": dict(sorted(files.items())),
        "counts": {
            "normative_documents": len(result["documents"]),
            "schemas": len(bundle.schemas),
            "examples": len(bundle.schemas),
            "implementation_items": sum(result["status_counts"].values()),
            "payout_roles": len(result["roles"]),
            "payout_vectors": len(result["vectors"]),
            "lifecycle_states": len(bundle.spec["lifecycle"]["states"]),
            "lifecycle_transitions": len(result["transitions"]),
            "assurance_modes": len(bundle.spec["assurance_modes"]),
            "network_message_types": len(bundle.spec["network"]["message_types"]),
            "invariants": len(result["invariants"]),
        },
        "implementation_status": dict(sorted(result["status_counts"].items())),
        "checks": [
            "json-schema-shape-and-example-subset",
            "canonical-schema-digest-pins",
            "normative-reference-closure",
            "implementation-claim-evidence",
            "implementation-evidence-digests",
            "oracle-free-single-asset-accounting",
            "same-asset-bond-policy",
            "basis-point-conservation",
            "versioned-launch-payout-and-bond-policy",
            "lifecycle-reachability-and-refunds",
            "assurance-mode-and-receipt-binding",
            "quality-consensus-bounds",
            "node-message-enum-closure",
            "typed-hash-domain-completeness",
            "typed-hash-domain-order",
            "governance-nonseizure",
            "proof-obligation-support-refute-recipes",
            "cross-example-consistency",
        ],
        "claim_boundary": "Structural target-design consistency only; not implementation, model-checking, economic, refinement, or purchasing-power evidence.",
    }


def report_bytes(report: dict[str, Any]) -> bytes:
    return (json.dumps(report, indent=2, sort_keys=True, ensure_ascii=True) + "\n").encode()


def clone_bundle(bundle: Bundle) -> Bundle:
    return Bundle(
        root=bundle.root,
        spec_path=bundle.spec_path,
        spec=copy.deepcopy(bundle.spec),
        spec_bytes=bundle.spec_bytes,
        schemas={
            key: SchemaRecord(
                object_id=value.object_id,
                schema_path=value.schema_path,
                example_path=value.example_path,
                canonical_sha256=value.canonical_sha256,
                schema=copy.deepcopy(value.schema),
                example=copy.deepcopy(value.example),
                schema_bytes=value.schema_bytes,
                example_bytes=value.example_bytes,
            )
            for key, value in bundle.schemas.items()
        },
    )


def expect_rejected(bundle: Bundle, name: str, mutation: Callable[[Bundle], None]) -> None:
    candidate = clone_bundle(bundle)
    mutation(candidate)
    try:
        validate_bundle(candidate)
    except SpecError as exc:
        print(f"mutation rejected: {name}: {exc}")
        return
    fail(f"mutation checker was vacuous: {name!r} was accepted")


def run_self_test(bundle: Bundle) -> None:
    baseline_result = validate_bundle(bundle)
    first = report_bytes(build_report(bundle, baseline_result))
    second = report_bytes(build_report(bundle, validate_bundle(bundle)))
    if first != second:
        fail("baseline protocol report is not deterministic")

    def mutate_split(candidate: Bundle) -> None:
        candidate.spec["economics"]["payout_vectors"][0]["allocations"][0]["bps"] -= 1

    def mutate_cross_asset(candidate: Bundle) -> None:
        candidate.spec["asset_model"]["cross_asset_netting"] = True

    def mutate_oracle(candidate: Bundle) -> None:
        candidate.spec["asset_model"]["base_kernel_price_oracle"] = True

    def mutate_bond_asset(candidate: Bundle) -> None:
        candidate.spec["asset_model"]["same_asset_bond_required"] = False

    def mutate_refund_edge(candidate: Bundle) -> None:
        candidate.spec["lifecycle"]["transitions"] = [
            item for item in candidate.spec["lifecycle"]["transitions"] if item["id"] != "SETTLE_CANCEL"
        ]

    def mutate_seizure(candidate: Bundle) -> None:
        candidate.spec["governance"]["governance_can_seize_liabilities"] = True

    def mutate_domain(candidate: Bundle) -> None:
        domain = next(item for item in candidate.spec["hash_domains"] if item["id"] == "PTAUTH_DOMAIN")
        domain["required_fields"].remove("rawBodyHash")

    def mutate_implementation_claim(candidate: Bundle) -> None:
        target = next(item for item in candidate.spec["implementation_map"] if item["id"] == "TARGET_TASK_MARKET")
        target["status"] = "implemented"

    def mutate_duplicate_id(candidate: Bundle) -> None:
        candidate.spec["invariants"][1]["id"] = candidate.spec["invariants"][0]["id"]

    def mutate_quantum(candidate: Bundle) -> None:
        candidate.schemas["TaskSpecV1"].example["fundedAmount"] = "1000001"

    def mutate_sponsor_refund(candidate: Bundle) -> None:
        candidate.spec["economics"]["refund_recipient_source"] = "TASK.requester"

    def mutate_receipt_signature_optional(candidate: Bundle) -> None:
        candidate.schemas["WorkReceiptV1"].schema["required"].remove("providerSignature")

    def mutate_nested_asset_optional(candidate: Bundle) -> None:
        candidate.schemas["TaskSpecV1"].schema["properties"]["paymentAsset"]["required"].remove("assetId")

    def mutate_receipt_domain(candidate: Bundle) -> None:
        domain = next(item for item in candidate.spec["hash_domains"] if item["id"] == "WORK_RECEIPT_DOMAIN")
        domain["required_fields"].remove("tcbManifestHash")

    def mutate_task_domain(candidate: Bundle) -> None:
        domain = next(item for item in candidate.spec["hash_domains"] if item["id"] == "TASK_SPEC_DOMAIN")
        domain["required_fields"].remove("fundedAmount")

    def mutate_target_partial(candidate: Bundle) -> None:
        target = next(item for item in candidate.spec["implementation_map"] if item["id"] == "TARGET_TASK_MARKET")
        target["status"] = "partial"

    def mutate_vector_principal(candidate: Bundle) -> None:
        vector = next(item for item in candidate.spec["economics"]["payout_vectors"] if item["id"] == "VALID_PROVIDER_BOND")
        vector["principal"] = "BOUNTY"

    def mutate_valid_bond_confiscation(candidate: Bundle) -> None:
        vector = next(item for item in candidate.spec["economics"]["payout_vectors"] if item["id"] == "VALID_PROVIDER_BOND")
        vector["allocations"] = [{"role": "SECURITY_RESERVE", "bps": 10000}]

    def mutate_asset_id(candidate: Bundle) -> None:
        candidate.schemas["TaskSpecV1"].example["paymentAsset"]["assetId"] = "0x" + "00" * 32

    def mutate_uint_overflow(candidate: Bundle) -> None:
        candidate.schemas["WorkReceiptV1"].example["providerNonce"] = str(1 << 256)

    def mutate_submitted_timeout(candidate: Bundle) -> None:
        candidate.spec["lifecycle"]["transitions"] = [
            item for item in candidate.spec["lifecycle"]["transitions"] if item["id"] != "TIMEOUT_SUBMITTED"
        ]

    def mutate_challenge_timeout(candidate: Bundle) -> None:
        candidate.spec["lifecycle"]["transitions"] = [
            item
            for item in candidate.spec["lifecycle"]["transitions"]
            if item["id"] != "TIMEOUT_CHALLENGE_RESOLUTION"
        ]

    def mutate_bond_disposition(candidate: Bundle) -> None:
        transition = next(
            item for item in candidate.spec["lifecycle"]["transitions"] if item["id"] == "SETTLE_REJECT"
        )
        provider = next(
            item for item in transition["principal_dispositions"] if item["principal"] == "PROVIDER_BOND"
        )
        provider["allowed_vectors"] = ["PROVABLE_PROVIDER_FAULT_BOND"]

    def mutate_decision_binding(candidate: Bundle) -> None:
        candidate.schemas["DecisionRecordV1"].example["taskSpecHash"] = "0x" + "ff" * 32

    def mutate_signature_nullifier(candidate: Bundle) -> None:
        candidate.spec["settlement_nullifiers"][0]["includes_signature_bytes"] = True

    def mutate_schema_const(candidate: Bundle) -> None:
        candidate.schemas["TaskSpecV1"].schema["properties"]["taskVersion"] = {"type": "string"}

    def mutate_hash_pattern(candidate: Bundle) -> None:
        candidate.schemas["DecisionRecordV1"].schema["$defs"]["hash32"]["pattern"] = "^0x[0-9a-fA-F]+$"

    def mutate_decision_enum(candidate: Bundle) -> None:
        candidate.schemas["DecisionRecordV1"].schema["properties"]["providerBondVectorId"]["enum"].remove("NONE")

    def mutate_assurance_enum(candidate: Bundle) -> None:
        candidate.schemas["DecisionRecordV1"].schema["properties"]["assuranceMode"]["enum"] = ["STATISTICAL"]

    def mutate_domain_order(candidate: Bundle) -> None:
        domain = next(item for item in candidate.spec["hash_domains"] if item["id"] == "WORK_RECEIPT_DOMAIN")
        domain["required_fields"][0], domain["required_fields"][1] = (
            domain["required_fields"][1],
            domain["required_fields"][0],
        )

    def mutate_coordinated_split(candidate: Bundle) -> None:
        provider = next(item for item in candidate.spec["economics"]["payout_roles"] if item["id"] == "PROVIDER")
        ecosystem = next(item for item in candidate.spec["economics"]["payout_roles"] if item["id"] == "ECOSYSTEM")
        provider["default_bps"] -= 100
        ecosystem["default_bps"] += 100
        accepted = next(
            item for item in candidate.spec["economics"]["payout_vectors"] if item["id"] == "ACCEPTED_BOUNTY"
        )
        next(item for item in accepted["allocations"] if item["role"] == "PROVIDER")["bps"] -= 100
        next(item for item in accepted["allocations"] if item["role"] == "ECOSYSTEM")["bps"] += 100

    def mutate_bond_bounds(candidate: Bundle) -> None:
        candidate.spec["economics"]["bond_policy"]["provider_min_bps"] = 0

    mutations: list[tuple[str, Callable[[Bundle], None]]] = [
        ("accepted split totals 9999", mutate_split),
        ("cross-asset netting enabled", mutate_cross_asset),
        ("price oracle enabled", mutate_oracle),
        ("same-asset bond disabled", mutate_bond_asset),
        ("refund settlement edge removed", mutate_refund_edge),
        ("governance liability seizure enabled", mutate_seizure),
        ("signed raw-body binding removed", mutate_domain),
        ("unimplemented module relabeled implemented", mutate_implementation_claim),
        ("duplicate invariant id", mutate_duplicate_id),
        ("funding quantum violated", mutate_quantum),
        ("sponsor refund redirected to requester", mutate_sponsor_refund),
        ("receipt signature made optional", mutate_receipt_signature_optional),
        ("nested asset identity made optional", mutate_nested_asset_optional),
        ("receipt TCB binding removed", mutate_receipt_domain),
        ("task funded-amount binding removed", mutate_task_domain),
        ("unimplemented target relabeled partial", mutate_target_partial),
        ("payout vector principal changed", mutate_vector_principal),
        ("valid provider bond confiscated", mutate_valid_bond_confiscation),
        ("task assetId mismatched", mutate_asset_id),
        ("uint256 overflow accepted", mutate_uint_overflow),
        ("submitted timeout removed", mutate_submitted_timeout),
        ("challenge-resolution timeout removed", mutate_challenge_timeout),
        ("provider bond fault bypassed", mutate_bond_disposition),
        ("decision task binding changed", mutate_decision_binding),
        ("signature bytes included in nullifier", mutate_signature_nullifier),
        ("task version constraint relaxed", mutate_schema_const),
        ("decision hash pattern relaxed", mutate_hash_pattern),
        ("decision NONE bond state removed", mutate_decision_enum),
        ("decision assurance modes narrowed", mutate_assurance_enum),
        ("typed receipt fields reordered", mutate_domain_order),
        ("accepted split drifted in lockstep", mutate_coordinated_split),
        ("provider bond minimum zeroed", mutate_bond_bounds),
    ]
    for name, mutation in mutations:
        expect_rejected(bundle, name, mutation)
    print(f"Protocol-spec checker self-test passed ({len(mutations)} invalid mutations rejected)")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=None, help="Repository root (defaults to the parent of scripts/)")
    parser.add_argument("--spec", default="specs/protocol/pulsetensor_target_v1.json")
    parser.add_argument("--report", default="runs/formal/pulsetensor_target_v1.report.json")
    parser.add_argument("--no-report", action="store_true", help="Validate without writing a report")
    parser.add_argument("--self-test", action="store_true", help="Run deterministic invalid-mutation tests")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = pathlib.Path(args.root).resolve() if args.root else pathlib.Path(__file__).resolve().parents[1]
    try:
        bundle = load_bundle(root, args.spec)
        if args.self_test:
            run_self_test(bundle)
            return 0
        result = validate_bundle(bundle)
        report = build_report(bundle, result)
        if not args.no_report:
            report_path = (root / args.report).resolve()
            try:
                report_path.relative_to(root)
            except ValueError:
                fail("report path escapes repository root")
            report_path.parent.mkdir(parents=True, exist_ok=True)
            report_path.write_bytes(report_bytes(report))
            print(f"Protocol target specification passed: {report_path.relative_to(root)}")
        else:
            print("Protocol target specification passed")
        print(report["claim_boundary"])
        return 0
    except SpecError as exc:
        print(f"Protocol target specification failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

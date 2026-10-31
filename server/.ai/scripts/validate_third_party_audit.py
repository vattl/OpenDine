#!/usr/bin/env python3
"""Validate an independent third-party Agent audit before Work Item acceptance."""

from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
from pathlib import Path
import re
import sys


PACKET_NAME = "AUDIT_PACKET.md"
RECEIPT_NAME = "AUDIT_RECEIPT.md"
REPORT_NAME = "THIRD_PARTY_AUDIT.md"
READINESS_NAME = "AGENT_PROVIDER_READINESS.md"
REQUIRED_AXES = {
    "REQUIREMENT",
    "CORRECTNESS",
    "ARCHITECTURE",
    "SECURITY",
    "TEST_EVIDENCE",
    "FALSE_COMPLETION",
    "ACCEPTANCE",
}
PLACEHOLDERS = {
    "", "-", "TBD", "UNKNOWN", "PENDING", "PATH", "N/A",
    "AGENT-ID", "AUDITOR-ID", "IMPLEMENTER-ID", "SESSION-ID",
    "PROVIDER / MODEL", "PROVIDER/MODEL", "ISO-8601 TIMESTAMP",
    "64-CHARACTER-SHA256", "IMMUTABLE SNAPSHOT IDENTIFIER",
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def field(text: str, name: str) -> str:
    match = re.search(
        rf"(?mi)^\s*(?:[-*]\s*)?{re.escape(name)}\s*:\s*(.*?)\s*$", text
    )
    return match.group(1).strip() if match else ""


def placeholder(value: str) -> bool:
    return value.strip().strip("`").upper() in PLACEHOLDERS


def require_value(
    errors: list[str], text: str, name: str, expected: str, artifact: str
) -> None:
    actual = field(text, name)
    if actual.upper() != expected:
        errors.append(
            f"{artifact}: {name} must be {expected}, got {actual or '<missing>'}"
        )


def require_present(
    errors: list[str], text: str, name: str, artifact: str
) -> str:
    actual = field(text, name)
    if placeholder(actual):
        errors.append(f"{artifact}: {name} must be resolved")
    return actual


def require_identity(errors: list[str], value: str, label: str) -> None:
    if placeholder(value) or not re.fullmatch(r"[A-Za-z0-9_./:@+-]{3,}", value):
        errors.append(f"{label} must be a concrete identity")


def require_provider_model(errors: list[str], value: str, label: str) -> None:
    if placeholder(value) or "/" not in value:
        errors.append(f"{label} must identify a concrete provider and model")
        return
    provider, model = (part.strip() for part in value.split("/", 1))
    if placeholder(provider) or placeholder(model) or not provider or not model:
        errors.append(f"{label} must identify a concrete provider and model")


def integer_field(
    errors: list[str], text: str, name: str, artifact: str
) -> int | None:
    actual = field(text, name)
    try:
        return int(actual)
    except ValueError:
        errors.append(
            f"{artifact}: {name} must be an integer, got {actual or '<missing>'}"
        )
        return None


def require_zero(errors: list[str], text: str, name: str, artifact: str) -> None:
    value = integer_field(errors, text, name, artifact)
    if value is not None and value != 0:
        errors.append(f"{artifact}: {name} must be 0, got {value}")


def table_after_heading(
    text: str, heading: str, artifact: str, errors: list[str]
) -> list[dict[str, str]]:
    lines = text.splitlines()
    heading_index = next(
        (
            index
            for index, line in enumerate(lines)
            if re.fullmatch(rf"\s*#+\s+{re.escape(heading)}\s*", line, re.I)
        ),
        None,
    )
    if heading_index is None:
        errors.append(f"{artifact}: missing section {heading}")
        return []
    header_index: int | None = None
    for index in range(heading_index + 1, len(lines)):
        stripped = lines[index].strip()
        if stripped.startswith("#"):
            break
        if stripped.startswith("|"):
            header_index = index
            break
    if header_index is None:
        errors.append(f"{artifact}: {heading} table is missing")
        return []

    headers = [cell.strip() for cell in lines[header_index].strip().strip("|").split("|")]
    rows: list[dict[str, str]] = []
    for line in lines[header_index + 1 :]:
        stripped = line.strip()
        if stripped.startswith("#") or (rows and not stripped):
            break
        if not (stripped.startswith("|") and stripped.endswith("|")):
            continue
        if set(stripped) <= {"|", "-", ":", " "}:
            continue
        cells = [cell.strip() for cell in stripped.strip("|").split("|")]
        if len(cells) != len(headers):
            errors.append(
                f"{artifact}: {heading} row has {len(cells)} cells; expected {len(headers)}"
            )
            continue
        rows.append(dict(zip(headers, cells)))
    if not rows:
        errors.append(f"{artifact}: {heading} table has no data rows")
    return rows


def require_columns(
    errors: list[str], rows: list[dict[str, str]], columns: tuple[str, ...], label: str
) -> bool:
    if not rows:
        return False
    missing = [column for column in columns if column not in rows[0]]
    if missing:
        errors.append(f"{label}: missing columns: {', '.join(missing)}")
        return False
    return True


def resolve_inside(
    root: Path,
    base: Path,
    value: str,
    label: str,
    errors: list[str],
) -> Path | None:
    if placeholder(value):
        errors.append(f"{label}: path is missing or unresolved")
        return None
    candidate = Path(value)
    if not candidate.is_absolute():
        candidate = base / candidate
    resolved = candidate.resolve()
    try:
        resolved.relative_to(root.resolve())
    except ValueError:
        errors.append(f"{label}: path escapes repository root: {value}")
        return None
    if not resolved.is_file() or resolved.stat().st_size == 0:
        errors.append(f"{label}: file is missing or empty: {value}")
        return None
    return resolved


def verify_hash(
    path: Path | None, expected: str, label: str, errors: list[str]
) -> None:
    if path is None:
        return
    if not re.fullmatch(r"[0-9a-fA-F]{64}", expected):
        errors.append(f"{label}: SHA256 must be 64 hexadecimal characters")
        return
    if sha256(path) != expected.lower():
        errors.append(f"{label}: SHA256 mismatch")


def acceptance_criteria(work_item_text: str) -> list[tuple[str, str]]:
    match = re.search(
        r"(?ms)^###\s+Acceptance criteria\s*$\n(.*?)(?=^#{2,3}\s+|\Z)",
        work_item_text,
    )
    if not match:
        return []
    rows = re.findall(r"(?m)^\s*-\s*\[[ xX]\]\s+(.+?)\s*$", match.group(1))
    return [(f"AC-{index:02d}", value.strip()) for index, value in enumerate(rows, 1)]


def acceptance_contract_sha(criteria: list[tuple[str, str]]) -> str:
    canonical = "\n".join(f"{criterion_id}|{requirement}" for criterion_id, requirement in criteria)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def validate_evidence_references(
    errors: list[str],
    value: str,
    evidence_ids: set[str],
    evidence_paths: set[str],
    label: str,
) -> None:
    references = [item.strip() for item in value.split(",") if item.strip()]
    normalized_paths = {
        path.replace("\\", "/").casefold() for path in evidence_paths
    }
    if not references:
        errors.append(f"{label} must reference inventoried evidence")
        return
    for reference in references:
        if (
            reference.upper() not in evidence_ids
            and reference.replace("\\", "/").casefold() not in normalized_paths
        ):
            errors.append(f"{label} has unknown evidence reference {reference}")


def section_body(text: str, heading: str) -> str:
    match = re.search(
        rf"(?ms)^#+\s+{re.escape(heading)}\s*$\n(.*?)(?=^#+\s+|\Z)", text
    )
    return match.group(1).strip() if match else ""


def parse_iso_timestamp(
    value: str, label: str, errors: list[str], artifact: str = RECEIPT_NAME
) -> datetime | None:
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        errors.append(f"{artifact}: {label} must be an ISO-8601 timestamp")
        return None


def validate(root: Path, work_item: Path) -> list[str]:
    errors: list[str] = []
    resolved_root = root.resolve()
    resolved_work = work_item.resolve()
    try:
        resolved_work.relative_to(resolved_root)
    except ValueError:
        return [f"Work Item directory escapes repository root: {resolved_work}"]
    if not resolved_work.is_dir():
        return [f"Work Item directory missing: {resolved_work}"]

    packet_path = resolved_work / PACKET_NAME
    report_path = resolved_work / REPORT_NAME
    if not packet_path.is_file():
        errors.append(f"required third-party audit artifact missing: {PACKET_NAME}")
    receipt_path_expected = resolved_work / RECEIPT_NAME
    if not receipt_path_expected.is_file():
        errors.append(f"required third-party audit artifact missing: {RECEIPT_NAME}")
    if not report_path.is_file():
        errors.append(f"required third-party audit artifact missing: {REPORT_NAME}")
    if errors:
        return errors

    work_item_path = resolved_work / "WORK_ITEM.md"
    if not work_item_path.is_file():
        return ["required Work Item evidence missing: WORK_ITEM.md"]
    work_text = work_item_path.read_text(encoding="utf-8", errors="replace")
    criteria = acceptance_criteria(work_text)
    criterion_count = len(criteria)
    if criterion_count == 0:
        errors.append("WORK_ITEM.md: no acceptance criteria found")

    packet = packet_path.read_text(encoding="utf-8", errors="replace")
    require_value(errors, packet, "Packet Status", "SEALED", PACKET_NAME)
    packet_work = require_present(errors, packet, "Work Item", PACKET_NAME)
    packet_implementer = require_present(
        errors, packet, "Implementer Agent", PACKET_NAME
    )
    require_identity(errors, packet_implementer, f"{PACKET_NAME}: Implementer Agent")
    packet_prepared_value = require_present(errors, packet, "Prepared At", PACKET_NAME)
    packet_prepared = parse_iso_timestamp(
        packet_prepared_value, "Prepared At", errors, PACKET_NAME
    ) if not placeholder(packet_prepared_value) else None
    packet_snapshot = require_present(errors, packet, "Reviewed Snapshot", PACKET_NAME)
    require_zero(errors, packet, "Material Unknowns", PACKET_NAME)
    if packet_work.upper() != resolved_work.name.upper():
        errors.append(
            f"{PACKET_NAME}: Work Item must be {resolved_work.name}, got {packet_work or '<missing>'}"
        )
    declared_criteria = integer_field(
        errors, packet, "Acceptance Criteria", PACKET_NAME
    )
    if declared_criteria is not None and declared_criteria != criterion_count:
        errors.append(
            f"{PACKET_NAME}: Acceptance Criteria is {declared_criteria}; expected {criterion_count} from WORK_ITEM.md"
        )
    declared_contract_hash = field(packet, "Acceptance Contract SHA256")
    expected_contract_hash = acceptance_contract_sha(criteria)
    if declared_contract_hash.lower() != expected_contract_hash:
        errors.append(f"{PACKET_NAME}: Acceptance Contract SHA256 mismatch")

    inventory = table_after_heading(
        packet, "Evidence Inventory", PACKET_NAME, errors
    )
    inventory_columns = ("Evidence ID", "Path", "SHA256", "Purpose")
    evidence_ids: set[str] = set()
    evidence_paths: set[str] = set()
    if require_columns(
        errors, inventory, inventory_columns, f"{PACKET_NAME} evidence inventory"
    ):
        declared_files = integer_field(errors, packet, "Evidence Files", PACKET_NAME)
        if declared_files is not None and declared_files != len(inventory):
            errors.append(
                f"{PACKET_NAME}: Evidence Files is {declared_files}; found {len(inventory)} rows"
            )
        for row in inventory:
            evidence_id = row["Evidence ID"].upper()
            value = row["Path"]
            if placeholder(evidence_id):
                errors.append(f"{PACKET_NAME}: Evidence ID must be resolved")
            elif evidence_id in evidence_ids:
                errors.append(f"{PACKET_NAME}: duplicate Evidence ID {evidence_id}")
            evidence_ids.add(evidence_id)
            if value.lower() in evidence_paths:
                errors.append(f"{PACKET_NAME}: duplicate evidence path {value}")
            evidence_paths.add(value)
            if Path(value).name.upper() in {PACKET_NAME, REPORT_NAME}:
                errors.append(f"{PACKET_NAME}: circular audit artifact in inventory: {value}")
            evidence_path = resolve_inside(
                resolved_root,
                resolved_work,
                value,
                f"{PACKET_NAME} evidence {evidence_id}",
                errors,
            )
            verify_hash(
                evidence_path,
                row["SHA256"],
                f"{PACKET_NAME} evidence {value}",
                errors,
            )
            if placeholder(row["Purpose"]):
                errors.append(f"{PACKET_NAME}: {evidence_id} Purpose must be resolved")

    acceptance_contract = table_after_heading(
        packet, "Acceptance Contract", PACKET_NAME, errors
    )
    contract_columns = ("Criterion ID", "Requirement", "Claimed Evidence")
    packet_criterion_ids: set[str] = set()
    if require_columns(
        errors, acceptance_contract, contract_columns, f"{PACKET_NAME} acceptance contract"
    ):
        if len(acceptance_contract) != criterion_count:
            errors.append(
                f"{PACKET_NAME}: Acceptance Contract has {len(acceptance_contract)} rows; expected {criterion_count}"
            )
        expected_criteria = dict(criteria)
        for row in acceptance_contract:
            criterion_id = row["Criterion ID"].upper()
            if placeholder(criterion_id):
                errors.append(f"{PACKET_NAME}: Criterion ID must be resolved")
            elif criterion_id in packet_criterion_ids:
                errors.append(f"{PACKET_NAME}: duplicate Criterion ID {criterion_id}")
            packet_criterion_ids.add(criterion_id)
            if placeholder(row["Requirement"]):
                errors.append(f"{PACKET_NAME}: {criterion_id} Requirement must be resolved")
            elif criterion_id in expected_criteria and row["Requirement"] != expected_criteria[criterion_id]:
                errors.append(
                    f"{PACKET_NAME}: {criterion_id} Requirement must exactly match WORK_ITEM.md"
                )
            if placeholder(row["Claimed Evidence"]):
                errors.append(f"{PACKET_NAME}: {criterion_id} Claimed Evidence must be resolved")
            else:
                validate_evidence_references(
                    errors, row["Claimed Evidence"], evidence_ids, evidence_paths,
                    f"{PACKET_NAME}: {criterion_id} Claimed Evidence",
                )
        expected_ids = set(expected_criteria)
        if packet_criterion_ids != expected_ids:
            missing = expected_ids - packet_criterion_ids
            extra = packet_criterion_ids - expected_ids
            if missing:
                errors.append(f"{PACKET_NAME}: missing canonical Criterion IDs: {', '.join(sorted(missing))}")
            if extra:
                errors.append(f"{PACKET_NAME}: unknown Criterion IDs: {', '.join(sorted(extra))}")

    report = report_path.read_text(encoding="utf-8", errors="replace")
    require_value(errors, report, "Audit Decision", "APPROVED", REPORT_NAME)
    require_value(
        errors, report, "Independence Status", "VERIFIED", REPORT_NAME
    )
    require_value(errors, report, "Fresh Context", "YES", REPORT_NAME)
    require_value(errors, report, "Read-Only Audit", "YES", REPORT_NAME)
    report_implementer = require_present(
        errors, report, "Implementer Agent", REPORT_NAME
    )
    auditor = require_present(errors, report, "Auditor Agent", REPORT_NAME)
    require_identity(errors, report_implementer, f"{REPORT_NAME}: Implementer Agent")
    require_identity(errors, auditor, f"{REPORT_NAME}: Auditor Agent")
    report_provider = require_present(errors, report, "Auditor Provider / Model", REPORT_NAME)
    require_provider_model(
        errors, report_provider, f"{REPORT_NAME}: Auditor Provider / Model"
    )
    audit_mode = require_present(errors, report, "Audit Mode", REPORT_NAME).upper()
    if audit_mode not in {"INDEPENDENT_AGENT", "CROSS_MODEL", "EXTERNAL_PROVIDER"}:
        errors.append(
            f"{REPORT_NAME}: Audit Mode must be INDEPENDENT_AGENT, CROSS_MODEL or EXTERNAL_PROVIDER"
        )
    session_id = require_present(errors, report, "Audit Session ID", REPORT_NAME)
    require_identity(errors, session_id, f"{REPORT_NAME}: Audit Session ID")
    if packet_implementer and report_implementer != packet_implementer:
        errors.append(f"{REPORT_NAME}: Implementer Agent must match {PACKET_NAME}")
    if auditor and report_implementer and auditor.casefold() == report_implementer.casefold():
        errors.append(f"{REPORT_NAME}: Auditor Agent must differ from Implementer Agent")

    report_work = require_present(errors, report, "Reviewed Work Item", REPORT_NAME)
    report_snapshot = require_present(errors, report, "Reviewed Snapshot", REPORT_NAME)
    if report_work.upper() != packet_work.upper():
        errors.append(f"{REPORT_NAME}: Reviewed Work Item must match {PACKET_NAME}")
    if report_snapshot != packet_snapshot:
        errors.append(f"{REPORT_NAME}: Reviewed Snapshot must match {PACKET_NAME}")

    packet_reference = require_present(errors, report, "Audit Packet", REPORT_NAME)
    referenced_packet = resolve_inside(
        resolved_root,
        resolved_work,
        packet_reference,
        f"{REPORT_NAME} Audit Packet",
        errors,
    )
    if referenced_packet is not None and referenced_packet != packet_path:
        errors.append(f"{REPORT_NAME}: Audit Packet must reference {PACKET_NAME}")
    packet_hash = field(report, "Audit Packet SHA256")
    before_packet_errors = len(errors)
    verify_hash(packet_path, packet_hash, f"{REPORT_NAME} Audit Packet", errors)
    if len(errors) > before_packet_errors and any(
        "Audit Packet: SHA256 mismatch" in error for error in errors[before_packet_errors:]
    ):
        errors[-1] = f"{REPORT_NAME}: Audit Packet SHA256 mismatch"

    receipt_reference = require_present(errors, report, "Audit Receipt", REPORT_NAME)
    receipt_path = resolve_inside(
        resolved_root,
        resolved_work,
        receipt_reference,
        f"{REPORT_NAME} Audit Receipt",
        errors,
    )
    if receipt_path is not None and receipt_path != receipt_path_expected:
        errors.append(f"{REPORT_NAME}: Audit Receipt must reference {RECEIPT_NAME}")
    verify_hash(
        receipt_path,
        field(report, "Audit Receipt SHA256"),
        f"{REPORT_NAME} Audit Receipt",
        errors,
    )
    if receipt_path is not None:
        receipt = receipt_path.read_text(encoding="utf-8", errors="replace")
        if field(receipt, "Audit Session ID") != session_id:
            errors.append("AUDIT_RECEIPT.md: Audit Session ID must match report")
        if field(receipt, "Auditor Agent").casefold() != auditor.casefold():
            errors.append("AUDIT_RECEIPT.md: Auditor Agent must match report")
        receipt_provider = require_present(
            errors, receipt, "Auditor Provider / Model", RECEIPT_NAME
        )
        require_identity(
            errors, field(receipt, "Auditor Agent"),
            f"{RECEIPT_NAME}: Auditor Agent",
        )
        require_identity(
            errors, field(receipt, "Audit Session ID"),
            f"{RECEIPT_NAME}: Audit Session ID",
        )
        require_provider_model(
            errors, receipt_provider, f"{RECEIPT_NAME}: Auditor Provider / Model"
        )
        if receipt_provider != report_provider:
            errors.append("AUDIT_RECEIPT.md: Auditor Provider / Model must match report")
        started_value = require_present(errors, receipt, "Started At", RECEIPT_NAME)
        completed_value = require_present(errors, receipt, "Completed At", RECEIPT_NAME)
        started = parse_iso_timestamp(started_value, "Started At", errors) if not placeholder(started_value) else None
        completed = parse_iso_timestamp(completed_value, "Completed At", errors) if not placeholder(completed_value) else None
        if started is not None and completed is not None:
            try:
                if completed < started:
                    errors.append("AUDIT_RECEIPT.md: Completed At must not precede Started At")
            except TypeError:
                errors.append("AUDIT_RECEIPT.md: Started At and Completed At must use compatible timezones")
        if packet_prepared is not None and started is not None:
            try:
                if packet_prepared > started:
                    errors.append("AUDIT_PACKET.md: Prepared At must not follow audit Started At")
            except TypeError:
                errors.append("AUDIT_PACKET.md: Prepared At and audit Started At must use compatible timezones")
        require_value(errors, receipt, "Context Mode", "FRESH", "AUDIT_RECEIPT.md")
        if field(receipt, "Mutation Permission").upper() not in {
            "NONE",
            "AUDIT_ARTIFACTS_ONLY",
        }:
            errors.append(
                "AUDIT_RECEIPT.md: Mutation Permission must be NONE or AUDIT_ARTIFACTS_ONLY"
            )
        if field(receipt, "Reviewed Packet") != PACKET_NAME:
            errors.append(f"AUDIT_RECEIPT.md: Reviewed Packet must be {PACKET_NAME}")
        invocation = section_body(receipt, "Invocation Record")
        invocation_lower = invocation.casefold()
        template_boilerplate = "record how the independent agent was started and the exact scope it was given"
        if placeholder(invocation):
            errors.append("AUDIT_RECEIPT.md: Invocation Record must be present and resolved")
        elif (
            template_boilerplate in invocation_lower
            or auditor.casefold() not in invocation_lower
            or not re.search(r"\b(started|spawned|dispatched|launched)\b", invocation_lower)
            or "scope" not in invocation_lower
        ):
            errors.append(
                "AUDIT_RECEIPT.md: Invocation Record must describe the actual dispatch, auditor and assigned scope"
            )

        if audit_mode == "EXTERNAL_PROVIDER":
            report_readiness_ref = require_present(
                errors, report, "Provider Readiness", REPORT_NAME
            )
            receipt_readiness_ref = require_present(
                errors, receipt, "Provider Readiness", RECEIPT_NAME
            )
            report_readiness_hash = require_present(
                errors, report, "Provider Readiness SHA256", REPORT_NAME
            )
            receipt_readiness_hash = require_present(
                errors, receipt, "Provider Readiness SHA256", RECEIPT_NAME
            )
            readiness_path = resolve_inside(
                resolved_root,
                resolved_work,
                report_readiness_ref,
                f"{REPORT_NAME} Provider Readiness ({READINESS_NAME})",
                errors,
            )
            if readiness_path is not None and readiness_path != resolved_work / READINESS_NAME:
                errors.append(
                    f"{REPORT_NAME}: Provider Readiness must reference {READINESS_NAME}"
                )
            if receipt_readiness_ref != report_readiness_ref:
                errors.append(
                    f"{RECEIPT_NAME}: Provider Readiness must match report"
                )
            if receipt_readiness_hash != report_readiness_hash:
                errors.append(
                    f"{RECEIPT_NAME}: Provider Readiness SHA256 must match report"
                )
            verify_hash(
                readiness_path,
                report_readiness_hash,
                f"{REPORT_NAME} Provider Readiness",
                errors,
            )
            if readiness_path is not None:
                readiness = readiness_path.read_text(
                    encoding="utf-8", errors="replace"
                )
                provider = require_present(
                    errors, readiness, "Provider", READINESS_NAME
                )
                if provider.casefold() == "builtin":
                    errors.append(
                        f"{READINESS_NAME}: Provider must identify an external provider"
                    )
                require_value(
                    errors,
                    readiness,
                    "Provider Mode",
                    "EXTERNAL_CLI",
                    READINESS_NAME,
                )
                require_value(
                    errors, readiness, "Provider State", "READY", READINESS_NAME
                )
                require_value(errors, readiness, "Ready", "YES", READINESS_NAME)
                require_value(
                    errors, readiness, "Live Probe", "PASS", READINESS_NAME
                )
                require_value(
                    errors,
                    readiness,
                    "Secret Values Recorded",
                    "NO",
                    READINESS_NAME,
                )

    for name in ("Critical Open", "High Open"):
        require_zero(errors, report, name, REPORT_NAME)
    require_value(
        errors, report, "Required Findings Resolved", "YES", REPORT_NAME
    )
    require_value(
        errors, report, "Acceptance Coverage", "COMPLETE", REPORT_NAME
    )
    require_value(errors, report, "Evidence Integrity", "VERIFIED", REPORT_NAME)

    coverage = table_after_heading(report, "Review Coverage", REPORT_NAME, errors)
    coverage_columns = ("Axis", "Scope", "Evidence", "Verdict")
    seen_axes: set[str] = set()
    if require_columns(
        errors, coverage, coverage_columns, f"{REPORT_NAME} review coverage"
    ):
        for row in coverage:
            axis = row["Axis"].upper()
            if axis in seen_axes:
                errors.append(f"{REPORT_NAME}: duplicate review axis {axis}")
            seen_axes.add(axis)
            if axis in REQUIRED_AXES and row["Verdict"].upper() != "PASS":
                errors.append(f"{REPORT_NAME}: review axis {axis} must be PASS")
            for column in ("Scope", "Evidence"):
                if placeholder(row[column]):
                    errors.append(f"{REPORT_NAME}: {axis} {column} must be resolved")
            if not placeholder(row["Evidence"]):
                validate_evidence_references(
                    errors, row["Evidence"], evidence_ids, evidence_paths,
                    f"{REPORT_NAME}: {axis} Evidence",
                )
    missing_axes = REQUIRED_AXES - seen_axes
    if missing_axes:
        errors.append(
            f"{REPORT_NAME}: missing required review axes: {', '.join(sorted(missing_axes))}"
        )

    criterion_audit = table_after_heading(
        report, "Acceptance Criterion Audit", REPORT_NAME, errors
    )
    audit_columns = ("Criterion ID", "Evidence Reviewed", "Auditor Verdict", "Notes")
    audited_ids: set[str] = set()
    if require_columns(
        errors, criterion_audit, audit_columns, f"{REPORT_NAME} acceptance audit"
    ):
        reviewed_count = integer_field(
            errors, report, "Acceptance Criteria Reviewed", REPORT_NAME
        )
        if reviewed_count is not None and reviewed_count != criterion_count:
            errors.append(
                f"{REPORT_NAME}: Acceptance Criteria Reviewed is {reviewed_count}; expected {criterion_count}"
            )
        if len(criterion_audit) != criterion_count:
            errors.append(
                f"{REPORT_NAME}: Acceptance Criterion Audit has {len(criterion_audit)} rows; expected {criterion_count}"
            )
        for row in criterion_audit:
            criterion_id = row["Criterion ID"].upper()
            if criterion_id in audited_ids:
                errors.append(f"{REPORT_NAME}: duplicate audited criterion {criterion_id}")
            audited_ids.add(criterion_id)
            if row["Auditor Verdict"].upper() != "PASS":
                errors.append(f"{REPORT_NAME}: criterion {criterion_id} must be PASS")
            if placeholder(row["Evidence Reviewed"]):
                errors.append(f"{REPORT_NAME}: {criterion_id} Evidence Reviewed must be resolved")
            else:
                validate_evidence_references(
                    errors, row["Evidence Reviewed"], evidence_ids, evidence_paths,
                    f"{REPORT_NAME}: {criterion_id} Evidence Reviewed",
                )
            if placeholder(row["Notes"]):
                errors.append(f"{REPORT_NAME}: {criterion_id} Notes must be resolved")
    if audited_ids != packet_criterion_ids:
        missing = packet_criterion_ids - audited_ids
        extra = audited_ids - packet_criterion_ids
        if missing:
            errors.append(
                f"{REPORT_NAME}: Acceptance Criterion Audit missing IDs: {', '.join(sorted(missing))}"
            )
        if extra:
            errors.append(
                f"{REPORT_NAME}: Acceptance Criterion Audit has unknown IDs: {', '.join(sorted(extra))}"
            )

    findings = table_after_heading(report, "Findings", REPORT_NAME, errors)
    finding_columns = (
        "Finding ID",
        "Severity",
        "Finding",
        "Required Action",
        "Status",
        "Reverification",
    )
    if require_columns(
        errors, findings, finding_columns, f"{REPORT_NAME} findings"
    ):
        none_rows = [row for row in findings if row["Severity"].upper() == "NONE"]
        if none_rows and (len(findings) != 1 or len(none_rows) != 1):
            errors.append(f"{REPORT_NAME}: Severity NONE is allowed only for a sole AUDIT-NONE row")
        for row in findings:
            severity = row["Severity"].upper()
            if severity not in {"NONE", "CRITICAL", "HIGH", "MEDIUM", "LOW"}:
                errors.append(
                    f"{REPORT_NAME}: invalid finding severity {row['Severity']}"
                )
            if severity == "NONE" and row["Finding ID"].upper() != "AUDIT-NONE":
                errors.append(
                    f"{REPORT_NAME}: Severity NONE is reserved for the sole AUDIT-NONE row"
                )
            if row["Status"].upper() != "CLOSED":
                errors.append(
                    f"{REPORT_NAME}: finding {row['Finding ID']} must be CLOSED"
                )
            if placeholder(row["Reverification"]):
                errors.append(
                    f"{REPORT_NAME}: finding {row['Finding ID']} needs reverification evidence"
                )
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate third-party Agent cross-audit evidence"
    )
    parser.add_argument("--root", default=".")
    parser.add_argument("--work-item", required=True)
    args = parser.parse_args()
    root = Path(args.root).resolve()
    work_item = Path(args.work_item)
    if not work_item.is_absolute():
        work_item = root / work_item
    errors = validate(root, work_item)
    if errors:
        print("THIRD-PARTY AUDIT GATE: BLOCKED")
        for error in errors:
            print(f"- {error}")
        print("Work Acceptance: FORBIDDEN")
        return 6
    print("THIRD-PARTY AUDIT GATE: PASS")
    print("Independent auditor: VERIFIED")
    print("Audit packet integrity: VERIFIED")
    print("Required review axes: PASS")
    print("Acceptance criteria coverage: COMPLETE")
    return 0


if __name__ == "__main__":
    sys.exit(main())

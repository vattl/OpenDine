#!/usr/bin/env python3
"""Validate approved prototype interactions against real production capabilities."""
from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import re
import sys


CONTRACT_NAME = "PROTOTYPE_INTERACTION_CONTRACT.md"
REPORT_NAME = "BACKEND_COORDINATION_REPORT.md"
CLASSIFICATIONS = {"AVAILABLE", "DERIVABLE", "API_EXTENSION", "NEW_API", "NOT_SUPPORTED"}
GAP_CLASSIFICATIONS = {"API_EXTENSION", "NEW_API"}
PLAN_REQUEST_STATUSES = {"PROPOSED", "PLANNED", "IMPLEMENTATION_PLANNED", "IMPLEMENTING", "IMPLEMENTED", "VERIFIED"}
PLACEHOLDERS = {"", "-", "TBD", "UNKNOWN", "PENDING", "PATH", "N/A", "NA", "NONE"}


@dataclass
class Interaction:
    interaction_id: str
    description: str
    classification: str
    production_integration: str
    capability_evidence: str
    capability_request: str
    e2e_evidence: str
    status: str


@dataclass
class CoordinationItem:
    interaction_id: str
    need: str
    classification: str
    request_path: str
    owner: str
    status: str
    next_action: str


def field(text: str, name: str) -> str:
    match = re.search(
        rf"(?mi)^\s*(?:[-*]\s*)?{re.escape(name)}\s*:\s*(.*?)\s*$", text
    )
    return match.group(1).strip() if match else ""


def status(text: str, name: str) -> str:
    return field(text, name).upper()


def is_placeholder(value: str) -> bool:
    return value.strip().strip("`").upper() in PLACEHOLDERS


def parse_interactions(text: str) -> tuple[list[Interaction], list[str]]:
    interactions: list[Interaction] = []
    errors: list[str] = []
    header_seen = False
    for line in text.splitlines():
        stripped = line.strip()
        if not (stripped.startswith("|") and stripped.endswith("|")):
            continue
        cells = [cell.strip().strip("`") for cell in stripped.strip("|").split("|")]
        if cells and cells[0].lower() == "interaction id":
            header_seen = True
            continue
        if not header_seen or set(stripped) <= {"|", "-", ":", " "}:
            continue
        if len(cells) != 8:
            errors.append(f"interaction table row must have 8 columns: {stripped}")
            continue
        interactions.append(Interaction(*cells[:7], status=cells[7].upper()))
    if not header_seen:
        errors.append("interaction table header is missing")
    if not interactions:
        errors.append("interaction table has no populated rows")
    return interactions, errors


def resolve_inside(base: Path, root: Path, value: str) -> Path | None:
    cleaned = value.strip().strip("`")
    candidate = Path(cleaned)
    if not candidate.is_absolute():
        candidate = base / candidate
    resolved = candidate.resolve()
    try:
        resolved.relative_to(root.resolve())
    except ValueError:
        return None
    return resolved


def require_zero(errors: list[str], text: str, name: str) -> None:
    value = field(text, name)
    try:
        parsed = int(value)
    except ValueError:
        errors.append(f"{name} must be integer 0, got {value or '<missing>'}")
        return
    if parsed != 0:
        errors.append(f"{name} must be 0, got {parsed}")


def write_coordination_report(path: Path, items: list[CoordinationItem]) -> None:
    coordination_status = "OPEN" if items else "CLEAR"
    lines = [
        "# Backend Coordination Report",
        "",
        f"Coordination Status: {coordination_status}",
        f"Open Backend Items: {len(items)}",
        "",
        "| Interaction ID | UI / Business Need | Classification | Capability Request | Owner | Status | Required Next Action |",
        "|---|---|---|---|---|---|---|",
    ]
    if items:
        for item in items:
            cells = [
                item.interaction_id, item.need, item.classification,
                item.request_path, item.owner or "UNASSIGNED",
                item.status or "OPEN", item.next_action,
            ]
            lines.append("| " + " | ".join(cell.replace("|", "/") for cell in cells) + " |")
    else:
        lines.append("| NONE | All approved prototype interactions are verified end-to-end | N/A | N/A | N/A | VERIFIED | No backend coordination required |")
    lines.extend([
        "",
        "## Acceptance Rule",
        "",
        "Any OPEN item keeps production UI acceptance BLOCKED/PARTIAL. Do not replace it with frontend mock, static success, empty handler, or placeholder data.",
        "",
    ])
    path.write_text("\n".join(lines), encoding="utf-8")


def validate(root: Path, ui_dir: Path, phase: str) -> list[str]:
    errors: list[str] = []
    coordination: list[CoordinationItem] = []
    root = root.resolve()
    ui_dir = ui_dir.resolve()
    try:
        ui_dir.relative_to(root)
    except ValueError:
        return [f"UI evidence directory escapes repository root: {ui_dir}"]
    if not ui_dir.is_dir():
        return [f"UI evidence directory missing: {ui_dir}"]

    contract_path = ui_dir / CONTRACT_NAME
    if not contract_path.is_file():
        write_coordination_report(
            ui_dir / REPORT_NAME,
            [CoordinationItem("UNKNOWN", "Interaction contract missing", "UNKNOWN", CONTRACT_NAME, "UNASSIGNED", "OPEN", f"Create {CONTRACT_NAME} and map every approved interaction")],
        )
        return [f"required UI capability artifact missing: {CONTRACT_NAME}"]

    text = contract_path.read_text(encoding="utf-8", errors="replace")
    if status(text, "Capability Mapping Status") != "COMPLETE":
        errors.append("Capability Mapping Status must be COMPLETE")
    if status(text, "All Prototype Interactions Mapped") != "YES":
        errors.append("All Prototype Interactions Mapped must be YES")
    require_zero(errors, text, "Unmapped Prototype Interactions")
    require_zero(errors, text, "Production Fake/Mock/Placeholder Interactions")
    if phase == "accept":
        require_zero(errors, text, "Unresolved Required Backend Capabilities")

    interactions, table_errors = parse_interactions(text)
    errors.extend(table_errors)
    seen_ids: set[str] = set()
    actual_unresolved_backend = 0
    for interaction in interactions:
        iid = interaction.interaction_id
        classification = interaction.classification.upper()
        if is_placeholder(iid) or iid in seen_ids:
            errors.append(f"interaction ID must be unique and resolved: {iid or '<missing>'}")
        seen_ids.add(iid)
        if is_placeholder(interaction.description):
            errors.append(f"{iid}: Prototype Interaction must be resolved")
        if classification not in CLASSIFICATIONS:
            errors.append(f"{iid}: invalid classification {interaction.classification or '<missing>'}")
            continue
        if classification == "NOT_SUPPORTED":
            actual_unresolved_backend += 1
            errors.append(
                f"{iid}: NOT_SUPPORTED interaction remains in the approved prototype; revise and re-approve the prototype before production implementation"
            )
            coordination.append(CoordinationItem(
                iid, interaction.description, classification, "N/A", "PRODUCT/UI",
                "BLOCKED", "Remove/redesign the interaction and obtain new prototype approval, or approve backend capability work",
            ))
            continue
        if is_placeholder(interaction.production_integration):
            errors.append(f"{iid}: Production Integration must identify the real production destination")

        if classification in {"AVAILABLE", "DERIVABLE"}:
            if is_placeholder(interaction.capability_evidence):
                errors.append(f"{iid}: Contract / Capability Evidence is required for {classification}")
            else:
                capability_path = resolve_inside(ui_dir, root, interaction.capability_evidence)
                if capability_path is None or not capability_path.is_file() or capability_path.stat().st_size == 0:
                    errors.append(f"{iid}: Contract / Capability Evidence is missing, empty, or outside repository root: {interaction.capability_evidence}")

        request_status = "NOT_APPLICABLE"
        request_owner = ""
        if classification in GAP_CLASSIFICATIONS:
            if is_placeholder(interaction.capability_request):
                actual_unresolved_backend += 1
                errors.append(f"{iid}: {classification} requires a Backend Capability Request")
                coordination.append(CoordinationItem(
                    iid, interaction.description, classification,
                    interaction.capability_request or "MISSING", "UNASSIGNED", "OPEN",
                    "Create and assign a Backend Capability Request with a concrete contract",
                ))
            else:
                request_path = resolve_inside(ui_dir, root, interaction.capability_request)
                if request_path is None or not request_path.is_file():
                    actual_unresolved_backend += 1
                    errors.append(f"{iid}: capability request is missing or outside repository root: {interaction.capability_request}")
                    coordination.append(CoordinationItem(
                        iid, interaction.description, classification,
                        interaction.capability_request, "UNASSIGNED", "OPEN",
                        "Create the referenced Backend Capability Request and assign an owner",
                    ))
                else:
                    request_text = request_path.read_text(encoding="utf-8", errors="replace")
                    request_status = status(request_text, "Status")
                    request_owner = field(request_text, "Owner")
                    if request_status not in PLAN_REQUEST_STATUSES:
                        errors.append(f"{iid}: capability request Status is unresolved: {request_status or '<missing>'}")
                    if not request_owner or is_placeholder(request_owner):
                        errors.append(f"{iid}: capability request Owner is missing")
                    if request_status != "VERIFIED":
                        actual_unresolved_backend += 1
                        coordination.append(CoordinationItem(
                            iid, interaction.description, classification,
                            interaction.capability_request, request_owner, request_status or "OPEN",
                            "Complete backend implementation, contract tests, and consumer verification",
                        ))
                    if phase == "accept" and request_status != "VERIFIED":
                        errors.append(f"{iid}: capability request must be VERIFIED for UI acceptance, got {request_status or '<missing>'}")

        if phase == "accept":
            if interaction.status != "VERIFIED":
                errors.append(f"{iid}: interaction Status must be VERIFIED for UI acceptance, got {interaction.status or '<missing>'}")
                if not any(item.interaction_id == iid for item in coordination):
                    coordination.append(CoordinationItem(
                        iid, interaction.description, classification,
                        interaction.capability_request, request_owner, interaction.status or "OPEN",
                        "Finish frontend/backend integration and mark only after end-to-end verification",
                    ))
            production_path = resolve_inside(root, root, interaction.production_integration)
            if production_path is None or not production_path.is_file():
                errors.append(f"{iid}: production integration file is missing or outside repository root: {interaction.production_integration}")
            if is_placeholder(interaction.e2e_evidence):
                errors.append(f"{iid}: E2E Evidence is required for UI capability acceptance")
            else:
                evidence_path = resolve_inside(ui_dir, root, interaction.e2e_evidence)
                if evidence_path is None or not evidence_path.is_file() or evidence_path.stat().st_size == 0:
                    errors.append(f"{iid}: E2E evidence is missing, empty, or outside repository root: {interaction.e2e_evidence}")

    unresolved_value = field(text, "Unresolved Required Backend Capabilities")
    try:
        declared_unresolved = int(unresolved_value)
    except ValueError:
        errors.append(
            "Unresolved Required Backend Capabilities must be an integer matching the open backend capability count"
        )
    else:
        if declared_unresolved != actual_unresolved_backend:
            errors.append(
                "Unresolved Required Backend Capabilities must match actual open backend capability rows: "
                f"declared {declared_unresolved}, actual {actual_unresolved_backend}"
            )

    write_coordination_report(ui_dir / REPORT_NAME, coordination)
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate prototype interaction capability delivery")
    parser.add_argument("--root", default=".")
    parser.add_argument("--ui-dir", required=True)
    parser.add_argument("--phase", choices=("plan", "accept"), default="accept")
    args = parser.parse_args()
    root = Path(args.root).resolve()
    ui_dir = Path(args.ui_dir)
    if not ui_dir.is_absolute():
        ui_dir = root / ui_dir
    errors = validate(root, ui_dir, args.phase)
    label = "UI CAPABILITY PLAN GATE" if args.phase == "plan" else "UI CAPABILITY ACCEPTANCE GATE"
    if errors:
        print(f"{label}: BLOCKED")
        for error in errors:
            print(f"- {error}")
        print(f"Backend coordination report: {ui_dir / REPORT_NAME}")
        print("Production UI Editing: FORBIDDEN" if args.phase == "plan" else "UI Acceptance: FORBIDDEN")
        return 4
    print(f"{label}: PASS")
    print("All approved prototype interactions mapped: YES")
    if args.phase == "accept":
        print("All production interactions verified end-to-end: YES")
        print("Unresolved backend capabilities: 0")
    print(f"Backend coordination report: {ui_dir / REPORT_NAME}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

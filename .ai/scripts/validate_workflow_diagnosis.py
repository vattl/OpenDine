#!/usr/bin/env python3
"""Validate an evidence-bound, read-only workflow diagnosis report."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import re


REQUIRED_DIMENSIONS = {
    "ROUTING_TIMELINE", "PLAN_ADHERENCE", "REPEATED_WORK", "STUMBLES_BLOCKERS",
    "QUALITY_EVIDENCE", "REQUEST_CONFLICTS", "TIME_COST",
}


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace") if path.is_file() else ""


def field(text: str, name: str) -> str:
    match = re.search(rf"(?mi)^\s*(?:[-*]\s*)?{re.escape(name)}\s*:\s*`?(.*?)`?\s*$", text)
    return match.group(1).strip() if match else ""


def table(text: str, heading: str, errors: list[str]) -> list[dict[str, str]]:
    lines = text.splitlines()
    start = next((i for i, line in enumerate(lines) if re.fullmatch(rf"\s*#+\s+{re.escape(heading)}\s*", line, re.I)), None)
    if start is None:
        errors.append(f"missing section {heading}")
        return []
    header = next((i for i in range(start + 1, len(lines)) if lines[i].strip().startswith("|")), None)
    if header is None:
        errors.append(f"{heading} table is missing")
        return []
    columns = [cell.strip() for cell in lines[header].strip().strip("|").split("|")]
    rows = []
    for line in lines[header + 1:]:
        stripped = line.strip()
        if stripped.startswith("#") or (rows and not stripped):
            break
        if not (stripped.startswith("|") and stripped.endswith("|")) or set(stripped) <= {"|", "-", ":", " "}:
            continue
        cells = [cell.strip().strip("`") for cell in stripped.strip("|").split("|")]
        if len(cells) == len(columns):
            rows.append(dict(zip(columns, cells)))
        else:
            errors.append(f"{heading} contains a malformed row")
    return rows


def resolve(root: Path, value: str, errors: list[str], label: str) -> Path | None:
    candidate = Path(value)
    if not candidate.is_absolute():
        candidate = root / candidate
    path = candidate.resolve()
    try:
        path.relative_to(root.resolve())
    except ValueError:
        errors.append(f"{label} escapes repository root")
        return None
    if not path.is_file():
        errors.append(f"{label} does not exist: {value}")
        return None
    return path


def validate(root: Path, work: Path, require_clear: bool = False) -> list[str]:
    errors: list[str] = []
    path = work / "WORKFLOW_DIAGNOSIS.md"
    text = read(path)
    if not text:
        return ["missing or empty WORKFLOW_DIAGNOSIS.md"]
    if field(text, "Diagnosis Status").upper() != "COMPLETE":
        errors.append("Diagnosis Status must be COMPLETE")
    if field(text, "Diagnosis Decision").upper() not in {"CLEAR", "BLOCKED"}:
        errors.append("Diagnosis Decision must be CLEAR or BLOCKED")
    if field(text, "Input Mutation").upper() != "NONE":
        errors.append("Input Mutation must be NONE")
    if not field(text, "Intake Statement"):
        errors.append("Intake Statement is required")
    if not field(text, "Scope"):
        errors.append("Scope is required")
    inventory = table(text, "Evidence Inventory", errors)
    evidence_ids: set[str] = set()
    evidence_paths: set[Path] = set()
    if not inventory:
        errors.append("Evidence Inventory must contain at least one item")
    for row in inventory:
        evidence_id = row.get("ID", "")
        if not re.fullmatch(r"E-\d{2,}", evidence_id):
            errors.append(f"invalid evidence ID {evidence_id or '<missing>'}")
        if evidence_id in evidence_ids:
            errors.append(f"duplicate evidence ID {evidence_id}")
        evidence_ids.add(evidence_id)
        evidence = resolve(root, row.get("Path", ""), errors, f"evidence {evidence_id}")
        if evidence:
            if evidence in evidence_paths:
                errors.append(f"duplicate evidence path {row.get('Path', '')}")
            evidence_paths.add(evidence)
        expected = row.get("SHA256", "").lower()
        if evidence and (not re.fullmatch(r"[0-9a-f]{64}", expected) or hashlib.sha256(evidence.read_bytes()).hexdigest() != expected):
            errors.append(f"evidence {evidence_id} SHA256 mismatch")
    coverage = table(text, "Dimension Coverage", errors)
    dimensions: set[str] = set()
    for row in coverage:
        dimension = row.get("Dimension", "").upper()
        if dimension in dimensions:
            errors.append(f"duplicate dimension {dimension}")
        dimensions.add(dimension)
    missing = REQUIRED_DIMENSIONS - dimensions
    if missing:
        errors.append("Dimension Coverage missing: " + ", ".join(sorted(missing)))
    unknown = dimensions - REQUIRED_DIMENSIONS
    if unknown:
        errors.append("Dimension Coverage contains unknown dimensions: " + ", ".join(sorted(unknown)))
    coverage_statuses: dict[str, str] = {}
    coverage_refs: list[str] = []
    for row in coverage:
        dimension = row.get("Dimension", "").upper()
        dimension_status = row.get("Status", "").upper()
        coverage_statuses[dimension] = dimension_status
        if dimension_status not in {"REVIEWED", "INSUFFICIENT_EVIDENCE", "BLOCKED"}:
            errors.append(f"dimension {dimension} has invalid status {dimension_status or '<missing>'}")
        expected_check = f"CHECK_{dimension}"
        if row.get("Check", "").upper() != expected_check:
            errors.append(f"dimension {dimension} Check must be {expected_check}")
        refs = [item.strip() for item in row.get("Evidence", "").split(",") if item.strip()]
        coverage_refs.extend(refs)
        if not refs or any(ref not in evidence_ids for ref in refs):
            errors.append(f"dimension {dimension} must reference inventoried evidence")
    if len(coverage_refs) >= len(REQUIRED_DIMENSIONS) and len(set(coverage_refs)) == 1:
        errors.append("Dimension Coverage cannot use a single fallback evidence item for all dimensions")
    findings = table(text, "Findings", errors)
    open_findings = 0
    open_finding_dimensions: set[str] = set()
    finding_ids: set[str] = set()
    for row in findings:
        finding_id = row.get("ID", "<missing>")
        if not re.fullmatch(r"D-\d{2,}", finding_id):
            errors.append(f"invalid finding ID {finding_id}")
        if finding_id in finding_ids:
            errors.append(f"duplicate finding ID {finding_id}")
        finding_ids.add(finding_id)
        finding_dimension = row.get("Dimension", "").upper()
        if finding_dimension not in REQUIRED_DIMENSIONS:
            errors.append(f"finding {finding_id} has invalid dimension {finding_dimension or '<missing>'}")
        severity = row.get("Severity", "").upper()
        if severity not in {"LOW", "MEDIUM", "HIGH", "CRITICAL"}:
            errors.append(f"finding {finding_id} has invalid severity {severity or '<missing>'}")
        evidence_ref = row.get("Evidence", "")
        match = re.fullmatch(r"(.+):(\d+)", evidence_ref)
        if not match:
            errors.append(f"finding {finding_id} evidence must use path:line")
        else:
            evidence = resolve(root, match.group(1), errors, f"finding {finding_id} evidence")
            if evidence:
                if evidence not in evidence_paths:
                    errors.append(f"finding {finding_id} must cite inventoried evidence")
                line_number = int(match.group(2))
                if line_number < 1 or line_number > len(read(evidence).splitlines()):
                    errors.append(f"finding {finding_id} path:line is outside the evidence file")
        for name in ("Observed Fact", "Impact", "Recommendation"):
            if not row.get(name, "").strip():
                errors.append(f"finding {finding_id} {name} is required")
        finding_status = row.get("Status", "").upper()
        if finding_status not in {"OPEN", "CLOSED"}:
            errors.append(f"finding {finding_id} status must be OPEN or CLOSED")
        if finding_status == "OPEN":
            open_findings += 1
            open_finding_dimensions.add(finding_dimension)
        evidence_text = read(resolve(root, match.group(1), [], "numeric evidence") or Path()) if match else ""
        for name in ("Observed Fact", "Impact", "Recommendation"):
            for number in re.findall(r"\b\d+\b", row.get(name, "")):
                if match and number not in evidence_text:
                    errors.append(f"finding {finding_id} has unsupported numeric claim {number}")
    decision = field(text, "Diagnosis Decision").upper()
    if decision == "CLEAR" and open_findings:
        errors.append("Diagnosis Decision CLEAR cannot contain OPEN findings")
    if decision == "CLEAR" and any(value != "REVIEWED" for value in coverage_statuses.values()):
        errors.append("Diagnosis Decision CLEAR requires every dimension REVIEWED")
    if decision == "BLOCKED" and not open_findings:
        errors.append("Diagnosis Decision BLOCKED requires at least one OPEN finding")
    for dimension, status in coverage_statuses.items():
        if dimension in REQUIRED_DIMENSIONS and status != "REVIEWED" and dimension not in open_finding_dimensions:
            errors.append(f"dimension {dimension} requires an OPEN finding when status is {status or '<missing>'}")
    if require_clear and decision != "CLEAR":
        errors.append("Diagnosis Decision must be CLEAR for lifecycle acceptance")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--work-item", type=Path, required=True)
    parser.add_argument("--require-clear", action="store_true")
    args = parser.parse_args()
    errors = validate(args.root.resolve(), args.work_item.resolve(), args.require_clear)
    if errors:
        print("WORKFLOW DIAGNOSIS GATE: BLOCKED")
        for error in errors:
            print(f"- {error}")
        return 1
    print("WORKFLOW DIAGNOSIS GATE: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Validate risk/type-driven audit routing and remediation closure."""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import subprocess
import sys


TYPE_TRACKS = {
    "FEATURE": {"ARCHITECTURE"},
    "CHANGE": {"ARCHITECTURE"},
    "REFACTOR": {"ARCHITECTURE"},
    "BUG": {"ROOT_CAUSE", "REGRESSION"},
    "REPAIR": {"ROOT_CAUSE", "REGRESSION"},
    "MAINTENANCE": {"CONSISTENCY"},
    "DOCS": {"CONSISTENCY"},
}
UNIVERSAL_TRACKS = {"CORE", "THIRD_PARTY"}
ENUMS = {
    "Risk Level": {"LOW", "MEDIUM", "HIGH", "CRITICAL"},
    "UI Impact": {"NONE", "MINOR", "STRUCTURAL"},
    "Contract Impact": {"NONE", "CONSUMER_ACTION", "PROVIDER_ACTION", "BOTH"},
    "Security Impact": {"YES", "NO"},
    "Data / Migration Impact": {"YES", "NO"},
    "Reliability / Performance Impact": {"YES", "NO"},
}


def field(text: str, name: str) -> str:
    match = re.search(rf"(?mi)^\s*{re.escape(name)}\s*:\s*(.*?)\s*$", text)
    return match.group(1).strip() if match else ""


def status(text: str, name: str) -> str:
    return field(text, name).upper()


def section_value(text: str, heading: str) -> str:
    match = re.search(
        rf"(?ms)^##\s+{re.escape(heading)}\s*$\s*(.*?)(?=^##\s+|\Z)", text
    )
    if not match:
        return ""
    for line in match.group(1).splitlines():
        value = line.strip().strip("`")
        if value:
            return value.upper()
    return ""


def table_rows(text: str, heading: str) -> list[dict[str, str]]:
    match = re.search(
        rf"(?ms)^##\s+{re.escape(heading)}\s*$\s*(.*?)(?=^##\s+|\Z)", text
    )
    if not match:
        return []
    lines = [line.strip() for line in match.group(1).splitlines() if line.strip().startswith("|")]
    if len(lines) < 2:
        return []
    headers = [cell.strip() for cell in lines[0].strip("|").split("|")]
    rows: list[dict[str, str]] = []
    for line in lines[2:]:
        cells = [cell.strip() for cell in line.strip("|").split("|")]
        if len(cells) == len(headers):
            rows.append(dict(zip(headers, cells)))
    return rows


def evidence_paths(root: Path, work: Path, packet: str) -> set[Path]:
    resolved: set[Path] = set()
    for row in table_rows(packet, "Evidence Inventory"):
        value = row.get("Path", "").strip()
        if not value:
            continue
        candidate = Path(value)
        if not candidate.is_absolute():
            candidate = work / candidate
        try:
            candidate = candidate.resolve()
            candidate.relative_to(root.resolve())
        except ValueError:
            continue
        resolved.add(candidate)
    return resolved


def listed_paths(value: str) -> list[str]:
    return [item.strip() for item in value.split(",") if item.strip()]


def resolve_repo_file(root: Path, value: str) -> Path | None:
    candidate = Path(value)
    if not candidate.is_absolute():
        candidate = root / candidate
    try:
        resolved = candidate.resolve()
        resolved.relative_to(root.resolve())
    except ValueError:
        return None
    return resolved


def retest_proves_pass(path: Path) -> bool:
    text = path.read_text(encoding="utf-8", errors="replace")
    return (
        status(text, "Test Decision") == "PASS"
        and status(text, "Required Checks Complete") == "YES"
        and status(text, "Failed Required Checks") == "0"
    )


def git_output(root: Path, *args: str) -> tuple[int, bytes]:
    result = subprocess.run(
        ["git", *args], cwd=root, capture_output=True, check=False
    )
    return result.returncode, result.stdout


def changed_from_base(root: Path, base: str, path: Path) -> bool:
    relative = path.resolve().relative_to(root.resolve()).as_posix()
    rc, _ = git_output(root, "cat-file", "-e", f"{base}:{relative}")
    if rc:
        return True
    rc, _ = git_output(root, "diff", "--quiet", base, "--", relative)
    return rc != 0


def selector_exists(selector: str, sealed_paths: set[Path]) -> bool:
    name = selector.strip().split(".")[-1]
    if not re.fullmatch(r"test_[A-Za-z0-9_]+", name):
        return False
    pattern = re.compile(rf"(?m)^\s*def\s+{re.escape(name)}\s*\(")
    return any(
        path.suffix == ".py"
        and pattern.search(path.read_text(encoding="utf-8", errors="replace"))
        for path in sealed_paths
        if path.is_file()
    )


def selected_tracks(text: str) -> set[str]:
    return {item.strip().upper() for item in field(text, "Required Audit Tracks").split(",") if item.strip()}


def required_tracks(text: str, errors: list[str]) -> set[str]:
    work_type = status(text, "Work Type")
    if work_type not in TYPE_TRACKS:
        errors.append(f"AUDIT_PLAN.md: unsupported Work Type {work_type or '<missing>'}")
    required = set(UNIVERSAL_TRACKS) | TYPE_TRACKS.get(work_type, set())
    if status(text, "UI Impact") not in {"", "NONE"}:
        required.add("UI_UX")
    if status(text, "Contract Impact") not in {"", "NONE"}:
        required.add("CONTRACT")
    if status(text, "Security Impact") == "YES":
        required.add("SECURITY")
    if status(text, "Data / Migration Impact") == "YES":
        required.add("DATA_MIGRATION")
    if status(text, "Reliability / Performance Impact") == "YES":
        required.add("RELIABILITY_PERFORMANCE")
    if status(text, "Risk Level") in {"HIGH", "CRITICAL"}:
        required.add("SECURITY")
    return required


def archived_blocked_findings(work: Path) -> tuple[set[str], set[str], set[str]]:
    findings: set[str] = set()
    sessions: set[str] = set()
    auditors: set[str] = set()
    history = work / "audit-history"
    if not history.is_dir():
        return findings, sessions, auditors
    for report in history.rglob("THIRD_PARTY_AUDIT.md"):
        text = report.read_text(encoding="utf-8", errors="replace")
        if status(text, "Audit Decision") != "BLOCKED":
            continue
        sessions.add(field(text, "Audit Session ID"))
        auditors.add(field(text, "Auditor Agent"))
        for line in text.splitlines():
            if not (line.strip().startswith("|") and line.strip().endswith("|")):
                continue
            cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
            if len(cells) >= 2 and cells[1].upper() in {"CRITICAL", "HIGH", "MEDIUM", "LOW"}:
                if cells[0] and cells[0].upper() != "AUDIT-NONE":
                    findings.add(cells[0].upper())
    return findings, sessions, auditors


def validate(root: Path, work: Path, phase: str) -> list[str]:
    errors: list[str] = []
    try:
        work.resolve().relative_to(root.resolve())
    except ValueError:
        return ["Work Item path must remain inside repository root"]
    plan_path = work / "AUDIT_PLAN.md"
    if not plan_path.is_file():
        return ["required audit routing artifact missing: AUDIT_PLAN.md"]
    plan = plan_path.read_text(encoding="utf-8", errors="replace")
    if status(plan, "Audit Plan Status") != "COMPLETE":
        errors.append("AUDIT_PLAN.md: Audit Plan Status must be COMPLETE")
    for name, allowed in ENUMS.items():
        value = status(plan, name)
        if value not in allowed:
            errors.append(
                f"AUDIT_PLAN.md: {name} must be one of {', '.join(sorted(allowed))}"
            )
    work_item_path = work / "WORK_ITEM.md"
    work_item = work_item_path.read_text(encoding="utf-8", errors="replace") if work_item_path.is_file() else ""
    authoritative_type = section_value(work_item, "Type")
    if authoritative_type not in TYPE_TRACKS:
        errors.append(
            "WORK_ITEM.md: Type must be one of " + ", ".join(sorted(TYPE_TRACKS))
        )
    elif status(plan, "Work Type") != authoritative_type:
        errors.append("AUDIT_PLAN.md: Work Type must match WORK_ITEM.md Type")
    impact_path = work / "IMPACT_MAP.md"
    impact = impact_path.read_text(encoding="utf-8", errors="replace") if impact_path.is_file() else ""
    for name in ENUMS:
        if status(plan, name) and status(impact, name) != status(plan, name):
            errors.append(f"AUDIT_PLAN.md: {name} must match IMPACT_MAP.md")
    required = required_tracks(plan, errors)
    missing = required - selected_tracks(plan)
    if missing:
        errors.append("AUDIT_PLAN.md: missing required audit tracks: " + ", ".join(sorted(missing)))

    if phase == "accept":
        for name, expected in {
            "Audit Execution Status": "PASS",
            "Remediation Cycle": "CLEAR",
            "Open Findings": "0",
            "Final Audit Decision": "APPROVED",
        }.items():
            if status(plan, name) != expected:
                errors.append(f"AUDIT_PLAN.md: {name} must be {expected}")
        findings, blocked_sessions, blocked_auditors = archived_blocked_findings(work)
        if findings:
            remediation_path = work / "AUDIT_REMEDIATION.md"
            if not remediation_path.is_file():
                errors.append("AUDIT_REMEDIATION.md is required for archived BLOCKED audits")
            else:
                remediation = remediation_path.read_text(encoding="utf-8", errors="replace")
                for name, expected in {
                    "Remediation Status": "COMPLETE",
                    "Unresolved Findings": "0",
                    "Retest Status": "PASS",
                    "Packet Resealed": "YES",
                }.items():
                    if status(remediation, name) != expected:
                        errors.append(f"AUDIT_REMEDIATION.md: {name} must be {expected}")
                if not field(remediation, "Code / Configuration Fix"):
                    errors.append("AUDIT_REMEDIATION.md: Code / Configuration Fix is required")
                for evidence_field in ("Code / Configuration Fix", "Retest Evidence"):
                    for value in listed_paths(field(remediation, evidence_field)):
                        candidate = resolve_repo_file(root, value)
                        if candidate is None:
                            errors.append(f"AUDIT_REMEDIATION.md: {evidence_field} escapes repository: {value}")
                            continue
                        if not candidate.is_file():
                            errors.append(f"AUDIT_REMEDIATION.md: {evidence_field} file missing: {value}")
                packet = work / "AUDIT_PACKET.md"
                packet_text = packet.read_text(encoding="utf-8", errors="replace") if packet.is_file() else ""
                if status(packet_text, "Packet Status") != "SEALED":
                    errors.append("AUDIT_REMEDIATION.md: a newly SEALED AUDIT_PACKET.md is required")
                sealed_paths = evidence_paths(root, work, packet_text)
                remediation_base = field(remediation, "Remediation Base Commit").lower()
                base_valid = bool(re.fullmatch(r"[0-9a-f]{40}", remediation_base))
                if not base_valid:
                    errors.append("AUDIT_REMEDIATION.md: Remediation Base Commit must be a full Git SHA")
                else:
                    rc, _ = git_output(root, "rev-parse", "--verify", f"{remediation_base}^{{commit}}")
                    if rc:
                        base_valid = False
                        errors.append("AUDIT_REMEDIATION.md: Remediation Base Commit must resolve locally")
                    else:
                        rc, _ = git_output(root, "merge-base", "--is-ancestor", remediation_base, "HEAD")
                        if rc:
                            base_valid = False
                            errors.append("AUDIT_REMEDIATION.md: Remediation Base Commit must be an ancestor of HEAD")
                closure_rows = {
                    row.get("Finding ID", "").upper(): row
                    for row in table_rows(remediation, "Finding Closure")
                    if row.get("Finding ID", "")
                }
                for finding in sorted(findings):
                    if not re.search(rf"(?mi)^\s*{re.escape(finding)}\s*:\s*CLOSED\s*$", remediation):
                        errors.append(f"AUDIT_REMEDIATION.md: {finding} must be CLOSED")
                    row = closure_rows.get(finding)
                    if row is None:
                        errors.append(f"AUDIT_REMEDIATION.md: {finding} requires a Finding Closure row")
                        continue
                    if row.get("Status", "").upper() != "CLOSED":
                        errors.append(f"AUDIT_REMEDIATION.md: {finding} Finding Closure status must be CLOSED")
                    for column in ("Code / Configuration Change", "Retest Evidence"):
                        values = listed_paths(row.get(column, ""))
                        if not values:
                            errors.append(f"AUDIT_REMEDIATION.md: {finding} {column} is required")
                            continue
                        for value in values:
                            candidate = resolve_repo_file(root, value)
                            if candidate is None or not candidate.is_file():
                                errors.append(f"AUDIT_REMEDIATION.md: {finding} {column} file missing: {value}")
                                continue
                            if candidate not in sealed_paths:
                                errors.append(
                                    f"AUDIT_REMEDIATION.md: {finding} {column} is not sealed audit evidence: {value}"
                                )
                            if column == "Retest Evidence" and not retest_proves_pass(candidate):
                                errors.append(
                                    f"AUDIT_REMEDIATION.md: {finding} Retest Evidence does not prove PASS: {value}"
                                )
                            if (
                                column == "Code / Configuration Change"
                                and base_valid
                                and not changed_from_base(root, remediation_base, candidate)
                            ):
                                errors.append(
                                    f"AUDIT_REMEDIATION.md: {finding} Code / Configuration Change has no remediation delta: {value}"
                                )
                    coverage_found = False
                    for value in listed_paths(row.get("Retest Evidence", "")):
                        candidate = resolve_repo_file(root, value)
                        if candidate is None or not candidate.is_file():
                            continue
                        coverage = {
                            item.get("Finding ID", "").upper(): item
                            for item in table_rows(
                                candidate.read_text(encoding="utf-8", errors="replace"),
                                "Finding Regression Coverage",
                            )
                        }.get(finding)
                        if not coverage:
                            continue
                        coverage_found = True
                        if coverage.get("Result", "").upper() != "PASS":
                            errors.append(
                                f"AUDIT_REMEDIATION.md: {finding} finding-specific retest result must be PASS"
                            )
                        selectors = listed_paths(coverage.get("Regression Test Selectors", ""))
                        if not selectors:
                            errors.append(
                                f"AUDIT_REMEDIATION.md: {finding} finding-specific regression selectors are required"
                            )
                        for selector in selectors:
                            if not selector_exists(selector, sealed_paths):
                                errors.append(
                                    f"AUDIT_REMEDIATION.md: {finding} regression selector is absent from sealed tests: {selector}"
                                )
                    if not coverage_found:
                        errors.append(
                            f"AUDIT_REMEDIATION.md: {finding} requires finding-specific regression coverage"
                        )
                final_report = work / "THIRD_PARTY_AUDIT.md"
                final_text = final_report.read_text(encoding="utf-8", errors="replace") if final_report.is_file() else ""
                if status(final_text, "Audit Decision") != "APPROVED":
                    errors.append("AUDIT_REMEDIATION.md: canonical fresh re-audit must be APPROVED")
                if field(final_text, "Audit Session ID") in blocked_sessions:
                    errors.append("AUDIT_REMEDIATION.md: fresh re-audit session must differ from blocked audit")
                if field(final_text, "Auditor Agent") in blocked_auditors:
                    errors.append("AUDIT_REMEDIATION.md: fresh re-audit Agent must differ from blocked auditor")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate audit routing and remediation cycle")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--work-item", type=Path, required=True)
    parser.add_argument("--phase", choices=("plan", "accept"), required=True)
    args = parser.parse_args()
    root = args.root.resolve()
    work = args.work_item if args.work_item.is_absolute() else root / args.work_item
    errors = validate(root, work.resolve(), args.phase)
    if errors:
        print("AUDIT PLAN GATE: BLOCKED")
        for error in errors:
            print(f"- {error}")
        return 5
    print("AUDIT PLAN GATE: PASS")
    print(f"Phase: {args.phase.upper()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())


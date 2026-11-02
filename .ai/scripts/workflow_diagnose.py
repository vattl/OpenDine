#!/usr/bin/env python3
"""Generate a read-only, evidence-cited diagnosis for one Work Item."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
from datetime import datetime


DIMENSIONS = (
    "ROUTING_TIMELINE", "PLAN_ADHERENCE", "REPEATED_WORK", "STUMBLES_BLOCKERS",
    "QUALITY_EVIDENCE", "REQUEST_CONFLICTS", "TIME_COST",
)


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace") if path.is_file() else ""


def field_line(text: str, name: str) -> int:
    for index, line in enumerate(text.splitlines(), 1):
        if re.match(rf"\s*{re.escape(name)}\s*:", line, re.I):
            return index
    return 1


def field(text: str, name: str) -> str:
    match = re.search(rf"(?mi)^\s*(?:[-*]\s*)?{re.escape(name)}\s*:\s*`?(.*?)`?\s*$", text)
    return match.group(1).strip() if match else ""


def heading_value(text: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^##\s+{re.escape(name)}\s*$\s*\n\s*([^\n#]+)",
        text,
    )
    return match.group(1).strip().strip("`") if match else ""


def delivery_phase(text: str) -> str:
    explicit = field(text, "Current Phase")
    if explicit:
        return explicit
    ordered = (
        ("Git Integration", "PASS", "INTEGRATED"),
        ("Acceptance", "ACCEPTED", "ACCEPTED"),
        ("Third Party Audit", "PASS", "THIRD_PARTY_AUDIT"),
        ("Independent Review", "PASS", "REVIEW"),
        ("Test Gate", "PASS", "TEST_APPROVED"),
        ("Security Gate", "PASS", "SECURITY_APPROVED"),
        ("Implementation Ready", "YES", "IMPLEMENTATION_READY"),
    )
    for name, expected, phase in ordered:
        if field(text, name).upper() == expected:
            return phase
    return ""


def planned_task_ids(text: str) -> set[str]:
    section = re.search(
        r"(?ms)^##\s+Tasks\s*/\s*Vertical Slices\s*$\n(.*?)(?=^##\s+|\Z)",
        text,
    )
    if not section:
        return set()
    return {
        value.upper()
        for value in re.findall(r"(?mi)^\s*-\s*\[[ xX]\]\s+([A-Za-z]+\d+)\b", section.group(1))
    }


def coverage_task_ids(text: str) -> set[str]:
    section = re.search(r"(?ms)^##\s+Task Coverage\s*$\n(.*?)(?=^##\s+|\Z)", text)
    if not section:
        return set()
    return {
        value.upper()
        for value in re.findall(r"(?mi)^\|\s*([A-Za-z]+\d+)\s*\|", section.group(1))
    }


def validator_pass(root: Path, script: str, work: Path, phase: str) -> bool:
    target = root / ".ai" / "scripts" / script
    if not target.is_file():
        return False
    result = subprocess.run(
        [sys.executable, str(target), "--root", str(root), "--work-item", str(work), "--phase", phase],
        text=True,
        capture_output=True,
        encoding="utf-8",
        errors="replace",
    )
    return result.returncode == 0


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--work-item", type=Path, required=True)
    parser.add_argument("--intake", default="diagnose lifecycle adherence, repeated work and evidence gaps")
    args = parser.parse_args()
    root = args.root.resolve()
    work = args.work_item.resolve()
    try:
        work.relative_to(root)
    except ValueError:
        print("ERROR: Work Item must remain inside repository root", file=sys.stderr)
        return 2
    candidates = [
        work / "WORK_ITEM.md", work / "DELIVERY_GATE.md", work / "AUDIT_PLAN.md",
        work / "TDD_CYCLE_REPORT.md", work / "TASK_AGENT_LEDGER.md",
        work / "EXECUTION_JOURNAL.jsonl", work / "WORKTREE_READINESS.md",
        work / "TEST_REPORT.md", work / "REVIEW_REPORT.md",
    ]
    evidence = [path for path in candidates if path.is_file() and path.stat().st_size]
    if not evidence:
        print("ERROR: no durable Work Item evidence exists", file=sys.stderr)
        return 2
    evidence_ids = {path: f"E-{index:02d}" for index, path in enumerate(evidence, 1)}
    def ev(path: Path) -> str:
        return evidence_ids.get(path, "")
    def add_finding(dimension: str, severity: str, source: Path, line: int,
                    fact: str, impact: str, recommendation: str) -> None:
        findings.append((
            f"D-{len(findings) + 1:02d}", dimension, severity,
            f"{source.relative_to(root).as_posix()}:{line}", fact, impact,
            recommendation, "OPEN",
        ))
    gate_path = work / "DELIVERY_GATE.md"
    gate = read(gate_path)
    findings: list[tuple[str, str, str, str, str, str, str, str]] = []
    dimension_results: dict[str, tuple[str, str, str]] = {}
    work_item_path = work / "WORK_ITEM.md"
    work_item_text = read(work_item_path)
    journal_path = work / "EXECUTION_JOURNAL.jsonl"
    journal_text = read(journal_path)

    # ROUTING_TIMELINE: compare durable Work Item and delivery phase when both exist.
    if gate and work_item_text:
        work_state = heading_value(work_item_text, "State") or field(work_item_text, "State") or field(work_item_text, "Status")
        gate_phase = delivery_phase(gate)
        if not work_state or not gate_phase:
            dimension_results["ROUTING_TIMELINE"] = ("INSUFFICIENT_EVIDENCE", "CHECK_ROUTING_TIMELINE", f"{ev(gate_path)},{ev(work_item_path)}")
            source = work_item_path if not work_state else gate_path
            source_text = work_item_text if not work_state else gate
            missing_field = "State" if not work_state else "Current Phase"
            add_finding("ROUTING_TIMELINE", "MEDIUM", source, field_line(source_text, missing_field),
                        "routing state or current phase is missing", "phase order cannot be verified", "record both the authoritative Work Item state and Delivery Gate current phase")
        elif work_state.upper() != gate_phase.upper():
            dimension_results["ROUTING_TIMELINE"] = ("BLOCKED", "CHECK_ROUTING_TIMELINE", f"{ev(gate_path)},{ev(work_item_path)}")
            add_finding("ROUTING_TIMELINE", "HIGH", gate_path, field_line(gate, "Current Phase"),
                        "route/phase mismatch between Work Item and Delivery Gate", "execution can occur in the wrong lifecycle phase", "reconcile the authoritative Work Item state and routed gate phase")
        else:
            dimension_results["ROUTING_TIMELINE"] = ("REVIEWED", "CHECK_ROUTING_TIMELINE", f"{ev(gate_path)},{ev(work_item_path)}")
    else:
        source = work_item_path if work_item_path.is_file() else evidence[0]
        dimension_results["ROUTING_TIMELINE"] = ("INSUFFICIENT_EVIDENCE", "CHECK_ROUTING_TIMELINE", ev(source))
        add_finding("ROUTING_TIMELINE", "MEDIUM", source, 1, "routing timeline evidence is incomplete", "phase order cannot be verified", "provide Work Item and Delivery Gate phase evidence")

    # PLAN_ADHERENCE: required routed artifacts and task list.
    plan_sources = [path for path in (work_item_path, gate_path) if path.is_file()]
    required_artifacts = {
        "TDD Gate": "TDD_CYCLE_REPORT.md",
        "Task Agent Review Gate": "TASK_AGENT_LEDGER.md",
        "Worktree Readiness Gate": "WORKTREE_READINESS.md",
    }
    required_paths: list[Path] = []
    plan_blocked = len(plan_sources) != 2
    for route, artifact in required_artifacts.items():
        if re.search(rf"(?mi)^\s*{re.escape(route)}\s*:\s*REQUIRED\s*$", gate):
            artifact_path = work / artifact
            if not artifact_path.is_file():
                plan_blocked = True
                add_finding("PLAN_ADHERENCE", "HIGH", gate_path, field_line(gate, route),
                            f"missing required lifecycle evidence {artifact}", "the lifecycle gate can be asserted without its required proof", f"create and validate {artifact} before continuing")
            else:
                required_paths.append(artifact_path)
    plan_sources.extend(required_paths)
    tdd_text = read(work / "TDD_CYCLE_REPORT.md")
    ledger_text = read(work / "TASK_AGENT_LEDGER.md")
    readiness_text = read(work / "WORKTREE_READINESS.md")
    planned_ids = planned_task_ids(work_item_text)
    if field(gate, "TDD Gate").upper() == "REQUIRED" or field(gate, "Task Agent Review Gate").upper() == "REQUIRED":
        discipline_valid = (
            field(tdd_text, "TDD Decision").upper() == "PASS"
            and field(ledger_text, "Task Agent Decision").upper() == "PASS"
            and bool(planned_ids)
            and coverage_task_ids(tdd_text) == planned_ids
            and validator_pass(root, "validate_execution_discipline.py", work, "accept")
        )
        plan_blocked = plan_blocked or not discipline_valid
    if field(gate, "Worktree Readiness Gate").upper() == "REQUIRED":
        readiness_valid = (
            field(readiness_text, "Readiness Decision").upper() == "PASS"
            and validator_pass(root, "validate_worktree_readiness.py", work, "accept")
        )
        plan_blocked = plan_blocked or not readiness_valid
    if plan_blocked and not any(finding[1] == "PLAN_ADHERENCE" for finding in findings):
        source = gate_path if gate_path.is_file() else evidence[0]
        add_finding(
            "PLAN_ADHERENCE", "HIGH", source, 1,
            "required lifecycle evidence is pending, invalid or does not match planned tasks",
            "the recorded plan cannot prove task and readiness adherence",
            "complete the required evidence and pass its phase-aware validators",
        )
    plan_status = "BLOCKED" if plan_blocked else "REVIEWED"
    plan_refs = ",".join(ev(path) for path in plan_sources if ev(path)) or ev(evidence[0])
    dimension_results["PLAN_ADHERENCE"] = (plan_status, "CHECK_PLAN_ADHERENCE", plan_refs)

    # Journal-backed dimensions.
    events: list[tuple[int, dict[str, object]]] = []
    if journal_text:
        for line_number, line in enumerate(journal_text.splitlines(), 1):
            try:
                value = json.loads(line)
                if isinstance(value, dict):
                    events.append((line_number, value))
            except json.JSONDecodeError:
                add_finding("STUMBLES_BLOCKERS", "HIGH", journal_path, line_number, "execution journal contains invalid JSON", "execution history is not trustworthy", "repair the recorder and regenerate evidence through real commands")
        dimension_results["REPEATED_WORK"] = ("REVIEWED", "CHECK_REPEATED_WORK", ev(journal_path))
        dimension_results["STUMBLES_BLOCKERS"] = ("REVIEWED", "CHECK_STUMBLES_BLOCKERS", ev(journal_path))
        parsed_times: list[float] = []
        seen: set[tuple[str, str, str]] = set()
        stage_rank = {"RED": 1, "GREEN": 2, "REFACTOR": 3, "REGRESSION": 4}
        task_ranks: dict[str, int] = {}
        for line_number, event in events:
            try:
                parsed_time = datetime.fromisoformat(str(event.get("timestamp_utc", "")).replace("Z", "+00:00"))
                if parsed_time.utcoffset() is None:
                    raise ValueError("timestamp_utc must include a UTC offset")
                parsed_times.append(parsed_time.timestamp())
            except ValueError:
                add_finding("TIME_COST", "MEDIUM", journal_path, line_number, "timestamp evidence is missing or invalid", "elapsed-time signals cannot be calculated", "record complete ISO-8601 timestamps through the execution journal")
            key = (str(event.get("task_id", "")), str(event.get("stage", "")), str(event.get("selector", "")))
            if key in seen:
                add_finding("REPEATED_WORK", "MEDIUM", journal_path, line_number, "execution journal repeats task/stage/selector", "duplicate work obscures the authoritative result", "retain one ordered event per required stage or explain a new review cycle")
            seen.add(key)
            task, stage = key[0], key[1].upper()
            rank = stage_rank.get(stage, 0)
            if rank and rank <= task_ranks.get(task, 0):
                add_finding("STUMBLES_BLOCKERS", "HIGH", journal_path, line_number, "execution stage order is invalid", "RED-GREEN chronology cannot be trusted", "rerun the task through the ordered execution journal")
            task_ranks[task] = max(rank, task_ranks.get(task, 0))
            if str(event.get("classification", "")).upper() in {"FAIL", "UNEXPECTED_FAILURE", "UNEXPECTED_PASS"}:
                add_finding("STUMBLES_BLOCKERS", "HIGH", journal_path, line_number, "failed execution event is present", "the workflow required remediation", "record cause, remediation and a new successful evidence cycle")
        strictly_ordered = all(earlier < later for earlier, later in zip(parsed_times, parsed_times[1:]))
        if len(parsed_times) >= 2 and len(parsed_times) == len(events) and strictly_ordered:
            dimension_results["TIME_COST"] = ("REVIEWED", "CHECK_TIME_COST", ev(journal_path))
        else:
            dimension_results["TIME_COST"] = ("INSUFFICIENT_EVIDENCE", "CHECK_TIME_COST", ev(journal_path))
            add_finding("TIME_COST", "MEDIUM", journal_path, 1, "time/cost evidence requires at least two ordered timestamps", "duration and retry cost cannot be supported", "record ordered start and completion events")
    else:
        for dimension, check in (("REPEATED_WORK", "CHECK_REPEATED_WORK"), ("STUMBLES_BLOCKERS", "CHECK_STUMBLES_BLOCKERS"), ("TIME_COST", "CHECK_TIME_COST")):
            dimension_results[dimension] = ("INSUFFICIENT_EVIDENCE", check, ev(work_item_path) or ev(evidence[0]))
            add_finding(dimension, "MEDIUM", work_item_path if work_item_path.is_file() else evidence[0], 1, f"{dimension.lower()} source evidence is unavailable", "the dimension cannot be truthfully reviewed", "provide an execution journal with ordered timestamped events")

    quality_paths = [path for path in (work / "TDD_CYCLE_REPORT.md", work / "TASK_AGENT_LEDGER.md", work / "TEST_REPORT.md", work / "REVIEW_REPORT.md") if path.is_file()]
    discipline = subprocess.run(
        [sys.executable, str(root / ".ai/scripts/validate_execution_discipline.py"),
         "--root", str(root), "--work-item", str(work), "--phase", "accept"],
        text=True, capture_output=True, encoding="utf-8", errors="replace",
    ) if (work / "TDD_CYCLE_REPORT.md").is_file() and (work / "TASK_AGENT_LEDGER.md").is_file() else None
    test_text, review_text = read(work / "TEST_REPORT.md"), read(work / "REVIEW_REPORT.md")
    test_pass = "Test Decision: PASS" in test_text and "Required Checks Complete: YES" in test_text
    review_pass = bool(re.search(r"(?mi)^\s*(?:Review Decision|Decision)\s*:\s*PASS\s*$", review_text))
    if discipline and discipline.returncode == 0 and test_pass and review_pass:
        dimension_results["QUALITY_EVIDENCE"] = ("REVIEWED", "CHECK_QUALITY_EVIDENCE", ",".join(ev(path) for path in quality_paths))
    else:
        source = gate_path if gate_path.is_file() else evidence[0]
        refs = ",".join(ev(path) for path in quality_paths) or ev(source)
        dimension_results["QUALITY_EVIDENCE"] = ("INSUFFICIENT_EVIDENCE", "CHECK_QUALITY_EVIDENCE", refs)
        add_finding("QUALITY_EVIDENCE", "HIGH", source, 1, "missing required quality evidence", "test and review quality cannot be assessed", "provide TDD, task review, test or review evidence")

    audit_plan_path = work / "AUDIT_PLAN.md"
    audit_plan_text = read(audit_plan_path)
    if audit_plan_path.is_file() and audit_plan_path not in evidence_ids:
        evidence.append(audit_plan_path)
        evidence_ids[audit_plan_path] = f"E-{len(evidence_ids) + 1:02d}"
    work_type = re.search(r"(?mi)^\s*##\s+Type\s*$\s*\n\s*([A-Z_]+)", work_item_text)
    plan_type = re.search(r"(?mi)^\s*Work Type\s*:\s*([A-Z_]+)", audit_plan_text)
    task_section = re.search(r"(?ms)^##\s+Tasks\s*/\s*Vertical Slices\s*$\n(.*?)(?=^##\s+|\Z)", work_item_text)
    has_tasks = bool(task_section and re.search(r"(?mi)^\s*-\s*\[[ xX]\]", task_section.group(1)))
    gates_required = all(re.search(rf"(?mi)^\s*{re.escape(name)}\s*:\s*REQUIRED\s*$", gate) for name in ("TDD Gate", "Task Agent Review Gate", "Worktree Readiness Gate"))
    if work_item_text and gate and audit_plan_text and work_type and plan_type and work_type.group(1) == plan_type.group(1) and (not has_tasks or gates_required):
        dimension_results["REQUEST_CONFLICTS"] = ("REVIEWED", "CHECK_REQUEST_CONFLICTS", f"{ev(work_item_path)},{ev(gate_path)},{ev(audit_plan_path)}")
    else:
        source = work_item_path if work_item_path.is_file() else evidence[0]
        refs = ",".join(filter(None, (ev(work_item_path), ev(gate_path), ev(audit_plan_path)))) or ev(source)
        dimension_results["REQUEST_CONFLICTS"] = ("INSUFFICIENT_EVIDENCE", "CHECK_REQUEST_CONFLICTS", refs)
        add_finding("REQUEST_CONFLICTS", "MEDIUM", source, 1, "request and policy routing evidence cannot be reconciled", "conflicting work type or gate decisions may be missed", "align Work Item type, Audit Plan type and mandatory routed gates")

    decision = "BLOCKED" if findings or any(value[0] != "REVIEWED" for value in dimension_results.values()) else "CLEAR"
    output = [
        "# Workflow Diagnosis",
        "",
        "Diagnosis Status: COMPLETE",
        f"Diagnosis Decision: {decision}",
        "Input Mutation: NONE",
        f"Intake Statement: {args.intake}",
        f"Scope: {work.relative_to(root).as_posix()}",
        "",
        "## Evidence Inventory",
        "| ID | Path | SHA256 |",
        "|---|---|---|",
    ]
    for path in evidence:
        output.append(f"| {evidence_ids[path]} | {path.relative_to(root).as_posix()} | {digest(path)} |")
    output.extend([
        "",
        "## Dimension Coverage",
        "| Dimension | Status | Evidence |",
        "|---|---|---|",
    ])
    output[-2] = "| Dimension | Status | Check | Evidence |"
    output[-1] = "|---|---|---|---|"
    for dimension in DIMENSIONS:
        status_value, check, evidence_value = dimension_results[dimension]
        output.append(f"| {dimension} | {status_value} | {check} | {evidence_value} |")
    output.extend([
        "",
        "## Findings",
        "| ID | Dimension | Severity | Evidence | Observed Fact | Impact | Recommendation | Status |",
        "|---|---|---|---|---|---|---|---|",
    ])
    for finding in findings:
        output.append("| " + " | ".join(finding) + " |")
    output.extend([
        "",
        "## Interpretation",
        "Findings are derived only from the inventoried files. No source evidence was modified.",
    ])
    work.mkdir(parents=True, exist_ok=True)
    target = work / "WORKFLOW_DIAGNOSIS.md"
    target.write_text("\n".join(output) + "\n", encoding="utf-8")
    print(f"WORKFLOW DIAGNOSIS: {decision}")
    print(f"Report: {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

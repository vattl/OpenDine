#!/usr/bin/env python3
"""Validate strict TDD and per-task fresh-Agent double-review evidence."""

from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess


TDD_REPORT = "TDD_CYCLE_REPORT.md"
TASK_LEDGER = "TASK_AGENT_LEDGER.md"
ALLOWED_TDD_NA = {"DOCS_ONLY", "DECLARATIVE_CONFIG", "GENERATED", "THROWAWAY_PROTOTYPE"}
PLACEHOLDERS = {"", "-", "TBD", "PENDING", "PLANNED", "UNKNOWN", "N/A", "NONE"}
INVALID_RED_FAILURE_PATTERNS = (
    r"\b(?:SyntaxError|IndentationError|ModuleNotFoundError|ImportError)\b",
    r"(?:can't|cannot) open file",
    r"\bNo such file or directory\b",
    r"\bcommand not found\b",
    r"is not recognized as an internal or external command",
    r"\b(?:ERROR collecting|collection errors?|collected 0 items|no tests ran)\b",
    r"\b(?:failed to import test module|could not import)\b",
    r"\b(?:connection refused|temporary failure in name resolution)\b",
    r"\b(?:TimeoutError|TimeoutExpired|timed?\s*out)\b",
    r"\bdependency resolution failed\b",
)


def has_invalid_red_failure(output: str) -> bool:
    return any(re.search(pattern, output, re.IGNORECASE) for pattern in INVALID_RED_FAILURE_PATTERNS)


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace") if path.is_file() else ""


def field(text: str, name: str) -> str:
    match = re.search(rf"(?mi)^\s*(?:[-*]\s*)?{re.escape(name)}\s*:\s*`?(.*?)`?\s*$", text)
    return match.group(1).strip() if match else ""


def table(text: str, heading: str, errors: list[str], artifact: str) -> list[dict[str, str]]:
    lines = text.splitlines()
    start = next((i for i, line in enumerate(lines) if re.fullmatch(
        rf"\s*#+\s+{re.escape(heading)}\s*", line, re.I
    )), None)
    if start is None:
        errors.append(f"{artifact}: missing section {heading}")
        return []
    header_index = next((i for i in range(start + 1, len(lines)) if lines[i].strip().startswith("|")), None)
    if header_index is None:
        errors.append(f"{artifact}: {heading} table is missing")
        return []
    headers = [cell.strip() for cell in lines[header_index].strip().strip("|").split("|")]
    rows: list[dict[str, str]] = []
    for line in lines[header_index + 1:]:
        stripped = line.strip()
        if stripped.startswith("#") or (rows and not stripped):
            break
        if not (stripped.startswith("|") and stripped.endswith("|")):
            continue
        if set(stripped) <= {"|", "-", ":", " "}:
            continue
        cells = [cell.strip().strip("`") for cell in stripped.strip("|").split("|")]
        if len(cells) != len(headers):
            errors.append(f"{artifact}: malformed {heading} row")
            continue
        rows.append(dict(zip(headers, cells)))
    if not rows:
        errors.append(f"{artifact}: {heading} table has no task rows")
    return rows


def require_columns(rows: list[dict[str, str]], columns: tuple[str, ...], errors: list[str], label: str) -> bool:
    if not rows:
        return False
    missing = [name for name in columns if name not in rows[0]]
    if missing:
        errors.append(f"{label}: missing columns: {', '.join(missing)}")
        return False
    return True


def resolve_file(root: Path, work: Path, value: str, errors: list[str], label: str) -> Path | None:
    if value.strip().upper() in PLACEHOLDERS:
        errors.append(f"{label}: path must be resolved")
        return None
    candidate = Path(value)
    if not candidate.is_absolute():
        candidate = root / candidate
    resolved = candidate.resolve()
    try:
        resolved.relative_to(root.resolve())
    except ValueError:
        errors.append(f"{label}: path escapes repository root")
        return None
    if not resolved.is_file() or resolved.stat().st_size == 0:
        errors.append(f"{label}: file missing or empty: {value}")
        return None
    return resolved


def file_sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def manifest_sha(root: Path, paths: list[str], revision: str | None = None) -> str | None:
    entries = []
    for value in sorted(paths):
        candidate = (root / value).resolve()
        try:
            candidate.relative_to(root.resolve())
        except ValueError:
            return None
        if revision:
            result = subprocess.run(["git", "show", f"{revision}:{value}"], cwd=root, capture_output=True)
            if result.returncode:
                return None
            digest = hashlib.sha256(result.stdout).hexdigest()
        else:
            if not candidate.is_file():
                return None
            digest = file_sha(candidate)
        entries.append({"path": value, "sha256": digest})
    canonical = json.dumps(entries, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def work_item_tasks(text: str) -> set[str]:
    section = re.search(
        r"(?ms)^##\s+Tasks\s*/\s*Vertical Slices\s*$\n(.*?)(?=^##\s+|\Z)", text
    )
    if not section:
        return set()
    return {
        value.upper()
        for value in re.findall(r"(?mi)^\s*-\s*\[[ xX]\]\s+([A-Za-z]+\d+)\b", section.group(1))
    }


def validate_journal(root: Path, work: Path, report: str, required_tasks: dict[str, str], errors: list[str]) -> None:
    journal = resolve_file(root, work, field(report, "Execution Journal"), errors, TDD_REPORT)
    expected_journal_sha = field(report, "Execution Journal SHA256").lower()
    if journal is None:
        return
    if not re.fullmatch(r"[0-9a-f]{64}", expected_journal_sha) or file_sha(journal) != expected_journal_sha:
        errors.append(f"{TDD_REPORT}: Execution Journal SHA256 mismatch")
    events: list[dict[str, object]] = []
    for line_number, line in enumerate(read(journal).splitlines(), 1):
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            errors.append(f"EXECUTION_JOURNAL.jsonl:{line_number}: invalid JSON")
            continue
        if not isinstance(value, dict):
            errors.append(f"EXECUTION_JOURNAL.jsonl:{line_number}: event must be an object")
            continue
        events.append(value)
    previous = "GENESIS"
    expected_sequence = 1
    per_task: dict[str, list[dict[str, object]]] = {}
    timestamps: list[datetime] = []
    for event in events:
        sequence = event.get("sequence")
        task_id = str(event.get("task_id", ""))
        if sequence != expected_sequence:
            errors.append("EXECUTION_JOURNAL.jsonl: event sequence must be contiguous and ordered")
        expected_sequence += 1
        if event.get("previous_event_hash") != previous:
            errors.append("EXECUTION_JOURNAL.jsonl: previous_event_hash chain is broken")
        supplied_hash = str(event.get("event_hash", ""))
        unsigned = dict(event)
        unsigned.pop("event_hash", None)
        canonical = json.dumps(unsigned, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        calculated = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
        if supplied_hash != calculated:
            errors.append("EXECUTION_JOURNAL.jsonl: event hash mismatch")
        previous = supplied_hash
        if event.get("schema") != "ai-development-os.execution-event/v1":
            errors.append(f"event {sequence}: unsupported schema")
        try:
            timestamps.append(datetime.fromisoformat(str(event.get("timestamp_utc", "")).replace("Z", "+00:00")))
        except ValueError:
            errors.append(f"event {sequence}: timestamp_utc must be ISO-8601")
        if not isinstance(event.get("command"), list) or not event.get("command"):
            errors.append(f"event {sequence}: command must be a non-empty argv array")
        if not re.fullmatch(r"[0-9a-f]{40}", str(event.get("git_head", ""))):
            errors.append(f"event {sequence}: git_head must be a full commit SHA")
        log_path = resolve_file(root, work, str(event.get("log_path", "")), errors, f"event {sequence} log")
        expected_log_sha = str(event.get("log_sha256", "")).lower()
        if log_path and (not re.fullmatch(r"[0-9a-f]{64}", expected_log_sha) or file_sha(log_path) != expected_log_sha):
            errors.append(f"event {sequence}: log SHA256 mismatch")
        test_source = resolve_file(root, work, str(event.get("test_source", "")), errors, f"event {sequence} test source")
        if test_source and file_sha(test_source) != str(event.get("test_source_sha256", "")).lower():
            errors.append(f"event {sequence}: test source SHA256 mismatch")
        per_task.setdefault(task_id, []).append(event)
    if timestamps and timestamps != sorted(timestamps):
        errors.append("EXECUTION_JOURNAL.jsonl: timestamps must be ordered")

    for task_id, selector in required_tasks.items():
        task_events = per_task.get(task_id, [])
        by_stage = {str(item.get("stage", "")).upper(): item for item in task_events}
        stages = [str(item.get("stage", "")).upper() for item in task_events]
        required_stages = ["RED", "GREEN", "REFACTOR", "REGRESSION"]
        if len(task_events) != len(required_stages) or len(stages) != len(set(stages)):
            errors.append(f"{task_id}: exactly one event is required for each RED/GREEN/REFACTOR/REGRESSION stage")
        for stage in required_stages:
            if stage not in by_stage:
                errors.append(f"{task_id}: missing observed {stage} event")
        if any(stage not in by_stage for stage in required_stages):
            continue
        if [stages.index(stage) for stage in required_stages] != sorted(stages.index(stage) for stage in required_stages):
            errors.append(f"{task_id}: RED, GREEN, REFACTOR and REGRESSION must be ordered")
        red = by_stage["RED"]
        if not isinstance(red.get("exit_code"), int) or int(red["exit_code"]) == 0:
            errors.append(f"{task_id}: RED must have a non-zero exit code")
        if str(red.get("classification", "")).upper() != "EXPECTED_ASSERTION_FAILURE":
            errors.append(f"{task_id}: RED classification must be EXPECTED_ASSERTION_FAILURE")
        signature = str(red.get("expected_signature", ""))
        red_log = resolve_file(root, work, str(red.get("log_path", "")), [], f"{task_id} RED log")
        if not signature or red_log is None or signature not in read(red_log):
            errors.append(f"{task_id}: RED expected_signature must occur in the hashed RED log")
        if red_log is not None and has_invalid_red_failure(read(red_log)):
            errors.append(
                f"{task_id}: RED log contains an invalid failure mode "
                "(syntax/import/collection/dependency/environment/infrastructure)"
            )
        for stage in ("GREEN", "REFACTOR", "REGRESSION"):
            event = by_stage[stage]
            if event.get("exit_code") != 0 or str(event.get("classification", "")).upper() != "PASS":
                errors.append(f"{task_id}: {stage} must PASS with exit code 0")
        if any(str(by_stage[stage].get("selector", "")) != selector for stage in required_stages):
            errors.append(f"{task_id}: all stages must use the same selector declared by the task")
        production_paths = red.get("production_paths")
        if not isinstance(production_paths, list) or not production_paths or not all(isinstance(item, str) for item in production_paths):
            errors.append(f"{task_id}: RED must bind concrete production_paths")
            continue
        baseline = manifest_sha(root, production_paths, str(red.get("git_head", "")))
        if baseline != red.get("production_baseline_sha256") or baseline != red.get("production_snapshot_sha256"):
            errors.append(f"{task_id}: RED must bind the unchanged production baseline at its Git commit")
        for stage in required_stages:
            event = by_stage[stage]
            if event.get("production_paths") != production_paths or event.get("production_baseline_sha256") != baseline:
                errors.append(f"{task_id}: all stages must bind the same production baseline and paths")
        current_snapshot = manifest_sha(root, production_paths)
        if current_snapshot != by_stage["REGRESSION"].get("production_snapshot_sha256"):
            errors.append(f"{task_id}: REGRESSION production snapshot must match current files")
        if current_snapshot == baseline:
            errors.append(f"{task_id}: production behavior did not change after RED")


def validate_review(
    root: Path,
    work: Path,
    task_id: str,
    path_value: str,
    review_type: str,
    errors: list[str],
) -> tuple[str, str, str, str, str]:
    path = resolve_file(root, work, path_value, errors, f"{task_id} {review_type} review")
    if path is None:
        return "", "", "", "", ""
    text = read(path)
    if field(text, "Task ID") != task_id:
        errors.append(f"{path.name}: Task ID must be {task_id}")
    if field(text, "Review Type").upper() != review_type:
        errors.append(f"{path.name}: Review Type must be {review_type}")
    for name, expected in {
        "Fresh Context": "YES", "Read Only": "YES", "Review Decision": "PASS",
        "Open Critical": "0", "Open High": "0",
    }.items():
        if field(text, name).upper() != expected:
            errors.append(f"{path.name}: {name} must be {expected}")
    session = field(text, "Reviewer Session")
    if session.upper() in PLACEHOLDERS or len(session) < 3:
        errors.append(f"{path.name}: Reviewer Session must be concrete")
    provider_model = field(text, "Provider / Model")
    if "/" not in provider_model or any(not part.strip() for part in provider_model.split("/", 1)):
        errors.append(f"{path.name}: Provider / Model must identify both values")
    task_brief = resolve_file(
        root, work, (work / "task-briefs" / f"{task_id}.md").relative_to(root).as_posix(),
        errors, f"{path.name} Task Brief"
    )
    validate_dispatch_receipt(
        root, work, task_id, session, review_type,
        field(text, "Dispatch Receipt"), field(text, "Dispatch Receipt SHA256"),
        provider_model, file_sha(task_brief) if task_brief else "", errors,
    )
    spec_hash = field(text, "Spec SHA256").lower()
    diff_hash = field(text, "Diff SHA256").lower()
    if not re.fullmatch(r"[0-9a-f]{64}", spec_hash):
        errors.append(f"{path.name}: Spec SHA256 must be 64 hexadecimal characters")
    if not re.fullmatch(r"[0-9a-f]{64}", diff_hash):
        errors.append(f"{path.name}: Diff SHA256 must be 64 hexadecimal characters")
    spec_snapshot = resolve_file(
        root, work, field(text, "Spec Snapshot"), errors, f"{path.name} Spec Snapshot"
    )
    diff_snapshot = resolve_file(
        root, work, field(text, "Diff Snapshot"), errors, f"{path.name} Diff Snapshot"
    )
    if spec_snapshot and re.fullmatch(r"[0-9a-f]{64}", spec_hash) and file_sha(spec_snapshot) != spec_hash:
        errors.append(f"{path.name}: Spec SHA256 mismatch")
    if diff_snapshot and re.fullmatch(r"[0-9a-f]{64}", diff_hash) and file_sha(diff_snapshot) != diff_hash:
        errors.append(f"{path.name}: Diff SHA256 mismatch")
    if field(text, "Diff Evidence Mode").upper() != "GIT_RANGE":
        errors.append(f"{path.name}: Diff Evidence Mode must be GIT_RANGE")
    base = field(text, "Git Base").lower()
    head = field(text, "Git Head").lower()
    if not re.fullmatch(r"[0-9a-f]{40}", base) or not re.fullmatch(r"[0-9a-f]{40}", head):
        errors.append(f"{path.name}: Git Base/Head must be full commit SHAs")
    elif diff_snapshot:
        result = subprocess.run(
            ["git", "diff", "--binary", "--no-ext-diff", base, head],
            cwd=root,
            text=True,
            capture_output=True,
            encoding="utf-8",
            errors="replace",
        )
        if result.returncode or diff_snapshot.read_text(encoding="utf-8", errors="replace") != result.stdout:
            errors.append(f"{path.name}: Diff Snapshot must equal the declared Git range")
        ancestor = subprocess.run(["git", "merge-base", "--is-ancestor", head, "HEAD"], cwd=root)
        if ancestor.returncode:
            errors.append(f"{path.name}: reviewed Git Head must be contained in current HEAD")
        changed_result = subprocess.run(
            ["git", "diff", "--name-only", base, head], cwd=root,
            text=True, capture_output=True, encoding="utf-8", errors="replace",
        )
        changed_paths = [value for value in changed_result.stdout.splitlines() if value.strip()]
        if changed_paths:
            stale = subprocess.run(["git", "diff", "--quiet", head, "HEAD", "--", *changed_paths], cwd=root)
            if stale.returncode:
                errors.append(f"{path.name}: reviewed task paths changed after review; fresh double review is required")
    return session, spec_hash, diff_hash, base, head


def validate_dispatch_receipt(
    root: Path, work: Path, task_id: str, session: str, role: str,
    path_value: str, expected_sha: str, expected_provider_model: str,
    expected_task_brief_sha: str, errors: list[str],
) -> None:
    path = resolve_file(root, work, path_value, errors, f"{task_id} {role} Dispatch Receipt")
    if path is None:
        return
    try:
        path.relative_to((root / ".ai-runtime" / "agent-dispatch").resolve())
    except ValueError:
        errors.append(f"{path.name}: Dispatch Receipt must be under .ai-runtime/agent-dispatch")
    if not re.fullmatch(r"[0-9a-fA-F]{64}", expected_sha) or file_sha(path) != expected_sha.lower():
        errors.append(f"{path.name}: Dispatch Receipt SHA256 mismatch")
    text = read(path)
    expected = {
        "Receipt Authority": "BUILTIN_ORCHESTRATOR",
        "Task ID": task_id,
        "Role": role,
        "Session ID": session,
        "Context Mode": "FRESH",
    }
    for name, value in expected.items():
        if field(text, name).upper() != value.upper():
            errors.append(f"{path.name}: {name} must be {value}")
    provider_model = field(text, "Provider / Model")
    if not field(text, "Receipt ID") or not provider_model:
        errors.append(f"{path.name}: Receipt ID and Provider / Model are required")
    elif provider_model != expected_provider_model:
        errors.append(f"{path.name}: Provider / Model must match the dispatched Agent evidence")
    brief_sha = field(text, "Task Brief SHA256").lower()
    if (
        not re.fullmatch(r"[0-9a-f]{64}", brief_sha)
        or not expected_task_brief_sha
        or brief_sha != expected_task_brief_sha
    ):
        errors.append(f"{path.name}: Task Brief SHA256 must match the dispatched task brief")
    try:
        datetime.fromisoformat(field(text, "Issued At").replace("Z", "+00:00"))
    except ValueError:
        errors.append(f"{path.name}: Issued At must be ISO-8601")


def validate_implementer_receipt(
    root: Path, work: Path, task_id: str, session: str, path_value: str,
    receipt_sha: str, errors: list[str]
) -> tuple[str, str, str]:
    path = resolve_file(root, work, path_value, errors, f"{task_id} Implementer Receipt")
    if path is None:
        return "", "", ""
    text = read(path)
    if not re.fullmatch(r"[0-9a-fA-F]{64}", receipt_sha) or file_sha(path) != receipt_sha.lower():
        errors.append(f"{path.name}: Implementer Receipt SHA256 mismatch")
    if field(text, "Receipt Schema") != "ai-development-os.task-implementation-receipt/v1":
        errors.append(f"{path.name}: unsupported Receipt Schema")
    if field(text, "Task ID") != task_id:
        errors.append(f"{path.name}: Task ID must be {task_id}")
    if field(text, "Agent Role").upper() != "IMPLEMENTER":
        errors.append(f"{path.name}: Agent Role must be IMPLEMENTER")
    if field(text, "Agent Session") != session:
        errors.append(f"{path.name}: Agent Session must match the ledger")
    if field(text, "Context Mode").upper() != "FRESH":
        errors.append(f"{path.name}: Context Mode must be FRESH")
    provider_model = field(text, "Provider / Model")
    if "/" not in provider_model or any(not part.strip() for part in provider_model.split("/", 1)):
        errors.append(f"{path.name}: Provider / Model must identify both values")
    task_brief = resolve_file(root, work, field(text, "Task Brief"), errors, f"{path.name} Task Brief")
    brief_sha = field(text, "Task Brief SHA256").lower()
    if task_brief and (not re.fullmatch(r"[0-9a-f]{64}", brief_sha) or file_sha(task_brief) != brief_sha):
        errors.append(f"{path.name}: Task Brief SHA256 mismatch")
    validate_dispatch_receipt(
        root, work, task_id, session, "IMPLEMENTER",
        field(text, "Dispatch Receipt"), field(text, "Dispatch Receipt SHA256"),
        provider_model, file_sha(task_brief) if task_brief else "", errors,
    )
    if field(text, "Verification Command").upper() in PLACEHOLDERS:
        errors.append(f"{path.name}: Verification Command must be concrete")
    if field(text, "Verification Exit Code") != "0":
        errors.append(f"{path.name}: Verification Exit Code must be 0")
    if not field(text, "Agent Attestation"):
        errors.append(f"{path.name}: Agent Attestation is required")
    for name in ("Started At", "Completed At"):
        try:
            datetime.fromisoformat(field(text, name).replace("Z", "+00:00"))
        except ValueError:
            errors.append(f"{path.name}: {name} must be ISO-8601")
    diff_snapshot = resolve_file(root, work, field(text, "Diff Snapshot"), errors, f"{path.name} Diff Snapshot")
    diff_sha = field(text, "Diff SHA256").lower()
    base, head = field(text, "Git Base").lower(), field(text, "Git Head").lower()
    if diff_snapshot and re.fullmatch(r"[0-9a-f]{40}", base) and re.fullmatch(r"[0-9a-f]{40}", head):
        result = subprocess.run(
            ["git", "diff", "--binary", "--no-ext-diff", base, head],
            cwd=root,
            text=True,
            capture_output=True,
            encoding="utf-8",
            errors="replace",
        )
        if result.returncode or file_sha(diff_snapshot) != diff_sha or diff_snapshot.read_text(encoding="utf-8", errors="replace") != result.stdout:
            errors.append(f"{path.name}: implementation diff does not match declared Git range")
    else:
        errors.append(f"{path.name}: Git Base/Head and Diff Snapshot must be resolved")
    return base, head, diff_sha


def validate(root: Path, work: Path, phase: str) -> list[str]:
    errors: list[str] = []
    report_path = work / TDD_REPORT
    ledger_path = work / TASK_LEDGER
    work_item_path = work / "WORK_ITEM.md"
    report = read(report_path)
    ledger = read(ledger_path)
    work_item = read(work_item_path)
    if not report:
        errors.append(f"missing or empty {TDD_REPORT}")
    if not ledger:
        errors.append(f"missing or empty {TASK_LEDGER}")
    if not work_item:
        errors.append("missing or empty WORK_ITEM.md")
    if errors:
        return errors
    if field(report, "TDD Plan Status").upper() != "READY":
        errors.append(f"{TDD_REPORT}: TDD Plan Status must be READY")
    if field(ledger, "Task Agent Plan Status").upper() != "READY":
        errors.append(f"{TASK_LEDGER}: Task Agent Plan Status must be READY")
    coverage = table(report, "Task Coverage", errors, TDD_REPORT)
    tasks = table(ledger, "Task Execution", errors, TASK_LEDGER)
    require_columns(coverage, ("Task ID", "Applicability", "Test Selector", "Status", "Rationale"), errors, TDD_REPORT)
    require_columns(tasks, ("Task ID", "Implementer Session", "Implementer Receipt", "Implementer Receipt SHA256", "Fresh Context", "Self Review", "Spec Review", "Quality Review", "Status"), errors, TASK_LEDGER)
    coverage_ids = [row.get("Task ID", "") for row in coverage]
    task_ids = [row.get("Task ID", "") for row in tasks]
    if len(coverage_ids) != len(set(coverage_ids)) or "" in coverage_ids:
        errors.append(f"{TDD_REPORT}: Task IDs must be unique and concrete")
    if len(task_ids) != len(set(task_ids)) or "" in task_ids:
        errors.append(f"{TASK_LEDGER}: Task IDs must be unique and concrete")
    if set(coverage_ids) != set(task_ids):
        errors.append("TDD task coverage and task-agent ledger must cover the same tasks")
    planned_tasks = work_item_tasks(work_item)
    if not planned_tasks:
        errors.append("WORK_ITEM.md must declare implementation tasks under Tasks / Vertical Slices")
    elif {value.upper() for value in task_ids} != planned_tasks:
        errors.append("TDD/Agent ledgers must exactly cover the Work Item implementation tasks")
    for row in coverage:
        applicability = row.get("Applicability", "").upper()
        if applicability not in {"REQUIRED", *ALLOWED_TDD_NA}:
            errors.append(f"{row.get('Task ID')}: unsupported TDD applicability {applicability or '<missing>'}")
        if applicability != "REQUIRED" and not row.get("Rationale", "").strip():
            errors.append(f"{row.get('Task ID')}: TDD N/A classification requires a rationale")
        if applicability != "REQUIRED":
            brief = resolve_file(
                root, work, f"task-briefs/{row.get('Task ID')}.md", errors,
                f"{row.get('Task ID')} TDD applicability brief",
            )
            if brief and f"TDD Applicability: {applicability}" not in read(brief):
                errors.append(f"{row.get('Task ID')}: task brief must declare TDD Applicability: {applicability}")
        expected_status = "PASS" if phase in {"accept", "integrate"} else "PLANNED"
        if row.get("Status", "").upper() != expected_status:
            errors.append(f"{row.get('Task ID')}: TDD status must be {expected_status}")
    if phase == "ready":
        for row in tasks:
            if row.get("Status", "").upper() != "PLANNED":
                errors.append(f"{row.get('Task ID')}: task-agent status must be PLANNED at ready")
        return errors

    if field(report, "TDD Decision").upper() != "PASS":
        errors.append(f"{TDD_REPORT}: TDD Decision must be PASS")
    if field(ledger, "Task Agent Decision").upper() != "PASS":
        errors.append(f"{TASK_LEDGER}: Task Agent Decision must be PASS")
    required_tasks = {
        row["Task ID"]: row["Test Selector"]
        for row in coverage
        if row.get("Applicability", "").upper() == "REQUIRED"
    }
    if required_tasks:
        validate_journal(root, work, report, required_tasks, errors)
    all_sessions: set[str] = set()
    for row in tasks:
        task_id = row.get("Task ID", "")
        implementer = row.get("Implementer Session", "")
        if implementer.upper() in PLACEHOLDERS or len(implementer) < 3:
            errors.append(f"{task_id}: Implementer Session must be concrete")
        if implementer in all_sessions:
            errors.append(f"{task_id}: Agent sessions must be globally unique across tasks and roles")
        all_sessions.add(implementer)
        implementer_base, implementer_head, implementer_diff = validate_implementer_receipt(
            root, work, task_id, implementer, row.get("Implementer Receipt", ""),
            row.get("Implementer Receipt SHA256", ""), errors
        )
        coverage_row = next((item for item in coverage if item.get("Task ID") == task_id), {})
        if coverage_row.get("Applicability", "").upper() == "DOCS_ONLY":
            receipt_path = resolve_file(root, work, row.get("Implementer Receipt", ""), [], "receipt")
            if receipt_path:
                receipt_text = read(receipt_path)
                base, head = field(receipt_text, "Git Base"), field(receipt_text, "Git Head")
                result = subprocess.run(
                    ["git", "diff", "--name-only", base, head], cwd=root,
                    text=True, capture_output=True, encoding="utf-8", errors="replace",
                )
                allowed = {".md", ".rst", ".txt"}
                changed = [Path(value) for value in result.stdout.splitlines() if value.strip()]
                if result.returncode or not changed or any(path.suffix.lower() not in allowed for path in changed):
                    errors.append(f"{task_id}: DOCS_ONLY is contradicted by the declared Git diff")
        if row.get("Fresh Context", "").upper() != "YES":
            errors.append(f"{task_id}: implementer Fresh Context must be YES")
        if row.get("Self Review", "").upper() != "PASS":
            errors.append(f"{task_id}: implementer Self Review must be PASS")
        if row.get("Status", "").upper() != "PASS":
            errors.append(f"{task_id}: task-agent status must be PASS")
        spec_session, spec_hash, spec_diff, spec_base, spec_head = validate_review(
            root, work, task_id, row.get("Spec Review", ""), "SPEC_COMPLIANCE", errors
        )
        quality_session, quality_hash, quality_diff, quality_base, quality_head = validate_review(
            root, work, task_id, row.get("Quality Review", ""), "CODE_QUALITY", errors
        )
        identities = {implementer, spec_session, quality_session}
        if "" in identities or len(identities) != 3:
            errors.append(f"{task_id}: implementer, spec reviewer and quality reviewer must be distinct")
        for reviewer in (spec_session, quality_session):
            if reviewer and reviewer in all_sessions:
                errors.append(f"{task_id}: Agent sessions must be globally unique across tasks and roles")
            all_sessions.add(reviewer)
        if spec_hash and quality_hash and spec_hash != quality_hash:
            errors.append(f"{task_id}: both reviews must bind the same spec snapshot")
        if spec_diff and quality_diff and spec_diff != quality_diff:
            errors.append(f"{task_id}: both reviews must bind the same final diff snapshot")
        for review_name, review_base, review_head, review_diff in (
            ("specification review", spec_base, spec_head, spec_diff),
            ("code-quality review", quality_base, quality_head, quality_diff),
        ):
            if (
                implementer_base and implementer_head and implementer_diff
                and (review_base, review_head, review_diff)
                != (implementer_base, implementer_head, implementer_diff)
            ):
                errors.append(
                    f"{task_id}: {review_name} must bind the implementer final Git range and diff"
                )
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--work-item", type=Path, required=True)
    parser.add_argument("--phase", choices=("ready", "accept", "integrate"), default="ready")
    args = parser.parse_args()
    root = args.root.resolve()
    work = args.work_item.resolve()
    errors = validate(root, work, args.phase)
    if errors:
        print("EXECUTION DISCIPLINE GATE: BLOCKED")
        for error in errors:
            print(f"- {error}")
        return 1
    print("EXECUTION DISCIPLINE GATE: PASS")
    print(f"Phase: {args.phase.upper()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

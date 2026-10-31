#!/usr/bin/env python3
"""Run tests with shell=False and append hash-chained RED/GREEN evidence."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys


SCHEMA = "ai-development-os.execution-event/v1"
STAGES = {"RED", "GREEN", "REFACTOR", "REGRESSION"}
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


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git_head(root: Path) -> str:
    result = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=root, text=True, capture_output=True
    )
    return result.stdout.strip() if result.returncode == 0 else "NON_GIT"


def manifest_sha(root: Path, paths: list[str], revision: str | None = None) -> str:
    entries = []
    for value in sorted(paths):
        if revision and revision != "NON_GIT":
            result = subprocess.run(["git", "show", f"{revision}:{value}"], cwd=root, capture_output=True)
            if result.returncode:
                raise ValueError(f"production path is absent from {revision}: {value}")
            digest = hashlib.sha256(result.stdout).hexdigest()
        else:
            path = (root / value).resolve()
            path.relative_to(root)
            if not path.is_file():
                raise ValueError(f"production path is missing: {value}")
            digest = sha(path)
        entries.append({"path": value, "sha256": digest})
    return hashlib.sha256(json.dumps(entries, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def load_events(path: Path) -> list[dict[str, object]]:
    if not path.is_file():
        return []
    events = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        try:
            event = json.loads(line)
        except json.JSONDecodeError as exc:
            raise ValueError(f"existing journal is corrupt at line {line_number}: {exc}") from exc
        if not isinstance(event, dict) or not event.get("event_hash"):
            raise ValueError(f"existing journal event {line_number} is invalid")
        events.append(event)
    return events


def append_event(path: Path, event: dict[str, object]) -> None:
    unsigned = dict(event)
    unsigned.pop("event_hash", None)
    canonical = json.dumps(unsigned, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    event["event_hash"] = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8", newline="\n") as handle:
        handle.write(json.dumps(event, ensure_ascii=False, sort_keys=True) + "\n")
        handle.flush()


def record_test(args: argparse.Namespace) -> int:
    root = args.root.resolve()
    work = args.work_item.resolve()
    try:
        work.relative_to(root)
    except ValueError:
        print("ERROR: Work Item must remain inside repository root", file=sys.stderr)
        return 2
    command = list(args.command)
    if command and command[0] == "--":
        command = command[1:]
    if not command:
        print("ERROR: a test command is required after --", file=sys.stderr)
        return 2
    stage = args.stage.upper()
    head = git_head(root)
    journal = work / "EXECUTION_JOURNAL.jsonl"
    try:
        existing = load_events(journal)
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 3
    sequence = len(existing) + 1
    log_dir = work / "execution-logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    log = log_dir / f"{sequence:03d}-{args.task}-{stage}.log"
    result = subprocess.run(command, cwd=root, text=True, capture_output=True, shell=False)
    output = result.stdout + result.stderr
    log.write_text(output, encoding="utf-8")
    if stage == "RED":
        if result.returncode == 0:
            classification = "UNEXPECTED_PASS"
            accepted = False
        elif has_invalid_red_failure(output):
            classification = "UNEXPECTED_FAILURE"
            accepted = False
        elif not args.expected_signature or args.expected_signature not in output:
            classification = "UNEXPECTED_FAILURE"
            accepted = False
        else:
            classification = "EXPECTED_ASSERTION_FAILURE"
            accepted = True
    else:
        classification = "PASS" if result.returncode == 0 else "FAIL"
        accepted = result.returncode == 0
    test_source = ""
    test_source_sha = ""
    production_paths = list(args.production_path or [])
    production_baseline = ""
    production_snapshot = ""
    if args.test_source:
        source = (root / args.test_source).resolve()
        try:
            source.relative_to(root)
        except ValueError:
            print("ERROR: test source escapes repository root", file=sys.stderr)
            return 2
        if not source.is_file():
            print("ERROR: test source is missing", file=sys.stderr)
            return 2
        test_source, test_source_sha = args.test_source, sha(source)
    if production_paths:
        try:
            production_snapshot = manifest_sha(root, production_paths)
            production_baseline = manifest_sha(root, production_paths, args.production_baseline or head)
        except (ValueError, OSError) as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            return 2
    event: dict[str, object] = {
        "schema": SCHEMA,
        "sequence": sequence,
        "task_id": args.task,
        "stage": stage,
        "selector": args.selector,
        "command": command,
        "exit_code": result.returncode,
        "classification": classification,
        "expected_signature": args.expected_signature or "",
        "log_path": log.relative_to(root).as_posix(),
        "log_sha256": sha(log),
        "previous_event_hash": str(existing[-1]["event_hash"]) if existing else "GENESIS",
        "git_head": head,
        "timestamp_utc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "test_source": test_source,
        "test_source_sha256": test_source_sha,
        "production_paths": production_paths,
        "production_baseline_sha256": production_baseline,
        "production_snapshot_sha256": production_snapshot,
    }
    append_event(journal, event)
    print(f"Recorded {stage} event {sequence}: {classification}")
    print(f"Journal: {journal}")
    print(f"Log: {log}")
    return 0 if accepted else 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--work-item", type=Path, required=True)
    sub = parser.add_subparsers(dest="command_name", required=True)
    record = sub.add_parser("record-test")
    record.add_argument("--task", required=True)
    record.add_argument("--stage", required=True, choices=sorted(STAGES))
    record.add_argument("--selector", required=True)
    record.add_argument("--expected-signature")
    record.add_argument("--test-source")
    record.add_argument("--production-path", action="append")
    record.add_argument("--production-baseline")
    record.add_argument("command", nargs=argparse.REMAINDER)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    if args.command_name == "record-test":
        return record_test(args)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())

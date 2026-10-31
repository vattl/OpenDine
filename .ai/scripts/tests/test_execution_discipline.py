from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parents[1]
VALIDATOR = SCRIPTS / "validate_execution_discipline.py"
WORKTREE_VALIDATOR = SCRIPTS / "validate_worktree_readiness.py"
DIAGNOSIS_VALIDATOR = SCRIPTS / "validate_workflow_diagnosis.py"
JOURNAL = SCRIPTS / "execution_journal.py"
PREFLIGHT = SCRIPTS / "worktree_preflight.py"
DIAGNOSE = SCRIPTS / "workflow_diagnose.py"


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def init_repo(root: Path, *, unicode_diff: bool = False) -> tuple[str, str]:
    subprocess.run(["git", "init", "-q"], cwd=root, check=True)
    subprocess.run(["git", "config", "user.email", "test@example.invalid"], cwd=root, check=True)
    subprocess.run(["git", "config", "user.name", "Test"], cwd=root, check=True)
    write(root / "src" / "gate.py", "ENFORCE = False\n")
    write(root / "tests" / "test_gate.py", "def test_missing_evidence():\n    assert False, 'missing evidence'\n")
    subprocess.run(["git", "add", "."], cwd=root, check=True)
    subprocess.run(["git", "commit", "-qm", "fixture baseline"], cwd=root, check=True)
    base = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=root, text=True, capture_output=True, check=True
    ).stdout.strip()
    final_source = "ENFORCE = True  # 中文 🚀\n" if unicode_diff else "ENFORCE = True\n"
    write(root / "src" / "gate.py", final_source)
    subprocess.run(["git", "add", "src/gate.py"], cwd=root, check=True)
    subprocess.run(["git", "commit", "-qm", "fixture implementation"], cwd=root, check=True)
    head = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=root, text=True, capture_output=True, check=True
    ).stdout.strip()
    return base, head


def manifest_sha(root: Path, paths: list[str], *, baseline: bool = False, revision: str = "") -> str:
    entries = []
    for value in sorted(paths):
        if baseline:
            result = subprocess.run(
                ["git", "show", f"{revision}:{value}"], cwd=root, capture_output=True, check=True
            )
            digest = hashlib.sha256(result.stdout).hexdigest()
        else:
            digest = sha(root / value)
        entries.append({"path": value, "sha256": digest})
    canonical = json.dumps(entries, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def run(script: Path, root: Path, work: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(script), "--root", str(root), "--work-item", str(work), *args],
        text=True,
        capture_output=True,
    )


def journal_event(
    previous_hash: str,
    *,
    sequence: int,
    task: str,
    stage: str,
    selector: str,
    exit_code: int,
    classification: str,
    log_path: str,
    log_sha256: str,
    git_head: str,
    test_source: str,
    test_source_sha256: str,
    production_paths: list[str],
    production_baseline_sha256: str,
    production_snapshot_sha256: str,
) -> dict[str, object]:
    event: dict[str, object] = {
        "schema": "ai-development-os.execution-event/v1",
        "sequence": sequence,
        "task_id": task,
        "stage": stage,
        "selector": selector,
        "command": ["python", "-m", "unittest", selector],
        "exit_code": exit_code,
        "classification": classification,
        "expected_signature": "AssertionError" if stage == "RED" else "",
        "log_path": log_path,
        "log_sha256": log_sha256,
        "previous_event_hash": previous_hash,
        "git_head": git_head,
        "timestamp_utc": f"2026-10-29T00:00:0{sequence}Z",
        "test_source": test_source,
        "test_source_sha256": test_source_sha256,
        "production_paths": production_paths,
        "production_baseline_sha256": production_baseline_sha256,
        "production_snapshot_sha256": production_snapshot_sha256,
    }
    canonical = json.dumps(event, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    event["event_hash"] = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
    return event


def make_valid_execution_evidence(
    root: Path, work: Path, *, unicode_diff: bool = False
) -> None:
    base, head = init_repo(root, unicode_diff=unicode_diff)
    write(work / "WORK_ITEM.md", "# Work\n\n## Tasks / Vertical Slices\n- [ ] T01 strict gate\n")
    task_brief = work / "task-briefs" / "T01.md"
    write(task_brief, "# T01\n\nReject missing execution evidence.\n")
    logs = work / "execution-logs"
    red = logs / "001-T01-RED.log"
    green = logs / "002-T01-GREEN.log"
    refactor = logs / "003-T01-REFACTOR.log"
    regression = logs / "004-T01-REGRESSION.log"
    write(red, "AssertionError: expected workflow gate to reject missing evidence\n")
    write(green, "OK\n")
    write(refactor, "OK\n")
    write(regression, "OK (120 tests)\n")

    previous = "GENESIS"
    events = []
    production_paths = ["src/gate.py"]
    baseline_sha = manifest_sha(root, production_paths, baseline=True, revision=base)
    final_sha = manifest_sha(root, production_paths)
    test_source = "tests/test_gate.py"
    for sequence, stage, code, classification, path in (
        (1, "RED", 1, "EXPECTED_ASSERTION_FAILURE", red),
        (2, "GREEN", 0, "PASS", green),
        (3, "REFACTOR", 0, "PASS", refactor),
        (4, "REGRESSION", 0, "PASS", regression),
    ):
        event = journal_event(
            previous,
            sequence=sequence,
            task="T01",
            stage=stage,
            selector="tests.test_gate.GateTests.test_missing_evidence",
            exit_code=code,
            classification=classification,
            log_path=path.relative_to(root).as_posix(),
            log_sha256=sha(path),
            git_head=base if stage == "RED" else head,
            test_source=test_source,
            test_source_sha256=sha(root / test_source),
            production_paths=production_paths,
            production_baseline_sha256=baseline_sha,
            production_snapshot_sha256=baseline_sha if stage == "RED" else final_sha,
        )
        previous = str(event["event_hash"])
        events.append(event)
    journal = work / "EXECUTION_JOURNAL.jsonl"
    write(journal, "".join(json.dumps(event, ensure_ascii=False, sort_keys=True) + "\n" for event in events))
    write(
        work / "TDD_CYCLE_REPORT.md",
        "TDD Plan Status: READY\nTDD Decision: PASS\nBehavior Change: YES\n"
        f"Execution Journal: {journal.relative_to(root).as_posix()}\n"
        f"Execution Journal SHA256: {sha(journal)}\n\n"
        "## Task Coverage\n"
        "| Task ID | Applicability | Test Selector | Status | Rationale |\n"
        "|---|---|---|---|---|\n"
        "| T01 | REQUIRED | tests.test_gate.GateTests.test_missing_evidence | PASS | behavior change |\n",
    )

    spec = work / "reviews" / "T01-spec.md"
    quality = work / "reviews" / "T01-quality.md"
    spec_snapshot = work / "snapshots" / "T01-spec.txt"
    diff_snapshot = work / "snapshots" / "T01-diff.patch"
    write(spec_snapshot, "AC-01 reject missing evidence\n")
    diff = subprocess.run(
        ["git", "diff", "--binary", "--no-ext-diff", base, head, "--", "src/gate.py"],
        cwd=root,
        text=True,
        capture_output=True,
        check=True,
        encoding="utf-8",
        errors="replace",
    ).stdout
    write(diff_snapshot, diff)
    spec_hash = sha(spec_snapshot)
    diff_hash = sha(diff_snapshot)
    dispatch_dir = root / ".ai-runtime" / "agent-dispatch"
    def dispatch(role: str, session: str) -> Path:
        target = dispatch_dir / f"T01-{role.lower()}.md"
        write(target, f"Receipt Authority: BUILTIN_ORCHESTRATOR\nReceipt ID: receipt-{role.lower()}\nTask ID: T01\nRole: {role}\nSession ID: {session}\nProvider / Model: builtin / gpt-test\nContext Mode: FRESH\nTask Brief SHA256: {sha(task_brief)}\nIssued At: 2026-10-29T00:00:00Z\n")
        return target
    implementer_dispatch = dispatch("IMPLEMENTER", "implementer-session-01")
    spec_dispatch = dispatch("SPEC_COMPLIANCE", "spec-session-01")
    quality_dispatch = dispatch("CODE_QUALITY", "quality-session-01")
    write(
        spec,
        "Task ID: T01\nReview Type: SPEC_COMPLIANCE\nReviewer Session: spec-session-01\n"
        "Provider / Model: builtin / gpt-test\n"
        f"Dispatch Receipt: {spec_dispatch.relative_to(root).as_posix()}\nDispatch Receipt SHA256: {sha(spec_dispatch)}\n"
        "Fresh Context: YES\nRead Only: YES\nReview Decision: PASS\nOpen Critical: 0\nOpen High: 0\n"
        f"Diff Evidence Mode: GIT_RANGE\nGit Base: {base}\nGit Head: {head}\n"
        f"Spec Snapshot: {spec_snapshot.relative_to(root).as_posix()}\nSpec SHA256: {spec_hash}\n"
        f"Diff Snapshot: {diff_snapshot.relative_to(root).as_posix()}\nDiff SHA256: {diff_hash}\n",
    )
    write(
        quality,
        "Task ID: T01\nReview Type: CODE_QUALITY\nReviewer Session: quality-session-01\n"
        "Provider / Model: builtin / gpt-test\n"
        f"Dispatch Receipt: {quality_dispatch.relative_to(root).as_posix()}\nDispatch Receipt SHA256: {sha(quality_dispatch)}\n"
        "Fresh Context: YES\nRead Only: YES\nReview Decision: PASS\nOpen Critical: 0\nOpen High: 0\n"
        f"Diff Evidence Mode: GIT_RANGE\nGit Base: {base}\nGit Head: {head}\n"
        f"Spec Snapshot: {spec_snapshot.relative_to(root).as_posix()}\nSpec SHA256: {spec_hash}\n"
        f"Diff Snapshot: {diff_snapshot.relative_to(root).as_posix()}\nDiff SHA256: {diff_hash}\n",
    )
    write(
        work / "TASK_AGENT_LEDGER.md",
        "Task Agent Plan Status: READY\nTask Agent Decision: PASS\n\n"
        "## Task Execution\n"
        "| Task ID | Implementer Session | Implementer Receipt | Implementer Receipt SHA256 | Fresh Context | Self Review | Spec Review | Quality Review | Status |\n"
        "|---|---|---|---|---|---|---|---|---|\n"
        "RECEIPT_ROW\n",
    )
    receipt = work / "receipts" / "T01-implementer.md"
    write(
        receipt,
        "Receipt Schema: ai-development-os.task-implementation-receipt/v1\n"
        "Task ID: T01\nAgent Role: IMPLEMENTER\nAgent Session: implementer-session-01\n"
        "Provider / Model: builtin / gpt-test\nContext Mode: FRESH\n"
        f"Dispatch Receipt: {implementer_dispatch.relative_to(root).as_posix()}\nDispatch Receipt SHA256: {sha(implementer_dispatch)}\n"
        "Started At: 2026-10-29T00:00:00Z\nCompleted At: 2026-10-29T00:10:00Z\n"
        f"Task Brief: {task_brief.relative_to(root).as_posix()}\nTask Brief SHA256: {sha(task_brief)}\n"
        f"Git Base: {base}\nGit Head: {head}\n"
        f"Diff Snapshot: {diff_snapshot.relative_to(root).as_posix()}\nDiff SHA256: {diff_hash}\n"
        "Verification Command: python -m unittest tests.test_gate\nVerification Exit Code: 0\n"
        "Agent Attestation: I executed this task in the declared fresh session and report this evidence truthfully.\n",
    )
    ledger = work / "TASK_AGENT_LEDGER.md"
    write(
        ledger,
        ledger.read_text(encoding="utf-8").replace(
            "RECEIPT_ROW",
            f"| T01 | implementer-session-01 | {receipt.relative_to(root).as_posix()} | {sha(receipt)} | YES | PASS | {spec.relative_to(root).as_posix()} | {quality.relative_to(root).as_posix()} | PASS |",
        ),
    )


class ExecutionDisciplineTests(unittest.TestCase):
    def test_accepts_valid_red_green_and_distinct_double_review(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "docs" / "work-items" / "WI-TEST"
            make_valid_execution_evidence(root, work)
            result = run(VALIDATOR, root, work, "--phase", "accept")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("EXECUTION DISCIPLINE GATE: PASS", result.stdout)

    def test_accepts_utf8_git_diff_on_windows_locale(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "docs" / "work-items" / "WI-TEST"
            make_valid_execution_evidence(root, work, unicode_diff=True)

            result = run(VALIDATOR, root, work, "--phase", "accept")

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("EXECUTION DISCIPLINE GATE: PASS", result.stdout)

    def test_rejects_reviews_bound_to_a_different_range_than_implementer(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "docs" / "work-items" / "WI-TEST"
            make_valid_execution_evidence(root, work)
            implementation_head = subprocess.run(
                ["git", "rev-parse", "HEAD"], cwd=root, text=True,
                capture_output=True, check=True,
            ).stdout.strip()
            write(root / "review-only.txt", "different review range\n")
            subprocess.run(["git", "add", "review-only.txt"], cwd=root, check=True)
            subprocess.run(["git", "commit", "-qm", "review-only commit"], cwd=root, check=True)
            review_head = subprocess.run(
                ["git", "rev-parse", "HEAD"], cwd=root, text=True,
                capture_output=True, check=True,
            ).stdout.strip()
            snapshot = work / "snapshots" / "T01-review-only.patch"
            diff = subprocess.run(
                ["git", "diff", "--binary", "--no-ext-diff", implementation_head, review_head],
                cwd=root, text=True, capture_output=True, check=True,
                encoding="utf-8", errors="replace",
            ).stdout
            write(snapshot, diff)
            for name in ("T01-spec.md", "T01-quality.md"):
                review = work / "reviews" / name
                text = review.read_text(encoding="utf-8")
                text = re.sub(r"(?m)^Git Base: [0-9a-f]{40}$", f"Git Base: {implementation_head}", text)
                text = re.sub(r"(?m)^Git Head: [0-9a-f]{40}$", f"Git Head: {review_head}", text)
                text = re.sub(r"(?m)^Diff Snapshot: .+$", f"Diff Snapshot: {snapshot.relative_to(root).as_posix()}", text)
                text = re.sub(r"(?m)^Diff SHA256: [0-9a-f]{64}$", f"Diff SHA256: {sha(snapshot)}", text)
                write(review, text)

            result = run(VALIDATOR, root, work, "--phase", "accept")

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("implementer final Git range and diff", result.stdout)

    def test_rejects_dispatch_receipt_with_wrong_task_brief_hash(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "docs" / "work-items" / "WI-TEST"
            make_valid_execution_evidence(root, work)
            dispatch = root / ".ai-runtime" / "agent-dispatch" / "T01-implementer.md"
            write(
                dispatch,
                dispatch.read_text(encoding="utf-8").replace(
                    f"Task Brief SHA256: {sha(work / 'task-briefs' / 'T01.md')}",
                    f"Task Brief SHA256: {'0' * 64}",
                ),
            )
            receipt = work / "receipts" / "T01-implementer.md"
            receipt_text = receipt.read_text(encoding="utf-8")
            receipt_text = re.sub(
                r"(?m)^Dispatch Receipt SHA256: [0-9a-f]{64}$",
                f"Dispatch Receipt SHA256: {sha(dispatch)}",
                receipt_text,
            )
            write(receipt, receipt_text)
            ledger = work / "TASK_AGENT_LEDGER.md"
            write(
                ledger,
                re.sub(
                    r"(?m)(\| T01 \| implementer-session-01 \| [^|]+ \|) [0-9a-f]{64} (\|)",
                    rf"\1 {sha(receipt)} \2",
                    ledger.read_text(encoding="utf-8"),
                ),
            )

            result = run(VALIDATOR, root, work, "--phase", "accept")

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Task Brief SHA256", result.stdout)

    def test_rejects_dispatch_provider_that_disagrees_with_implementer(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "docs" / "work-items" / "WI-TEST"
            make_valid_execution_evidence(root, work)
            dispatch = root / ".ai-runtime" / "agent-dispatch" / "T01-implementer.md"
            write(
                dispatch,
                dispatch.read_text(encoding="utf-8").replace(
                    "Provider / Model: builtin / gpt-test",
                    "Provider / Model: external / other-model",
                ),
            )
            receipt = work / "receipts" / "T01-implementer.md"
            receipt_text = re.sub(
                r"(?m)^Dispatch Receipt SHA256: [0-9a-f]{64}$",
                f"Dispatch Receipt SHA256: {sha(dispatch)}",
                receipt.read_text(encoding="utf-8"),
            )
            write(receipt, receipt_text)
            ledger = work / "TASK_AGENT_LEDGER.md"
            write(
                ledger,
                re.sub(
                    r"(?m)(\| T01 \| implementer-session-01 \| [^|]+ \|) [0-9a-f]{64} (\|)",
                    rf"\1 {sha(receipt)} \2",
                    ledger.read_text(encoding="utf-8"),
                ),
            )

            result = run(VALIDATOR, root, work, "--phase", "accept")

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Provider / Model", result.stdout)

    def test_rejects_nonzero_implementation_verification_exit_code(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "docs" / "work-items" / "WI-TEST"
            make_valid_execution_evidence(root, work)
            receipt = work / "receipts" / "T01-implementer.md"
            write(
                receipt,
                receipt.read_text(encoding="utf-8").replace(
                    "Verification Exit Code: 0", "Verification Exit Code: 1"
                ),
            )
            ledger = work / "TASK_AGENT_LEDGER.md"
            write(
                ledger,
                re.sub(
                    r"(?m)(\| T01 \| implementer-session-01 \| [^|]+ \|) [0-9a-f]{64} (\|)",
                    rf"\1 {sha(receipt)} \2",
                    ledger.read_text(encoding="utf-8"),
                ),
            )

            result = run(VALIDATOR, root, work, "--phase", "accept")

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Verification Exit Code", result.stdout)


class ExecutionJournalTests(unittest.TestCase):
    def test_records_observed_red_and_green_with_hash_chain(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "docs" / "work-items" / "WI-TEST"
            red = subprocess.run(
                [
                    sys.executable, str(JOURNAL), "--root", str(root), "--work-item", str(work),
                    "record-test", "--task", "T01", "--stage", "RED", "--selector", "gate.test_missing",
                    "--expected-signature", "AssertionError", "--", sys.executable, "-c",
                    "raise AssertionError('missing behavior')",
                ],
                text=True, capture_output=True,
            )
            self.assertEqual(red.returncode, 0, red.stdout + red.stderr)
            green = subprocess.run(
                [
                    sys.executable, str(JOURNAL), "--root", str(root), "--work-item", str(work),
                    "record-test", "--task", "T01", "--stage", "GREEN", "--selector", "gate.test_missing",
                    "--", sys.executable, "-c", "print('OK')",
                ],
                text=True, capture_output=True,
            )
            self.assertEqual(green.returncode, 0, green.stdout + green.stderr)
            events = [json.loads(line) for line in (work / "EXECUTION_JOURNAL.jsonl").read_text(encoding="utf-8").splitlines()]
            self.assertEqual([event["stage"] for event in events], ["RED", "GREEN"])
            self.assertEqual(events[0]["classification"], "EXPECTED_ASSERTION_FAILURE")
            self.assertEqual(events[1]["previous_event_hash"], events[0]["event_hash"])

    def test_rejects_passing_red_and_records_unexpected_pass(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "docs" / "work-items" / "WI-TEST"
            result = subprocess.run(
                [
                    sys.executable, str(JOURNAL), "--root", str(root), "--work-item", str(work),
                    "record-test", "--task", "T01", "--stage", "RED", "--selector", "gate.test_missing",
                    "--expected-signature", "AssertionError", "--", sys.executable, "-c", "print('already green')",
                ],
                text=True, capture_output=True,
            )
            self.assertNotEqual(result.returncode, 0)
            event = json.loads((work / "EXECUTION_JOURNAL.jsonl").read_text(encoding="utf-8").strip())
            self.assertEqual(event["classification"], "UNEXPECTED_PASS")

    def test_rejects_red_that_is_not_expected_assertion_failure(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "docs" / "work-items" / "WI-TEST"
            make_valid_execution_evidence(root, work)
            journal = work / "EXECUTION_JOURNAL.jsonl"
            text = journal.read_text(encoding="utf-8").replace(
                '"classification": "EXPECTED_ASSERTION_FAILURE"',
                '"classification": "SYNTAX_ERROR"',
            )
            write(journal, text)
            report = work / "TDD_CYCLE_REPORT.md"
            write(report, report.read_text(encoding="utf-8").replace(
                next(line for line in report.read_text(encoding="utf-8").splitlines() if line.startswith("Execution Journal SHA256:")),
                f"Execution Journal SHA256: {sha(journal)}",
            ))
            result = run(VALIDATOR, root, work, "--phase", "accept")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("EXPECTED_ASSERTION_FAILURE", result.stdout)

    def test_journal_rejects_missing_script_even_when_signature_matches(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "docs" / "work-items" / "WI-TEST"
            missing = "tests/missing_behavior_test.py"

            result = subprocess.run(
                [
                    sys.executable,
                    str(JOURNAL),
                    "--root",
                    str(root),
                    "--work-item",
                    str(work),
                    "record-test",
                    "--task",
                    "T01",
                    "--stage",
                    "RED",
                    "--selector",
                    "gate.test_missing",
                    "--expected-signature",
                    "missing_behavior_test.py",
                    "--",
                    sys.executable,
                    missing,
                ],
                text=True,
                capture_output=True,
            )

            self.assertNotEqual(result.returncode, 0)
            event = json.loads(
                (work / "EXECUTION_JOURNAL.jsonl").read_text(encoding="utf-8").strip()
            )
            self.assertEqual(event["classification"], "UNEXPECTED_FAILURE")

    def test_journal_rejects_timeout_even_when_signature_matches(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "docs" / "work-items" / "WI-TEST"
            result = subprocess.run(
                [
                    sys.executable, str(JOURNAL), "--root", str(root), "--work-item", str(work),
                    "record-test", "--task", "T01", "--stage", "RED", "--selector", "gate.timeout",
                    "--expected-signature", "TimeoutError", "--", sys.executable, "-c",
                    "raise TimeoutError('service timed out')",
                ],
                text=True, capture_output=True,
            )
            self.assertNotEqual(result.returncode, 0)
            event = json.loads((work / "EXECUTION_JOURNAL.jsonl").read_text(encoding="utf-8").strip())
            self.assertEqual(event["classification"], "UNEXPECTED_FAILURE")

    def test_validator_rejects_environment_failure_hidden_as_expected_red(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "docs" / "work-items" / "WI-TEST"
            make_valid_execution_evidence(root, work)
            red_log = work / "execution-logs" / "001-T01-RED.log"
            write(
                red_log,
                "AssertionError: expected signature\n"
                "python: can't open file 'missing_test.py': No such file or directory\n",
            )
            journal = work / "EXECUTION_JOURNAL.jsonl"
            events = [
                json.loads(line)
                for line in journal.read_text(encoding="utf-8").splitlines()
            ]
            previous = "GENESIS"
            for event in events:
                if event["stage"] == "RED":
                    event["log_sha256"] = sha(red_log)
                event["previous_event_hash"] = previous
                unsigned = dict(event)
                unsigned.pop("event_hash", None)
                event["event_hash"] = hashlib.sha256(
                    json.dumps(
                        unsigned,
                        ensure_ascii=False,
                        sort_keys=True,
                        separators=(",", ":"),
                    ).encode("utf-8")
                ).hexdigest()
                previous = event["event_hash"]
            write(
                journal,
                "".join(
                    json.dumps(event, ensure_ascii=False, sort_keys=True) + "\n"
                    for event in events
                ),
            )
            report = work / "TDD_CYCLE_REPORT.md"
            old_hash = next(
                line
                for line in report.read_text(encoding="utf-8").splitlines()
                if line.startswith("Execution Journal SHA256:")
            )
            write(
                report,
                report.read_text(encoding="utf-8").replace(
                    old_hash, f"Execution Journal SHA256: {sha(journal)}"
                ),
            )

            result = run(VALIDATOR, root, work, "--phase", "accept")

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("invalid failure mode", result.stdout)

    def test_validator_rejects_dependency_resolution_failure_hidden_as_red(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "docs" / "work-items" / "WI-TEST"
            make_valid_execution_evidence(root, work)
            red_log = work / "execution-logs" / "001-T01-RED.log"
            write(red_log, "AssertionError: expected signature\ndependency resolution failed for package\n")
            journal = work / "EXECUTION_JOURNAL.jsonl"
            events = [json.loads(line) for line in journal.read_text(encoding="utf-8").splitlines()]
            previous = "GENESIS"
            for event in events:
                if event["stage"] == "RED":
                    event["log_sha256"] = sha(red_log)
                event["previous_event_hash"] = previous
                unsigned = dict(event)
                unsigned.pop("event_hash", None)
                event["event_hash"] = hashlib.sha256(
                    json.dumps(unsigned, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
                ).hexdigest()
                previous = event["event_hash"]
            write(journal, "".join(json.dumps(event, ensure_ascii=False, sort_keys=True) + "\n" for event in events))
            report = work / "TDD_CYCLE_REPORT.md"
            write(report, re.sub(
                r"(?m)^Execution Journal SHA256: [0-9a-f]{64}$",
                f"Execution Journal SHA256: {sha(journal)}",
                report.read_text(encoding="utf-8"),
            ))

            result = run(VALIDATOR, root, work, "--phase", "accept")

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("invalid failure mode", result.stdout)

    def test_rejects_green_with_different_selector(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "docs" / "work-items" / "WI-TEST"
            make_valid_execution_evidence(root, work)
            journal = work / "EXECUTION_JOURNAL.jsonl"
            lines = journal.read_text(encoding="utf-8").splitlines()
            event = json.loads(lines[1])
            event["selector"] = "tests.other.OtherTests.test_unrelated"
            event_without_hash = dict(event)
            event_without_hash.pop("event_hash")
            event["event_hash"] = hashlib.sha256(
                json.dumps(event_without_hash, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
            ).hexdigest()
            lines[1] = json.dumps(event, ensure_ascii=False, sort_keys=True)
            write(journal, "\n".join(lines) + "\n")
            report = work / "TDD_CYCLE_REPORT.md"
            old = next(line for line in report.read_text(encoding="utf-8").splitlines() if line.startswith("Execution Journal SHA256:"))
            write(report, report.read_text(encoding="utf-8").replace(old, f"Execution Journal SHA256: {sha(journal)}"))
            result = run(VALIDATOR, root, work, "--phase", "accept")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("same selector", result.stdout)

    def test_rejects_reused_implementer_and_reviewer_identity(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "docs" / "work-items" / "WI-TEST"
            make_valid_execution_evidence(root, work)
            ledger = work / "TASK_AGENT_LEDGER.md"
            write(
                ledger,
                ledger.read_text(encoding="utf-8").replace(
                    "| T01 | implementer-session-01 |",
                    "| T01 | spec-session-01 |",
                ),
            )
            result = run(VALIDATOR, root, work, "--phase", "accept")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("distinct", result.stdout.lower())

    def test_rejects_missing_fresh_implementer_receipt(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "docs" / "work-items" / "WI-TEST"
            make_valid_execution_evidence(root, work)
            (work / "receipts" / "T01-implementer.md").unlink()
            result = run(VALIDATOR, root, work, "--phase", "accept")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Implementer Receipt", result.stdout)

    def test_rejects_task_ledger_that_omits_planned_work_item_task(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "docs" / "work-items" / "WI-TEST"
            make_valid_execution_evidence(root, work)
            write(
                work / "WORK_ITEM.md",
                "# Work\n\n## Tasks / Vertical Slices\n- [ ] T01 strict gate\n- [ ] T02 omitted task\n",
            )
            result = run(VALIDATOR, root, work, "--phase", "accept")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Work Item implementation tasks", result.stdout)

    def test_ready_requires_plans_but_not_completed_reviews(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "docs" / "work-items" / "WI-TEST"
            write(work / "WORK_ITEM.md", "# Work\n\n## Tasks / Vertical Slices\n- [ ] T01 planned\n")
            write(
                work / "TDD_CYCLE_REPORT.md",
                "TDD Plan Status: READY\nTDD Decision: PENDING\nBehavior Change: YES\n\n"
                "## Task Coverage\n| Task ID | Applicability | Test Selector | Status | Rationale |\n"
                "|---|---|---|---|---|\n| T01 | REQUIRED | tests.test_one | PLANNED | behavior |\n",
            )
            write(
                work / "TASK_AGENT_LEDGER.md",
                "Task Agent Plan Status: READY\nTask Agent Decision: PENDING\n\n"
                "## Task Execution\n| Task ID | Implementer Session | Implementer Receipt | Implementer Receipt SHA256 | Fresh Context | Self Review | Spec Review | Quality Review | Status |\n"
                "|---|---|---|---|---|---|---|---|---|\n"
                "| T01 | PLANNED | PLANNED | PLANNED | PLANNED | PENDING | PENDING | PENDING | PLANNED |\n",
            )
            result = run(VALIDATOR, root, work, "--phase", "ready")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


class WorktreeReadinessTests(unittest.TestCase):
    def init_repo(self, root: Path) -> str:
        subprocess.run(["git", "init", "-q"], cwd=root, check=True)
        subprocess.run(["git", "config", "user.email", "test@example.invalid"], cwd=root, check=True)
        subprocess.run(["git", "config", "user.name", "Test"], cwd=root, check=True)
        write(root / "README.md", "fixture\n")
        write(root / ".ai" / "config" / "worktree-command-profile.json", json.dumps({
            "schema": "ai-development-os.worktree-command-profile/v1",
            "setup": None,
            "baseline": [sys.executable, "-c", "print('baseline ok')"],
        }))
        subprocess.run(["git", "add", "."], cwd=root, check=True)
        subprocess.run(["git", "commit", "-qm", "fixture"], cwd=root, check=True)
        return subprocess.run(["git", "rev-parse", "HEAD"], cwd=root, text=True, capture_output=True, check=True).stdout.strip()

    def test_rejects_primary_checkout_claiming_linked_worktree(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            head = self.init_repo(root)
            work = root / "docs" / "work-items" / "WI-TEST"
            git_dir = subprocess.run(["git", "rev-parse", "--absolute-git-dir"], cwd=root, text=True, capture_output=True, check=True).stdout.strip()
            common = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"], cwd=root, text=True, capture_output=True, check=True).stdout.strip()
            branch = subprocess.run(["git", "branch", "--show-current"], cwd=root, text=True, capture_output=True, check=True).stdout.strip()
            write(
                work / "WORKTREE_READINESS.md",
                f"Readiness Decision: PASS\nRepository Root: {root}\nWorktree Path: {root}\n"
                f"Isolation Mode: LINKED_WORKTREE\nGit Dir: {git_dir}\nCommon Git Dir: {common}\n"
                f"Superproject: NONE\nBranch: {branch}\nHead Commit: {head}\n"
                "Worktree Mapping: VERIFIED\nRepository Local: NO\nIgnore Check: NOT_APPLICABLE\n"
                "Setup Result: NOT_APPLICABLE\nBaseline Result: PASS\nClean Baseline: YES\n",
            )
            result = run(WORKTREE_VALIDATOR, root, work)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("not a linked worktree", result.stdout.lower())

    def test_preflight_generates_live_primary_checkout_evidence_with_explicit_exception(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            baseline = self.init_repo(root)
            subprocess.run(["git", "switch", "-c", "feature/preflight"], cwd=root, check=True, capture_output=True)
            work = root / "docs" / "work-items" / "WI-TEST"
            authorization = root / "docs" / "primary-checkout-authorization.md"
            write(authorization, f"Authorization Status: APPROVED\nScope: WI-TEST\nAuthorized Mode: PRIMARY_CHECKOUT\nAuthorization Source: PROJECT_POLICY\nAuthorized Baseline Commit: {baseline}\n")
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            subprocess.run(["git", "commit", "-qm", "authorize primary preflight"], cwd=root, check=True)
            result = subprocess.run(
                [
                    sys.executable, str(PREFLIGHT), "--root", str(root), "--work-item", str(work),
                    "--allow-primary-checkout", "--primary-exception-reason", "serial bootstrap task",
                    "--authorization-evidence", str(authorization),
                    "--command-profile", str(root / ".ai" / "config" / "worktree-command-profile.json"),
                ],
                text=True, capture_output=True,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            validation = run(WORKTREE_VALIDATOR, root, work)
            self.assertEqual(validation.returncode, 0, validation.stdout + validation.stderr)

            baseline_log = work / "preflight-logs" / "baseline.log"
            write(baseline_log, "tampered\n")
            tampered = run(WORKTREE_VALIDATOR, root, work)
            self.assertNotEqual(tampered.returncode, 0)
            self.assertIn("Baseline Log SHA256 mismatch", tampered.stdout)

    def test_validator_rejects_commands_that_do_not_match_hashed_profile(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            baseline = self.init_repo(root)
            subprocess.run(["git", "switch", "-c", "feature/preflight"], cwd=root, check=True, capture_output=True)
            work = root / "docs" / "work-items" / "WI-TEST"
            authorization = root / "authorization.md"
            write(authorization, f"Authorization Status: APPROVED\nScope: WI-TEST\nAuthorized Mode: PRIMARY_CHECKOUT\nAuthorization Source: PROJECT_POLICY\nAuthorized Baseline Commit: {baseline}\n")
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            subprocess.run(["git", "commit", "-qm", "authorization"], cwd=root, check=True)
            preflight = subprocess.run(
                [
                    sys.executable, str(PREFLIGHT), "--root", str(root), "--work-item", str(work),
                    "--allow-primary-checkout", "--primary-exception-reason", "serial",
                    "--authorization-evidence", str(authorization),
                    "--command-profile", str(root / ".ai" / "config" / "worktree-command-profile.json"),
                ],
                text=True, capture_output=True,
            )
            self.assertEqual(preflight.returncode, 0, preflight.stdout + preflight.stderr)
            evidence = work / "WORKTREE_READINESS.md"
            write(
                evidence,
                re.sub(
                    r"(?m)^Baseline Command:.*$",
                    "Baseline Command: [\"python\", \"-c\", \"print('unapproved command')\"]",
                    evidence.read_text(encoding="utf-8"),
                ),
            )

            result = run(WORKTREE_VALIDATOR, root, work)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Baseline Command does not match Command Profile", result.stdout)

    def test_preflight_rejects_cli_exception_without_authorization_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.init_repo(root)
            subprocess.run(["git", "switch", "-c", "feature/preflight"], cwd=root, check=True, capture_output=True)
            work = root / "docs" / "work-items" / "WI-TEST"

            result = subprocess.run(
                [
                    sys.executable, str(PREFLIGHT), "--root", str(root), "--work-item", str(work),
                    "--allow-primary-checkout", "--primary-exception-reason", "self asserted",
                    "--command-profile", str(root / ".ai" / "config" / "worktree-command-profile.json"),
                ],
                text=True, capture_output=True,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("authorization evidence", (result.stdout + result.stderr).lower())

    def test_preflight_records_git_status_separately_and_blocks_dirty_baseline(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            baseline = self.init_repo(root)
            subprocess.run(["git", "switch", "-c", "feature/preflight"], cwd=root, check=True, capture_output=True)
            authorization = root / "authorization.md"
            write(authorization, f"Authorization Status: APPROVED\nScope: WI-TEST\nAuthorized Mode: PRIMARY_CHECKOUT\nAuthorization Source: PROJECT_POLICY\nAuthorized Baseline Commit: {baseline}\n")
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            subprocess.run(["git", "commit", "-qm", "authorization"], cwd=root, check=True)
            write(root / "dirty.txt", "uncommitted\n")
            work = root / "docs" / "work-items" / "WI-TEST"

            result = subprocess.run(
                [
                    sys.executable, str(PREFLIGHT), "--root", str(root), "--work-item", str(work),
                    "--allow-primary-checkout", "--primary-exception-reason", "serial",
                    "--authorization-evidence", str(authorization),
                    "--command-profile", str(root / ".ai" / "config" / "worktree-command-profile.json"),
                ],
                text=True, capture_output=True,
            )

            self.assertNotEqual(result.returncode, 0)
            evidence = (work / "WORKTREE_READINESS.md").read_text(encoding="utf-8")
            self.assertIn("Baseline Result: PASS", evidence)
            self.assertIn("Git Status Result: DIRTY", evidence)
            self.assertIn("Clean Baseline: NO", evidence)

    def test_preflight_blocks_when_passing_baseline_command_dirties_worktree(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            baseline = self.init_repo(root)
            subprocess.run(["git", "switch", "-c", "feature/preflight"], cwd=root, check=True, capture_output=True)
            write(root / ".ai" / "config" / "worktree-command-profile.json", json.dumps({
                "schema": "ai-development-os.worktree-command-profile/v1",
                "setup": None,
                "baseline": [
                    sys.executable,
                    "-c",
                    "from pathlib import Path; Path('generated-dirty.txt').write_text('dirty')",
                ],
            }))
            authorization = root / "authorization.md"
            write(authorization, f"Authorization Status: APPROVED\nScope: WI-TEST\nAuthorized Mode: PRIMARY_CHECKOUT\nAuthorization Source: PROJECT_POLICY\nAuthorized Baseline Commit: {baseline}\n")
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            subprocess.run(["git", "commit", "-qm", "authorization and command profile"], cwd=root, check=True)
            work = root / "docs" / "work-items" / "WI-TEST"

            result = subprocess.run(
                [
                    sys.executable, str(PREFLIGHT), "--root", str(root), "--work-item", str(work),
                    "--allow-primary-checkout", "--primary-exception-reason", "serial",
                    "--authorization-evidence", str(authorization),
                    "--command-profile", str(root / ".ai" / "config" / "worktree-command-profile.json"),
                ],
                text=True, capture_output=True,
            )

            self.assertNotEqual(result.returncode, 0)
            evidence = (work / "WORKTREE_READINESS.md").read_text(encoding="utf-8")
            self.assertIn("Baseline Result: PASS", evidence)
            self.assertIn("Git Status Result: DIRTY", evidence)
            self.assertIn("Clean Baseline: NO", evidence)
            validation = run(WORKTREE_VALIDATOR, root, work)
            self.assertNotEqual(validation.returncode, 0)
            self.assertIn("live Git status is dirty", validation.stdout)

    def test_validator_requires_setup_evidence_when_profile_has_setup_command(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            baseline = self.init_repo(root)
            subprocess.run(["git", "switch", "-c", "feature/preflight"], cwd=root, check=True, capture_output=True)
            write(root / ".ai" / "config" / "worktree-command-profile.json", json.dumps({
                "schema": "ai-development-os.worktree-command-profile/v1",
                "setup": [sys.executable, "-c", "print('setup ok')"],
                "baseline": [sys.executable, "-c", "print('baseline ok')"],
            }))
            authorization = root / "authorization.md"
            write(authorization, f"Authorization Status: APPROVED\nScope: WI-TEST\nAuthorized Mode: PRIMARY_CHECKOUT\nAuthorization Source: PROJECT_POLICY\nAuthorized Baseline Commit: {baseline}\n")
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            subprocess.run(["git", "commit", "-qm", "authorization and setup profile"], cwd=root, check=True)
            work = root / "docs" / "work-items" / "WI-TEST"
            preflight = subprocess.run(
                [
                    sys.executable, str(PREFLIGHT), "--root", str(root), "--work-item", str(work),
                    "--allow-primary-checkout", "--primary-exception-reason", "serial",
                    "--authorization-evidence", str(authorization),
                    "--command-profile", str(root / ".ai" / "config" / "worktree-command-profile.json"),
                ],
                text=True, capture_output=True,
            )
            self.assertEqual(preflight.returncode, 0, preflight.stdout + preflight.stderr)
            evidence = work / "WORKTREE_READINESS.md"
            tampered = re.sub(
                r"(?m)^Setup Result:.*$\n^Setup Log:.*$\n^Setup Log SHA256:.*$",
                "Setup Result: NOT_APPLICABLE\nSetup Log: NOT_APPLICABLE\nSetup Log SHA256: NOT_APPLICABLE",
                evidence.read_text(encoding="utf-8"),
            )
            write(evidence, tampered)

            validation = run(WORKTREE_VALIDATOR, root, work)

            self.assertNotEqual(validation.returncode, 0)
            self.assertIn("Setup Result must be PASS when Command Profile defines setup", validation.stdout)

    def test_accept_allows_head_descended_from_recorded_baseline(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            baseline = self.init_repo(root)
            subprocess.run(["git", "switch", "-c", "feature/preflight"], cwd=root, check=True, capture_output=True)
            authorization = root / "authorization.md"
            write(authorization, f"Authorization Status: APPROVED\nScope: WI-TEST\nAuthorized Mode: PRIMARY_CHECKOUT\nAuthorization Source: PROJECT_POLICY\nAuthorized Baseline Commit: {baseline}\n")
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            subprocess.run(["git", "commit", "-qm", "authorization"], cwd=root, check=True)
            work = root / "docs" / "work-items" / "WI-TEST"
            preflight = subprocess.run(
                [
                    sys.executable, str(PREFLIGHT), "--root", str(root), "--work-item", str(work),
                    "--allow-primary-checkout", "--primary-exception-reason", "serial",
                    "--authorization-evidence", str(authorization),
                    "--command-profile", str(root / ".ai" / "config" / "worktree-command-profile.json"),
                ],
                text=True, capture_output=True,
            )
            self.assertEqual(preflight.returncode, 0, preflight.stdout + preflight.stderr)
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            subprocess.run(["git", "commit", "-qm", "implementation"], cwd=root, check=True)

            validation = run(WORKTREE_VALIDATOR, root, work, "--phase", "accept")

            self.assertEqual(validation.returncode, 0, validation.stdout + validation.stderr)

    def test_rejects_linked_worktree_claiming_primary_checkout(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            primary = Path(tmp) / "primary"
            primary.mkdir()
            self.init_repo(primary)
            linked = Path(tmp) / "linked"
            subprocess.run(["git", "worktree", "add", "-qb", "feature/linked", str(linked)], cwd=primary, check=True)
            work = linked / "docs" / "work-items" / "WI-TEST"
            preflight = subprocess.run(
                [
                    sys.executable, str(PREFLIGHT), "--root", str(linked), "--work-item", str(work),
                    "--command-profile", str(linked / ".ai" / "config" / "worktree-command-profile.json"),
                ],
                text=True, capture_output=True,
            )
            self.assertEqual(preflight.returncode, 0, preflight.stdout + preflight.stderr)
            evidence = work / "WORKTREE_READINESS.md"
            write(evidence, evidence.read_text(encoding="utf-8").replace(
                "Isolation Mode: LINKED_WORKTREE", "Isolation Mode: PRIMARY_CHECKOUT"
            ))

            result = run(WORKTREE_VALIDATOR, linked, work)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("claims PRIMARY_CHECKOUT", result.stdout)


class WorkflowDiagnosisTests(unittest.TestCase):
    def diagnosis_report(
        self,
        root: Path,
        work: Path,
        *,
        decision: str = "CLEAR",
        statuses: dict[str, str] | None = None,
        evidence_by_dimension: dict[str, str] | None = None,
        findings: str = "",
    ) -> None:
        dimensions = (
            ("ROUTING_TIMELINE", "CHECK_ROUTING_TIMELINE"),
            ("PLAN_ADHERENCE", "CHECK_PLAN_ADHERENCE"),
            ("REPEATED_WORK", "CHECK_REPEATED_WORK"),
            ("STUMBLES_BLOCKERS", "CHECK_STUMBLES_BLOCKERS"),
            ("QUALITY_EVIDENCE", "CHECK_QUALITY_EVIDENCE"),
            ("REQUEST_CONFLICTS", "CHECK_REQUEST_CONFLICTS"),
            ("TIME_COST", "CHECK_TIME_COST"),
        )
        inventory = []
        coverage = []
        statuses = statuses or {}
        evidence_by_dimension = evidence_by_dimension or {}
        for index, (dimension, check) in enumerate(dimensions, 1):
            evidence = root / f"{dimension.lower()}.txt"
            write(evidence, f"{dimension} evidence\n")
            evidence_id = f"E-{index:02d}"
            inventory.append(f"| {evidence_id} | {evidence.relative_to(root).as_posix()} | {sha(evidence)} |")
            coverage.append(
                f"| {dimension} | {statuses.get(dimension, 'REVIEWED')} | {check} | "
                f"{evidence_by_dimension.get(dimension, evidence_id)} |"
            )
        write(
            work / "WORKFLOW_DIAGNOSIS.md",
            "Diagnosis Status: COMPLETE\n"
            f"Diagnosis Decision: {decision}\n"
            "Input Mutation: NONE\nIntake Statement: diagnose\nScope: WI-TEST\n\n"
            "## Evidence Inventory\n| ID | Path | SHA256 |\n|---|---|---|\n"
            + "\n".join(inventory)
            + "\n\n## Dimension Coverage\n| Dimension | Status | Check | Evidence |\n|---|---|---|---|\n"
            + "\n".join(coverage)
            + "\n\n## Findings\n"
            "| ID | Dimension | Severity | Evidence | Observed Fact | Impact | Recommendation | Status |\n"
            "|---|---|---|---|---|---|---|---|\n"
            + findings,
        )

    def test_rejects_finding_without_path_line_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "docs" / "work-items" / "WI-TEST"
            write(root / "evidence.txt", "line one\nline two\n")
            write(
                work / "WORKFLOW_DIAGNOSIS.md",
                "Diagnosis Status: COMPLETE\nDiagnosis Decision: BLOCKED\nInput Mutation: NONE\n"
                "Intake Statement: investigate repeated work\nScope: WI-TEST\n\n"
                "## Evidence Inventory\n| ID | Path | SHA256 |\n|---|---|---|\n"
                f"| E-01 | evidence.txt | {sha(root / 'evidence.txt')} |\n\n"
                "## Dimension Coverage\n| Dimension | Status | Evidence |\n|---|---|---|\n"
                "| ROUTING_TIMELINE | REVIEWED | E-01 |\n| PLAN_ADHERENCE | REVIEWED | E-01 |\n"
                "| REPEATED_WORK | REVIEWED | E-01 |\n| STUMBLES_BLOCKERS | REVIEWED | E-01 |\n"
                "| QUALITY_EVIDENCE | REVIEWED | E-01 |\n| REQUEST_CONFLICTS | REVIEWED | E-01 |\n"
                "| TIME_COST | REVIEWED | E-01 |\n\n"
                "## Findings\n| ID | Dimension | Severity | Evidence | Observed Fact | Impact | Recommendation | Status |\n"
                "|---|---|---|---|---|---|---|---|\n"
                "| D-01 | REPEATED_WORK | HIGH | evidence.txt | repeated | delay | fix router | OPEN |\n",
            )
            result = run(DIAGNOSIS_VALIDATOR, root, work)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("path:line", result.stdout)

    def test_diagnose_generates_blocked_report_for_missing_required_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "docs" / "work-items" / "WI-TEST"
            write(work / "WORK_ITEM.md", "# Work\n\n## Tasks / Vertical Slices\n- [ ] T01\n")
            write(
                work / "DELIVERY_GATE.md",
                "TDD Gate: REQUIRED\nTask Agent Review Gate: REQUIRED\n"
                "Worktree Readiness Gate: REQUIRED\nWorkflow Diagnosis Gate: REQUIRED\n",
            )
            result = subprocess.run(
                [sys.executable, str(DIAGNOSE), "--root", str(root), "--work-item", str(work)],
                text=True, capture_output=True,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            report = (work / "WORKFLOW_DIAGNOSIS.md").read_text(encoding="utf-8")
            self.assertIn("Diagnosis Decision: BLOCKED", report)
            self.assertIn("missing required lifecycle evidence", report)
            validation = run(DIAGNOSIS_VALIDATOR, root, work)
            self.assertEqual(validation.returncode, 0, validation.stdout + validation.stderr)

    def test_validator_rejects_clear_with_insufficient_dimension(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "docs" / "work-items" / "WI-TEST"
            self.diagnosis_report(
                root,
                work,
                statuses={"TIME_COST": "INSUFFICIENT_EVIDENCE"},
            )
            result = run(DIAGNOSIS_VALIDATOR, root, work)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("CLEAR requires every dimension REVIEWED", result.stdout)

    def test_validator_rejects_shared_fallback_evidence_for_all_dimensions(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "docs" / "work-items" / "WI-TEST"
            self.diagnosis_report(
                root,
                work,
                evidence_by_dimension={dimension: "E-01" for dimension in (
                    "ROUTING_TIMELINE", "PLAN_ADHERENCE", "REPEATED_WORK", "STUMBLES_BLOCKERS",
                    "QUALITY_EVIDENCE", "REQUEST_CONFLICTS", "TIME_COST",
                )},
            )
            result = run(DIAGNOSIS_VALIDATOR, root, work)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("single fallback evidence", result.stdout)

    def test_validator_rejects_unknown_statuses_and_unsupported_numeric_claim(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "docs" / "work-items" / "WI-TEST"
            self.diagnosis_report(
                root,
                work,
                decision="BLOCKED",
                statuses={"TIME_COST": "PARTIAL"},
                findings=(
                    "| D-01 | TIME_COST | MEDIUM | time_cost.txt:1 | observed 17 retries | delay | inspect | ACTIVE |\n"
                ),
            )
            result = run(DIAGNOSIS_VALIDATOR, root, work)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("invalid status PARTIAL", result.stdout)
            self.assertIn("finding D-01 status must be OPEN or CLOSED", result.stdout)
            self.assertIn("unsupported numeric claim 17", result.stdout)

    def test_validator_rejects_duplicate_dimension_and_evidence_ids(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "docs" / "work-items" / "WI-TEST"
            self.diagnosis_report(root, work)
            report = work / "WORKFLOW_DIAGNOSIS.md"
            text = report.read_text(encoding="utf-8")
            text = text.replace(
                "| E-02 | plan_adherence.txt |",
                "| E-01 | plan_adherence.txt |",
            ).replace(
                "| PLAN_ADHERENCE | REVIEWED | CHECK_PLAN_ADHERENCE | E-02 |",
                "| ROUTING_TIMELINE | REVIEWED | CHECK_ROUTING_TIMELINE | E-01 |",
            )
            write(report, text)

            result = run(DIAGNOSIS_VALIDATOR, root, work)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("duplicate evidence ID E-01", result.stdout)
            self.assertIn("duplicate dimension ROUTING_TIMELINE", result.stdout)
            self.assertIn("Dimension Coverage missing: PLAN_ADHERENCE", result.stdout)

    def test_validator_requires_open_finding_for_each_nonreviewed_dimension(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "docs" / "work-items" / "WI-TEST"
            self.diagnosis_report(
                root,
                work,
                decision="BLOCKED",
                statuses={"TIME_COST": "INSUFFICIENT_EVIDENCE"},
                findings=(
                    "| D-01 | QUALITY_EVIDENCE | HIGH | quality_evidence.txt:1 | quality gap | risk | fix | OPEN |\n"
                ),
            )

            result = run(DIAGNOSIS_VALIDATOR, root, work)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("dimension TIME_COST requires an OPEN finding", result.stdout)

    def test_validator_rejects_finding_citation_outside_inventory(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "docs" / "work-items" / "WI-TEST"
            write(root / "not-inventory.txt", "uncited source\n")
            self.diagnosis_report(
                root,
                work,
                decision="BLOCKED",
                statuses={"TIME_COST": "BLOCKED"},
                findings=(
                    "| D-01 | TIME_COST | MEDIUM | not-inventory.txt:1 | missing duration | delay | inspect | OPEN |\n"
                ),
            )

            result = run(DIAGNOSIS_VALIDATOR, root, work)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("must cite inventoried evidence", result.stdout)

    def test_diagnose_does_not_review_routing_without_phase_fields(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "docs" / "work-items" / "WI-TEST"
            write(work / "WORK_ITEM.md", "# Work\n\n## Type\n\nCHANGE\n")
            write(work / "DELIVERY_GATE.md", "Workflow Diagnosis Gate: REQUIRED\n")

            result = subprocess.run(
                [sys.executable, str(DIAGNOSE), "--root", str(root), "--work-item", str(work)],
                text=True, capture_output=True,
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            report = (work / "WORKFLOW_DIAGNOSIS.md").read_text(encoding="utf-8")
            self.assertIn(
                "| ROUTING_TIMELINE | INSUFFICIENT_EVIDENCE | CHECK_ROUTING_TIMELINE |",
                report,
            )
            self.assertIn("routing state or current phase is missing", report)

    def test_diagnose_parses_authoritative_state_heading_and_delivery_template(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "docs" / "work-items" / "WI-TEST"
            write(
                work / "WORK_ITEM.md",
                "# Work\n\n## Type\n\nCHANGE\n\n## State\n\nIMPLEMENTATION_READY\n",
            )
            write(
                work / "DELIVERY_GATE.md",
                "Implementation Ready: YES\nWorkflow Diagnosis Gate: REQUIRED\n"
                "Security Gate: PLANNED\nTest Gate: PLANNED\n"
                "Independent Review: PENDING\nThird Party Audit: PENDING\n"
                "Acceptance: PENDING\nGit Integration: PENDING\n",
            )

            result = subprocess.run(
                [sys.executable, str(DIAGNOSE), "--root", str(root), "--work-item", str(work)],
                text=True, capture_output=True,
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            report = (work / "WORKFLOW_DIAGNOSIS.md").read_text(encoding="utf-8")
            self.assertIn("| ROUTING_TIMELINE | REVIEWED | CHECK_ROUTING_TIMELINE |", report)
            self.assertNotIn("routing state or current phase is missing", report)

    def test_diagnose_blocks_plan_adherence_for_pending_or_invalid_required_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "docs" / "work-items" / "WI-TEST"
            write(
                work / "WORK_ITEM.md",
                "# Work\n\n## Type\n\nCHANGE\n\n## State\n\nIMPLEMENTATION_READY\n\n"
                "## Tasks / Vertical Slices\n- [ ] T01 behavior\n",
            )
            write(
                work / "DELIVERY_GATE.md",
                "Implementation Ready: YES\nTDD Gate: REQUIRED\n"
                "Task Agent Review Gate: REQUIRED\nWorktree Readiness Gate: REQUIRED\n"
                "Workflow Diagnosis Gate: REQUIRED\n",
            )
            write(
                work / "TDD_CYCLE_REPORT.md",
                "TDD Plan Status: READY\nTDD Decision: PENDING\n\n## Task Coverage\n"
                "| Task ID | Applicability | Test Selector | Status | Rationale |\n"
                "|---|---|---|---|---|\n| T02 | REQUIRED | tests.x | PLANNED | wrong task |\n",
            )
            write(work / "TASK_AGENT_LEDGER.md", "Task Agent Plan Status: READY\nTask Agent Decision: PENDING\n")
            write(work / "WORKTREE_READINESS.md", "Readiness Decision: BLOCKED\n")

            result = subprocess.run(
                [sys.executable, str(DIAGNOSE), "--root", str(root), "--work-item", str(work)],
                text=True, capture_output=True,
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            report = (work / "WORKFLOW_DIAGNOSIS.md").read_text(encoding="utf-8")
            self.assertIn("| PLAN_ADHERENCE | BLOCKED | CHECK_PLAN_ADHERENCE |", report)
            self.assertIn("required lifecycle evidence is pending, invalid or does not match planned tasks", report)

    def test_validator_rejects_unsupported_numbers_in_all_finding_narratives(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "docs" / "work-items" / "WI-TEST"
            self.diagnosis_report(
                root,
                work,
                decision="BLOCKED",
                statuses={"TIME_COST": "BLOCKED"},
                findings=(
                    "| D-01 | TIME_COST | MEDIUM | time_cost.txt:1 | delay observed | "
                    "causes 17 retries | retry 9 times | OPEN |\n"
                ),
            )

            result = run(DIAGNOSIS_VALIDATOR, root, work)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("unsupported numeric claim 17", result.stdout)
            self.assertIn("unsupported numeric claim 9", result.stdout)

    def test_diagnose_fails_closed_for_mixed_or_naive_timestamps(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "docs" / "work-items" / "WI-TEST"
            write(work / "WORK_ITEM.md", "# Work\nStatus: IMPLEMENT\n")
            write(work / "DELIVERY_GATE.md", "Current Phase: IMPLEMENT\n")
            write(
                work / "EXECUTION_JOURNAL.jsonl",
                '{"task_id":"T01","stage":"RED","selector":"test_one","classification":"EXPECTED_RED","timestamp_utc":"2026-10-29T00:00:00Z"}\n'
                '{"task_id":"T01","stage":"GREEN","selector":"test_one","classification":"PASS","timestamp_utc":"2026-10-29T00:00:01"}\n',
            )

            result = subprocess.run(
                [sys.executable, str(DIAGNOSE), "--root", str(root), "--work-item", str(work)],
                text=True, capture_output=True,
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            report = (work / "WORKFLOW_DIAGNOSIS.md").read_text(encoding="utf-8")
            self.assertIn("timestamp evidence is missing or invalid", report)
            self.assertIn("| TIME_COST | INSUFFICIENT_EVIDENCE | CHECK_TIME_COST |", report)

    def test_diagnose_detects_mismatch_repetition_stage_disorder_failure_and_quality_gap(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "docs" / "work-items" / "WI-TEST"
            write(
                work / "WORK_ITEM.md",
                "# Work\nStatus: IMPLEMENT\nWork Type: BACKEND\n\n## Tasks / Vertical Slices\n- [ ] T01 behavior\n",
            )
            write(
                work / "DELIVERY_GATE.md",
                "Current Phase: PLAN\nTDD Gate: REQUIRED\nTask Agent Review Gate: REQUIRED\n"
                "Worktree Readiness Gate: REQUIRED\nWorkflow Diagnosis Gate: REQUIRED\n",
            )
            write(
                work / "EXECUTION_JOURNAL.jsonl",
                '{"task_id":"T01","stage":"GREEN","selector":"tests.test_one","classification":"FAIL","timestamp_utc":"2026-10-29T00:00:00Z"}\n'
                '{"task_id":"T01","stage":"GREEN","selector":"tests.test_one","classification":"PASS","timestamp_utc":"2026-10-29T00:00:01Z"}\n',
            )
            result = subprocess.run(
                [sys.executable, str(DIAGNOSE), "--root", str(root), "--work-item", str(work)],
                text=True, capture_output=True,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            report = (work / "WORKFLOW_DIAGNOSIS.md").read_text(encoding="utf-8")
            self.assertIn("route/phase mismatch", report)
            self.assertIn("repeats task/stage/selector", report)
            self.assertIn("stage order", report)
            self.assertIn("failed execution event", report)
            self.assertIn("missing required quality evidence", report)
            self.assertIn("| TIME_COST | REVIEWED | CHECK_TIME_COST |", report)
            validation = run(DIAGNOSIS_VALIDATOR, root, work)
            self.assertEqual(validation.returncode, 0, validation.stdout + validation.stderr)

    def test_diagnose_marks_absent_dimension_sources_insufficient(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "docs" / "work-items" / "WI-TEST"
            write(work / "WORK_ITEM.md", "# Work\nStatus: REQUEST\n")
            result = subprocess.run(
                [sys.executable, str(DIAGNOSE), "--root", str(root), "--work-item", str(work)],
                text=True, capture_output=True,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            report = (work / "WORKFLOW_DIAGNOSIS.md").read_text(encoding="utf-8")
            self.assertIn("| REPEATED_WORK | INSUFFICIENT_EVIDENCE | CHECK_REPEATED_WORK |", report)
            self.assertIn("| TIME_COST | INSUFFICIENT_EVIDENCE | CHECK_TIME_COST |", report)
            self.assertIn("Diagnosis Decision: BLOCKED", report)


if __name__ == "__main__":
    unittest.main()

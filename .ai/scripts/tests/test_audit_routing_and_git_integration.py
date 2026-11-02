from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
AUDIT_SCRIPT = ROOT / ".ai" / "scripts" / "validate_audit_plan.py"
GATE_SCRIPT = ROOT / ".ai" / "scripts" / "gate.py"


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def init_git(root: Path) -> str:
    subprocess.run(["git", "init", "-q"], cwd=root, check=True)
    subprocess.run(["git", "config", "user.name", "Test"], cwd=root, check=True)
    subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=root, check=True)
    subprocess.run(["git", "add", "."], cwd=root, check=True)
    subprocess.run(["git", "commit", "-qm", "remediation baseline"], cwd=root, check=True)
    return subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=root, text=True, capture_output=True, check=True
    ).stdout.strip()


def write_plan(work: Path, *, work_type="CHANGE", tracks="CORE, ARCHITECTURE, THIRD_PARTY", **fields):
    values = {
        "Audit Plan Status": "COMPLETE",
        "Work Type": work_type,
        "Risk Level": "MEDIUM",
        "UI Impact": "NONE",
        "Contract Impact": "NONE",
        "Security Impact": "NO",
        "Data / Migration Impact": "NO",
        "Reliability / Performance Impact": "NO",
        "Required Audit Tracks": tracks,
        "Audit Execution Status": "PLANNED",
        "Remediation Cycle": "NOT_STARTED",
        "Open Findings": "0",
        "Final Audit Decision": "PENDING",
    }
    values.update(fields)
    work.mkdir(parents=True, exist_ok=True)
    (work / "WORK_ITEM.md").write_text(
        f"# Work Item\n\n## Type\n\n{work_type}\n", encoding="utf-8"
    )
    (work / "AUDIT_PLAN.md").write_text(
        "# Audit Plan\n\n" + "\n".join(f"{key}: {value}" for key, value in values.items()) + "\n",
        encoding="utf-8",
    )
    (work / "IMPACT_MAP.md").write_text(
        "# Impact Map\n\n## Audit Routing Inputs\n\n"
        + "\n".join(f"{name}: {values[name]}" for name in (
            "Risk Level", "UI Impact", "Contract Impact", "Security Impact",
            "Data / Migration Impact", "Reliability / Performance Impact",
        )) + "\n",
        encoding="utf-8",
    )


class AuditRoutingTests(unittest.TestCase):
    def setUp(self):
        self.audit = load(AUDIT_SCRIPT, "audit_plan")

    def test_change_requires_architecture_track(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "WI"
            write_plan(work, tracks="CORE, THIRD_PARTY")
            errors = self.audit.validate(root, work, "plan")
        self.assertTrue(any("ARCHITECTURE" in error for error in errors))

    def test_plan_work_type_must_match_authoritative_work_item_type(self):
        for authoritative_type in (
            "FEATURE", "CHANGE", "REFACTOR", "BUG", "REPAIR", "MAINTENANCE", "DOCS"
        ):
            with self.subTest(authoritative_type=authoritative_type), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                work = root / "WI"
                write_plan(work, work_type="DOCS", tracks="CORE, CONSISTENCY, THIRD_PARTY")
                (work / "WORK_ITEM.md").write_text(
                    f"# Work Item\n\n## Type\n\n{authoritative_type}\n", encoding="utf-8"
                )
                errors = self.audit.validate(root, work, "plan")
            if authoritative_type == "DOCS":
                self.assertFalse(any("must match WORK_ITEM.md" in error for error in errors))
            else:
                self.assertTrue(any("must match WORK_ITEM.md" in error for error in errors))

    def test_missing_invalid_or_contradictory_routing_inputs_fail_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "WI"
            write_plan(work)
            plan = work / "AUDIT_PLAN.md"
            plan.write_text(
                plan.read_text(encoding="utf-8")
                .replace("Risk Level: MEDIUM\n", "")
                .replace("Security Impact: NO", "Security Impact: MAYBE"),
                encoding="utf-8",
            )
            impact = work / "IMPACT_MAP.md"
            impact.write_text(
                impact.read_text(encoding="utf-8").replace("UI Impact: NONE", "UI Impact: STRUCTURAL"),
                encoding="utf-8",
            )
            errors = self.audit.validate(root, work, "plan")
        rendered = "\n".join(errors)
        self.assertIn("Risk Level", rendered)
        self.assertIn("Security Impact", rendered)
        self.assertIn("must match IMPACT_MAP.md", rendered)

    def test_bug_requires_root_cause_and_regression_tracks(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "WI"
            write_plan(work, work_type="BUG", tracks="CORE, THIRD_PARTY")
            errors = self.audit.validate(root, work, "plan")
        self.assertTrue(any("ROOT_CAUSE" in error for error in errors))
        self.assertTrue(any("REGRESSION" in error for error in errors))

    def test_impacts_add_specialist_tracks(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "WI"
            write_plan(
                work,
                tracks="CORE, ARCHITECTURE, THIRD_PARTY",
                **{
                    "UI Impact": "MINOR",
                    "Contract Impact": "BOTH",
                    "Security Impact": "YES",
                    "Data / Migration Impact": "YES",
                    "Reliability / Performance Impact": "YES",
                },
            )
            errors = self.audit.validate(root, work, "plan")
        rendered = "\n".join(errors)
        for track in ("UI_UX", "CONTRACT", "SECURITY", "DATA_MIGRATION", "RELIABILITY_PERFORMANCE"):
            self.assertIn(track, rendered)

    def test_blocked_audit_history_requires_complete_remediation(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "WI"
            write_plan(
                work,
                tracks="CORE, ARCHITECTURE, THIRD_PARTY",
                **{
                    "Audit Execution Status": "PASS",
                    "Remediation Cycle": "CLEAR",
                    "Final Audit Decision": "APPROVED",
                },
            )
            history = work / "audit-history" / "session-1"
            history.mkdir(parents=True)
            (history / "THIRD_PARTY_AUDIT.md").write_text(
                "Audit Decision: BLOCKED\n| AUDIT-123 | HIGH | defect | fix | OPEN | none |\n",
                encoding="utf-8",
            )
            errors = self.audit.validate(root, work, "accept")
        self.assertTrue(any("AUDIT_REMEDIATION.md" in error for error in errors))

    def test_complete_remediation_closes_archived_findings(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "WI"
            write_plan(
                work,
                tracks="CORE, ARCHITECTURE, THIRD_PARTY",
                **{
                    "Audit Execution Status": "PASS",
                    "Remediation Cycle": "CLEAR",
                    "Final Audit Decision": "APPROVED",
                },
            )
            history = work / "audit-history" / "session-1"
            history.mkdir(parents=True)
            (history / "THIRD_PARTY_AUDIT.md").write_text(
                "Audit Decision: BLOCKED\n| AUDIT-123 | HIGH | defect | fix | OPEN | none |\n",
                encoding="utf-8",
            )
            remediation_base = init_git(root)
            (work / "AUDIT_REMEDIATION.md").write_text(
                "Remediation Status: COMPLETE\nUnresolved Findings: 0\n"
                f"Remediation Base Commit: {remediation_base}\n"
                "Code / Configuration Fix: src/change.py\nRetest Evidence: tests/result.txt\nRetest Status: PASS\n"
                "Packet Resealed: YES\nFresh Re-Audit: PASS\nAUDIT-123: CLOSED\n\n"
                "## Finding Closure\n\n"
                "| Finding ID | Code / Configuration Change | Retest Evidence | Status |\n"
                "|---|---|---|---|\n"
                "| AUDIT-123 | src/change.py | tests/result.txt | CLOSED |\n",
                encoding="utf-8",
            )
            (root / "src").mkdir()
            (root / "src" / "change.py").write_text("fixed = True\n", encoding="utf-8")
            (root / "tests").mkdir()
            (root / "tests" / "result.txt").write_text(
                "Test Decision: PASS\nRequired Checks Complete: YES\nFailed Required Checks: 0\n\n"
                "## Finding Regression Coverage\n\n"
                "| Finding ID | Regression Test Selectors | Result |\n"
                "|---|---|---|\n"
                "| AUDIT-123 | test_audit_123_regression | PASS |\n",
                encoding="utf-8",
            )
            (root / "tests" / "test_change.py").write_text(
                "def test_audit_123_regression():\n    assert True\n", encoding="utf-8"
            )
            (work / "AUDIT_PACKET.md").write_text(
                "Packet Status: SEALED\n\n## Evidence Inventory\n\n"
                "| Evidence ID | Path | SHA256 | Purpose |\n|---|---|---|---|\n"
                "| E01 | ../src/change.py | hash | fix |\n"
                "| E02 | ../tests/result.txt | hash | retest |\n"
                "| E03 | ../tests/test_change.py | hash | regression source |\n",
                encoding="utf-8",
            )
            (work / "THIRD_PARTY_AUDIT.md").write_text(
                "Audit Decision: APPROVED\nAudit Session ID: session-2\nAuditor Agent: auditor-2\n",
                encoding="utf-8",
            )
            errors = self.audit.validate(root, work, "accept")
        self.assertEqual(errors, [])

    def test_sealed_unchanged_fix_and_generic_pass_are_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "WI"
            write_plan(
                work,
                **{"Audit Execution Status": "PASS", "Remediation Cycle": "CLEAR", "Final Audit Decision": "APPROVED"},
            )
            history = work / "audit-history" / "session-1"
            history.mkdir(parents=True)
            (history / "THIRD_PARTY_AUDIT.md").write_text(
                "Audit Decision: BLOCKED\nAudit Session ID: session-1\nAuditor Agent: auditor-1\n"
                "| SEC-1 | HIGH | defect | fix | OPEN | none |\n",
                encoding="utf-8",
            )
            (root / "unrelated.txt").write_text("pre-existing unrelated\n", encoding="utf-8")
            (root / "fake-retest.txt").write_text(
                "Test Decision: PASS\nRequired Checks Complete: YES\nFailed Required Checks: 0\n",
                encoding="utf-8",
            )
            remediation_base = init_git(root)
            (work / "AUDIT_REMEDIATION.md").write_text(
                "Remediation Status: COMPLETE\nUnresolved Findings: 0\n"
                f"Remediation Base Commit: {remediation_base}\n"
                "Code / Configuration Fix: unrelated.txt\nRetest Evidence: fake-retest.txt\nRetest Status: PASS\n"
                "Packet Resealed: YES\nFresh Re-Audit: PASS\nSEC-1: CLOSED\n\n"
                "## Finding Closure\n\n"
                "| Finding ID | Code / Configuration Change | Retest Evidence | Status |\n"
                "|---|---|---|---|\n"
                "| SEC-1 | unrelated.txt | fake-retest.txt | CLOSED |\n",
                encoding="utf-8",
            )
            (work / "AUDIT_PACKET.md").write_text(
                "Packet Status: SEALED\n\n## Evidence Inventory\n\n"
                "| Evidence ID | Path | SHA256 | Purpose |\n|---|---|---|---|\n"
                "| E01 | ../unrelated.txt | hash | unrelated |\n"
                "| E02 | ../fake-retest.txt | hash | generic retest |\n",
                encoding="utf-8",
            )
            (work / "THIRD_PARTY_AUDIT.md").write_text(
                "Audit Decision: APPROVED\nAudit Session ID: session-2\nAuditor Agent: auditor-2\n",
                encoding="utf-8",
            )
            errors = self.audit.validate(root, work, "accept")
        rendered = "\n".join(errors)
        self.assertIn("has no remediation delta", rendered)
        self.assertIn("requires finding-specific regression coverage", rendered)

    def test_noncanonical_finding_id_and_paper_only_fix_are_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "WI"
            write_plan(
                work,
                **{"Audit Execution Status": "PASS", "Remediation Cycle": "CLEAR", "Final Audit Decision": "APPROVED"},
            )
            history = work / "audit-history" / "session-1"
            history.mkdir(parents=True)
            (history / "THIRD_PARTY_AUDIT.md").write_text(
                "Audit Decision: BLOCKED\nAudit Session ID: session-1\nAuditor Agent: auditor-1\n"
                "| SEC-1 | HIGH | defect | fix | OPEN | none |\n",
                encoding="utf-8",
            )
            (work / "AUDIT_REMEDIATION.md").write_text(
                "Remediation Status: COMPLETE\nUnresolved Findings: 0\n"
                "Code / Configuration Fix: missing.py\nRetest Evidence: missing.txt\nRetest Status: PASS\n"
                "Packet Resealed: YES\nFresh Re-Audit: PASS\nSEC-1: CLOSED\n",
                encoding="utf-8",
            )
            errors = self.audit.validate(root, work, "accept")
        rendered = "\n".join(errors)
        self.assertIn("file missing", rendered)
        self.assertIn("newly SEALED", rendered)


class GitIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.gate = load(GATE_SCRIPT, "delivery_gate")

    def test_non_git_directory_blocks_integration(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "WI"
            work.mkdir()
            errors = self.gate.check_git_integration(root, work)
        self.assertTrue(any("Git repository" in error for error in errors))

    def test_dirty_worktree_blocks_integration(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.name", "Test"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=root, check=True)
            (root / "file.txt").write_text("base", encoding="utf-8")
            subprocess.run(["git", "add", "file.txt"], cwd=root, check=True)
            subprocess.run(["git", "commit", "-qm", "base"], cwd=root, check=True)
            work = root / "WI"
            work.mkdir()
            (work / "WORK_ITEM.md").write_text("## Integration / Release\n\nINTEGRATED / NOT_RELEASED\n", encoding="utf-8")
            (work / "DELIVERY_GATE.md").write_text("Git Integration: PASS\n", encoding="utf-8")
            errors = self.gate.check_git_integration(root, work)
        self.assertTrue(any("working tree" in error for error in errors))

    def test_clean_committed_worktree_passes_integration(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.name", "Test"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=root, check=True)
            (root / "feature.py").write_text("enabled = True\n", encoding="utf-8")
            subprocess.run(["git", "add", "feature.py"], cwd=root, check=True)
            subprocess.run(["git", "commit", "-qm", "feature"], cwd=root, check=True)
            feature_commit = subprocess.run(
                ["git", "rev-parse", "HEAD"], cwd=root, text=True, capture_output=True, check=True
            ).stdout.strip()
            work = root / "WI"
            work.mkdir()
            (work / "WORK_ITEM.md").write_text("## Integration / Release\n\nINTEGRATED / NOT_RELEASED\n", encoding="utf-8")
            (work / "DELIVERY_GATE.md").write_text("Git Integration: PASS\n", encoding="utf-8")
            (work / "GIT_INTEGRATION_EVIDENCE.md").write_text(
                "Integration Status: COMMITTED\n"
                f"Integrated Commit: {feature_commit}\n"
                "Staged Diff Reviewed: YES\nUnrelated Changes Included: NO\n"
                "Required Tracked Paths: WI/WORK_ITEM.md, WI/DELIVERY_GATE.md, WI/GIT_INTEGRATION_EVIDENCE.md\n"
                "Change Paths: feature.py\n",
                encoding="utf-8",
            )
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            subprocess.run(["git", "commit", "-qm", "integration evidence"], cwd=root, check=True)
            errors = self.gate.check_git_integration(root, work)
        self.assertEqual(errors, [])

    def test_ignored_uncommitted_work_item_cannot_pass_integration(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.name", "Test"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=root, check=True)
            (root / ".gitignore").write_text("WI/\n", encoding="utf-8")
            (root / "base.txt").write_text("base", encoding="utf-8")
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            subprocess.run(["git", "commit", "-qm", "base"], cwd=root, check=True)
            head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=root, text=True, capture_output=True, check=True).stdout.strip()
            work = root / "WI"
            work.mkdir()
            (work / "WORK_ITEM.md").write_text("INTEGRATED / NOT_RELEASED\n", encoding="utf-8")
            (work / "DELIVERY_GATE.md").write_text("Git Integration: PASS\n", encoding="utf-8")
            (work / "GIT_INTEGRATION_EVIDENCE.md").write_text(
                f"Integration Status: COMMITTED\nIntegrated Commit: {head}\n"
                "Staged Diff Reviewed: YES\nUnrelated Changes Included: NO\n"
                "Change Paths: base.txt\n",
                encoding="utf-8",
            )
            errors = self.gate.check_git_integration(root, work)
        self.assertTrue(any("not tracked" in error for error in errors))

    def test_unrelated_integrated_commit_cannot_claim_unchanged_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.name", "Test"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=root, check=True)
            (root / "feature.py").write_text("enabled = False\n", encoding="utf-8")
            subprocess.run(["git", "add", "feature.py"], cwd=root, check=True)
            subprocess.run(["git", "commit", "-qm", "base"], cwd=root, check=True)
            (root / "unrelated.txt").write_text("unrelated\n", encoding="utf-8")
            subprocess.run(["git", "add", "unrelated.txt"], cwd=root, check=True)
            subprocess.run(["git", "commit", "-qm", "unrelated"], cwd=root, check=True)
            integrated = subprocess.run(
                ["git", "rev-parse", "HEAD"], cwd=root, text=True, capture_output=True, check=True
            ).stdout.strip()
            work = root / "WI"
            work.mkdir()
            (work / "WORK_ITEM.md").write_text("INTEGRATED / NOT_RELEASED\n", encoding="utf-8")
            (work / "DELIVERY_GATE.md").write_text("Git Integration: PASS\n", encoding="utf-8")
            (work / "GIT_INTEGRATION_EVIDENCE.md").write_text(
                f"Integration Status: COMMITTED\nIntegrated Commit: {integrated}\n"
                "Staged Diff Reviewed: YES\nUnrelated Changes Included: NO\n"
                "Required Tracked Paths: WI/WORK_ITEM.md, WI/DELIVERY_GATE.md, WI/GIT_INTEGRATION_EVIDENCE.md\n"
                "Change Paths: feature.py\n",
                encoding="utf-8",
            )
            subprocess.run(["git", "add", "WI"], cwd=root, check=True)
            subprocess.run(["git", "commit", "-qm", "integration evidence"], cwd=root, check=True)
            errors = self.gate.check_git_integration(root, work)
        rendered = "\n".join(errors)
        self.assertIn("did not modify declared Change Path", rendered)
        self.assertIn("undeclared paths", rendered)


if __name__ == "__main__":
    unittest.main()


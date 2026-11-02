from __future__ import annotations

import hashlib
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "gate.py"


def write(path: Path, text: str = "evidence\n") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def run_gate(root: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--root", str(root), *args],
        text=True,
        capture_output=True,
    )


def create_work(root: Path, *, accepted: bool = False) -> Path:
    work = root / "docs" / "work-items" / "WI-TEST"
    write(work / "WORK_ITEM.md", "## Requirement Contract\n## Acceptance Decision\n")
    write(work / "IMPACT_MAP.md", "## Authoritative Owner\n## Layer Coverage\n")
    write(work / "IMPLEMENTATION_DESIGN.md", "## Root Fix / Owner\n## Verification Strategy\n")
    write(work / "IMPLEMENTATION_READY_REPORT.md", "IMPLEMENTATION_READY: YES\n")
    result = "PASS" if accepted else "NOT_RUN"
    write(work / "SCENARIO_MATRIX.md", f"| S01 | path | expected | inv | test | {result} |\n")
    gate = [
        "Implementation Ready: YES",
        "Product Inception Gate: NOT_APPLICABLE",
        "UI Gate: NOT_APPLICABLE",
        "Cross Layer Gate: NOT_APPLICABLE",
        "Multi Agent Gate: NOT_APPLICABLE",
        "TDD Gate: NOT_APPLICABLE",
        "Task Agent Review Gate: NOT_APPLICABLE",
        "Worktree Readiness Gate: NOT_APPLICABLE",
        "Workflow Diagnosis Gate: NOT_APPLICABLE",
        "Audit Plan: PASS",
        f"Security Gate: {'PASS' if accepted else 'PLANNED'}",
        f"Test Gate: {'PASS' if accepted else 'PLANNED'}",
        f"Independent Review: {'PASS' if accepted else 'PENDING'}",
        f"Third Party Audit: {'PASS' if accepted else 'PENDING'}",
        f"Acceptance: {'ACCEPTED' if accepted else 'PENDING'}",
        "Git Integration: PENDING",
    ]
    write(work / "DELIVERY_GATE.md", "\n".join(gate) + "\n")
    write(work / "AUDIT_PLAN.md", "Audit Plan Status: COMPLETE\n")
    write(root / ".ai" / "scripts" / "validate_audit_plan.py", "raise SystemExit(0)\n")
    if accepted:
        write(
            work / "SECURITY_AUDIT.md",
            "Security Decision: APPROVED\nThreat Model Status: COMPLETE\n"
            "Critical Open: 0\nHigh Open: 0\nSecret Scan: PASS\n"
            "Dependency Scan: PASS\nSAST: PASS\n",
        )
        write(
            work / "TEST_REPORT.md",
            "Test Decision: PASS\nRequired Checks Complete: YES\n"
            "Failed Required Checks: 0\n",
        )
        write(work / "ACCEPTANCE_REPORT.md", "Decision: ACCEPTED\n")
        write(root / ".ai" / "scripts" / "validate_third_party_audit.py", "raise SystemExit(0)\n")
    return work


class DeliveryGateTests(unittest.TestCase):
    def test_work_gate_rejects_missing_delivery_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "docs" / "work-items" / "WI-TEST"
            write(work / "WORK_ITEM.md", "## Requirement Contract\n## Acceptance Decision\n")
            result = run_gate(root, "work", "--work-item", str(work), "--phase", "ready")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("DELIVERY_GATE.md", result.stdout)

    def test_ready_gate_accepts_complete_planning_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = create_work(root)
            result = run_gate(root, "work", "--work-item", str(work), "--phase", "ready")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("WORK GATE: PASS", result.stdout)

    def test_accept_gate_requires_security_test_review_and_acceptance(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = create_work(root)
            result = run_gate(root, "work", "--work-item", str(work), "--phase", "accept")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Security Gate", result.stdout)
            self.assertIn("Scenario Matrix", result.stdout)

    def test_accept_gate_invokes_third_party_audit(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = create_work(root, accepted=True)
            write(
                root / ".ai" / "scripts" / "validate_third_party_audit.py",
                "print('THIRD-PARTY AUDIT GATE: BLOCKED')\nraise SystemExit(6)\n",
            )

            result = run_gate(root, "work", "--work-item", str(work), "--phase", "accept")

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("third-party audit", result.stdout.lower())

    def test_ready_invokes_required_worktree_readiness_gate(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = create_work(root)
            gate = work / "DELIVERY_GATE.md"
            gate.write_text(
                gate.read_text(encoding="utf-8").replace(
                    "Worktree Readiness Gate: NOT_APPLICABLE",
                    "Worktree Readiness Gate: REQUIRED",
                ),
                encoding="utf-8",
            )
            write(
                root / ".ai" / "scripts" / "validate_worktree_readiness.py",
                "print('WORKTREE READINESS GATE: BLOCKED')\nraise SystemExit(9)\n",
            )
            result = run_gate(root, "work", "--work-item", str(work), "--phase", "ready")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("worktree readiness", result.stdout.lower())

    def test_implementation_tasks_force_execution_and_worktree_routes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = create_work(root)
            write(
                work / "WORK_ITEM.md",
                "## Requirement Contract\n## Tasks / Vertical Slices\n"
                "- [ ] T01 implement behavior\n## Acceptance Decision\n",
            )

            result = run_gate(root, "work", "--work-item", str(work), "--phase", "ready")

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("TDD Gate must be REQUIRED", result.stdout)
            self.assertIn("Task Agent Review Gate must be REQUIRED", result.stdout)
            self.assertIn("Worktree Readiness Gate must be REQUIRED", result.stdout)

    def test_heading_work_type_cannot_bypass_implementation_routes_when_tasks_are_omitted(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = create_work(root)
            write(
                work / "WORK_ITEM.md",
                "## Type\nCHANGE\n\n## Requirement Contract\n## Acceptance Decision\n",
            )

            result = run_gate(root, "work", "--work-item", str(work), "--phase", "ready")

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("implementation Work Items must declare Tasks / Vertical Slices", result.stdout)
            self.assertIn("TDD Gate must be REQUIRED", result.stdout)
            self.assertIn("Task Agent Review Gate must be REQUIRED", result.stdout)
            self.assertIn("Worktree Readiness Gate must be REQUIRED", result.stdout)

    def test_accept_revalidates_required_worktree_readiness_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = create_work(root, accepted=True)
            gate = work / "DELIVERY_GATE.md"
            gate.write_text(
                gate.read_text(encoding="utf-8").replace(
                    "Worktree Readiness Gate: NOT_APPLICABLE",
                    "Worktree Readiness Gate: REQUIRED",
                ),
                encoding="utf-8",
            )
            write(
                root / ".ai" / "scripts" / "validate_worktree_readiness.py",
                "print('WORKTREE READINESS GATE: BLOCKED')\nraise SystemExit(9)\n",
            )
            result = run_gate(root, "work", "--work-item", str(work), "--phase", "accept")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("worktree readiness", result.stdout.lower())

    def test_required_execution_discipline_is_phase_aware(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = create_work(root)
            gate = work / "DELIVERY_GATE.md"
            gate.write_text(
                gate.read_text(encoding="utf-8")
                .replace("TDD Gate: NOT_APPLICABLE", "TDD Gate: REQUIRED")
                .replace("Task Agent Review Gate: NOT_APPLICABLE", "Task Agent Review Gate: REQUIRED"),
                encoding="utf-8",
            )
            write(
                root / ".ai" / "scripts" / "validate_execution_discipline.py",
                "import sys\nprint('PHASE=' + sys.argv[sys.argv.index('--phase') + 1])\n"
                "raise SystemExit(7 if sys.argv[sys.argv.index('--phase') + 1] == 'ready' else 0)\n",
            )
            result = run_gate(root, "work", "--work-item", str(work), "--phase", "ready")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("execution discipline", result.stdout.lower())
            self.assertIn("PHASE=ready", result.stdout)

    def test_multi_agent_required_does_not_require_completed_aggregation_at_ready(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = create_work(root)
            gate = work / "DELIVERY_GATE.md"
            gate.write_text(
                gate.read_text(encoding="utf-8").replace(
                    "Multi Agent Gate: NOT_APPLICABLE", "Multi Agent Gate: REQUIRED"
                ),
                encoding="utf-8",
            )
            write(
                work / "AGENT_PLAN.md",
                "Multi Agent Required: YES\nAggregation Owner: controller\n"
                "Independent Reviewer: reviewer-planned\nAggregation Status: PLANNED\n",
            )
            result = run_gate(root, "work", "--work-item", str(work), "--phase", "ready")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_expected_blocked_outcome_does_not_fail_passed_scenario(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = create_work(root, accepted=True)
            write(
                work / "SCENARIO_MATRIX.md",
                "| ID | Scenario | Expected Business Outcome | Result |\n"
                "|---|---|---|---|\n"
                "| S01 | invalid audit | BLOCKED | PASS |\n",
            )

            result = run_gate(root, "work", "--work-item", str(work), "--phase", "accept")

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("WORK GATE: PASS", result.stdout)

    def test_product_inception_requires_go_and_approved_traceable_prd(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = create_work(root)
            gate = work / "DELIVERY_GATE.md"
            gate.write_text(
                gate.read_text(encoding="utf-8").replace(
                    "Product Inception Gate: NOT_APPLICABLE",
                    "Product Inception Gate: REQUIRED",
                ),
                encoding="utf-8",
            )
            for name in ("PROJECT_CHARTER.md", "RESEARCH_BRIEF.md"):
                write(work / name)
            write(work / "PRODUCT_ANALYSIS.md", "Go/No-Go Decision: PENDING\n")
            write(work / "PRD_APPROVAL.md", "Research Traceability: INCOMPLETE\nApproval Status: DRAFT\n")
            blocked = run_gate(root, "work", "--work-item", str(work), "--phase", "ready")
            self.assertNotEqual(blocked.returncode, 0)
            self.assertIn("Go/No-Go Decision", blocked.stdout)
            self.assertIn("Approval Status", blocked.stdout)

            write(work / "PRODUCT_ANALYSIS.md", "Go/No-Go Decision: GO\n")
            write(work / "PRD_APPROVAL.md", "Research Traceability: COMPLETE\nApproval Status: APPROVED\n")
            passed = run_gate(root, "work", "--work-item", str(work), "--phase", "ready")
            self.assertEqual(passed.returncode, 0, passed.stdout + passed.stderr)

    def test_routed_ui_work_invokes_interaction_capability_gate(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = create_work(root)
            gate = work / "DELIVERY_GATE.md"
            gate.write_text(
                gate.read_text(encoding="utf-8")
                .replace("UI Gate: NOT_APPLICABLE", "UI Gate: REQUIRED\nUI Artifact Dir: design/ui-1"),
                encoding="utf-8",
            )
            (root / "design" / "ui-1").mkdir(parents=True)
            scripts = root / ".ai" / "scripts"
            write(scripts / "validate_ui_gate.py", "raise SystemExit(0)\n")
            write(scripts / "validate_ui_fidelity.py", "raise SystemExit(0)\n")
            write(
                scripts / "validate_ui_capabilities.py",
                "print('UI CAPABILITY PLAN GATE: BLOCKED')\nraise SystemExit(4)\n",
            )
            write(scripts / "validate_ui_adaptive.py", "raise SystemExit(0)\n")

            result = run_gate(root, "work", "--work-item", str(work), "--phase", "ready")

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("UI capability", result.stdout)

    def test_routed_ui_work_invokes_adaptive_ui_gate(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = create_work(root)
            gate = work / "DELIVERY_GATE.md"
            gate.write_text(
                gate.read_text(encoding="utf-8")
                .replace("UI Gate: NOT_APPLICABLE", "UI Gate: REQUIRED\nUI Artifact Dir: design/ui-1"),
                encoding="utf-8",
            )
            (root / "design" / "ui-1").mkdir(parents=True)
            scripts = root / ".ai" / "scripts"
            write(scripts / "validate_ui_gate.py", "raise SystemExit(0)\n")
            write(scripts / "validate_ui_fidelity.py", "raise SystemExit(0)\n")
            write(scripts / "validate_ui_capabilities.py", "raise SystemExit(0)\n")
            write(
                scripts / "validate_ui_adaptive.py",
                "print('ADAPTIVE UI PLAN GATE: BLOCKED')\nraise SystemExit(5)\n",
            )

            result = run_gate(root, "work", "--work-item", str(work), "--phase", "ready")

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("adaptive UI", result.stdout)

    def test_release_gate_rejects_non_git_workspace(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = create_work(root, accepted=True)
            release = root / "release.md"
            write(release, "Release Decision: APPROVED\n")
            result = run_gate(
                root, "release", "--work-item", str(work),
                "--release-evidence", str(release),
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Git repository", result.stdout)

    def test_release_gate_passes_only_with_integrated_deployment_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.email", "gate@example.test"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.name", "Gate Test"], cwd=root, check=True)
            work = create_work(root, accepted=True)
            artifact = root / "dist" / "artifact.bin"
            write(artifact, "release artifact\n")
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            subprocess.run(["git", "commit", "-qm", "test fixture"], cwd=root, check=True)
            commit = subprocess.run(
                ["git", "rev-parse", "HEAD"], cwd=root, check=True,
                text=True, capture_output=True,
            ).stdout.strip()
            branch = subprocess.run(
                ["git", "branch", "--show-current"], cwd=root, check=True,
                text=True, capture_output=True,
            ).stdout.strip()
            digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
            release = root / "release.md"
            write(
                release,
                f"Release Decision: APPROVED\nIntegration Branch: {branch}\nIntegrated Commit: {commit}\n"
                f"Deployed Commit: {commit}\nArtifact Path: dist/artifact.bin\n"
                f"Artifact SHA256: {digest}\nTarget Environment: production\n"
                "Deployment Status: PASS\nSmoke Test: PASS\n"
                "Production Verification: PASS\nRollback Ready: YES\n"
                "Release Approval: APPROVED\n",
            )
            result = run_gate(
                root, "release", "--work-item", str(work),
                "--release-evidence", str(release),
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("RELEASE GATE: PASS", result.stdout)


if __name__ == "__main__":
    unittest.main()

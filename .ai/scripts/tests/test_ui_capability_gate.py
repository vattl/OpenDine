from __future__ import annotations

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "validate_ui_capabilities.py"


def write(path: Path, text: str = "evidence\n") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def run_gate(root: Path, ui_dir: Path, phase: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable, str(SCRIPT), "--root", str(root),
            "--ui-dir", str(ui_dir), "--phase", phase,
        ],
        text=True,
        capture_output=True,
    )


def contract(rows: list[str], *, unmapped: int = 0, fake: int = 0, unresolved: int = 0) -> str:
    return (
        "# Prototype Interaction Capability Contract\n\n"
        "Capability Mapping Status: COMPLETE\n"
        "All Prototype Interactions Mapped: YES\n"
        f"Unmapped Prototype Interactions: {unmapped}\n"
        f"Production Fake/Mock/Placeholder Interactions: {fake}\n"
        f"Unresolved Required Backend Capabilities: {unresolved}\n\n"
        "| Interaction ID | Prototype Interaction | Classification | Production Integration | Contract / Capability Evidence | Capability Request | E2E Evidence | Status |\n"
        "|---|---|---|---|---|---|---|---|\n"
        + "\n".join(rows)
        + "\n"
    )


class UiCapabilityGateTests(unittest.TestCase):
    def test_missing_interaction_contract_blocks_plan(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            ui_dir = root / "design" / "ui-1"
            ui_dir.mkdir(parents=True)
            result = run_gate(root, ui_dir, "plan")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("PROTOTYPE_INTERACTION_CONTRACT.md", result.stdout)

    def test_new_api_without_capability_request_blocks_and_reports_coordination(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            ui_dir = root / "design" / "ui-1"
            write(
                ui_dir / "PROTOTYPE_INTERACTION_CONTRACT.md",
                contract([
                    "| INT-01 | Submit reservation | NEW_API | src/reservation.ts | N/A | requests/RESERVE.md | PENDING | PLANNED |"
                ], unresolved=1),
            )
            result = run_gate(root, ui_dir, "plan")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("capability request", result.stdout.lower())
            report = (ui_dir / "BACKEND_COORDINATION_REPORT.md").read_text(encoding="utf-8")
            self.assertIn("INT-01", report)
            self.assertIn("OPEN", report)

    def test_not_supported_interaction_blocks_until_prototype_is_revised(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            ui_dir = root / "design" / "ui-1"
            write(
                ui_dir / "PROTOTYPE_INTERACTION_CONTRACT.md",
                contract([
                    "| INT-02 | Export billing report | NOT_SUPPORTED | N/A | N/A | N/A | PENDING | BLOCKED |"
                ], unresolved=1),
            )
            result = run_gate(root, ui_dir, "plan")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("revise and re-approve", result.stdout.lower())

    def test_accept_blocks_fake_or_unverified_production_interactions(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            ui_dir = root / "design" / "ui-1"
            request = ui_dir / "requests" / "RESERVE.md"
            write(request, "Status: IMPLEMENTED\nOwner: backend-team\n")
            write(
                ui_dir / "PROTOTYPE_INTERACTION_CONTRACT.md",
                contract([
                    "| INT-01 | Submit reservation | NEW_API | src/reservation.ts | N/A | requests/RESERVE.md | PENDING | IMPLEMENTED |"
                ], fake=1, unresolved=1),
            )
            result = run_gate(root, ui_dir, "accept")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("must be 0", result.stdout)
            self.assertIn("VERIFIED", result.stdout)
            self.assertIn("E2E", result.stdout)

    def test_available_capability_without_real_contract_evidence_blocks_plan(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            ui_dir = root / "design" / "ui-1"
            write(
                ui_dir / "PROTOTYPE_INTERACTION_CONTRACT.md",
                contract([
                    "| INT-03 | Filter members | AVAILABLE | src/filters.ts | PENDING | N/A | PENDING | PLANNED |"
                ]),
            )
            result = run_gate(root, ui_dir, "plan")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Contract / Capability Evidence", result.stdout)

    def test_planned_backend_request_allows_plan_but_stays_in_coordination_report(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            ui_dir = root / "design" / "ui-1"
            write(
                ui_dir / "requests" / "RESERVE.md",
                "Status: PROPOSED\nOwner: backend-team\n",
            )
            write(
                ui_dir / "PROTOTYPE_INTERACTION_CONTRACT.md",
                contract([
                    "| INT-04 | Submit reservation | NEW_API | src/reservation.ts | N/A | requests/RESERVE.md | PENDING | PLANNED |"
                ], unresolved=1),
            )
            result = run_gate(root, ui_dir, "plan")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            report = (ui_dir / "BACKEND_COORDINATION_REPORT.md").read_text(encoding="utf-8")
            self.assertIn("Coordination Status: OPEN", report)
            self.assertIn("backend-team", report)

    def test_complete_existing_and_new_api_interactions_pass_both_phases(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            ui_dir = root / "design" / "ui-1"
            write(root / "src" / "filters.ts", "export const filters = true;\n")
            write(root / "src" / "reservation.ts", "export const reservation = true;\n")
            write(ui_dir / "evidence" / "filter-contract.txt", "GET /api/members supports filters\n")
            write(ui_dir / "evidence" / "filter-e2e.txt", "PASS\n")
            write(ui_dir / "evidence" / "reservation-e2e.txt", "PASS\n")
            write(
                ui_dir / "requests" / "RESERVE.md",
                "Status: VERIFIED\nOwner: backend-team\nVerification Evidence: evidence/reservation-e2e.txt\n",
            )
            write(
                ui_dir / "PROTOTYPE_INTERACTION_CONTRACT.md",
                contract([
                    "| INT-01 | Filter members | AVAILABLE | src/filters.ts | evidence/filter-contract.txt | N/A | evidence/filter-e2e.txt | VERIFIED |",
                    "| INT-02 | Submit reservation | NEW_API | src/reservation.ts | N/A | requests/RESERVE.md | evidence/reservation-e2e.txt | VERIFIED |",
                ]),
            )
            planned = run_gate(root, ui_dir, "plan")
            accepted = run_gate(root, ui_dir, "accept")
            self.assertEqual(planned.returncode, 0, planned.stdout + planned.stderr)
            self.assertEqual(accepted.returncode, 0, accepted.stdout + accepted.stderr)
            self.assertIn("UI CAPABILITY ACCEPTANCE GATE: PASS", accepted.stdout)
            report = (ui_dir / "BACKEND_COORDINATION_REPORT.md").read_text(encoding="utf-8")
            self.assertIn("Coordination Status: CLEAR", report)


if __name__ == "__main__":
    unittest.main()

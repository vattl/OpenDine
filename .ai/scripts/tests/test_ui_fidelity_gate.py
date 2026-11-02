from __future__ import annotations

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / ".ai" / "scripts" / "validate_ui_fidelity.py"


def prepare_complete_evidence(root: Path) -> Path:
    ui_dir = root / "design" / "visual-verification" / "UI999"
    ui_dir.mkdir(parents=True, exist_ok=True)
    (ui_dir / "UI_IMPLEMENTATION_MAP.md").write_text(
        """# UI Implementation Map
Mapping Status: COMPLETE
All Prototype Regions Mapped: YES
Unmapped Prototype Regions: 0
Legacy Structure Reused Without Approval: NO

| Prototype Region | Production File / Component | Operation | Business Logic | Visual Constraints | Notes |
|---|---|---|---|---|---|
| header | src/Header.tsx | REPLACE | PRESERVE | height=72 | approved target |
""",
        encoding="utf-8",
    )
    (ui_dir / "MEASURED_UI_SPEC.md").write_text(
        """# Measured UI Specification
Measurement Status: COMPLETE
Material UNKNOWN Count: 0
Reference Viewport: 1440x900
""",
        encoding="utf-8",
    )
    (ui_dir / "STRUCTURAL_DIFF.md").write_text(
        """# Structural Diff
Plan Status: APPROVED
Unclassified Legacy Regions: 0
Target State Match: YES
Legacy Remaining: NO
Unexpected Active Behavior: NO
Final Status: VERIFIED

| ID | Element | Current | Target | Operation | Risk |
|---|---|---|---|---|---|
| D1 | legacy-shell | old wrapper | approved shell | REPLACE | MEDIUM |
""",
        encoding="utf-8",
    )
    (ui_dir / "SCREENSHOT_VISUAL_DIFF_REPORT.md").write_text(
        """# Screenshot Visual Diff Report
Prototype Screenshot: prototype.png
Production Screenshot: production.png
Diff Image: diff.png
Image Dimensions Match: YES
Critical Deltas: 0
High Deltas: 0
Decision: APPROVED
Production Presented To User: YES
User Fidelity Confirmation: APPROVED
""",
        encoding="utf-8",
    )
    for name in ("prototype.png", "production.png", "diff.png"):
        (ui_dir / name).write_bytes(b"evidence")
    return ui_dir


def run_gate(
    root: Path, ui_dir: Path, *, phase: str = "accept"
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            str(SCRIPT),
            "--root",
            str(root),
            "--ui-dir",
            ui_dir.relative_to(root).as_posix(),
            "--phase",
            phase,
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )


class UiFidelityGateTests(unittest.TestCase):
    def test_complete_translation_plan_passes_before_production_editing(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            ui_dir = prepare_complete_evidence(root)
            (ui_dir / "SCREENSHOT_VISUAL_DIFF_REPORT.md").unlink()
            for name in ("prototype.png", "production.png", "diff.png"):
                (ui_dir / name).unlink()

            result = run_gate(root, ui_dir, phase="plan")

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("UI TRANSLATION PLAN GATE: PASS", result.stdout)

    def test_complete_translation_and_fidelity_evidence_passes(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            ui_dir = prepare_complete_evidence(root)

            result = run_gate(root, ui_dir)

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("UI FIDELITY GATE: PASS", result.stdout)

    def test_missing_implementation_map_blocks_acceptance(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            ui_dir = prepare_complete_evidence(root)
            (ui_dir / "UI_IMPLEMENTATION_MAP.md").unlink()

            result = run_gate(root, ui_dir)

            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("UI_IMPLEMENTATION_MAP.md", result.stdout)

    def test_status_only_mapping_without_rows_blocks_acceptance(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            ui_dir = prepare_complete_evidence(root)
            mapping = ui_dir / "UI_IMPLEMENTATION_MAP.md"
            mapping.write_text(
                mapping.read_text(encoding="utf-8").replace(
                    "| header | src/Header.tsx | REPLACE | PRESERVE | height=72 | approved target |\n",
                    "",
                ),
                encoding="utf-8",
            )

            result = run_gate(root, ui_dir)

            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("mapping table", result.stdout.lower())

    def test_legacy_structure_remaining_blocks_acceptance(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            ui_dir = prepare_complete_evidence(root)
            structural_diff = ui_dir / "STRUCTURAL_DIFF.md"
            structural_diff.write_text(
                structural_diff.read_text(encoding="utf-8").replace(
                    "Legacy Remaining: NO", "Legacy Remaining: YES"
                ),
                encoding="utf-8",
            )

            result = run_gate(root, ui_dir)

            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("legacy structure remains", result.stdout.lower())

    def test_partial_target_match_blocks_functionally_usable_ui(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            ui_dir = prepare_complete_evidence(root)
            structural_diff = ui_dir / "STRUCTURAL_DIFF.md"
            structural_diff.write_text(
                structural_diff.read_text(encoding="utf-8").replace(
                    "Target State Match: YES", "Target State Match: PARTIAL"
                ),
                encoding="utf-8",
            )

            result = run_gate(root, ui_dir)

            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("target state match", result.stdout.lower())

    def test_missing_user_fidelity_confirmation_blocks_acceptance(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            ui_dir = prepare_complete_evidence(root)
            report = ui_dir / "SCREENSHOT_VISUAL_DIFF_REPORT.md"
            report.write_text(
                report.read_text(encoding="utf-8").replace(
                    "User Fidelity Confirmation: APPROVED",
                    "User Fidelity Confirmation: PENDING",
                ),
                encoding="utf-8",
            )

            result = run_gate(root, ui_dir)

            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("user fidelity confirmation", result.stdout.lower())


if __name__ == "__main__":
    unittest.main()

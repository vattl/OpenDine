from __future__ import annotations

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / ".ai" / "scripts" / "validate_ui_adaptive.py"


def write(path: Path, text: str = "evidence\n") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def create_contract(root: Path, *, multi_device: bool = False) -> Path:
    ui_dir = root / "design" / "prototypes" / "UI999-adaptive"
    ui_dir.mkdir(parents=True, exist_ok=True)

    profiles = [
        "| DESKTOP | Desktop Web | 1440x900 | Landscape | Pointer + Keyboard | Office operations | REQUIRED | COMPACT / side-nav | desktop-prototype.png | READY |",
    ]
    components = [
        "| BTN-PRIMARY | Button / Primary action | desktop-compact | DESKTOP | control-md | 32px visual / 40px hit | icon-md | label-md | space-2/3 | inline toolbar | default/focus/disabled/loading | READY |",
    ]
    operations = [
        "| OP-001 | Create order | CRITICAL | DESKTOP | Orders / New | Submit order | Confirmation + order ID | Inline errors + retry | Dialog on desktop | INT-001 | READY |",
    ]

    if multi_device:
        profiles.extend(
            [
                "| PHONE | Mobile Web | 375x812 | Portrait | Touch | On-the-go operation | REQUIRED | COMFORTABLE / bottom-nav | phone-prototype.png | READY |",
                "| TABLET | Tablet Web | 1024x768 | Landscape | Touch + Keyboard | Counter operation | REQUIRED | COMFORTABLE / adaptive rail | tablet-prototype.png | READY |",
            ]
        )
        components.extend(
            [
                "| BTN-PRIMARY-MOBILE | Button / Primary action | touch-prominent | PHONE,TABLET | control-lg | 48px | icon-md | label-md | space-3/4 | sticky action bar | default/focus/pressed/disabled/loading | READY |",
                "| FIELD-DEFAULT | Input / data entry | adaptive-field | ALL_REQUIRED | field-adaptive | 44px desktop / 48px touch | icon-sm | body-md | space-2/3 | full-width on phone | default/focus/error/disabled | READY |",
            ]
        )
        operations[0] = "| OP-001 | Create order | CRITICAL | ALL_REQUIRED | Orders / New | Submit order | Confirmation + order ID | Inline errors + retry | Dialog desktop / full-screen phone / sheet tablet | INT-001 | READY |"

    required_count = 3 if multi_device else 1
    write(
        ui_dir / "ADAPTIVE_UI_CONTRACT.md",
        "# Adaptive UI Contract\n\n"
        "Adaptive Contract Status: COMPLETE\n"
        f"Required Device Profiles: {required_count}\n"
        f"Covered Required Profiles: {required_count}\n"
        "Unmapped Critical Operations: 0\n"
        "Unresolved Component Variants: 0\n"
        "Arbitrary Component Size Values: 0\n\n"
        "## Device Experience Profiles\n\n"
        "| Profile ID | Terminal / Platform | Viewport | Orientation | Input Modality | Usage Context | Support | Density / Navigation | Prototype Evidence | Status |\n"
        "|---|---|---|---|---|---|---|---|---|---|\n"
        + "\n".join(profiles)
        + "\n\n## Component Family Contract\n\n"
        "| Component ID | Family / Role | Variant | Profiles | Visual Size Token | Hit Target | Icon Token | Typography Token | Spacing Token | Adaptation | States | Status |\n"
        "|---|---|---|---|---|---|---|---|---|---|---|---|\n"
        + "\n".join(components)
        + "\n\n## Business Operation Coverage\n\n"
        "| Operation ID | Business Operation | Priority | Required Profiles | Entry / Navigation | Primary Action | Completion Feedback | Error / Recovery | Adaptive Pattern | Capability Link | Status |\n"
        "|---|---|---|---|---|---|---|---|---|---|---|\n"
        + "\n".join(operations)
        + "\n",
    )
    for profile in ("desktop", "phone", "tablet"):
        if profile == "desktop" or multi_device:
            (ui_dir / f"{profile}-prototype.png").write_bytes(b"prototype")
    return ui_dir


def create_acceptance_report(ui_dir: Path, *, multi_device: bool = False) -> None:
    profiles = [
        "| DESKTOP | desktop-production.png | PASS | desktop-operation.txt | 0 | PASS | NOT_APPLICABLE | VERIFIED |",
    ]
    operation_rows = [
        "| OP-001 | DESKTOP | desktop-operation.txt | PASS |",
    ]
    if multi_device:
        profiles.extend(
            [
                "| PHONE | phone-production.png | PASS | phone-operation.txt | 0 | PASS | PASS | VERIFIED |",
                "| TABLET | tablet-production.png | PASS | tablet-operation.txt | 0 | PASS | PASS | VERIFIED |",
            ]
        )
        operation_rows.extend(
            [
                "| OP-001 | PHONE | phone-operation.txt | PASS |",
                "| OP-001 | TABLET | tablet-operation.txt | PASS |",
            ]
        )
    required_count = 3 if multi_device else 1
    write(
        ui_dir / "DEVICE_UX_VERIFICATION_REPORT.md",
        "# Device UX Verification Report\n\n"
        "Adaptive Verification Status: VERIFIED\n"
        f"Required Device Profiles: {required_count}\n"
        f"Verified Required Profiles: {required_count}\n"
        "Failed Required Profiles: 0\n"
        "Critical Operation Failures: 0\n"
        "Component Consistency Violations: 0\n"
        "Unintended Overflow / Clipping: 0\n"
        "Input Modality Checks: PASS\n"
        "Orientation / Safe Area Checks: PASS\n"
        "Business Operation Checks: PASS\n\n"
        "## Required Profile Verification\n\n"
        "| Profile ID | Production Evidence | Component Check | Operation Evidence | Overflow / Clipping | Input / Focus | Orientation / Safe Area | Status |\n"
        "|---|---|---|---|---|---|---|---|\n"
        + "\n".join(profiles)
        + "\n\n## Operation Verification\n\n"
        "| Operation ID | Profile ID | E2E / Manual Evidence | Result |\n"
        "|---|---|---|---|\n"
        + "\n".join(operation_rows)
        + "\n",
    )
    for profile in ("desktop", "phone", "tablet"):
        if profile == "desktop" or multi_device:
            (ui_dir / f"{profile}-production.png").write_bytes(b"production")
            write(ui_dir / f"{profile}-operation.txt", "verified operation\n")


def run_gate(root: Path, ui_dir: Path, phase: str) -> subprocess.CompletedProcess[str]:
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


class UiAdaptiveGateTests(unittest.TestCase):
    def test_missing_adaptive_contract_blocks_plan(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            ui_dir = root / "design" / "prototypes" / "UI999-adaptive"
            ui_dir.mkdir(parents=True)

            result = run_gate(root, ui_dir, "plan")

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("ADAPTIVE_UI_CONTRACT.md", result.stdout)

    def test_complete_single_terminal_contract_passes_plan(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            ui_dir = create_contract(root)

            result = run_gate(root, ui_dir, "plan")

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("ADAPTIVE UI PLAN GATE: PASS", result.stdout)

    def test_required_profile_without_prototype_evidence_blocks_plan(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            ui_dir = create_contract(root, multi_device=True)
            (ui_dir / "phone-prototype.png").unlink()

            result = run_gate(root, ui_dir, "plan")

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("PHONE", result.stdout)
            self.assertIn("prototype evidence", result.stdout.lower())

    def test_arbitrary_component_sizes_block_plan(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            ui_dir = create_contract(root)
            contract = ui_dir / "ADAPTIVE_UI_CONTRACT.md"
            contract.write_text(
                contract.read_text(encoding="utf-8").replace(
                    "Arbitrary Component Size Values: 0",
                    "Arbitrary Component Size Values: 2",
                ),
                encoding="utf-8",
            )

            result = run_gate(root, ui_dir, "plan")

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Arbitrary Component Size Values", result.stdout)

    def test_operation_with_unknown_profile_blocks_plan(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            ui_dir = create_contract(root)
            contract = ui_dir / "ADAPTIVE_UI_CONTRACT.md"
            contract.write_text(
                contract.read_text(encoding="utf-8").replace(
                    "| OP-001 | Create order | CRITICAL | DESKTOP |",
                    "| OP-001 | Create order | CRITICAL | WATCH |",
                ),
                encoding="utf-8",
            )

            result = run_gate(root, ui_dir, "plan")

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("WATCH", result.stdout)

    def test_bare_measurement_in_component_token_blocks_plan(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            ui_dir = create_contract(root)
            contract = ui_dir / "ADAPTIVE_UI_CONTRACT.md"
            contract.write_text(
                contract.read_text(encoding="utf-8").replace(
                    "| control-md | 32px visual / 40px hit |",
                    "| 37px | 32px visual / 40px hit |",
                ),
                encoding="utf-8",
            )

            result = run_gate(root, ui_dir, "plan")

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Visual Size Token", result.stdout)
            self.assertIn("semantic token", result.stdout)

    def test_required_profile_without_component_coverage_blocks_plan(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            ui_dir = create_contract(root, multi_device=True)
            contract = ui_dir / "ADAPTIVE_UI_CONTRACT.md"
            text = contract.read_text(encoding="utf-8")
            text = text.replace(
                "| BTN-PRIMARY-MOBILE | Button / Primary action | touch-prominent | PHONE,TABLET | control-lg | 48px | icon-md | label-md | space-3/4 | sticky action bar | default/focus/pressed/disabled/loading | READY |\n",
                "",
            ).replace(
                "| FIELD-DEFAULT | Input / data entry | adaptive-field | ALL_REQUIRED | field-adaptive | 44px desktop / 48px touch | icon-sm | body-md | space-2/3 | full-width on phone | default/focus/error/disabled | READY |",
                "| FIELD-DEFAULT | Input / data entry | adaptive-field | DESKTOP,TABLET | field-adaptive | 44px desktop / 48px touch | icon-sm | body-md | space-2/3 | full-width on phone | default/focus/error/disabled | READY |",
            )
            contract.write_text(text, encoding="utf-8")

            result = run_gate(root, ui_dir, "plan")

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("PHONE", result.stdout)
            self.assertIn("component-family coverage", result.stdout)

    def test_operation_cannot_reference_unsupported_profile(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            ui_dir = create_contract(root)
            contract = ui_dir / "ADAPTIVE_UI_CONTRACT.md"
            text = contract.read_text(encoding="utf-8")
            unsupported_row = "| WATCH | Watch | 200x200 | Portrait | Touch | Glance only | UNSUPPORTED | N/A | N/A | BLOCKED |\n"
            text = text.replace(
                "| DESKTOP | Desktop Web | 1440x900 | Landscape | Pointer + Keyboard | Office operations | REQUIRED | COMPACT / side-nav | desktop-prototype.png | READY |\n",
                "| DESKTOP | Desktop Web | 1440x900 | Landscape | Pointer + Keyboard | Office operations | REQUIRED | COMPACT / side-nav | desktop-prototype.png | READY |\n"
                + unsupported_row,
            ).replace(
                "| OP-001 | Create order | CRITICAL | DESKTOP |",
                "| OP-001 | Create order | CRITICAL | WATCH |",
            )
            contract.write_text(text, encoding="utf-8")

            result = run_gate(root, ui_dir, "plan")

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("WATCH", result.stdout)
            self.assertIn("unsupported", result.stdout.lower())

    def test_accept_requires_device_verification_report(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            ui_dir = create_contract(root)

            result = run_gate(root, ui_dir, "accept")

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("DEVICE_UX_VERIFICATION_REPORT.md", result.stdout)

    def test_accept_blocks_component_consistency_violation(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            ui_dir = create_contract(root)
            create_acceptance_report(ui_dir)
            report = ui_dir / "DEVICE_UX_VERIFICATION_REPORT.md"
            report.write_text(
                report.read_text(encoding="utf-8").replace(
                    "Component Consistency Violations: 0",
                    "Component Consistency Violations: 1",
                ),
                encoding="utf-8",
            )

            result = run_gate(root, ui_dir, "accept")

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Component Consistency Violations", result.stdout)

    def test_accept_blocks_missing_required_profile_operation_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            ui_dir = create_contract(root, multi_device=True)
            create_acceptance_report(ui_dir, multi_device=True)
            report = ui_dir / "DEVICE_UX_VERIFICATION_REPORT.md"
            report.write_text(
                report.read_text(encoding="utf-8").replace(
                    "| OP-001 | PHONE | phone-operation.txt | PASS |\n", ""
                ),
                encoding="utf-8",
            )

            result = run_gate(root, ui_dir, "accept")

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("OP-001", result.stdout)
            self.assertIn("PHONE", result.stdout)

    def test_complete_multi_device_evidence_passes_acceptance(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            ui_dir = create_contract(root, multi_device=True)
            create_acceptance_report(ui_dir, multi_device=True)

            result = run_gate(root, ui_dir, "accept")

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("ADAPTIVE UI ACCEPTANCE GATE: PASS", result.stdout)


if __name__ == "__main__":
    unittest.main()

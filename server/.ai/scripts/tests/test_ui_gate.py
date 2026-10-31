from __future__ import annotations

from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]


def run_gate(root: Path, prototype_dir: Path, flag: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            ".ai/scripts/validate_ui_gate.py",
            "--root",
            str(root),
            flag,
            "--prototype-dir",
            prototype_dir.relative_to(root).as_posix(),
        ],
        cwd=root,
        text=True,
        capture_output=True,
        check=False,
    )


def prepare_prototype(
    root: Path, *, extension: str, approval_status: str, presented: str = "YES"
) -> Path:
    prototype_dir = root / "design" / "prototypes" / "UI999-test-prototype"
    prototype_dir.mkdir(parents=True, exist_ok=True)
    (prototype_dir / f"prototype{extension}").write_text(
        "<!doctype html><title>Prototype</title>" if extension == ".html" else "export default {};",
        encoding="utf-8",
    )
    (prototype_dir / "prototype.png").write_bytes(b"visual-evidence")
    (prototype_dir / "PROTOTYPE_APPROVAL.md").write_text(
        f"Presented To User: {presented}\nApproval Status: {approval_status}\n",
        encoding="utf-8",
    )
    (prototype_dir / "UI_LOCK_MANIFEST.md").write_text(
        "Status: UI_LOCKED\n", encoding="utf-8"
    )
    return prototype_dir


class HtmlPrototypeGateTests(unittest.TestCase):
    def copy_package(self, temp_dir: str) -> Path:
        copied_root = Path(temp_dir) / "package"
        shutil.copytree(ROOT, copied_root)
        return copied_root

    def test_approved_html_prototype_passes_ui_gate(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = self.copy_package(temp_dir)
            prototype_dir = prepare_prototype(
                root, extension=".html", approval_status="APPROVED"
            )

            result = run_gate(root, prototype_dir, "--require-ui-prototype")

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("HTML prototypes: 1", result.stdout)
            self.assertIn("Explicit approvals: 1", result.stdout)

    def test_non_html_prototype_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = self.copy_package(temp_dir)
            prototype_dir = prepare_prototype(
                root, extension=".tsx", approval_status="APPROVED"
            )

            result = run_gate(root, prototype_dir, "--require-ui-prototype")

            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("HTML prototype", result.stdout)

    def test_waived_approval_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = self.copy_package(temp_dir)
            prototype_dir = prepare_prototype(
                root, extension=".html", approval_status="WAIVED_BY_USER"
            )

            result = run_gate(root, prototype_dir, "--require-ui-prototype")

            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("explicit user approval", result.stdout.lower())

    def test_unpresented_html_prototype_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = self.copy_package(temp_dir)
            prototype_dir = prepare_prototype(
                root, extension=".html", approval_status="APPROVED", presented="NO"
            )

            result = run_gate(root, prototype_dir, "--require-ui-prototype")

            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("presented to user", result.stdout.lower())

    def test_presentation_and_approval_must_share_one_record(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = self.copy_package(temp_dir)
            prototype_dir = prepare_prototype(
                root, extension=".html", approval_status="APPROVED", presented="NO"
            )
            (prototype_dir / "PRESENTATION_APPROVAL.md").write_text(
                "Presented To User: YES\nApproval Status: DRAFT\n",
                encoding="utf-8",
            )

            result = run_gate(root, prototype_dir, "--require-ui-prototype")

            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("same approval record", result.stdout.lower())

    def test_structural_flag_remains_a_compatible_alias(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = self.copy_package(temp_dir)
            prototype_dir = prepare_prototype(
                root, extension=".html", approval_status="APPROVED"
            )

            result = run_gate(root, prototype_dir, "--require-structural-ui")

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()

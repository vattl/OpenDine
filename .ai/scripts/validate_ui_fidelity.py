#!/usr/bin/env python3
"""Validate prototype-to-production translation and final UI fidelity evidence."""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys


ARTIFACTS = {
    "implementation_map": "UI_IMPLEMENTATION_MAP.md",
    "measured_spec": "MEASURED_UI_SPEC.md",
    "structural_diff": "STRUCTURAL_DIFF.md",
    "visual_report": "SCREENSHOT_VISUAL_DIFF_REPORT.md",
}

PLACEHOLDERS = {"", "-", "TBD", "UNKNOWN", "PENDING", "PATH"}


def field(text: str, name: str) -> str:
    match = re.search(
        rf"(?mi)^\s*(?:[-*]\s*)?{re.escape(name)}\s*:\s*(.*?)\s*$", text
    )
    return match.group(1).strip() if match else ""


def table_has_data_row(text: str, header_marker: str) -> bool:
    in_table = False
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("|") and header_marker.lower() in stripped.lower():
            in_table = True
            continue
        if not in_table:
            continue
        if stripped.startswith("#"):
            return False
        if not (stripped.startswith("|") and stripped.endswith("|")):
            continue
        if set(stripped) <= {"|", "-", ":", " "}:
            continue
        cells = [cell.strip() for cell in stripped.strip("|").split("|")]
        if any(cell and cell.upper() not in PLACEHOLDERS for cell in cells):
            return True
    return False


def require_value(
    blockers: list[str], text: str, name: str, expected: str, artifact: str
) -> None:
    actual = field(text, name)
    if actual.upper() != expected:
        blockers.append(
            f"{artifact}: {name} must be {expected}, got {actual or '<missing>'}"
        )


def require_zero(
    blockers: list[str], text: str, name: str, artifact: str
) -> None:
    actual = field(text, name)
    try:
        value = int(actual)
    except ValueError:
        blockers.append(f"{artifact}: {name} must be integer 0, got {actual or '<missing>'}")
        return
    if value != 0:
        blockers.append(f"{artifact}: {name} must be 0, got {value}")


def resolve_evidence_path(
    root: Path, report_path: Path, value: str, label: str, blockers: list[str]
) -> None:
    if value.upper() in PLACEHOLDERS:
        blockers.append(f"visual report: {label} path is missing or unresolved")
        return
    candidate = Path(value)
    if not candidate.is_absolute():
        candidate = report_path.parent / candidate
    resolved = candidate.resolve()
    try:
        resolved.relative_to(root)
    except ValueError:
        blockers.append(f"visual report: {label} path escapes repository root: {value}")
        return
    if not resolved.is_file() or resolved.stat().st_size == 0:
        blockers.append(f"visual report: {label} evidence is missing or empty: {value}")


def validate(root: Path, ui_dir: Path, phase: str = "accept") -> list[str]:
    blockers: list[str] = []
    resolved_root = root.resolve()
    resolved_ui_dir = ui_dir.resolve()
    try:
        resolved_ui_dir.relative_to(resolved_root)
    except ValueError:
        return [f"UI evidence directory escapes repository root: {resolved_ui_dir}"]

    paths = {key: resolved_ui_dir / name for key, name in ARTIFACTS.items()}
    required_keys = (
        ("implementation_map", "measured_spec", "structural_diff")
        if phase == "plan"
        else tuple(ARTIFACTS)
    )
    for key in required_keys:
        path = paths[key]
        if not path.is_file():
            blockers.append(f"required fidelity artifact missing: {path.name}")

    if paths["implementation_map"].is_file():
        text = paths["implementation_map"].read_text(encoding="utf-8", errors="replace")
        artifact = paths["implementation_map"].name
        require_value(blockers, text, "Mapping Status", "COMPLETE", artifact)
        require_value(blockers, text, "All Prototype Regions Mapped", "YES", artifact)
        require_zero(blockers, text, "Unmapped Prototype Regions", artifact)
        require_value(
            blockers,
            text,
            "Legacy Structure Reused Without Approval",
            "NO",
            artifact,
        )
        if not table_has_data_row(text, "Prototype Region"):
            blockers.append(
                f"{artifact}: mapping table has no populated prototype-region rows"
            )

    if paths["measured_spec"].is_file():
        text = paths["measured_spec"].read_text(encoding="utf-8", errors="replace")
        artifact = paths["measured_spec"].name
        require_value(blockers, text, "Measurement Status", "COMPLETE", artifact)
        require_zero(blockers, text, "Material UNKNOWN Count", artifact)
        viewport = field(text, "Reference Viewport")
        if viewport.upper() in PLACEHOLDERS:
            blockers.append(f"{artifact}: Reference Viewport must be resolved")

    if paths["structural_diff"].is_file():
        text = paths["structural_diff"].read_text(encoding="utf-8", errors="replace")
        artifact = paths["structural_diff"].name
        require_value(blockers, text, "Plan Status", "APPROVED", artifact)
        require_zero(blockers, text, "Unclassified Legacy Regions", artifact)
        if not table_has_data_row(text, "| ID | Element"):
            blockers.append(
                f"{artifact}: structural diff table has no populated legacy/target rows"
            )
        if phase == "accept":
            require_value(blockers, text, "Target State Match", "YES", artifact)
            if field(text, "Legacy Remaining").upper() != "NO":
                blockers.append(f"{artifact}: legacy structure remains; expected Legacy Remaining: NO")
            require_value(blockers, text, "Unexpected Active Behavior", "NO", artifact)
            require_value(blockers, text, "Final Status", "VERIFIED", artifact)

    if phase == "accept" and paths["visual_report"].is_file():
        report_path = paths["visual_report"]
        text = report_path.read_text(encoding="utf-8", errors="replace")
        artifact = report_path.name
        for label in ("Prototype Screenshot", "Production Screenshot", "Diff Image"):
            resolve_evidence_path(
                resolved_root, report_path, field(text, label), label, blockers
            )
        require_value(blockers, text, "Image Dimensions Match", "YES", artifact)
        require_zero(blockers, text, "Critical Deltas", artifact)
        require_zero(blockers, text, "High Deltas", artifact)
        require_value(blockers, text, "Decision", "APPROVED", artifact)
        require_value(
            blockers, text, "Production Presented To User", "YES", artifact
        )
        require_value(
            blockers, text, "User Fidelity Confirmation", "APPROVED", artifact
        )

    return blockers


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate final UI translation and fidelity evidence"
    )
    parser.add_argument("--root", default=".")
    parser.add_argument("--ui-dir", required=True)
    parser.add_argument("--phase", choices=("plan", "accept"), default="accept")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    ui_dir = Path(args.ui_dir)
    if not ui_dir.is_absolute():
        ui_dir = root / ui_dir

    blockers = validate(root, ui_dir, args.phase)
    if blockers:
        print(
            "UI TRANSLATION PLAN GATE: BLOCKED"
            if args.phase == "plan"
            else "UI FIDELITY GATE: BLOCKED"
        )
        for blocker in blockers:
            print(f"- {blocker}")
        print(
            "Production UI Editing: FORBIDDEN"
            if args.phase == "plan"
            else "UI Acceptance: FORBIDDEN"
        )
        return 3

    if args.phase == "plan":
        print("UI TRANSLATION PLAN GATE: PASS")
        print("Prototype regions mapped: YES")
        print("Unclassified legacy regions: 0")
        print("Production UI Editing: AUTHORIZED BY TRANSLATION PLAN")
        return 0

    print("UI FIDELITY GATE: PASS")
    print("Prototype regions mapped: YES")
    print("Legacy structure remaining: NO")
    print("Target state match: YES")
    print("User fidelity confirmation: APPROVED")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Validate adaptive multi-device UI planning and production evidence."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import re
import sys


CONTRACT_NAME = "ADAPTIVE_UI_CONTRACT.md"
REPORT_NAME = "DEVICE_UX_VERIFICATION_REPORT.md"
PLACEHOLDERS = {"", "-", "TBD", "UNKNOWN", "PENDING", "PATH", "N/A"}
BARE_MEASUREMENT = re.compile(r"^\s*\d+(?:\.\d+)?(?:px|pt|dp|rem|em|%)\s*$", re.I)


@dataclass(frozen=True)
class OperationScope:
    operation_id: str
    profiles: frozenset[str]


def field(text: str, name: str) -> str:
    match = re.search(
        rf"(?mi)^\s*(?:[-*]\s*)?{re.escape(name)}\s*:\s*(.*?)\s*$", text
    )
    return match.group(1).strip() if match else ""


def is_placeholder(value: str, *, allow_na: bool = False) -> bool:
    normalized = value.strip().strip("`").upper()
    return normalized in (PLACEHOLDERS - ({"N/A"} if allow_na else set()))


def require_value(
    errors: list[str], text: str, name: str, expected: str, artifact: str
) -> None:
    actual = field(text, name)
    if actual.upper() != expected:
        errors.append(
            f"{artifact}: {name} must be {expected}, got {actual or '<missing>'}"
        )


def integer_field(
    errors: list[str], text: str, name: str, artifact: str
) -> int | None:
    actual = field(text, name)
    try:
        return int(actual)
    except ValueError:
        errors.append(
            f"{artifact}: {name} must be an integer, got {actual or '<missing>'}"
        )
        return None


def require_zero(errors: list[str], text: str, name: str, artifact: str) -> None:
    value = integer_field(errors, text, name, artifact)
    if value is not None and value != 0:
        errors.append(f"{artifact}: {name} must be 0, got {value}")


def table_after_heading(
    text: str, heading: str, artifact: str, errors: list[str]
) -> list[dict[str, str]]:
    lines = text.splitlines()
    heading_index = next(
        (
            index
            for index, line in enumerate(lines)
            if re.fullmatch(rf"\s*#+\s+{re.escape(heading)}\s*", line, re.I)
        ),
        None,
    )
    if heading_index is None:
        errors.append(f"{artifact}: missing section {heading}")
        return []

    header_index = next(
        (
            index
            for index in range(heading_index + 1, len(lines))
            if lines[index].strip().startswith("|")
        ),
        None,
    )
    if header_index is None:
        errors.append(f"{artifact}: {heading} table is missing")
        return []

    headers = [cell.strip() for cell in lines[header_index].strip().strip("|").split("|")]
    rows: list[dict[str, str]] = []
    for line in lines[header_index + 1 :]:
        stripped = line.strip()
        if stripped.startswith("#") or (rows and not stripped):
            break
        if not (stripped.startswith("|") and stripped.endswith("|")):
            continue
        if set(stripped) <= {"|", "-", ":", " "}:
            continue
        cells = [cell.strip() for cell in stripped.strip("|").split("|")]
        if len(cells) != len(headers):
            errors.append(
                f"{artifact}: {heading} row has {len(cells)} cells; expected {len(headers)}"
            )
            continue
        rows.append(dict(zip(headers, cells)))
    if not rows:
        errors.append(f"{artifact}: {heading} table has no data rows")
    return rows


def require_columns(
    errors: list[str], rows: list[dict[str, str]], columns: tuple[str, ...], label: str
) -> bool:
    if not rows:
        return False
    missing = [column for column in columns if column not in rows[0]]
    if missing:
        errors.append(f"{label}: missing columns: {', '.join(missing)}")
        return False
    return True


def resolve_evidence(
    root: Path,
    artifact_path: Path,
    value: str,
    label: str,
    errors: list[str],
) -> None:
    if is_placeholder(value):
        errors.append(f"{label}: evidence path is missing or unresolved")
        return
    candidate = Path(value)
    if not candidate.is_absolute():
        candidate = artifact_path.parent / candidate
    resolved = candidate.resolve()
    try:
        resolved.relative_to(root.resolve())
    except ValueError:
        errors.append(f"{label}: evidence path escapes repository root: {value}")
        return
    if not resolved.is_file() or resolved.stat().st_size == 0:
        errors.append(f"{label}: evidence is missing or empty: {value}")


def parse_profile_list(
    value: str,
    required_profiles: set[str],
    all_profiles: set[str],
    label: str,
    errors: list[str],
) -> set[str]:
    if value.strip().upper() == "ALL_REQUIRED":
        return set(required_profiles)
    profiles = {
        item.strip().upper()
        for item in re.split(r"[,;/]", value)
        if item.strip()
    }
    if not profiles:
        errors.append(f"{label}: at least one profile is required")
        return set()
    unknown = profiles - all_profiles
    if unknown:
        errors.append(f"{label}: unknown profiles: {', '.join(sorted(unknown))}")
    return profiles - unknown


def validate_contract(
    root: Path, contract_path: Path
) -> tuple[list[str], set[str], list[OperationScope]]:
    errors: list[str] = []
    if not contract_path.is_file():
        return [f"required adaptive UI artifact missing: {CONTRACT_NAME}"], set(), []

    text = contract_path.read_text(encoding="utf-8", errors="replace")
    require_value(
        errors, text, "Adaptive Contract Status", "COMPLETE", CONTRACT_NAME
    )
    require_zero(errors, text, "Unmapped Critical Operations", CONTRACT_NAME)
    require_zero(errors, text, "Unresolved Component Variants", CONTRACT_NAME)
    require_zero(errors, text, "Arbitrary Component Size Values", CONTRACT_NAME)

    profile_rows = table_after_heading(
        text, "Device Experience Profiles", CONTRACT_NAME, errors
    )
    profile_columns = (
        "Profile ID",
        "Terminal / Platform",
        "Viewport",
        "Orientation",
        "Input Modality",
        "Usage Context",
        "Support",
        "Density / Navigation",
        "Prototype Evidence",
        "Status",
    )
    profiles_ok = require_columns(
        errors, profile_rows, profile_columns, f"{CONTRACT_NAME} device profiles"
    )
    all_profiles: set[str] = set()
    required_profiles: set[str] = set()
    unsupported_profiles: set[str] = set()
    if profiles_ok:
        for row in profile_rows:
            profile_id = row["Profile ID"].upper()
            if is_placeholder(profile_id):
                errors.append(f"{CONTRACT_NAME}: profile ID is missing")
                continue
            if profile_id in all_profiles:
                errors.append(f"{CONTRACT_NAME}: duplicate profile ID {profile_id}")
                continue
            all_profiles.add(profile_id)
            support = row["Support"].upper()
            if support not in {"REQUIRED", "OPTIONAL", "UNSUPPORTED"}:
                errors.append(
                    f"{profile_id}: Support must be REQUIRED, OPTIONAL or UNSUPPORTED"
                )
            if support != "REQUIRED":
                if support == "UNSUPPORTED":
                    unsupported_profiles.add(profile_id)
                continue
            required_profiles.add(profile_id)
            for column in profile_columns[1:8]:
                if is_placeholder(row[column]):
                    errors.append(f"{profile_id}: {column} must be resolved")
            if row["Status"].upper() != "READY":
                errors.append(f"{profile_id}: profile Status must be READY")
            resolve_evidence(
                root,
                contract_path,
                row["Prototype Evidence"],
                f"{profile_id} prototype evidence",
                errors,
            )

    declared_required = integer_field(
        errors, text, "Required Device Profiles", CONTRACT_NAME
    )
    declared_covered = integer_field(
        errors, text, "Covered Required Profiles", CONTRACT_NAME
    )
    if not required_profiles:
        errors.append(f"{CONTRACT_NAME}: at least one REQUIRED device profile is needed")
    if declared_required is not None and declared_required != len(required_profiles):
        errors.append(
            f"{CONTRACT_NAME}: Required Device Profiles is {declared_required}; found {len(required_profiles)}"
        )
    if declared_covered is not None and declared_covered != len(required_profiles):
        errors.append(
            f"{CONTRACT_NAME}: Covered Required Profiles is {declared_covered}; expected {len(required_profiles)}"
        )

    component_rows = table_after_heading(
        text, "Component Family Contract", CONTRACT_NAME, errors
    )
    component_columns = (
        "Component ID",
        "Family / Role",
        "Variant",
        "Profiles",
        "Visual Size Token",
        "Hit Target",
        "Icon Token",
        "Typography Token",
        "Spacing Token",
        "Adaptation",
        "States",
        "Status",
    )
    if require_columns(
        errors, component_rows, component_columns, f"{CONTRACT_NAME} components"
    ):
        component_ids: set[str] = set()
        component_profile_coverage: set[str] = set()
        for row in component_rows:
            component_id = row["Component ID"].upper()
            if is_placeholder(component_id):
                errors.append(f"{CONTRACT_NAME}: Component ID is missing")
                continue
            if component_id in component_ids:
                errors.append(f"{CONTRACT_NAME}: duplicate Component ID {component_id}")
            component_ids.add(component_id)
            for column in component_columns[1:11]:
                if is_placeholder(row[column]):
                    errors.append(f"{component_id}: {column} must be resolved")
            for column in (
                "Visual Size Token",
                "Icon Token",
                "Typography Token",
                "Spacing Token",
            ):
                if BARE_MEASUREMENT.fullmatch(row[column]):
                    errors.append(
                        f"{component_id}: {column} must use a semantic token, not bare measurement {row[column]}"
                    )
            component_profiles = parse_profile_list(
                row["Profiles"],
                required_profiles,
                all_profiles,
                f"{component_id} Profiles",
                errors,
            )
            unsupported = component_profiles & unsupported_profiles
            if unsupported:
                errors.append(
                    f"{component_id}: component cannot target unsupported profiles: "
                    + ", ".join(sorted(unsupported))
                )
            component_profile_coverage.update(component_profiles & required_profiles)
            if row["Status"].upper() != "READY":
                errors.append(f"{component_id}: component Status must be READY")
        missing_component_profiles = required_profiles - component_profile_coverage
        if missing_component_profiles:
            errors.append(
                f"{CONTRACT_NAME}: required profiles lack component-family coverage: "
                + ", ".join(sorted(missing_component_profiles))
            )

    operation_rows = table_after_heading(
        text, "Business Operation Coverage", CONTRACT_NAME, errors
    )
    operation_columns = (
        "Operation ID",
        "Business Operation",
        "Priority",
        "Required Profiles",
        "Entry / Navigation",
        "Primary Action",
        "Completion Feedback",
        "Error / Recovery",
        "Adaptive Pattern",
        "Capability Link",
        "Status",
    )
    operations: list[OperationScope] = []
    profile_operation_coverage: set[str] = set()
    if require_columns(
        errors, operation_rows, operation_columns, f"{CONTRACT_NAME} operations"
    ):
        operation_ids: set[str] = set()
        for row in operation_rows:
            operation_id = row["Operation ID"].upper()
            if is_placeholder(operation_id):
                errors.append(f"{CONTRACT_NAME}: Operation ID is missing")
                continue
            if operation_id in operation_ids:
                errors.append(f"{CONTRACT_NAME}: duplicate Operation ID {operation_id}")
            operation_ids.add(operation_id)
            for column in operation_columns[1:10]:
                if is_placeholder(row[column]):
                    errors.append(f"{operation_id}: {column} must be resolved")
            if row["Priority"].upper() not in {"CRITICAL", "HIGH", "MEDIUM", "LOW"}:
                errors.append(
                    f"{operation_id}: Priority must be CRITICAL, HIGH, MEDIUM or LOW"
                )
            profiles = parse_profile_list(
                row["Required Profiles"],
                required_profiles,
                all_profiles,
                f"{operation_id} Required Profiles",
                errors,
            )
            unsupported = profiles & unsupported_profiles
            if unsupported:
                errors.append(
                    f"{operation_id}: operation cannot target unsupported profiles: "
                    + ", ".join(sorted(unsupported))
                )
            profile_operation_coverage.update(profiles & required_profiles)
            operations.append(OperationScope(operation_id, frozenset(profiles)))
            if row["Status"].upper() != "READY":
                errors.append(f"{operation_id}: operation Status must be READY")

    uncovered_profiles = required_profiles - profile_operation_coverage
    if uncovered_profiles:
        errors.append(
            f"{CONTRACT_NAME}: required profiles lack business-operation coverage: "
            + ", ".join(sorted(uncovered_profiles))
        )
    return errors, required_profiles, operations


def validate_acceptance(
    root: Path,
    report_path: Path,
    required_profiles: set[str],
    operations: list[OperationScope],
) -> list[str]:
    errors: list[str] = []
    if not report_path.is_file():
        return [f"required adaptive UI artifact missing: {REPORT_NAME}"]
    text = report_path.read_text(encoding="utf-8", errors="replace")
    require_value(
        errors, text, "Adaptive Verification Status", "VERIFIED", REPORT_NAME
    )
    for name in (
        "Failed Required Profiles",
        "Critical Operation Failures",
        "Component Consistency Violations",
        "Unintended Overflow / Clipping",
    ):
        require_zero(errors, text, name, REPORT_NAME)
    for name in (
        "Input Modality Checks",
        "Orientation / Safe Area Checks",
        "Business Operation Checks",
    ):
        require_value(errors, text, name, "PASS", REPORT_NAME)

    declared_required = integer_field(
        errors, text, "Required Device Profiles", REPORT_NAME
    )
    declared_verified = integer_field(
        errors, text, "Verified Required Profiles", REPORT_NAME
    )
    if declared_required is not None and declared_required != len(required_profiles):
        errors.append(
            f"{REPORT_NAME}: Required Device Profiles is {declared_required}; expected {len(required_profiles)}"
        )
    if declared_verified is not None and declared_verified != len(required_profiles):
        errors.append(
            f"{REPORT_NAME}: Verified Required Profiles is {declared_verified}; expected {len(required_profiles)}"
        )

    profile_rows = table_after_heading(
        text, "Required Profile Verification", REPORT_NAME, errors
    )
    profile_columns = (
        "Profile ID",
        "Production Evidence",
        "Component Check",
        "Operation Evidence",
        "Overflow / Clipping",
        "Input / Focus",
        "Orientation / Safe Area",
        "Status",
    )
    verified_profiles: set[str] = set()
    if require_columns(
        errors, profile_rows, profile_columns, f"{REPORT_NAME} profiles"
    ):
        for row in profile_rows:
            profile_id = row["Profile ID"].upper()
            if profile_id not in required_profiles:
                continue
            if profile_id in verified_profiles:
                errors.append(f"{REPORT_NAME}: duplicate profile verification {profile_id}")
                continue
            verified_profiles.add(profile_id)
            if row["Component Check"].upper() != "PASS":
                errors.append(f"{profile_id}: Component Check must be PASS")
            if row["Overflow / Clipping"] != "0":
                errors.append(f"{profile_id}: Overflow / Clipping must be 0")
            if row["Input / Focus"].upper() != "PASS":
                errors.append(f"{profile_id}: Input / Focus must be PASS")
            if row["Orientation / Safe Area"].upper() not in {"PASS", "NOT_APPLICABLE"}:
                errors.append(
                    f"{profile_id}: Orientation / Safe Area must be PASS or NOT_APPLICABLE"
                )
            if row["Status"].upper() != "VERIFIED":
                errors.append(f"{profile_id}: verification Status must be VERIFIED")
            resolve_evidence(
                root,
                report_path,
                row["Production Evidence"],
                f"{profile_id} production evidence",
                errors,
            )
            resolve_evidence(
                root,
                report_path,
                row["Operation Evidence"],
                f"{profile_id} operation evidence",
                errors,
            )
    missing_profiles = required_profiles - verified_profiles
    if missing_profiles:
        errors.append(
            f"{REPORT_NAME}: missing required profile verification: "
            + ", ".join(sorted(missing_profiles))
        )

    operation_rows = table_after_heading(
        text, "Operation Verification", REPORT_NAME, errors
    )
    operation_columns = (
        "Operation ID",
        "Profile ID",
        "E2E / Manual Evidence",
        "Result",
    )
    actual_pairs: set[tuple[str, str]] = set()
    if require_columns(
        errors, operation_rows, operation_columns, f"{REPORT_NAME} operations"
    ):
        for row in operation_rows:
            pair = (row["Operation ID"].upper(), row["Profile ID"].upper())
            if pair in actual_pairs:
                errors.append(
                    f"{REPORT_NAME}: duplicate operation verification {pair[0]} / {pair[1]}"
                )
                continue
            actual_pairs.add(pair)
            if row["Result"].upper() != "PASS":
                errors.append(f"{pair[0]} / {pair[1]}: operation Result must be PASS")
            resolve_evidence(
                root,
                report_path,
                row["E2E / Manual Evidence"],
                f"{pair[0]} / {pair[1]} operation evidence",
                errors,
            )
    expected_pairs = {
        (operation.operation_id, profile)
        for operation in operations
        for profile in operation.profiles
        if profile in required_profiles
    }
    for operation_id, profile_id in sorted(expected_pairs - actual_pairs):
        errors.append(
            f"{REPORT_NAME}: missing operation verification for {operation_id} / {profile_id}"
        )
    return errors


def validate(root: Path, ui_dir: Path, phase: str) -> list[str]:
    resolved_root = root.resolve()
    resolved_ui_dir = ui_dir.resolve()
    try:
        resolved_ui_dir.relative_to(resolved_root)
    except ValueError:
        return [f"UI evidence directory escapes repository root: {resolved_ui_dir}"]
    if not resolved_ui_dir.is_dir():
        return [f"UI evidence directory missing: {resolved_ui_dir}"]

    errors, required_profiles, operations = validate_contract(
        resolved_root, resolved_ui_dir / CONTRACT_NAME
    )
    if phase == "accept" and not errors:
        errors.extend(
            validate_acceptance(
                resolved_root,
                resolved_ui_dir / REPORT_NAME,
                required_profiles,
                operations,
            )
        )
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate adaptive multi-device UI contracts and evidence"
    )
    parser.add_argument("--root", default=".")
    parser.add_argument("--ui-dir", required=True)
    parser.add_argument("--phase", choices=("plan", "accept"), default="accept")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    ui_dir = Path(args.ui_dir)
    if not ui_dir.is_absolute():
        ui_dir = root / ui_dir
    errors = validate(root, ui_dir, args.phase)
    label = (
        "ADAPTIVE UI PLAN GATE"
        if args.phase == "plan"
        else "ADAPTIVE UI ACCEPTANCE GATE"
    )
    if errors:
        print(f"{label}: BLOCKED")
        for error in errors:
            print(f"- {error}")
        print(
            "Production UI Editing: FORBIDDEN"
            if args.phase == "plan"
            else "UI Acceptance: FORBIDDEN"
        )
        return 5
    print(f"{label}: PASS")
    print("Required device profiles covered: YES")
    print("Component family consistency: PASS")
    print("Business operation coverage: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Validate AI Development OS v4.3 package structure, semantics, and integrity."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import sys


PACKAGE_VERSION = "4.3"
MANIFEST_NAME = "MANIFEST.json"

REQUIRED_FILES = (
    "VERSION.md",
    "AGENTS.md",
    "README.md",
    "USAGE.md",
    ".ai/SKILL.md",
    ".ai/commands/work.md",
    ".ai/commands/workflow-diagnose.md",
    ".ai/commands/third-party-audit.md",
    ".ai/commands/agent-provider.md",
    ".ai/config/agent-providers.json",
    ".ai/config/worktree-command-profile.json",
    ".ai/rules/WORKFLOW_CORE.md",
    ".ai/rules/WORKFLOW_ROUTER_RULES.md",
    ".ai/rules/IMPLEMENTATION_READY_RULES.md",
    ".ai/rules/TDD_CYCLE_RULES.md",
    ".ai/rules/TASK_AGENT_REVIEW_RULES.md",
    ".ai/rules/WORKTREE_INITIALIZATION_RULES.md",
    ".ai/rules/WORKFLOW_DIAGNOSIS_RULES.md",
    ".ai/rules/IMPACT_MAP_AUTHORITY_RULES.md",
    ".ai/rules/SCENARIO_MATRIX_RULES.md",
    ".ai/rules/COMPLETION_STATE_RULES.md",
    ".ai/rules/PROTOTYPE_ENFORCEMENT_RULES.md",
    ".ai/templates/WORK_ITEM.md",
    ".ai/templates/IMPACT_MAP.md",
    ".ai/templates/IMPLEMENTATION_DESIGN.md",
    ".ai/templates/SCENARIO_MATRIX.md",
    ".ai/templates/IMPLEMENTATION_READY_REPORT.md",
    ".ai/templates/TDD_CYCLE_REPORT.md",
    ".ai/templates/TASK_AGENT_LEDGER.md",
    ".ai/templates/TASK_IMPLEMENTATION_RECEIPT.md",
    ".ai/templates/AGENT_DISPATCH_RECEIPT.md",
    ".ai/templates/TASK_REVIEW.md",
    ".ai/templates/WORKTREE_READINESS.md",
    ".ai/templates/WORKFLOW_DIAGNOSIS.md",
    ".ai/templates/PROTOTYPE_APPROVAL.md",
    ".ai/templates/UI_IMPLEMENTATION_MAP.md",
    ".ai/templates/MEASURED_UI_SPEC.md",
    ".ai/templates/STRUCTURAL_DIFF.md",
    ".ai/templates/SCREENSHOT_VISUAL_DIFF_REPORT.md",
    ".ai/templates/PROTOTYPE_INTERACTION_CONTRACT.md",
    ".ai/templates/BACKEND_COORDINATION_REPORT.md",
    ".ai/scripts/validate.py",
    ".ai/scripts/validate_ui_gate.py",
    ".ai/scripts/validate_ui_fidelity.py",
    ".ai/scripts/validate_ui_capabilities.py",
    ".ai/scripts/validate_ui_adaptive.py",
    ".ai/scripts/gate.py",
    ".ai/scripts/execution_journal.py",
    ".ai/scripts/validate_execution_discipline.py",
    ".ai/scripts/worktree_preflight.py",
    ".ai/scripts/validate_worktree_readiness.py",
    ".ai/scripts/workflow_diagnose.py",
    ".ai/scripts/validate_workflow_diagnosis.py",
    ".ai/rules/PRODUCT_LIFECYCLE_RULES.md",
    ".ai/rules/SECURITY_AUDIT_RULES.md",
    ".ai/rules/MULTI_AGENT_ORCHESTRATION_RULES.md",
    ".ai/rules/THIRD_PARTY_AUDIT_RULES.md",
    ".ai/rules/AGENT_PROVIDER_RULES.md",
    ".ai/rules/AUDIT_ROUTING_AND_REMEDIATION_RULES.md",
    ".ai/templates/DELIVERY_GATE.md",
    ".ai/templates/SECURITY_AUDIT.md",
    ".ai/templates/TEST_REPORT.md",
    ".ai/templates/RELEASE_EVIDENCE.md",
    ".ai/templates/ADAPTIVE_UI_CONTRACT.md",
    ".ai/templates/DEVICE_UX_VERIFICATION_REPORT.md",
    ".ai/templates/AUDIT_PACKET.md",
    ".ai/templates/AUDIT_RECEIPT.md",
    ".ai/templates/THIRD_PARTY_AUDIT.md",
    ".ai/templates/AGENT_PROVIDER_READINESS.md",
    ".ai/templates/AUDIT_PLAN.md",
    ".ai/templates/AUDIT_REMEDIATION.md",
    ".ai/templates/GIT_INTEGRATION_EVIDENCE.md",
    ".ai/rules/ADAPTIVE_UI_UX_RULES.md",
    ".ai/scripts/validate_third_party_audit.py",
    ".ai/scripts/agent_provider.py",
    ".ai/scripts/validate_audit_plan.py",
    "docs/WORKFLOW_V4_2.md",
    "docs/UI_PROTOTYPE_ENFORCEMENT.md",
    MANIFEST_NAME,
)

SEMANTIC_MARKERS = {
    "VERSION.md": ("AI Development OS v4.3",),
    "AGENTS.md": (
        "AI Development OS v4.3",
        "IMPLEMENTATION_READY = YES",
        "PROTOTYPE_REQUIREMENT=REQUIRED",
        "PROTOTYPE_MODE=HTML",
        "Approval Status: APPROVED",
        "validate_ui_fidelity.py --phase plan",
        "validate_ui_fidelity.py --phase accept",
        "validate_third_party_audit.py",
        "RED → GREEN → REFACTOR → REGRESSION",
        "WORKTREE_READINESS.md",
        "/workflow-diagnose",
    ),
    ".ai/SKILL.md": (
        "AI Development OS v4.3",
        "Impact Map",
        "Scenario Matrix",
        "ACCEPTED",
        "INTEGRATED",
        "RELEASED",
        "PROTOTYPE_MODE=HTML",
        "strict prototype-to-production fidelity gate",
        "THIRD_PARTY_AUDIT",
        "validate_third_party_audit.py",
        "execution_journal.py",
        "TASK_AGENT_LEDGER.md",
        "worktree_preflight.py",
    ),
    ".ai/commands/work.md": (
        "IMPLEMENTATION_READY — HARD GATE",
        "Production edits are forbidden until the result is `YES`",
        "Scenario Matrix",
        "HTML/HTM prototype",
        "THIRD_PARTY_AUDIT — HARD GATE",
        "/agent-provider",
        "AUDIT_PLAN.md",
        "--phase integrate",
        "TDD_CYCLE_REPORT.md",
        "TASK_AGENT_LEDGER.md",
        "WORKTREE_READINESS.md",
        "/workflow-diagnose",
    ),
    ".ai/rules/WORKFLOW_ROUTER_RULES.md": (
        "UI_IMPACT=MINOR|STRUCTURAL",
        "PROTOTYPE_MODE=HTML",
        "Approval Status: APPROVED",
    ),
    ".ai/rules/PROTOTYPE_ENFORCEMENT_RULES.md": (
        "PROTOTYPE_REQUIREMENT=REQUIRED",
        "PROTOTYPE_MODE=HTML",
        "IMPLEMENTATION_READY=NO",
        "Approval Status: APPROVED",
    ),
    ".ai/templates/PROTOTYPE_APPROVAL.md": (
        "Prototype Mode: HTML",
        "Presented To User: YES / NO",
        "Approval Status: DRAFT / APPROVED / REVISE",
    ),
    ".ai/commands/ui-implement.md": (
        "Unmapped Prototype Regions",
        "Unclassified Legacy Regions",
        "validate_ui_capabilities.py",
        "BACKEND_COORDINATION_REPORT.md",
        "--phase plan",
    ),
    ".ai/rules/ACCEPTANCE_RULES.md": (
        "validate_ui_fidelity.py --phase accept",
        "validate_ui_capabilities.py --phase accept",
        "BACKEND_COORDINATION_REPORT.md",
        "Functional usability",
    ),
    ".ai/templates/UI_IMPLEMENTATION_MAP.md": (
        "Mapping Status: DRAFT / COMPLETE",
        "All Prototype Regions Mapped: YES / NO",
        "Legacy Structure Reused Without Approval: YES / NO",
    ),
    ".ai/templates/SCREENSHOT_VISUAL_DIFF_REPORT.md": (
        "Production Presented To User: YES / NO",
        "User Fidelity Confirmation: PENDING / APPROVED / REVISE",
    ),
    ".ai/rules/COMPLETION_STATE_RULES.md": (
        "`ACCEPTED`",
        "`INTEGRATED`",
        "`RELEASED`",
        "`DONE` must not hide these distinctions",
    ),
    ".ai/rules/WORKFLOW_CORE.md": (
        "IDEA → RESEARCHED → PROJECT_APPROVED → PRD_APPROVED",
        "package` validates installation/package integrity only",
        "RELEASE_READY → DEPLOYED → PRODUCTION_VERIFIED → RELEASED",
        "RED → GREEN → REFACTOR",
        "specification reviewer",
    ),
    ".ai/scripts/gate.py": (
        "def check_work",
        "def check_git_integration",
        "def check_release",
        "validate_package(root)",
        "Release Gate requires a Git repository and integrated commit",
        "execution discipline sub-gate failed",
        "worktree readiness sub-gate failed",
        "workflow diagnosis sub-gate failed",
    ),
    ".ai/rules/SECURITY_AUDIT_RULES.md": (
        "Security Decision: APPROVED",
        "open CRITICAL = 0",
    ),
    ".ai/templates/DELIVERY_GATE.md": (
        "Product Inception Gate",
        "Multi Agent Gate",
        "Audit Plan",
        "Independent Review",
        "Third Party Audit",
        "Git Integration",
        "TDD Gate",
        "Task Agent Review Gate",
        "Worktree Readiness Gate",
        "Workflow Diagnosis Gate",
    ),
    ".ai/rules/TDD_CYCLE_RULES.md": (
        "RED → GREEN → REFACTOR → REGRESSION",
        "EXPECTED_ASSERTION_FAILURE",
        "validate_execution_discipline.py",
    ),
    ".ai/rules/TASK_AGENT_REVIEW_RULES.md": (
        "fresh implementer session",
        "specification reviewer",
        "code-quality reviewer",
    ),
    ".ai/rules/WORKTREE_INITIALIZATION_RULES.md": (
        "git-dir",
        "--show-superproject-working-tree",
        "worktree_preflight.py",
    ),
    ".ai/rules/WORKFLOW_DIAGNOSIS_RULES.md": (
        "path:line",
        "Input Mutation",
        "--require-clear",
    ),
    ".ai/scripts/execution_journal.py": (
        "shell=False",
        "previous_event_hash",
        "EXPECTED_ASSERTION_FAILURE",
    ),
    ".ai/scripts/validate_execution_discipline.py": (
        "EXECUTION DISCIPLINE GATE: PASS",
        "implementer, spec reviewer and quality reviewer must be distinct",
        "all stages must use the same selector",
    ),
    ".ai/scripts/validate_worktree_readiness.py": (
        "WORKTREE READINESS GATE: PASS",
        "--git-common-dir",
        "--show-superproject-working-tree",
    ),
    ".ai/scripts/validate_workflow_diagnosis.py": (
        "WORKFLOW DIAGNOSIS GATE: PASS",
        "path:line",
        "Diagnosis Decision must be CLEAR for lifecycle acceptance",
    ),
    ".ai/rules/THIRD_PARTY_AUDIT_RULES.md": (
        "mandatory, independent acceptance control",
        "AUDIT_PACKET.md",
        "AUDIT_RECEIPT.md",
        "THIRD_PARTY_AUDIT.md",
        "validate_third_party_audit.py",
        "AGENT_PROVIDER_READINESS.md",
    ),
    ".ai/templates/AUDIT_PACKET.md": (
        "Packet Status: DRAFT / SEALED",
        "Acceptance Contract SHA256",
        "Evidence Inventory",
        "Acceptance Contract",
        "Material Unknowns",
    ),
    ".ai/templates/AUDIT_RECEIPT.md": (
        "Context Mode: FRESH",
        "Mutation Permission: NONE / AUDIT_ARTIFACTS_ONLY",
        "Audit Session ID",
        "Reviewed Packet: AUDIT_PACKET.md",
    ),
    ".ai/templates/THIRD_PARTY_AUDIT.md": (
        "Audit Decision: APPROVED / BLOCKED",
        "Fresh Context: YES / NO",
        "Review Coverage",
        "Acceptance Criterion Audit",
        "FALSE_COMPLETION",
        "Provider Readiness SHA256",
    ),
    ".ai/scripts/validate_third_party_audit.py": (
        "THIRD-PARTY AUDIT GATE: PASS",
        "Auditor Agent must differ from Implementer Agent",
        "Acceptance criteria coverage: COMPLETE",
        "Provider State",
        "Live Probe",
    ),
    ".ai/commands/agent-provider.md": (
        "agent_provider.py setup",
        "explicit confirmation",
        "AGENT_PROVIDER_READINESS.md",
    ),
    ".ai/rules/AGENT_PROVIDER_RULES.md": (
        "CHOICE_REQUIRED",
        "shell=False",
        "Live Probe: PASS",
        "Secret Values Recorded: NO",
    ),
    ".ai/templates/AGENT_PROVIDER_READINESS.md": (
        "Provider Mode: EXTERNAL_CLI",
        "Provider State: READY / NON_READY_STATE",
        "Live Probe: PASS / NOT_RUN / FAIL",
        "Secret Values Recorded: NO",
    ),
    ".ai/config/agent-providers.json": (
        "@openai/codex",
        "@anthropic-ai/claude-code",
        "@google/gemini-cli",
    ),
    ".ai/config/worktree-command-profile.json": (
        "ai-development-os.worktree-command-profile/v1",
        "baseline",
    ),
    ".ai/scripts/agent_provider.py": (
        "CHOICE_REQUIRED",
        "CONFIRMATION_REQUIRED",
        "shell\": False",
        "AGENT_PROVIDER_READINESS.md",
    ),
    ".ai/rules/AUDIT_ROUTING_AND_REMEDIATION_RULES.md": (
        "ROOT_CAUSE",
        "audit-history/<session-id>/",
        "AUDIT BLOCKED",
        "--phase integrate",
    ),
    ".ai/templates/AUDIT_PLAN.md": (
        "Audit Plan Status: DRAFT / COMPLETE",
        "Required Audit Tracks: CORE, THIRD_PARTY",
        "Remediation Cycle: NOT_STARTED / ACTIVE / CLEAR",
    ),
    ".ai/templates/AUDIT_REMEDIATION.md": (
        "Remediation Base Commit",
        "Code / Configuration Fix",
        "Packet Resealed: YES / NO",
        "Fresh Re-Audit: PENDING / PASS / BLOCKED",
    ),
    ".ai/templates/GIT_INTEGRATION_EVIDENCE.md": (
        "Integration Status: COMMITTED",
        "Integrated Commit",
        "Unrelated Changes Included: NO",
        "Change Paths",
    ),
    ".ai/scripts/validate_audit_plan.py": (
        "TYPE_TRACKS",
        "AUDIT PLAN GATE: PASS",
        "Code / Configuration Fix",
        "canonical fresh re-audit must be APPROVED",
        "has no remediation delta",
        "finding-specific regression coverage",
    ),
    ".ai/scripts/validate_ui_capabilities.py": (
        "PROTOTYPE_INTERACTION_CONTRACT.md",
        "BACKEND_COORDINATION_REPORT.md",
        "UI CAPABILITY ACCEPTANCE GATE",
        "Unresolved backend capabilities: 0",
    ),
    ".ai/scripts/validate_ui_adaptive.py": (
        "ADAPTIVE_UI_CONTRACT.md",
        "DEVICE_UX_VERIFICATION_REPORT.md",
        "ADAPTIVE UI ACCEPTANCE GATE",
        "Component Consistency Violations",
    ),
    ".ai/rules/ADAPTIVE_UI_UX_RULES.md": (
        "Design by experience profile, not width alone",
        "Component families and semantic variants",
        "Business-operation continuity",
        "validate_ui_adaptive.py",
    ),
    ".ai/templates/ADAPTIVE_UI_CONTRACT.md": (
        "Device Experience Profiles",
        "Component Family Contract",
        "Business Operation Coverage",
        "Arbitrary Component Size Values",
    ),
    ".ai/templates/DEVICE_UX_VERIFICATION_REPORT.md": (
        "Required Profile Verification",
        "Operation Verification",
        "Component Consistency Violations",
        "Unintended Overflow / Clipping",
    ),
    ".ai/templates/PROTOTYPE_INTERACTION_CONTRACT.md": (
        "All Prototype Interactions Mapped",
        "Production Fake/Mock/Placeholder Interactions",
        "Unresolved Required Backend Capabilities",
        "API_EXTENSION / NEW_API / NOT_SUPPORTED",
    ),
    "docs/WORKFLOW_V4_2.md": (
        "BASELINE FAST CONTEXT",
        "IMPLEMENTATION_READY",
        "SELF_VERIFY",
        "BASELINE UPDATE",
    ),
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def package_files(root: Path) -> set[str]:
    return {
        path.relative_to(root).as_posix()
        for path in root.rglob("*")
        if path.is_file()
        and path.name != MANIFEST_NAME
        and path.suffix != ".pyc"
        and not {".git", "__pycache__", ".pytest_cache"}.intersection(
            path.relative_to(root).parts
        )
    }


def validate_required_files(root: Path, errors: list[str]) -> None:
    for relative_path in REQUIRED_FILES:
        if not (root / relative_path).is_file():
            errors.append(f"missing required file: {relative_path}")


def validate_semantics(root: Path, errors: list[str]) -> None:
    for relative_path, markers in SEMANTIC_MARKERS.items():
        path = root / relative_path
        if not path.is_file():
            continue
        content = path.read_text(encoding="utf-8", errors="replace")
        for marker in markers:
            if marker not in content:
                errors.append(f"semantic marker missing in {relative_path}: {marker}")


def validate_manifest(root: Path, errors: list[str]) -> None:
    manifest_path = root / MANIFEST_NAME
    if not manifest_path.is_file():
        return

    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        errors.append(f"invalid {MANIFEST_NAME}: {exc}")
        return

    if str(manifest.get("version")) != PACKAGE_VERSION:
        errors.append(
            f"manifest version mismatch: expected {PACKAGE_VERSION}, "
            f"got {manifest.get('version')!r}"
        )

    entries = manifest.get("files")
    if not isinstance(entries, list):
        errors.append("manifest field 'files' must be a list")
        return

    declared_count = manifest.get("file_count_excluding_manifest")
    if declared_count != len(entries):
        errors.append(
            "manifest file count mismatch: "
            f"declared {declared_count!r}, listed {len(entries)}"
        )

    listed: dict[str, dict[str, object]] = {}
    for index, entry in enumerate(entries):
        if not isinstance(entry, dict):
            errors.append(f"manifest entry {index} must be an object")
            continue
        relative_path = entry.get("path")
        if not isinstance(relative_path, str) or not relative_path:
            errors.append(f"manifest entry {index} has invalid path")
            continue
        pure_path = PurePosixPath(relative_path)
        if pure_path.is_absolute() or ".." in pure_path.parts or "\\" in relative_path:
            errors.append(f"manifest path is not normalized/safe: {relative_path}")
            continue
        if relative_path in listed:
            errors.append(f"duplicate manifest path: {relative_path}")
            continue
        listed[relative_path] = entry

    actual = package_files(root)
    listed_paths = set(listed)
    for relative_path in sorted(actual - listed_paths):
        errors.append(f"unlisted file: {relative_path}")
    for relative_path in sorted(listed_paths - actual):
        errors.append(f"manifest references missing file: {relative_path}")

    for relative_path in sorted(actual & listed_paths):
        path = root / relative_path
        entry = listed[relative_path]
        actual_size = path.stat().st_size
        expected_size = entry.get("size")
        if expected_size != actual_size:
            errors.append(
                f"size mismatch: {relative_path} "
                f"(manifest={expected_size!r}, actual={actual_size})"
            )
        expected_hash = entry.get("sha256")
        actual_hash = sha256(path)
        if expected_hash != actual_hash:
            errors.append(f"hash mismatch: {relative_path}")


def validate_package(root: Path, *, verify_manifest: bool = True) -> list[str]:
    resolved_root = root.resolve()
    errors: list[str] = []
    validate_required_files(resolved_root, errors)
    validate_semantics(resolved_root, errors)
    if verify_manifest:
        validate_manifest(resolved_root, errors)
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate an AI Development OS v4.3 package"
    )
    parser.add_argument(
        "root",
        nargs="?",
        type=Path,
        default=Path(__file__).resolve().parents[2],
        help="package root (defaults to this script's package)",
    )
    args = parser.parse_args()

    errors = validate_package(args.root)
    if errors:
        print("FAIL: v4.3 package validation")
        for error in errors:
            print(f"- {error}")
        return 1

    print("PASS: v4.3 package structure, semantics, and manifest are valid")
    return 0


if __name__ == "__main__":
    sys.exit(main())

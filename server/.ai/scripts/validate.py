#!/usr/bin/env python3
"""Compatibility package/policy validator for AI Development OS v4.3.

Use gate.py for scope-honest Work Item and release decisions.
"""
from __future__ import annotations
import argparse
from pathlib import Path
import re
import subprocess
import sys

from validate_v43_package import validate_package

ROOT = Path(__file__).resolve().parents[2]


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8") if path.exists() else ""


def git(*args: str, cwd: Path | None = None) -> tuple[int, str]:
    try:
        p = subprocess.run(
            ["git", *args], cwd=cwd or ROOT, text=True, encoding="utf-8",
            errors="replace", capture_output=True,
        )
    except FileNotFoundError:
        return 127, ""
    return p.returncode, p.stdout.strip()


def field(text: str, name: str) -> str:
    m = re.search(rf"(?mi)^\s*{re.escape(name)}\s*:\s*(.*?)\s*$", text)
    return m.group(1).strip() if m else ""


def check_state(errors: list[str], warnings: list[str]):
    p = ROOT / "docs" / "PROJECT_STATE.md"
    if not p.exists():
        errors.append("docs/PROJECT_STATE.md is missing")
        return
    txt = read(p)
    for name in ["Current Phase", "Active Work", "Active Workstreams"]:
        if name not in txt:
            warnings.append(f"PROJECT_STATE may be missing section/field: {name}")


def check_config(errors: list[str], warnings: list[str]):
    if not (ROOT / "docs" / "CONFIGURATION.md").exists():
        warnings.append("docs/CONFIGURATION.md is missing")


def check_git(errors: list[str], warnings: list[str]):
    rc, out = git("status", "--porcelain")
    if rc != 0:
        warnings.append("not a Git repository or Git unavailable; Git transaction checks skipped")
        return
    if out:
        warnings.append("current working tree contains uncommitted changes")


def worktree_map() -> dict[str, str]:
    rc, out = git("worktree", "list", "--porcelain")
    if rc != 0:
        return {}
    result: dict[str, str] = {}
    path = branch = ""
    for line in out.splitlines() + [""]:
        if line.startswith("worktree "):
            path = str(Path(line[len("worktree "):]).resolve())
        elif line.startswith("branch refs/heads/"):
            branch = line[len("branch refs/heads/"):]
        elif not line.strip() and path:
            result[path] = branch
            path = branch = ""
    return result


def check_workstreams(errors: list[str], warnings: list[str], release: bool):
    base = ROOT / "workstreams"
    if not base.exists():
        warnings.append("workstreams directory missing")
        return
    if not (base / "REGISTRY.md").exists():
        warnings.append("workstreams/REGISTRY.md is missing")
    actual = worktree_map()
    active_branches: dict[str, str] = {}
    active_paths: dict[str, str] = {}
    active_status = {"PLANNED", "ACTIVE", "BLOCKED", "READY_TO_MERGE", "MERGING"}
    for d in sorted(base.iterdir()):
        if not d.is_dir() or not d.name.startswith("WS"):
            continue
        state = d / "STATE.md"
        if not state.exists():
            warnings.append(f"workstream {d.name} has no STATE.md")
            continue
        txt = read(state)
        wid = field(txt, "Workstream ID") or d.name
        status = field(txt, "Status").upper()
        branch = field(txt, "Branch")
        wt = field(txt, "Worktree")
        iso = field(txt, "Isolation Mode").upper()
        if status in active_status:
            if branch:
                if branch in active_branches:
                    errors.append(f"active workstreams {active_branches[branch]} and {wid} share branch {branch}")
                active_branches[branch] = wid
            if iso == "WORKTREE":
                if not wt:
                    errors.append(f"active WORKTREE workstream {wid} has no Worktree path")
                else:
                    rp = str(Path(wt).expanduser().resolve())
                    if rp in active_paths:
                        errors.append(f"active workstreams {active_paths[rp]} and {wid} share worktree {rp}")
                    active_paths[rp] = wid
                    if actual and rp not in actual:
                        warnings.append(f"workstream {wid} records missing/stale Git worktree: {rp}")
                    elif actual and branch and actual.get(rp) and actual.get(rp) != branch:
                        errors.append(f"workstream {wid} branch/worktree mismatch: state={branch}, git={actual.get(rp)}")
                    if Path(rp).exists():
                        rc, dirty = git("status", "--porcelain", cwd=Path(rp))
                        if rc == 0 and dirty and status in {"READY_TO_MERGE", "MERGED"}:
                            errors.append(f"workstream {wid} is {status} but its worktree is dirty")
        if release and status in {"READY_TO_MERGE", "MERGING"}:
            warnings.append(f"release has unintegrated workstream {wid} in status {status}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--release", action="store_true", help="run strict release gate after package checks")
    ap.add_argument("--work-item", type=Path, help="Work Item directory required with --release")
    ap.add_argument("--release-evidence", type=Path, help="release evidence file required with --release")
    args = ap.parse_args()
    errors: list[str] = []
    warnings: list[str] = []
    check_state(errors, warnings)
    check_config(errors, warnings)
    check_git(errors, warnings)
    check_workstreams(errors, warnings, args.release)
    # Retained screenshot visual-verification contract.
    for rel in [
        ".ai/commands/ui-verify.md",
        ".ai/rules/SCREENSHOT_VISUAL_DIFF_RULES.md",
        ".ai/templates/SCREENSHOT_VISUAL_DIFF_REPORT.md",
        "docs/UI_ACCEPTANCE_STANDARD.md",
    ]:
        if not (ROOT / rel).exists():
            errors.append(f"UI verification artifact missing: {rel}")
    if args.release:
        for rel in ["docs/CHANGELOG.md", "docs/RELEASE_STRATEGY.md"]:
            if not (ROOT / rel).exists():
                errors.append(f"release document missing: {rel}")
    errors.extend(
        f"package: {error}"
        for error in validate_package(ROOT, verify_manifest=args.release)
    )
    if args.release:
        if not args.work_item or not args.release_evidence:
            errors.append(
                "strict release validation requires --work-item and --release-evidence; "
                "package integrity alone never proves release readiness"
            )
        else:
            from gate import check_release
            errors.extend(check_release(ROOT, args.work_item.resolve(), args.release_evidence.resolve()))
    print("AI Development OS v4.3 policy check")
    for w in warnings:
        print(f"WARN: {w}")
    for e in errors:
        print(f"ERROR: {e}")
    print(f"Result: {len(errors)} error(s), {len(warnings)} warning(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Validate live Git/worktree initialization evidence before production edits."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace") if path.is_file() else ""


def field(text: str, name: str) -> str:
    match = re.search(rf"(?mi)^\s*(?:[-*]\s*)?{re.escape(name)}\s*:\s*`?(.*?)`?\s*$", text)
    return match.group(1).strip() if match else ""


def authorization_fields(path: Path) -> dict[str, str]:
    text = read(path)
    return {name: field(text, name) for name in (
        "Authorization Status", "Scope", "Authorized Mode", "Authorization Source",
        "Authorized Baseline Commit",
    )}


def git(cwd: Path, *args: str) -> tuple[int, str]:
    result = subprocess.run(
        ["git", *args], cwd=cwd, text=True, capture_output=True,
        encoding="utf-8", errors="replace",
    )
    return result.returncode, result.stdout.strip()


def norm(value: str) -> str:
    return str(Path(value).resolve()).replace("\\", "/").casefold() if value else ""


def worktree_paths(root: Path) -> set[str]:
    rc, output = git(root, "worktree", "list", "--porcelain")
    if rc:
        return set()
    return {norm(line.split(" ", 1)[1]) for line in output.splitlines() if line.startswith("worktree ")}


def worktree_path_list(root: Path) -> list[Path]:
    rc, output = git(root, "worktree", "list", "--porcelain")
    if rc:
        return []
    return [Path(line.split(" ", 1)[1]).resolve() for line in output.splitlines() if line.startswith("worktree ")]


def verify_log(root: Path, text: str, prefix: str, required: bool, errors: list[str]) -> None:
    value = field(text, f"{prefix} Log")
    expected = field(text, f"{prefix} Log SHA256").lower()
    if not required and value.upper() == "NOT_APPLICABLE" and expected.upper() == "NOT_APPLICABLE":
        return
    candidate = Path(value)
    if not candidate.is_absolute():
        candidate = root / candidate
    path = candidate.resolve()
    try:
        path.relative_to(root.resolve())
    except ValueError:
        errors.append(f"{prefix} Log escapes repository root")
        return
    if not path.is_file():
        errors.append(f"{prefix} Log is missing")
        return
    if not re.fullmatch(r"[0-9a-f]{64}", expected) or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        errors.append(f"{prefix} Log SHA256 mismatch")


def validate(root: Path, work: Path, phase: str = "ready") -> list[str]:
    errors: list[str] = []
    artifact = work / "WORKTREE_READINESS.md"
    text = read(artifact)
    if not text:
        return ["missing or empty WORKTREE_READINESS.md"]
    if field(text, "Readiness Decision").upper() != "PASS":
        errors.append("Readiness Decision must be PASS")
    recorded_root = field(text, "Repository Root")
    recorded_path = field(text, "Worktree Path")
    if norm(recorded_root) != norm(str(root)):
        errors.append("Repository Root does not match the live repository")
    if norm(recorded_path) != norm(str(root)):
        errors.append("Worktree Path does not match the gate execution root")
    rc, live_git_dir = git(root, "rev-parse", "--absolute-git-dir")
    if rc:
        return errors + ["current root is not a Git worktree"]
    rc, live_common = git(root, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if rc:
        errors.append("unable to resolve Git common directory")
    if norm(field(text, "Git Dir")) != norm(live_git_dir):
        errors.append("Git Dir does not match live Git state")
    if norm(field(text, "Common Git Dir")) != norm(live_common):
        errors.append("Common Git Dir does not match live Git state")
    is_linked = norm(live_git_dir) != norm(live_common)
    mode = field(text, "Isolation Mode").upper()
    if mode == "LINKED_WORKTREE" and not is_linked:
        errors.append("Isolation Mode claims LINKED_WORKTREE but this is not a linked worktree")
    if mode == "PRIMARY_CHECKOUT" and is_linked:
        errors.append("Isolation Mode claims PRIMARY_CHECKOUT but this is a linked worktree")
    if mode not in {"LINKED_WORKTREE", "PRIMARY_CHECKOUT"}:
        errors.append("Isolation Mode must be LINKED_WORKTREE or PRIMARY_CHECKOUT")
    if mode == "PRIMARY_CHECKOUT" and field(text, "Primary Checkout Exception").upper() != "APPROVED":
        errors.append("PRIMARY_CHECKOUT requires an explicit approved exception")
    rc, superproject = git(root, "rev-parse", "--show-superproject-working-tree")
    recorded_superproject = field(text, "Superproject")
    if rc:
        errors.append("unable to inspect superproject/submodule state")
    elif superproject:
        errors.append("submodule worktrees are blocked for automatic initialization")
    elif recorded_superproject.upper() != "NONE":
        errors.append("Superproject must be NONE when no superproject is present")
    rc, branch = git(root, "branch", "--show-current")
    if rc or field(text, "Branch") != branch:
        errors.append("Branch does not match live Git state")
    if branch.casefold() in {"main", "master"} and field(text, "Default Branch Exception").upper() != "APPROVED":
        errors.append("default branch is unsafe without an approved exception")
    rc, head = git(root, "rev-parse", "HEAD")
    recorded_head = field(text, "Head Commit").lower()
    if rc:
        errors.append("unable to resolve live HEAD")
    elif phase == "ready" and recorded_head != head.lower():
        errors.append("Head Commit does not match live Git state")
    elif phase in {"accept", "integrate"}:
        ancestor_rc, _ = git(root, "merge-base", "--is-ancestor", recorded_head, head)
        if not re.fullmatch(r"[0-9a-f]{40}", recorded_head) or ancestor_rc:
            errors.append("recorded preflight Head Commit must be an ancestor of live HEAD")
    if norm(recorded_path) not in worktree_paths(root):
        errors.append("Worktree Mapping is not present in git worktree list")
    if field(text, "Worktree Mapping").upper() != "VERIFIED":
        errors.append("Worktree Mapping must be VERIFIED")
    paths = worktree_path_list(root)
    primary_path = paths[0] if paths else root
    try:
        root.relative_to(primary_path)
        live_repo_local = root != primary_path
    except ValueError:
        live_repo_local = False
    repo_local = field(text, "Repository Local").upper()
    if repo_local != ("YES" if live_repo_local else "NO"):
        errors.append("Repository Local does not match live worktree topology")
    if norm(field(text, "Primary Worktree Path")) != norm(str(primary_path)):
        errors.append("Primary Worktree Path does not match live worktree topology")
    if live_repo_local:
        ignored = subprocess.run(
            ["git", "check-ignore", "-q", str(root)], cwd=primary_path,
            text=True, capture_output=True,
        ).returncode == 0
        if not ignored or field(text, "Ignore Check").upper() != "PASS":
            errors.append("repository-local worktree directory must pass the live Git ignore check")
    elif field(text, "Ignore Check").upper() != "NOT_APPLICABLE":
        errors.append("Ignore Check must be NOT_APPLICABLE for an external/primary worktree")
    if mode == "PRIMARY_CHECKOUT":
        auth_value = field(text, "Authorization Evidence")
        auth_expected = field(text, "Authorization Evidence SHA256").lower()
        verify_log(root, text.replace("Authorization Evidence:", "Authorization Log:").replace(
            "Authorization Evidence SHA256:", "Authorization Log SHA256:"
        ), "Authorization", True, errors)
        auth_path = (root / auth_value).resolve() if not Path(auth_value).is_absolute() else Path(auth_value).resolve()
        if auth_path.is_file():
            auth = authorization_fields(auth_path)
            expected = {
                "Authorization Status": "APPROVED",
                "Scope": work.name,
                "Authorized Mode": "PRIMARY_CHECKOUT",
            }
            for name, value in expected.items():
                if auth.get(name, "").upper() != value.upper():
                    errors.append(f"Authorization Evidence {name} must be {value}")
            if auth.get("Authorization Source", "").upper() not in {"USER", "PROJECT_POLICY"}:
                errors.append("Authorization Evidence Source must be USER or PROJECT_POLICY")
            auth_base = auth.get("Authorized Baseline Commit", "").lower()
            if not re.fullmatch(r"[0-9a-f]{40}", auth_base) or git(
                root, "merge-base", "--is-ancestor", auth_base, recorded_head
            )[0]:
                errors.append("Authorization Evidence baseline must be an ancestor of the preflight HEAD")
    setup_result = field(text, "Setup Result").upper()
    if setup_result not in {"PASS", "NOT_APPLICABLE"}:
        errors.append("Setup Result must be PASS or NOT_APPLICABLE")
    baseline_result = field(text, "Baseline Result").upper()
    if baseline_result != "PASS":
        errors.append("Baseline Result must be PASS")
    if field(text, "Clean Baseline").upper() != "YES":
        errors.append("Clean Baseline must be YES")
    if field(text, "Git Status Result").upper() != "CLEAN":
        errors.append("Git Status Result must be CLEAN at preflight")
    if phase == "ready":
        ignored_paths: list[str] = []
        for candidate in (
            artifact,
            Path(field(text, "Setup Log")),
            Path(field(text, "Baseline Log")),
        ):
            if str(candidate).upper() == "NOT_APPLICABLE":
                continue
            resolved = candidate.resolve() if candidate.is_absolute() else (root / candidate).resolve()
            try:
                ignored_paths.append(resolved.relative_to(root).as_posix())
            except ValueError:
                continue
        status_args = ["status", "--porcelain", "--untracked-files=all", "--", "."]
        status_args.extend(f":(exclude){value}" for value in ignored_paths)
        status_rc, live_status = git(root, *status_args)
        if status_rc or live_status:
            errors.append("live Git status is dirty at ready validation")
    setup_log_required = setup_result == "PASS"
    profile_value = field(text, "Command Profile")
    profile_expected = field(text, "Command Profile SHA256").lower()
    profile_path = (root / profile_value).resolve() if not Path(profile_value).is_absolute() else Path(profile_value).resolve()
    try:
        profile_path.relative_to(root)
    except ValueError:
        errors.append("Command Profile escapes repository root")
    else:
        if not profile_path.is_file() or not re.fullmatch(r"[0-9a-f]{64}", profile_expected) or hashlib.sha256(profile_path.read_bytes()).hexdigest() != profile_expected:
            errors.append("Command Profile SHA256 mismatch")
        else:
            try:
                profile = json.loads(profile_path.read_text(encoding="utf-8"))
                if profile.get("schema") != "ai-development-os.worktree-command-profile/v1":
                    raise ValueError("unsupported schema")
                setup_argv = profile.get("setup")
                baseline_argv = profile.get("baseline")
                if setup_argv is not None and (
                    not isinstance(setup_argv, list)
                    or not setup_argv
                    or not all(isinstance(item, str) and item for item in setup_argv)
                ):
                    raise ValueError("setup must be null or a non-empty argv array")
                if (
                    not isinstance(baseline_argv, list)
                    or not baseline_argv
                    or not all(isinstance(item, str) and item for item in baseline_argv)
                ):
                    raise ValueError("baseline must be a non-empty argv array")
            except (OSError, json.JSONDecodeError, ValueError) as exc:
                errors.append(f"Command Profile is invalid: {exc}")
            else:
                expected_setup = (
                    "NOT_APPLICABLE" if setup_argv is None
                    else json.dumps(setup_argv, ensure_ascii=False)
                )
                expected_baseline = json.dumps(baseline_argv, ensure_ascii=False)
                if field(text, "Setup Command") != expected_setup:
                    errors.append("Setup Command does not match Command Profile")
                if field(text, "Baseline Command") != expected_baseline:
                    errors.append("Baseline Command does not match Command Profile")
                setup_log_required = setup_argv is not None
                if setup_argv is None and setup_result != "NOT_APPLICABLE":
                    errors.append("Setup Result must be NOT_APPLICABLE when Command Profile omits setup")
                if setup_argv is not None and setup_result != "PASS":
                    errors.append("Setup Result must be PASS when Command Profile defines setup")
    verify_log(root, text, "Setup", setup_log_required, errors)
    verify_log(root, text, "Baseline", True, errors)
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--work-item", type=Path, required=True)
    parser.add_argument("--phase", choices=("ready", "accept", "integrate"), default="ready")
    args = parser.parse_args()
    errors = validate(args.root.resolve(), args.work_item.resolve(), args.phase)
    if errors:
        print("WORKTREE READINESS GATE: BLOCKED")
        for error in errors:
            print(f"- {error}")
        return 1
    print("WORKTREE READINESS GATE: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

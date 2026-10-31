#!/usr/bin/env python3
"""Generate worktree initialization evidence from live Git state and real commands."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys


def git(root: Path, *args: str) -> tuple[int, str]:
    result = subprocess.run(
        ["git", *args], cwd=root, text=True, capture_output=True,
        encoding="utf-8", errors="replace",
    )
    return result.returncode, result.stdout.strip()


def norm(path: str) -> str:
    return str(Path(path).resolve()).replace("\\", "/").casefold()


def parse_argv(value: str | None, label: str) -> list[str] | None:
    if value is None:
        return None
    try:
        argv = json.loads(value)
    except json.JSONDecodeError as exc:
        raise ValueError(f"{label} must be a JSON array: {exc}") from exc
    if not isinstance(argv, list) or not argv or not all(isinstance(item, str) and item for item in argv):
        raise ValueError(f"{label} must be a non-empty JSON array of strings")
    return argv


def auth_field(text: str, name: str) -> str:
    import re
    match = re.search(rf"(?mi)^\s*{re.escape(name)}\s*:\s*(.*?)\s*$", text)
    return match.group(1).strip() if match else ""


def run_command(root: Path, work: Path, name: str, argv: list[str] | None) -> tuple[str, str, str, str]:
    if argv is None:
        return "NOT_APPLICABLE", "NOT_APPLICABLE", "", ""
    log = work / "preflight-logs" / f"{name}.log"
    log.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(argv, cwd=root, text=True, capture_output=True, shell=False)
    log.write_text(result.stdout + result.stderr, encoding="utf-8")
    digest = hashlib.sha256(log.read_bytes()).hexdigest()
    return json.dumps(argv, ensure_ascii=False), "PASS" if result.returncode == 0 else "FAIL", log.relative_to(root).as_posix(), digest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--work-item", type=Path, required=True)
    parser.add_argument("--setup-argv-json")
    parser.add_argument("--baseline-argv-json")
    parser.add_argument("--command-profile", type=Path, required=True)
    parser.add_argument("--allow-primary-checkout", action="store_true")
    parser.add_argument("--primary-exception-reason")
    parser.add_argument("--allow-default-branch", action="store_true")
    parser.add_argument("--authorization-evidence", type=Path)
    args = parser.parse_args()
    root = args.root.resolve()
    work = args.work_item.resolve()
    try:
        work.relative_to(root)
    except ValueError:
        print("ERROR: Work Item must remain inside repository root", file=sys.stderr)
        return 2
    try:
        profile_path = args.command_profile.resolve()
        profile_path.relative_to(root)
        profile = json.loads(profile_path.read_text(encoding="utf-8"))
        if profile.get("schema") != "ai-development-os.worktree-command-profile/v1":
            raise ValueError("command profile schema is invalid")
        setup_argv = profile.get("setup")
        baseline_argv = profile.get("baseline")
        if setup_argv is not None and (
            not isinstance(setup_argv, list)
            or not setup_argv
            or not all(isinstance(item, str) and item for item in setup_argv)
        ):
            raise ValueError("profile setup must be null or an argv array")
        if not isinstance(baseline_argv, list) or not baseline_argv or not all(isinstance(item, str) and item for item in baseline_argv):
            raise ValueError("profile baseline must be a non-empty argv array")
        if args.setup_argv_json or args.baseline_argv_json:
            raise ValueError("direct setup/baseline argv is forbidden; use the approved command profile")
        profile_sha = hashlib.sha256(profile_path.read_bytes()).hexdigest()
    except (ValueError, OSError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    rc, repository_root = git(root, "rev-parse", "--show-toplevel")
    if rc or norm(repository_root) != norm(str(root)):
        print("ERROR: --root must be the Git worktree root", file=sys.stderr)
        return 2
    _, git_dir = git(root, "rev-parse", "--absolute-git-dir")
    _, common_dir = git(root, "rev-parse", "--path-format=absolute", "--git-common-dir")
    _, superproject = git(root, "rev-parse", "--show-superproject-working-tree")
    _, branch = git(root, "branch", "--show-current")
    _, head = git(root, "rev-parse", "HEAD")
    is_linked = norm(git_dir) != norm(common_dir)
    mode = "LINKED_WORKTREE" if is_linked else "PRIMARY_CHECKOUT"
    worktree_output = git(root, "worktree", "list", "--porcelain")[1]
    worktree_values = [line.split(" ", 1)[1] for line in worktree_output.splitlines() if line.startswith("worktree ")]
    mapped = norm(str(root)) in {norm(value) for value in worktree_values}
    primary_path = Path(worktree_values[0]).resolve() if worktree_values else root
    try:
        root.relative_to(primary_path)
        repository_local = root != primary_path
    except ValueError:
        repository_local = False
    ignore_check = "NOT_APPLICABLE"
    if repository_local:
        ignored = subprocess.run(
            ["git", "check-ignore", "-q", str(root)], cwd=primary_path,
            text=True, capture_output=True,
        ).returncode == 0
        ignore_check = "PASS" if ignored else "FAIL"
    authorization_path = args.authorization_evidence.resolve() if args.authorization_evidence else None
    authorization_sha = "NOT_APPLICABLE"
    if authorization_path:
        try:
            authorization_path.relative_to(root)
        except ValueError:
            authorization_path = None
        if authorization_path and authorization_path.is_file():
            authorization_sha = hashlib.sha256(authorization_path.read_bytes()).hexdigest()
            authorization_text = authorization_path.read_text(encoding="utf-8", errors="replace")
            expected_scope = work.name
            if auth_field(authorization_text, "Authorization Status").upper() != "APPROVED":
                authorization_path = None
            elif auth_field(authorization_text, "Scope").upper() != expected_scope.upper():
                authorization_path = None
            elif auth_field(authorization_text, "Authorized Mode").upper() != "PRIMARY_CHECKOUT":
                authorization_path = None
            elif auth_field(authorization_text, "Authorization Source").upper() not in {"USER", "PROJECT_POLICY"}:
                authorization_path = None
            else:
                authorized_baseline = auth_field(authorization_text, "Authorized Baseline Commit").lower()
                if not re.fullmatch(r"[0-9a-f]{40}", authorized_baseline) or subprocess.run(
                    ["git", "merge-base", "--is-ancestor", authorized_baseline, head], cwd=root
                ).returncode:
                    authorization_path = None
    initial_git_status = git(root, "status", "--porcelain", "--untracked-files=all")[1]
    git_status_result = "CLEAN" if not initial_git_status else "DIRTY"
    blockers = []
    if superproject:
        blockers.append("submodule/superproject worktree is not supported")
    if not mapped:
        blockers.append("worktree is missing from git worktree list")
    if not is_linked and not (
        args.allow_primary_checkout and args.primary_exception_reason and authorization_path
    ):
        blockers.append("primary checkout requires an explicit exception and reason")
        if args.allow_primary_checkout and not authorization_path:
            blockers.append("primary checkout exception requires valid authorization evidence")
    if branch.casefold() in {"main", "master"} and not (args.allow_default_branch and authorization_path):
        blockers.append("default branch requires explicit authorization")
    if repository_local and ignore_check != "PASS":
        blockers.append("repository-local worktree path is not ignored")
    if git_status_result != "CLEAN":
        blockers.append("Git baseline is dirty")
    setup_command, setup_result, setup_log, setup_sha = run_command(root, work, "setup", setup_argv)
    baseline_command, baseline_result, baseline_log, baseline_sha = run_command(root, work, "baseline", baseline_argv)
    generated_logs = [value for value in (setup_log, baseline_log) if value]
    status_args = ["status", "--porcelain", "--untracked-files=all", "--", "."]
    status_args.extend(f":(exclude){value}" for value in generated_logs)
    post_command_status = git(root, *status_args)[1]
    if post_command_status:
        git_status_result = "DIRTY"
        if not initial_git_status:
            blockers.append("setup/baseline commands dirtied Git baseline")
    if setup_result == "FAIL":
        blockers.append("dependency/setup command failed")
    if baseline_result != "PASS":
        blockers.append("baseline command failed")
    decision = "PASS" if not blockers else "BLOCKED"
    lines = [
        "# Worktree Readiness",
        "",
        f"Readiness Decision: {decision}",
        f"Repository Root: {root}",
        f"Worktree Path: {root}",
        f"Isolation Mode: {mode}",
        f"Git Dir: {git_dir}",
        f"Common Git Dir: {common_dir}",
        f"Superproject: {superproject or 'NONE'}",
        f"Branch: {branch}",
        f"Head Commit: {head}",
        f"Worktree Mapping: {'VERIFIED' if mapped else 'BLOCKED'}",
        f"Primary Worktree Path: {primary_path}",
        f"Repository Local: {'YES' if repository_local else 'NO'}",
        f"Ignore Check: {ignore_check}",
        f"Primary Checkout Exception: {'APPROVED' if not is_linked and args.allow_primary_checkout and authorization_path else 'NOT_APPLICABLE'}",
        f"Primary Exception Reason: {args.primary_exception_reason or 'NOT_APPLICABLE'}",
        f"Default Branch Exception: {'APPROVED' if args.allow_default_branch and authorization_path else 'NOT_APPLICABLE'}",
        f"Command Profile: {profile_path.relative_to(root).as_posix()}",
        f"Command Profile SHA256: {profile_sha}",
        f"Authorization Evidence: {authorization_path.relative_to(root).as_posix() if authorization_path else 'NOT_APPLICABLE'}",
        f"Authorization Evidence SHA256: {authorization_sha}",
        f"Setup Command: {setup_command}",
        f"Setup Result: {setup_result}",
        f"Setup Log: {setup_log or 'NOT_APPLICABLE'}",
        f"Setup Log SHA256: {setup_sha or 'NOT_APPLICABLE'}",
        f"Baseline Command: {baseline_command}",
        f"Baseline Result: {baseline_result}",
        f"Baseline Log: {baseline_log}",
        f"Baseline Log SHA256: {baseline_sha}",
        f"Git Status Result: {git_status_result}",
        f"Clean Baseline: {'YES' if baseline_result == 'PASS' and git_status_result == 'CLEAN' else 'NO'}",
        "",
        "## Blockers",
    ]
    lines.extend(f"- {blocker}" for blocker in blockers)
    if not blockers:
        lines.append("- NONE")
    work.mkdir(parents=True, exist_ok=True)
    (work / "WORKTREE_READINESS.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"WORKTREE PREFLIGHT: {decision}")
    print(f"Evidence: {work / 'WORKTREE_READINESS.md'}")
    for blocker in blockers:
        print(f"- {blocker}")
    return 0 if decision == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())

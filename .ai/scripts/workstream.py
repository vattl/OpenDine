#!/usr/bin/env python3
"""Safe workstream/worktree manager for AI Development OS v4.3.

This automates machine-verifiable isolation mechanics while deliberately avoiding
force resets, implicit stashes, unrelated commits, and forced worktree removal.
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

SCRIPT_ROOT = Path(__file__).resolve().parents[2]


def run_git(cwd: Path, *args: str) -> tuple[int, str, str]:
    p = subprocess.run(["git", *args], cwd=cwd, text=True, capture_output=True)
    return p.returncode, p.stdout.strip(), p.stderr.strip()


def git_root(start: Path) -> Path | None:
    rc, out, _ = run_git(start, "rev-parse", "--show-toplevel")
    return Path(out).resolve() if rc == 0 and out else None


def slugify(value: str) -> str:
    value = value.strip().lower()
    value = re.sub(r"[^a-z0-9]+", "-", value)
    value = re.sub(r"-+", "-", value).strip("-")
    return value or "work"


def now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def parse_field(text: str, name: str) -> str:
    m = re.search(rf"(?mi)^\s*{re.escape(name)}\s*:\s*(.*?)\s*$", text)
    return m.group(1).strip() if m else ""


def replace_field(text: str, name: str, value: str) -> str:
    pat = re.compile(rf"(?mi)^(\s*{re.escape(name)}\s*:)\s*.*$")
    if pat.search(text):
        return pat.sub(rf"\1 {value}", text, count=1)
    return text.rstrip() + f"\n{name}: {value}\n"


@dataclass
class WS:
    path: Path
    wid: str
    title: str
    work_type: str
    parent: str
    status: str
    branch: str
    worktree: str
    active_task: str
    conflict: str


def load_ws(path: Path) -> WS:
    txt = path.read_text(encoding="utf-8")
    return WS(
        path=path.parent,
        wid=parse_field(txt, "Workstream ID") or path.parent.name.split("-", 1)[0],
        title=parse_field(txt, "Title"),
        work_type=parse_field(txt, "Work Type"),
        parent=parse_field(txt, "Parent Work"),
        status=parse_field(txt, "Status"),
        branch=parse_field(txt, "Branch"),
        worktree=parse_field(txt, "Worktree"),
        active_task=parse_field(txt, "Active Task"),
        conflict=parse_field(txt, "Semantic Conflict Risk") or "UNKNOWN",
    )


def workstreams(root: Path) -> list[WS]:
    """Discover workstream state across all currently attached Git worktrees.

    This avoids requiring a central mutable registry commit just to coordinate agents.
    Each workstream's STATE.md lives with that workstream branch/worktree.
    """
    roots = [root]
    for path, _branch in worktree_list(root):
        rp = Path(path)
        if rp.exists() and rp not in roots:
            roots.append(rp)
    found: dict[str, WS] = {}
    fallback_key = 0
    for r in roots:
        base = r / "workstreams"
        if not base.exists():
            continue
        for state in sorted(base.glob("WS*/STATE.md")):
            w = load_ws(state)
            key = w.wid or f"UNKNOWN-{fallback_key}"
            fallback_key += 1
            # Prefer the copy whose recorded worktree contains the state itself.
            current = found.get(key)
            if current is None:
                found[key] = w
            elif w.worktree:
                try:
                    if state.resolve().is_relative_to(Path(w.worktree).resolve()):
                        found[key] = w
                except (ValueError, OSError):
                    pass
    return sorted(found.values(), key=lambda w: w.wid)

def active_workstreams(root: Path) -> list[WS]:
    active = {"PLANNED", "ACTIVE", "BLOCKED", "READY_TO_MERGE", "MERGING"}
    return [w for w in workstreams(root) if w.status.upper() in active]


def next_id(root: Path) -> str:
    nums = []
    for w in workstreams(root):
        m = re.fullmatch(r"WS(\d+)", w.wid.upper())
        if m:
            nums.append(int(m.group(1)))
    return f"WS{(max(nums) + 1 if nums else 1):03d}"


def branch_prefix(work_type: str) -> str:
    return {
        "FEATURE": "feature",
        "CHANGE": "change",
        "UI": "ui",
        "BUG": "fix",
        "INCIDENT": "incident",
    }.get(work_type.upper(), "work")


def branch_exists(root: Path, branch: str) -> bool:
    rc, _, _ = run_git(root, "show-ref", "--verify", "--quiet", f"refs/heads/{branch}")
    return rc == 0


def worktree_list(root: Path) -> list[tuple[str, str]]:
    rc, out, _ = run_git(root, "worktree", "list", "--porcelain")
    if rc != 0:
        return []
    items: list[tuple[str, str]] = []
    path = branch = ""
    for line in out.splitlines() + [""]:
        if line.startswith("worktree "):
            path = line[len("worktree "):]
        elif line.startswith("branch refs/heads/"):
            branch = line[len("branch refs/heads/"):]
        elif not line.strip() and path:
            items.append((str(Path(path).resolve()), branch))
            path = branch = ""
    return items


def rebuild_registry(root: Path) -> None:
    base = root / "workstreams"
    base.mkdir(parents=True, exist_ok=True)
    rows = [
        "# Workstream Registry",
        "",
        "This file summarizes workstreams. Detailed state lives in each `workstreams/<WSID-name>/STATE.md`.",
        "",
        "| ID | Title | Type | Status | Branch | Worktree | Active Task | Conflict Risk |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for w in workstreams(root):
        vals = [w.wid, w.title, w.work_type, w.status, w.branch, w.worktree, w.active_task, w.conflict]
        vals = [v.replace("|", "\\|") if v else "" for v in vals]
        rows.append("| " + " | ".join(vals) + " |")
    rows += [
        "",
        "## Notes",
        "",
        "- Generated/reconciled by `.ai/scripts/workstream.py` when used.",
        "- This file is not a locking primitive.",
    ]
    (base / "REGISTRY.md").write_text("\n".join(rows) + "\n", encoding="utf-8")


def make_state(root: Path, wid: str, title: str, work_type: str, parent: str,
               isolation: str, branch: str, wt: Path, base_branch: str, base_commit: str) -> Path:
    slug = slugify(title)
    state_root = wt if wt.resolve() != root.resolve() else root
    d = state_root / "workstreams" / f"{wid}-{slug}"
    d.mkdir(parents=True, exist_ok=False)
    content = f"""# Workstream State

Workstream ID: {wid}
Title: {title}
Slug: {slug}
Work Type: {work_type.upper()}
Parent Work: {parent or 'NONE'}
Status: PLANNED

## Isolation

Isolation Mode: {isolation}
Isolation Status: CREATED
Branch: {branch}
Worktree: {wt}
Base Branch: {base_branch}
Base Commit: {base_commit}
Created At: {now_iso()}

## Ownership

Owner / Agent:
Session Label:
Last Attached: {now_iso()}

## Execution

Current Phase: PLANNING
Active Task: NONE
Active Diff: NONE
Execution Cursor: NONE
Last Completed Task: NONE
Next Action: Continue work inside the recorded worktree.

## Scope

Expected Files / Modules:
- UNKNOWN

Shared/Core Areas:
- UNKNOWN

Semantic Conflict Risk: UNKNOWN
Potential Conflicting Workstreams:
- NONE

## Validation

Tests: NOT_RUN
Review: NOT_STARTED
Policy Check: NOT_RUN
Runtime / UI Checks: NOT_ASSESSED

## Git

Last Commit: NONE
Ready To Merge: NO
Merge Target: {base_branch}
Merge Reference: NONE

## Handoff

Resume Hint: Run /continue inside {wt}
Known Risks: NONE
Blockers: NONE

## Cleanup

Merged: NO
Worktree Clean: UNKNOWN
Cleanup Eligible: NO
"""
    state = d / "STATE.md"
    state.write_text(content, encoding="utf-8")
    return state


def current_branch(root: Path) -> str:
    rc, out, _ = run_git(root, "branch", "--show-current")
    return out if rc == 0 and out else "HEAD"


def head_sha(root: Path, ref: str = "HEAD") -> str:
    rc, out, _ = run_git(root, "rev-parse", ref)
    return out if rc == 0 else "UNKNOWN"


def cmd_list(root: Path) -> int:
    ws = workstreams(root)
    if not ws:
        print("No registered workstreams.")
        return 0
    for w in ws:
        print(f"{w.wid}\t{w.status}\t{w.work_type}\t{w.branch}\t{w.worktree}\t{w.title}")
    return 0


def cmd_status(root: Path) -> int:
    print(f"Repository: {root}")
    print(f"Current branch: {current_branch(root)}")
    rc, out, _ = run_git(root, "status", "--porcelain")
    print(f"Working tree: {'DIRTY' if rc == 0 and out else 'CLEAN' if rc == 0 else 'UNKNOWN'}")
    items = worktree_list(root)
    print(f"Git worktrees: {len(items)}")
    for path, branch in items:
        print(f"  - {branch or '(detached)'} -> {path}")
    active = active_workstreams(root)
    print(f"Active workstreams: {len(active)}")
    for w in active:
        print(f"  - {w.wid} [{w.status}] {w.branch} -> {w.worktree} :: {w.title}")
    return 0


def find_matching(root: Path, parent: str, title: str) -> WS | None:
    slug = slugify(title)
    candidates = []
    for w in active_workstreams(root):
        if parent and w.parent and w.parent.upper() == parent.upper():
            candidates.append(w)
        elif slug and slug in slugify(w.title):
            candidates.append(w)
    unique = {w.wid: w for w in candidates}
    return list(unique.values())[0] if len(unique) == 1 else None


def cmd_ensure(root: Path, args: argparse.Namespace) -> int:
    match = find_matching(root, args.parent or "", args.title)
    if match and not args.force_new:
        print("Existing matching workstream found; duplicate not created.")
        print(f"Workstream: {match.wid}")
        print(f"Branch: {match.branch}")
        print(f"Worktree: {match.worktree}")
        print("Next: run /continue in that worktree.")
        return 0

    active = active_workstreams(root)
    rc, dirty, _ = run_git(root, "status", "--porcelain")
    dirty_flag = bool(dirty) if rc == 0 else False

    requested = args.isolation.upper()
    if requested == "AUTO":
        isolation = "WORKTREE" if active or dirty_flag or args.concurrent else "BRANCH"
    else:
        isolation = requested
    if isolation not in {"NONE", "BRANCH", "WORKTREE"}:
        print(f"ERROR: unsupported isolation mode: {isolation}", file=sys.stderr)
        return 2

    wid = next_id(root)
    slug = slugify(args.title)
    prefix = branch_prefix(args.type)
    work_key = args.parent if args.parent and args.parent.upper() != "NONE" else wid
    branch = args.branch or f"{prefix}/{work_key}-{slug}"
    base_branch = args.base or current_branch(root)
    base_ref = args.base or "HEAD"
    base_commit = head_sha(root, base_ref)

    # NONE means document workstream on current branch/current worktree.
    if isolation == "NONE":
        wt = root
    elif isolation == "BRANCH":
        # If branch does not exist, create it but do not switch a dirty worktree.
        if dirty_flag:
            print("Dirty working tree detected. Refusing automatic branch switch because it may mix user changes.")
            print("Use WORKTREE isolation or clean/commit the current work intentionally.")
            return 3
        if branch_exists(root, branch):
            rc, _, err = run_git(root, "switch", branch)
        else:
            rc, _, err = run_git(root, "switch", "-c", branch, base_ref)
        if rc != 0:
            print(f"ERROR: could not switch/create branch: {err}", file=sys.stderr)
            return 4
        wt = root
    else:
        wt_root = Path(args.worktree_root).expanduser().resolve() if args.worktree_root else (root.parent / ".ai-worktrees" / root.name)
        wt = wt_root / f"{wid}-{slug}"
        wt.parent.mkdir(parents=True, exist_ok=True)
        if wt.exists():
            print(f"ERROR: target worktree path already exists: {wt}", file=sys.stderr)
            return 5
        if branch_exists(root, branch):
            rc, _, err = run_git(root, "worktree", "add", str(wt), branch)
        else:
            rc, _, err = run_git(root, "worktree", "add", "-b", branch, str(wt), base_ref)
        if rc != 0:
            print(f"ERROR: could not create worktree: {err}", file=sys.stderr)
            return 6

    state = make_state(root, wid, args.title, args.type, args.parent or "NONE", isolation, branch, wt, base_branch, base_commit)
    rebuild_registry(wt)

    print("Workstream created; initialization preflight is still required.")
    print(f"Workstream: {wid}")
    print(f"Isolation: {isolation}")
    print(f"Branch: {branch}")
    print(f"Worktree: {wt}")
    print(f"State: {state}")
    if dirty_flag and isolation == "WORKTREE":
        print("NOTE: pre-existing dirty changes were left untouched in the original worktree and are not present in the new worktree.")
    print("Next: run worktree_preflight.py and validate_worktree_readiness.py in the selected worktree before production edits.")
    print(f"Worktree to initialize: {wt}")
    return 0


def find_ws(root: Path, wid: str) -> WS | None:
    for w in workstreams(root):
        if w.wid.upper() == wid.upper():
            return w
    return None


def cmd_close(root: Path, args: argparse.Namespace) -> int:
    w = find_ws(root, args.id)
    if not w:
        print(f"ERROR: workstream not found: {args.id}", file=sys.stderr)
        return 2
    state = w.path / "STATE.md"
    txt = state.read_text(encoding="utf-8")
    txt = replace_field(txt, "Status", "MERGED" if args.merged else "ABANDONED")
    txt = replace_field(txt, "Merged", "YES" if args.merged else "NO")
    if args.merge_reference:
        txt = replace_field(txt, "Merge Reference", args.merge_reference)
    txt = replace_field(txt, "Cleanup Eligible", "YES")
    state.write_text(txt, encoding="utf-8")
    print(f"{w.wid} marked {'MERGED' if args.merged else 'ABANDONED'}. Worktree was not removed.")
    return 0


def cmd_cleanup(root: Path, args: argparse.Namespace) -> int:
    w = find_ws(root, args.id)
    if not w:
        print(f"ERROR: workstream not found: {args.id}", file=sys.stderr)
        return 2
    if w.status.upper() not in {"MERGED", "ABANDONED"}:
        print(f"ERROR: cleanup blocked; status is {w.status}, not MERGED/ABANDONED", file=sys.stderr)
        return 3
    if not w.worktree:
        print("ERROR: no recorded worktree path", file=sys.stderr)
        return 4
    wt = Path(w.worktree).resolve()
    if wt == root.resolve():
        print("ERROR: refusing to remove the primary/current repository worktree", file=sys.stderr)
        return 5
    managed_parent = (root.parent / ".ai-worktrees" / root.name).resolve()
    if args.worktree_root:
        managed_parent = Path(args.worktree_root).expanduser().resolve()
    try:
        wt.relative_to(managed_parent)
    except ValueError:
        print(f"ERROR: recorded worktree is outside managed root {managed_parent}; refusing automatic removal", file=sys.stderr)
        return 6
    if wt.exists():
        rc, out, err = run_git(wt, "status", "--porcelain")
        if rc != 0:
            print(f"ERROR: cannot inspect worktree: {err}", file=sys.stderr)
            return 7
        if out:
            print("ERROR: worktree contains uncommitted changes; refusing cleanup", file=sys.stderr)
            return 8
        rc, _, err = run_git(root, "worktree", "remove", str(wt))
        if rc != 0:
            print(f"ERROR: worktree removal failed: {err}", file=sys.stderr)
            return 9
    state = w.path / "STATE.md"
    txt = state.read_text(encoding="utf-8")
    txt = replace_field(txt, "Worktree Clean", "YES")
    txt = replace_field(txt, "Cleanup Eligible", "NO")
    state.write_text(txt, encoding="utf-8")
    print(f"Worktree removed safely for {w.wid}. Branch preserved: {w.branch}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(description="AI Development OS v3.2 workstream isolation manager")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("status")
    sub.add_parser("list")

    p = sub.add_parser("ensure")
    p.add_argument("--type", default="FEATURE", choices=["FEATURE", "CHANGE", "UI", "BUG", "INCIDENT", "OTHER"])
    p.add_argument("--parent", default="NONE")
    p.add_argument("--title", required=True)
    p.add_argument("--isolation", default="auto", choices=["auto", "none", "branch", "worktree"])
    p.add_argument("--base")
    p.add_argument("--branch")
    p.add_argument("--worktree-root")
    p.add_argument("--concurrent", action="store_true")
    p.add_argument("--force-new", action="store_true")

    p = sub.add_parser("close")
    p.add_argument("id")
    p.add_argument("--merged", action="store_true")
    p.add_argument("--merge-reference")

    p = sub.add_parser("cleanup")
    p.add_argument("id")
    p.add_argument("--worktree-root")
    return ap


def main() -> int:
    root = git_root(SCRIPT_ROOT)
    if not root:
        print("ERROR: this command must run inside a Git repository", file=sys.stderr)
        return 1
    args = build_parser().parse_args()
    if args.cmd == "status":
        return cmd_status(root)
    if args.cmd == "list":
        return cmd_list(root)
    if args.cmd == "ensure":
        return cmd_ensure(root, args)
    if args.cmd == "close":
        return cmd_close(root, args)
    if args.cmd == "cleanup":
        return cmd_cleanup(root, args)
    return 2


if __name__ == "__main__":
    sys.exit(main())

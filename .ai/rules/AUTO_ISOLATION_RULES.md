# Automatic Workstream Isolation Rules

## Purpose

Automatically isolate concurrent AI development so independent agents do not contaminate each other's working trees, commits, state files, or rollback boundaries.

The system should prefer isolation when concurrency or overlap risk makes shared-worktree development unsafe, while keeping single-agent local work lightweight.

---

# 1. Isolation Modes

Use one of:

- `NONE` — single workstream, no meaningful concurrency risk.
- `BRANCH` — independent branch is sufficient because work is serial or the working directory is not shared.
- `WORKTREE` — separate Git worktree is required or strongly preferred.
- `BLOCKED` — safe isolation cannot be created automatically.

---

# 2. Automatic Isolation Decision

Before starting non-trivial `/feature`, `/change`, `/ui`, `/bug`, or long-running `/continue` work, inspect repository and workstream state.

Set `WORKTREE` when any of the following is true:

1. Another ACTIVE workstream already exists and the new work may run concurrently.
2. Another agent/process may be editing the same repository working directory.
3. The current work may touch files/modules listed by another active workstream.
4. The work is STRUCTURAL or CRITICAL and another workstream is active.
5. The user explicitly requests parallel agents or isolated work.
6. The shared root working tree contains unrelated in-progress changes that cannot safely be separated from the new task.

Set `BRANCH` when:

- independent history is useful,
- work is serial,
- no concurrent editor shares the working directory,
- and the current working tree can remain safely isolated.

Set `NONE` when:

- there is only one active workstream,
- no concurrent work is expected,
- the change is TRIVIAL or isolated,
- and the working tree is clean or belongs entirely to the current task.

---

# 3. Safety Before Automatic Creation

Before creating a branch/worktree:

1. Confirm the repository is Git-managed.
2. Inspect `git status`.
3. Do not silently move, stash, discard, commit, or overwrite user changes.
4. Identify the base branch and current HEAD.
5. Check whether the target branch/worktree already exists.
6. Check `workstreams/` for an existing matching workstream.
7. Prefer resuming an existing matching workstream instead of creating a duplicate.
8. Compare absolute Git dir/common dir, inspect the superproject boundary and verify the porcelain worktree mapping.
9. If a managed worktree root is inside the repository, prove it is ignored before creation.
10. After creation, run project setup and a clean baseline test. Failure means BLOCKED, not READY.

If safe isolation cannot be established without manipulating unrelated user changes, set:

`Isolation Status: BLOCKED`

and explain the blocker.

---

# 4. Workstream Identity

Each isolated unit should have:

- Workstream ID, e.g. `WS004`
- Work Type: FEATURE / CHANGE / UI / BUG / INCIDENT / OTHER
- Parent Work ID when available, e.g. `F012`, `C007`, `UI003`
- Branch
- Worktree path
- Base branch / base commit
- Active task
- Active diff
- Runtime/UI risk when relevant
- Conflict surface
- Status

Recommended branch naming:

- `feature/F012-reservation`
- `change/C007-order-flow`
- `ui/UI003-member-page`
- `fix/BUG031-kds-refresh`
- `incident/INC004-payment-recovery`

Recommended worktree root:

`../.ai-worktrees/<repository-name>/<workstream-id>-<slug>`

Do not place nested worktrees inside the main repository unless project policy explicitly chooses that layout.

---

# 5. Workstream Registry

`workstreams/REGISTRY.md` is the human-readable summary of known workstreams.

Each workstream stores authoritative detailed state in:

`workstreams/<WSID-name>/STATE.md`

Optional workstream-local files:

- `EXECUTION_CURSOR.md`
- `TASKS.md`
- `DIFF.md`
- `HANDOFF.md`

`docs/PROJECT_STATE.md` should only summarize active workstream IDs and the currently attached workstream, not duplicate all workstream details.

---

# 6. Agent Attachment

An agent should attach itself to exactly one mutable workstream before editing non-trivial code.

Record:

- Agent label if known
- Session start
- Workstream ID
- Current worktree
- Active task

Do not rely on an agent name as a locking primitive. Repository/worktree isolation is the safety mechanism.

---

# 7. Conflict Surface

Before parallel work begins, record likely affected areas:

- files
- modules
- database tables/migrations
- API contracts
- shared UI shells/design tokens
- configuration
- package/dependency manifests

If two active workstreams overlap, mark:

`Semantic Conflict Risk: LOW / MEDIUM / HIGH`

HIGH overlap does not always forbid parallel work, but it requires stronger merge review and may justify serializing the work.

---

# 8. Automatic Resume

`/continue` must first determine whether the current directory belongs to an active workstream.

If yes:

- resume that workstream.

If no, but exactly one unfinished workstream clearly matches the requested work:

- recommend or perform attachment to its existing worktree when safe.

If multiple plausible workstreams exist:

- do not guess; show the candidates and require disambiguation unless repository evidence uniquely resolves it.

Never create a second workstream merely because the agent cannot find the first one without checking registry/branches/worktrees.

---

# 9. Merge Lifecycle

A workstream is not complete merely because its branch is mergeable.

Before merge:

1. Task commits complete.
2. Required tests/review pass.
3. Policy validation passes at the required level.
4. Semantic conflict review completed.
5. Base branch drift assessed.
6. Required rebase/merge-from-base performed safely when project policy requires it.

After merge:

- record merge commit or integration reference,
- mark workstream `MERGED`,
- update registry,
- only then consider worktree cleanup.

---

# 10. Automatic Cleanup

Automatic cleanup may remove a worktree only when all are true:

- workstream status is MERGED or explicitly ABANDONED,
- worktree is clean,
- no uncommitted work exists,
- branch preservation policy is known,
- the worktree path is positively identified as managed by the workstream system.

Never use forced removal by default.

Branch deletion is more destructive than worktree removal and should be conservative. Keep the branch unless project policy or the user explicitly allows deletion after merge.

---

# 11. Stale Workstream Detection

A workstream may be classified `STALE` when:

- its branch/worktree no longer exists,
- state says ACTIVE but no unfinished task exists,
- it was merged but never closed,
- or its recorded worktree points somewhere invalid.

Do not auto-delete stale state. Reconcile it through `/workstream status` or `/sync`.

---

# 12. User Changes Are Sacred

Automatic isolation must never:

- discard user changes,
- auto-stash without a documented restore plan,
- auto-commit unrelated changes,
- force reset,
- force delete a branch/worktree with uncommitted content.

When automation conflicts with preservation of user work, preservation wins.

---

# Final Principle

Automatic isolation should remove coordination burden, not remove engineering judgment.

Create isolation automatically when it is clearly safer; otherwise remain conservative and explain why automation stopped.

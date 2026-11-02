# Workstream and Multi-Agent Rules

## Purpose

Provide a stable unit of ownership for parallel or long-lived AI development.

Read `.ai/rules/AUTO_ISOLATION_RULES.md` for automatic branch/worktree decisions.

---

# Workstream Model

A workstream represents one independently resumable and integratable line of work.

Recommended structure:

```text
workstreams/
├── REGISTRY.md
└── WS001-feature-name/
    ├── STATE.md
    ├── EXECUTION_CURSOR.md      # optional
    ├── TASKS.md                 # optional
    ├── DIFF.md                  # optional
    └── HANDOFF.md               # optional
```

Detailed state belongs to the workstream. `PROJECT_STATE` only summarizes active IDs.

---

# Statuses

Use:

- `PLANNED`
- `ACTIVE`
- `BLOCKED`
- `READY_TO_MERGE`
- `MERGING`
- `MERGED`
- `ABANDONED`
- `STALE`

---

# Isolation

Independent simultaneous work should use separate branches and, when the repository/workspace may be shared concurrently, separate Git worktrees.

Do not let independent agents edit unrelated tasks in the same mutable working tree.

---

# Ownership

Each active workstream records:

- branch
- worktree
- base branch/base commit
- work type / parent work
- active task
- active diff
- likely touched areas
- semantic conflict risk
- agent/session label when useful

This is coordination metadata, not an exclusive distributed lock.

---

# Shared Files and Semantic Conflicts

If multiple workstreams touch the same core module, database schema, contract, config, package manifest, shared UI shell, or design tokens, record potential semantic conflict before merge.

Git text conflicts are only one form of conflict.

Example:

- Workstream A changes order state transitions.
- Workstream B changes scheduler behavior relying on those states.
- Git merges cleanly.
- Business semantics may still conflict.

Use `/merge` for semantic review.

---

# State Authority

For a workstream, use evidence in this order:

1. Actual branch/worktree code and tests
2. Git status/log
3. Workstream STATE / cursor / task artifacts
4. Global PROJECT_STATE summary
5. Chat memory

---

# Completion

A workstream may be `READY_TO_MERGE` only when its required tasks, commits, validation, review, and policy checks are complete.

After successful integration, set `MERGED` and record integration evidence before worktree cleanup.

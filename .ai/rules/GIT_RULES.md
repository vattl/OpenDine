# Git Transaction Rules

## Purpose

Make every completed task independently understandable, traceable, and reversible.

A task is not only an implementation unit. It is also the default Git transaction boundary.

---

# 1. Core Rule

For STANDARD, STRUCTURAL, and CRITICAL work:

TASK IMPLEMENTATION
→ TASK-SCOPED VALIDATION
→ REVIEW TASK DIFF
→ STAGE ONLY TASK-RELATED CHANGES
→ COMMIT
→ RECORD COMMIT HASH
→ MARK TASK DONE

A task must not be marked complete before its required local commit and integrate gate succeed. If Git is unavailable, safely initialize repository tracking or keep the task `READY_TO_COMMIT`; do not waive the commit because the directory was not previously a repository.

TRIVIAL work may use a single direct commit after verification.

---

# 2. One Task, One Reversible Commit by Default

Prefer one independently revertible commit per completed task.

A task commit should contain only changes required for that task, including directly related tests and documentation.

Do not mix unrelated work into the same commit.

---

# 3. Dirty Working Tree Safety

Before starting a task, inspect Git status.

Classify existing changes as:

- PRE_EXISTING
- CURRENT_TASK
- UNKNOWN

Never silently include PRE_EXISTING or UNKNOWN changes in the current task commit.

If changes are interleaved in the same file, use selective staging when safe.

If safe isolation is not possible, do not create a misleading mixed commit. Record the blocker or create a deliberate recovery strategy.

---

# 4. Selective Staging

Do not default to broad staging commands that may capture unrelated files.

Prefer task-scoped staging.

Examples of acceptable intent:

- stage explicit files owned by the task
- stage selected hunks when a file contains unrelated modifications

Before committing, inspect the staged diff.

The staged diff must correspond to the current task's Definition of Done.

---

# 5. Commit Message Contract

Use a concise Conventional Commit-style subject when appropriate:

`<type>(<scope>): <summary>`

Examples:

- `feat(kds): add scheduler priority scoring`
- `fix(order): remove cancelled orders from queue`
- `refactor(layout): replace legacy two-column shell`
- `docs(api): sync reservation endpoints`

The commit body should explain meaningful changes when the task is not trivial:

Task: T004
Parent: F012

Changed:
- Added wait-time priority scoring.
- Added cancellation guard.
- Added regression tests.

Verified:
- unit tests: PASS
- type check: PASS

Diff:
- D3 MODIFY SchedulerPriority
- D4 REMOVE legacy cancellation path

Do not write vague messages such as `update`, `fix stuff`, or `changes`.

---

# 6. Commit Evidence

After a successful task commit, record:

- Commit Hash
- Commit Subject
- Task ID
- Parent Work ID
- Files / areas changed
- Verification summary

Store the primary record in the task file and update PROJECT_STATE / SESSION_CHECKPOINT when relevant.

---

# 7. Task DONE Rule

For normal Work Items, completion requires:

- Definition of Done satisfied
- Required validation completed
- Staged diff reviewed
- Task-scoped commit created
- Commit hash recorded

Without the commit, use:

`READY_TO_COMMIT`

or

`PARTIAL`

rather than DONE.

After committing, run `python .ai/scripts/gate.py work --work-item <dir> --phase integrate`. A dirty shared worktree blocks integration; isolate it instead of committing unrelated changes.

---

# 8. Partial Work

Do not create a normal task-completion commit for incomplete work.

If interruption risk is high and a durable checkpoint is needed, a Work-In-Progress commit may be used only when useful and clearly labeled:

`wip(<scope>): checkpoint T004 step 03`

WIP commits must not be confused with task completion.

When practical, clean them up according to project policy before release.

---

# 9. Failed Validation

If required task validation fails because of the current task:

Do not create the task-completion commit.

Keep the task PARTIAL / IN_PROGRESS and fix it first.

Pre-existing unrelated failures may be documented without blocking a task commit when the task itself is verified and project policy permits it.

---

# 10. Documentation Changes

Documentation directly required to describe the completed task may be included in the same task commit.

Large global synchronization work should normally be committed separately by `/sync`.

This keeps implementation commits focused and rollback behavior predictable.

---

# 11. Revertability Check

Before marking a task DONE, ask:

> If this commit is reverted, does it approximately revert only this task?

If NO, the commit boundary is probably too broad or mixed.

Exceptions must be documented.

---

# 12. /continue Recovery

When `/continue` starts, inspect:

- Git status
- recent relevant commits
- task commit records
- uncommitted diffs

If a task is documented DONE but has no matching commit evidence, verify repository reality and classify it as:

- COMMITTED_DONE
- IMPLEMENTED_UNCOMMITTED
- PARTIAL
- UNKNOWN

`IMPLEMENTED_UNCOMMITTED` should be committed separately before starting unrelated new work, when it can be isolated safely.

---

# 13. Do Not Auto-Commit User-Unrelated Changes

The AI must never use the task-commit rule as justification to commit unrelated user changes.

Repository ownership and user work take priority over workflow convenience.

---

# 14. Commit Is Not Push

Creating a local commit does not imply pushing to a remote.

Do not push unless the user or project policy explicitly requests it.

---

# Final Principle

A completed task should leave behind one clear answer to:

- What changed?
- Why did it change?
- How was it verified?
- Which commit contains it?
- How can it be reverted independently?

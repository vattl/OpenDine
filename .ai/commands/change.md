# v4.0 Unified Routing

This command is a typed entry into `/work` with Work Type = `CHANGE`. Do not create a separate lifecycle. Attach all discovery, design, implementation, verification and acceptance evidence to the parent Work Item.


---

# /change

Use for an intentional behavior change.

## Required flow

1. Restate desired current-state → target-state delta.
2. Identify capability and authoritative owner.
3. Build Layer Impact Matrix.
4. Search direct + indirect consumers.
5. If contract semantics change, create Contract Delta.
6. Review semantic UI impact.
7. Break work into tasks with Definition of Done.
8. Implement the smallest coherent cross-layer change.
9. Verify request and response propagation.
10. Run consumer regression.
11. Record completion evidence.

Do not stop after the first layer passes.

## Documentation & API Sync

After verification, update relevant:

- PRD.md
- PROJECT_STATE.md
- SESSION_CHECKPOINT.md
- ARCHITECTURE.md
- Change Spec
- `docs/openapi.yaml` (mandatory if any API endpoint was added, modified, or deleted)
- `docs/API.md`
- Tests
- CHANGELOG.md when appropriate
- Build runnable JAR (`mvn clean package -DskipTests` / `.\mvnw.cmd clean package -DskipTests`) if API was modified/added/removed

If the old behavior no longer exists, documentation must not continue describing it as current behavior.

## Completion

Only when Target State matches Actual State, legacy removal is verified, API docs are synchronized, and the JAR is built (`BUILD SUCCESS`) may IMPLEMENTATION → TESTING.


## Interruption-Safe Change Execution

For STRUCTURAL changes, the execution cursor should reference both the active Task and active Structural Diff operation/step where practical.

If interrupted during REPLACE/MOVE/REMOVE, the next agent must be able to distinguish:

- target structure already added,
- active switch completed or not,
- legacy cleanup completed or not,
- verification remaining.

Checkpoint after meaningful transformation boundaries so old/new mixed states are recoverable rather than mistaken for completion.


---

# Task Commit Gate

After a task satisfies its Definition of Done and required validation:

1. Inspect Git status.
2. Exclude pre-existing and unrelated changes.
3. Review the staged task diff.
4. Create a descriptive task-scoped commit.
5. Record commit hash and change summary in the task file.
6. Mark the task DONE only after commit succeeds.

If implementation is complete but not committed, use `READY_TO_COMMIT` / `IMPLEMENTED_UNCOMMITTED`, not DONE.



---

# v2.6 Runtime/NFR Gate

A behavioral/structural Diff must also classify runtime consequences when the changed code is long-lived, high-frequency, stateful, concurrent, or data-scale-sensitive.

The Target State must not merely look/function correctly; it must avoid retaining obsolete timers/listeners/subscriptions, duplicate data fetch loops, duplicated workers, or legacy resource paths after replacement.



## Automatic Workstream Isolation Gate (v3.1)

Before non-trivial mutable work, inspect active workstreams and Git state.

When shell/Python execution is available, prefer:

```bash
python .ai/scripts/workstream.py status
```

If another active workstream exists, concurrent work is expected, the root working tree contains unrelated changes, or the change may overlap shared modules, evaluate `.ai/rules/AUTO_ISOLATION_RULES.md` and establish/resume the appropriate workstream before editing.

Use `.ai/scripts/workstream.py ensure ...` when safe automation can create the branch/worktree. Prefer resuming an existing matching workstream over creating a duplicate.

Never discard, auto-stash, auto-commit, reset, or force-remove unrelated user changes in order to satisfy isolation.


---

# v3.4 Shared-Capability Gate

Before implementing a STANDARD+ change to a shared rule/contract/service, determine whether the target is a capability with multiple consumers.

If yes:

1. identify authoritative owner,
2. build consumer coverage,
3. include upstream/downstream semantics in the Diff,
4. avoid caller-specific patches unless explicitly justified,
5. run `/verify` before DONE.

# v4.0 Unified Routing

This command is a typed entry into `/work` with Work Type = `FEATURE`. Do not create a separate lifecycle. Attach all discovery, design, implementation, verification and acceptance evidence to the parent Work Item.


---

# /feature

For new capabilities.

Before implementation, determine the complete feature path from UI interaction to persistence/response/display where applicable. A backend endpoint without its required UI/client/contract work is a partial feature unless the scope explicitly says backend-only.

## Documentation & API Sync

If the feature adds or modifies API endpoints:

- Synchronously update `docs/openapi.yaml` with full schemas, parameters, and responses.
- Synchronously update `docs/API.md` contract details.
- Execute a complete Maven build (`mvn clean package -DskipTests` / `.\mvnw.cmd clean package -DskipTests`) to build the runnable JAR package.

## Completion

Before advancing to TESTING:

- Required feature behavior exists.
- Existing unaffected flows remain valid.
- Feature Diff rows are verified.
- Unexpected structural changes are classified.
- API documentation (`docs/openapi.yaml` / `docs/API.md`) synchronized for any added/modified/deleted endpoints.
- Deployable JAR artifact successfully built and verified (`BUILD SUCCESS`).
- State/checkpoint updated.


## Interruption-Safe Feature Execution

For STANDARD work that spans multiple meaningful steps, and for STRUCTURAL/CRITICAL work, initialize and maintain `docs/EXECUTION_CURSOR.md`.

Before starting a non-trivial task step, persist the cursor. After a meaningful atomic boundary, verify and advance it.

Do not impose step-level ceremony on TRIVIAL feature edits.


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

For features that introduce runtime-sensitive behavior, determine Runtime Risk independently from task complexity.

If Runtime Risk is MEDIUM/HIGH/CRITICAL, include relevant NFR analysis before implementation. Inspect performance, resource lifecycle, concurrency, boundaries, failure recovery, and observability.

Before marking runtime-sensitive feature tasks DONE, verify there is no unexplained unbounded accumulation, duplicate long-lived resource creation, unsafe retry loop, or unbounded concurrency introduced by the feature.



## Automatic Workstream Isolation Gate (v3.1)

Before non-trivial mutable work, inspect active workstreams and Git state.

When shell/Python execution is available, prefer:

```bash
python .ai/scripts/workstream.py status
```

If another active workstream exists, concurrent work is expected, the root working tree contains unrelated changes, or the change may overlap shared modules, evaluate `.ai/rules/AUTO_ISOLATION_RULES.md` and establish/resume the appropriate workstream before editing.

Use `.ai/scripts/workstream.py ensure ...` when safe automation can create the branch/worktree. Prefer resuming an existing matching workstream over creating a duplicate.

Never discard, auto-stash, auto-commit, reset, or force-remove unrelated user changes in order to satisfy isolation.

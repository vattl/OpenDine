# v4.0 Unified Routing

This command is a typed entry into `/work` with Work Type = `BUG`. Do not create a separate lifecycle. Attach all discovery, design, implementation, verification and acceptance evidence to the parent Work Item.


---

# /bug

Investigate and fix behavior where ACTUAL != EXPECTED.

Input: `$ARGUMENTS`


## Automatic Workstream Isolation Gate (v3.1)

Before non-trivial mutable work, inspect active workstreams and Git state.

When shell/Python execution is available, prefer:

```bash
python .ai/scripts/workstream.py status
```

If another active workstream exists, concurrent work is expected, the root working tree contains unrelated changes, or the change may overlap shared modules, evaluate `.ai/rules/AUTO_ISOLATION_RULES.md` and establish/resume the appropriate workstream before editing.

Use `.ai/scripts/workstream.py ensure ...` when safe automation can create the branch/worktree. Prefer resuming an existing matching workstream over creating a duplicate.

Never discard, auto-stash, auto-commit, reset, or force-remove unrelated user changes in order to satisfy isolation.

## Adaptive Investigation Rule

Root-cause depth must be proportional to risk. For an obvious isolated defect with strong evidence, do not perform unnecessary archaeology. For recurring, cross-module, data-integrity, security, concurrency, or production-critical bugs, perform full reproduction/path/root-cause analysis. Never use symptom masking as a substitute for credible diagnosis when risk is material.

## Workflow

SYMPTOM → REPRODUCTION → EXECUTION PATH → ROOT CAUSE → MINIMAL BEHAVIOR DIFF → FIX → REGRESSION TEST

## Rules

- Do not start by changing code.
- Do not pretend reproduction succeeded.
- Find the first point where actual behavior diverges from expected behavior.
- Document root cause confidence: HIGH / MEDIUM / LOW.
- Keep bug Diff surface minimal; unrelated elements should be UNCHANGED.
- Avoid arbitrary delays/retries/swallowed exceptions unless root cause justifies them.

## Bug Diff Example

Current: cancelled order remains in scheduler.
Target: cancelled order removed immediately.
Diff:
- cancellation handler → MODIFY
- queue cleanup → ADD
- scheduling algorithm → UNCHANGED

## Completion

When practical, add a regression test that fails before the fix and passes after it.

## Interruption-Safe Bug Work

For non-trivial bugs, persist the current investigation/fix step when interruption would lose important evidence.

Useful cursor states include:

- reproducing symptom,
- tracing execution path,
- root cause established,
- fix partially implemented,
- regression test pending.

Do not persist speculative root cause as fact. Record confidence and evidence.


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

# v2.6 Runtime Failure Analysis

For bugs involving crashes, slowdown, memory growth, duplicate work, queue buildup, long-running degradation, or intermittent concurrency failures, inspect runtime behavior explicitly.

Possible evidence includes memory trend, active handles/listeners/timers, request overlap, queue depth, retry count, query behavior, and reproduction under sustained load.

A symptom-masking restart/retry is not a root-cause fix unless the underlying failure model justifies it.

---

# v3.4 Escalation to Capability Repair

Escalate from `/bug` to `/repair` when any of these are true:

- the same issue has already been patched once and recurred,
- the root cause is a shared business rule,
- multiple controllers/services/screens calculate the same rule,
- fixing one consumer risks inconsistent behavior in others,
- consumer coverage is not obvious.

A local bug fix is incomplete when the root shared rule has unevaluated known consumers.

## Documentation & API Sync

If the bug fix modified any API request parameters, responses, validation, or error codes:

- Update `docs/openapi.yaml` to match the corrected API behavior.
- Update `docs/API.md` if applicable.
- Re-compile and build runnable JAR (`mvn clean package -DskipTests` / `.\mvnw.cmd clean package -DskipTests`) to ensure zero packaging regressions.

## Completion

When practical, add a regression test that fails before the fix and passes after it. Ensure API documentation is synchronized and JAR build succeeds.

# Interruption Safety Rules

## Purpose

Make non-trivial development safely resumable across model limits, crashes, tool interruptions, or agent handoffs without turning every small edit into process overhead.

## Activation

Use interruption-safe execution when any of these are true:

- Complexity is STANDARD, STRUCTURAL, or CRITICAL and work may span multiple meaningful steps.
- The task modifies several files or layers.
- A migration, API contract, state-machine, or structural UI change is in progress.
- The user or environment may switch agents before completion.

TRIVIAL work normally does not require persistent step-level checkpoints.

## Core Principle

Important continuation knowledge must not live only in model context.

Persist enough evidence so a different agent can reconstruct:

- what is being done,
- what has actually completed,
- what is partially implemented,
- what should happen next,
- what must not be repeated,
- what verification remains.

## Atomic Progress Rule

Checkpoint after a meaningful atomic boundary, not after every line and not only at session end.

Good atomic boundaries include:

- schema/migration created and validated,
- service behavior implemented,
- UI structure switched to target layout,
- legacy implementation retired,
- test group executed,
- review blocker fixed.

## Write-Before-Work Rule

Before starting a non-trivial active task, persist the execution cursor:

- Active Task
- Current Step
- Expected outcome
- Relevant files
- Next verification

This prevents a sudden interruption from leaving no clue what the agent was attempting.

## Write-After-Step Rule

After completing a meaningful step, update:

1. the task step status,
2. `docs/EXECUTION_CURSOR.md`,
3. `docs/SESSION_CHECKPOINT.md` when the finding matters beyond the current step,
4. `docs/PROJECT_STATE.md` only when project-level state materially changes.

Do not rewrite large state documents on every tiny edit.

## Repository Evidence Rule

On resume, conversational memory is optional evidence only.

Use repository evidence in this order:

1. Actual code/schema/tests
2. Git working tree and diff
3. Execution Cursor
4. Active Task and step statuses
5. Active Structural Diff
6. Session Checkpoint
7. Project State
8. General documentation

A prior agent's statement that work is complete is not sufficient without verification.

## Partial Work Rule

If a step is interrupted:

- mark or infer it as PARTIAL,
- inspect existing code before changing it,
- preserve valid partial implementation,
- complete missing work instead of restarting.

## Cross-Agent Handoff Rule

A new agent must not assume the previous agent's implementation strategy remains correct.

It should:

1. verify the current step against repository reality,
2. verify the step still serves the target state,
3. continue if valid,
4. revise the plan/Diff if evidence shows a safer or more correct approach.

## No Duplicate Recovery Rule

Before recreating any migration, service, route, component, listener, or task step, search for existing partial or completed implementation.

## Crash Recovery

If the previous agent disappeared before checkpointing:

PROJECT_STATE
→ EXECUTION_CURSOR
→ ACTIVE TASK
→ ACTIVE DIFF
→ GIT STATUS/DIFF
→ CODE
→ TESTS

Classify recovery confidence:

- HIGH: active work is clearly reconstructable.
- MEDIUM: some state is stale, but the next safe action is supported by evidence.
- LOW: intent or partial implementation cannot be reliably reconstructed.

LOW confidence must not trigger broad destructive changes. Rebuild the plan/state first.

## Checkpoint Quality

A checkpoint should record decisions and continuation facts, not a diary.

Good:

- "Moved filter state out of LegacySidebar; UI move remains."
- "Migration V023 exists and is not yet applied in tests."
- "Next: remove old sidebar rendering and run order-page tests."

Bad:

- long narrative of every command executed,
- speculative reasoning that does not affect continuation,
- duplicate copies of the PRD.

## Final Principle

Interruption safety should reduce lost work without reducing model judgment.

Persist execution state at meaningful boundaries; keep reasoning adaptive and evidence-driven.

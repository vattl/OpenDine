# Cross-Agent Handoff Rules

## Purpose

Allow Claude Code, Codex, Cursor, or another coding agent to take over unfinished work safely.

## Handoff Inputs

The receiving agent should normally inspect:

1. `docs/PROJECT_STATE.md`
2. `docs/EXECUTION_CURSOR.md`
3. `docs/SESSION_CHECKPOINT.md`
4. active task
5. active Structural Diff when present
6. Git status/diff
7. relevant code/tests

## Handoff Contract

The previous agent is expected to leave:

- current task and step,
- last verified step,
- next expected step,
- relevant files,
- verification state,
- blockers/risks that materially affect continuation.

If this contract is incomplete, use Crash Recovery rather than guessing.

## Receiving Agent Duties

Before editing:

- verify completed claims,
- identify partial work,
- check for unrepresented Git changes,
- check whether the active plan still matches the target state,
- avoid redoing verified work.

## Strategy Freedom

The receiving agent may improve or replace the previous implementation strategy when repository evidence justifies it.

It must preserve the user's target and update the relevant task/Diff when the strategy changes materially.

## Uncommitted Work

Uncommitted changes are not disposable.

Inspect them before reset, overwrite, or large rewrites.

Classify each relevant change as:

- INTENDED
- ACCIDENTAL
- UNKNOWN

Do not discard UNKNOWN work without establishing whether it contains valid partial implementation.

## Safe Handoff Summary

Before continuing meaningful implementation, produce a concise internal/visible summary when useful:

- Active work
- Verified completed steps
- Partial step
- Next step
- Relevant files
- Recovery confidence
- Key risk

## Completion

After takeover, the receiving agent owns keeping the repository resumable for the next handoff.

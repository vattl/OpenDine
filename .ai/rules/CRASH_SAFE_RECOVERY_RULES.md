# Crash-Safe Recovery Rules

## Problem

A model can hit quota/capacity/crash before it writes normal project checkpoints. State stored only inside one Git worktree may be invisible to another agent.

## Write-Ahead Principle

For non-trivial work, register the workstream **before** substantial code edits.

REGISTER → BEGIN → EDIT → JOURNAL/CHECKPOINT → VERIFY → COMMIT → COMPLETE

## Shared Runtime Registry

Use `.ai-runtime/` as project-local shared runtime metadata outside individual worktree state semantics.

Recommended files:

- `.ai-runtime/registry.json`
- `.ai-runtime/journal/<WORKSTREAM>.jsonl`
- `.ai-runtime/locks/`

If worktrees are outside the repository, tools should resolve a common project runtime root.

## Minimal Heartbeat

At meaningful execution boundaries update lightweight state:

- workstream id
- parent work id
- status
- phase
- task/step
- worktree path
- branch
- dirty flag
- last activity

Do not rewrite large Markdown files merely for heartbeat.

## Interrupted Detection

An ACTIVE/CHECKPOINTED workstream with stale heartbeat plus dirty worktree may be classified `INTERRUPTED` after verifying the worktree.

## Resume Priority

`/continue` should search in this order when available:

1. shared runtime registry
2. interrupted/dirty workstreams
3. READY_TO_COMMIT workstreams
4. matching workstream state
5. PROJECT_STATE / EXECUTION_CURSOR
6. Git diff/code/tests

## Duplicate Prevention

If the same parent requirement already has an unfinished dirty workstream, do not create a new workstream by default. Resume or explicitly resolve/abandon the existing one.

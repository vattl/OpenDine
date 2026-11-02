# /context

Inspect and summarize current project state without modifying business code.

Input: `$ARGUMENTS`


## Workstream Context (v3.1)

When workstreams exist, include current branch/worktree identity, attached workstream ID, active workstreams, and known conflict risk in the context report. Do not mutate workstream state in `/context`.

## Read

1. `docs/PROJECT_STATE.md`
2. `docs/SESSION_CHECKPOINT.md`
3. Active Diff
4. Active Feature / Change / Bug
5. Active Task
6. Git state and relevant code/tests when needed for verification

## Reconcile

Classify state as:

- CONSISTENT
- STALE
- PARTIAL
- UNKNOWN

Do not silently repair drift. Use `/sync` for synchronization.

## Output

- Current Version
- Production Version
- Current Phase
- Work Type
- Active Work
- Active Diff and progress
- Active Task
- Git Branch / Working Tree
- Validation State
- Known Issues
- Blockers
- Resume Hint
- Next Recommended Command

## Interruption Context

When active non-trivial work exists, read `docs/EXECUTION_CURSOR.md` and report:

- Current Step
- Last Completed Step
- Next Step
- Recovery Confidence

Do not modify the cursor in read-only `/context` mode.



# UI Context

When active UI work exists, also report:
- Prototype ID/path
- Prototype Status
- Prototype Gate
- Approved Target
- UI Diff
- Visual Verification
- Responsive Verification

# /merge

Safely merge one workstream/branch into another.

Input: $ARGUMENTS


## Automatic Workstream Isolation Gate (v3.1)

Merge is the integration boundary for isolated workstreams.

Before merging:

- identify source workstream and target branch,
- verify workstream status and task commits,
- inspect target-branch drift since the workstream base commit,
- check potential semantic conflicts recorded by all active/recent workstreams,
- run required contract/config/architecture checks.

A clean Git merge does not prove semantic compatibility.

After successful integration, record merge evidence and mark the workstream `MERGED`. Worktree cleanup is a separate safe operation; never force-remove a dirty worktree.

## Workflow

1. Identify source and target branches/workstreams.
2. Read source intent, Diff, tasks, and commits.
3. Inspect target changes since divergence.
4. Detect both Git conflicts and semantic conflicts.
5. Resolve conflicts according to current product intent, not line-by-line convenience.
6. Run affected contract, regression, and integration tests.
7. Verify no completed Diff operation was accidentally reversed.
8. Commit merge resolution with a clear summary.

## Semantic conflict examples

- two branches change the same state transition differently,
- one branch removes behavior another still depends on,
- API schemas remain textually mergeable but semantically incompatible.

Do not treat a clean Git merge as proof of a safe product merge.

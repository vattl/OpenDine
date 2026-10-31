# v4.0 Resume Priority

Resume in this order: active/interrupted Work Item → `.ai-runtime` registry/journal → Git worktree/diff/commits → compatibility summaries. Do not conclude there is no task merely because PROJECT_STATE or a checkpoint is stale/missing.


---

# /continue

Recovery order:

1. Shared runtime registry / interrupted workstreams
2. Dirty worktrees
3. READY_TO_COMMIT workstreams
4. Current task state
5. Execution cursor/checkpoint
6. Git status/diff
7. Requirement and Layer Impact Matrix

Before trusting previous DONE claims, verify evidence. If the existing task is cross-layer, resume missing layer work instead of opening a duplicate task.

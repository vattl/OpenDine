# Crash-Safe Recovery Rules

Before editing a STANDARD+ task, register the work before implementation.

Preferred lifecycle:
REGISTERED → ACTIVE → CHECKPOINTED → READY_TO_COMMIT → COMMITTED → VERIFIED → MERGED/CLOSED

If an ACTIVE workstream has stale activity and a dirty worktree, treat it as INTERRUPTED and inspect it before creating duplicate work for the same requirement.

`/continue` must prioritize interrupted/dirty existing work over creating a new workstream.

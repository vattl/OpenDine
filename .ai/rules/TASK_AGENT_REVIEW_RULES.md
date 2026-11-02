# Per-Task Fresh Agent and Double-Review Rules

Every planned implementation task must use a fresh implementer session and two fresh, read-only reviewers:

1. implementer: receives only the task brief, owned surface, input contract and verification command; implements, tests, commits/self-reviews and returns evidence;
2. specification reviewer: checks the final task diff against the bound requirement/spec snapshot;
3. code-quality reviewer: checks correctness, maintainability, security, test quality and patch scope.

All session identities must be concrete and globally unique across tasks and roles. A reviewer may not edit the implementation it reviews. Every orchestration dispatch receipt must bind the real task-brief SHA-256 and the same provider/model declared by the dispatched Agent. The implementer receipt binds that hashed task brief, a successful concrete verification command with exit code `0`, and a real Git base/head diff; both reviews must bind that same real final Git base, Git head, spec SHA-256 and diff SHA-256. Reviewers agreeing on a different range is invalid. Any later code change invalidates both reviews.

CRITICAL/HIGH findings block. Fixes require new final snapshots and fresh review attempts until both verdicts PASS. Tasks with overlapping mutable surfaces execute serially in one owned worktree; parallel execution requires explicit non-overlapping ownership and stable handoff contracts.

Task review does not replace whole-branch Independent Review, security review, sealed audit packet or the mandatory fresh-context Third Party Audit.

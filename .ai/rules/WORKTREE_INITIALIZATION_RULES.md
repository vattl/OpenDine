# Worktree Initialization Verification Rules

Before production edits, `/work` must prove repository isolation and a clean project baseline through `WORKTREE_READINESS.md` and `validate_worktree_readiness.py`.

Required live checks:

- repository root, current path, branch and HEAD;
- absolute `git-dir` and common dir, with truthful linked-worktree detection;
- `git worktree list --porcelain` mapping;
- `git rev-parse --show-superproject-working-tree` submodule guard;
- Git ignore proof for any repository-local managed worktree directory;
- dependency/setup command result when applicable;
- a real baseline test command and PASS result before implementation.

`worktree_preflight.py` loads setup and baseline argv only from the repository-owned `.ai/config/worktree-command-profile.json`, runs them with `shell=False`, retains logs and writes evidence. Direct command overrides are forbidden. The readiness artifact binds the command-profile hash, exact recorded commands and log hashes; the validator rechecks all three. A non-null setup command requires `Setup Result: PASS` plus a hash-valid setup log; only a null setup command may use `NOT_APPLICABLE` for every setup evidence field. Setup or baseline failure leaves the task BLOCKED and preserves the original failure. Never reinterpret a failing baseline as the new feature's RED.

Git cleanliness must be checked both before and after setup/baseline execution. Only the exact preflight-owned log files may be excluded from the post-command check; a command that exits zero but creates or changes any other repository file leaves readiness BLOCKED. The ready-phase validator independently rechecks live Git status while excluding only the readiness artifact and its declared logs.

At `ready`, the recorded preflight HEAD must equal live HEAD. At `accept` and `integrate`, that preflight HEAD must remain an ancestor of live HEAD so legitimate implementation commits are allowed without accepting unrelated history.

Linked worktrees are the default for STANDARD+ implementation. A primary checkout is allowed only as an explicit, reasoned exception for a serial, uncontended task and requires a repository-bound authorization artifact plus SHA-256; a CLI flag cannot self-authorize it. Main/master has the same requirement. Submodules are fail-closed.

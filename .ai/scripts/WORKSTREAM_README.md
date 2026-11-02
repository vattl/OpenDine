# Automatic Workstream Isolation Script

`workstream.py` manages safe branch/worktree isolation for v3.2.

Examples:

```bash
python .ai/scripts/workstream.py status
python .ai/scripts/workstream.py list
python .ai/scripts/workstream.py ensure --type FEATURE --parent F012 --title "reservation ordering"
python .ai/scripts/workstream.py ensure --type UI --parent UI004 --title "member dashboard" --concurrent
python .ai/scripts/workstream.py close WS003 --merged --merge-reference abc1234
python .ai/scripts/workstream.py cleanup WS003
```

## Safety behavior

The script does not automatically:

- discard changes,
- stash user changes,
- commit unrelated files,
- force-reset branches,
- force-remove dirty worktrees,
- delete branches after cleanup.

When the main worktree is dirty and a new isolated workstream is requested, WORKTREE mode can be created from committed HEAD while leaving the dirty main worktree untouched.

The script cannot change the parent shell's current directory. After creation, switch your coding agent/editor to the printed worktree path.

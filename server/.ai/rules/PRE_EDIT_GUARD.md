# Pre-Edit Guard (Compatibility Layer)

v4.2 consolidates pre-edit enforcement into `IMPLEMENTATION_READY`.

Before modifying production code, evaluate `.ai/rules/IMPLEMENTATION_READY_RULES.md` and produce an Implementation Ready result.

If the result is `NO`, do not edit production code. Resolve blockers first.

For implementation work, readiness also requires truthful worktree initialization/baseline evidence and complete TDD/task-Agent plans. A merely created branch/worktree is not ready.

This file remains for backward compatibility with v4.1 commands/rules that mention Pre-Edit Guard.


## v4.3 UI enforcement

For any UI impact or REFINE/REFACTOR/REDESIGN intent, run the HTML prototype evidence check before production UI edits. A design strategy, implementation plan or native preview cannot satisfy this gate.

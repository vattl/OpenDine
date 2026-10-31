# /multi-agent

Plan and govern parallel agents for one Work Item.

1. Define the task dependency DAG and contract-first prerequisites.
2. Assign roles, owned areas and immutable handoff contracts in `AGENT_PLAN.md`.
3. Create isolated workstreams/worktrees for simultaneous mutable work.
4. Do not dispatch a dependent task before its input contract is stable.
5. Aggregate actual command/evidence results; do not convert agent claims into PASS.
6. Dispatch a unique fresh implementer session for each implementation task with only its brief and immutable contracts.
7. After self-review, dispatch a different fresh read-only specification reviewer, then another different fresh read-only code-quality reviewer.
8. Bind both reviews to the same final spec/diff SHA-256 values; a fix invalidates both reviews and requires fresh attempts.
9. Serialize mutable tasks whose owned surfaces overlap and resolve semantic conflicts in declared integration order.
10. Preserve a final independent whole-branch reviewer in addition to task-level double review.

`Aggregation Status: PLANNED/READY` is valid only at IMPLEMENTATION_READY. Only `Aggregation Status: PASS` satisfies accept/integrate. Task identities and review evidence live in `TASK_AGENT_LEDGER.md`.

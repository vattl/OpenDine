# Multi-Agent Orchestration Rules

Worktrees isolate files; they do not by themselves coordinate a product team.

When more than one agent works on a Work Item, create `AGENT_PLAN.md` before dispatch.

It must define:

- role and accountable output for every agent;
- task dependency DAG and sequential/parallel boundaries;
- owned files/modules/contracts and shared conflict surfaces;
- immutable input contract and expected handoff artifact;
- verification command and completion evidence per task;
- per-task unique fresh implementer, different fresh read-only specification reviewer and different fresh read-only code-quality reviewer;
- snapshot-bound task review evidence plus an independent whole-branch reviewer;
- integration order and evidence aggregation owner.

No agent may broaden its owned scope or assume another layer will adapt. Contract-first tasks land before dependent parallel tasks. Overlapping mutable tasks must be serialized. `Aggregation Status: PLANNED/READY` is planning-only; `PASS` requires all task double-reviews, handoffs, checks, conflict resolution and whole-branch review complete.

The mandatory acceptance auditor must not be one of the implementation authors. Start it with fresh context, grant no implementation-edit permission, and give it only the sealed `AUDIT_PACKET.md` plus referenced evidence. Implementation agents may not write their own `THIRD_PARTY_AUDIT.md`. If the auditor finds a defect, the implementation owner fixes it and a new sealed packet is audited.

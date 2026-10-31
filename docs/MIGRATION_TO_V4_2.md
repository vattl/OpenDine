# Migration to v4.2

v4.2 does not remove v4.1 capabilities. It changes which artifacts are authoritative.

## New authoritative additions
- `docs/project/BUSINESS_RULES.md`
- Work Item Business Invariants section
- Work Item Impact Map as downstream affected-surface authority
- Scenario Matrix for STANDARD+
- `IMPLEMENTATION_READY` hard gate
- explicit completion levels

## Legacy compatibility
`PRE_EDIT_GUARD`, `PROJECT_STATE`, `SESSION_CHECKPOINT`, `EXECUTION_CURSOR`, old task/workstream summaries remain available but must not compete with the Work Item + runtime registry + Git truth model.

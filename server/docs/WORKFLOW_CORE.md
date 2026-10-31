# v4.3 Unified Product Delivery Workflow

The authoritative full state machine is `.ai/rules/WORKFLOW_CORE.md`. This overview must not redefine or weaken its gates.

v4.0 models normal frontline product/software work as one lifecycle instead of asking the agent/user to manually orchestrate many command-specific processes.

## Real-team analogy

| v4 Phase | Typical real team behavior |
|---|---|
| REQUEST | Product/owner raises work |
| UNDERSTAND | PM + engineer clarify target |
| DISCOVER | Senior engineer investigates system impact |
| DESIGN | Tech lead/UI designer define solution |
| PLAN | Engineer breaks into executable slices |
| IMPLEMENT | Developer builds |
| SELF_VERIFY | Developer tests own work |
| REVIEW | Peer/senior review |
| ACCEPT | Product/QA verifies original requirement |
| INTEGRATE | Merge/integration validation |
| RELEASE | Deploy/release gate |
| MONITOR | Observe production health |

The same lifecycle adapts to small changes: phases may be lightweight/in-memory, but their logic remains intact.

## Why this matters

The v3.x system had strong specialist capabilities but weak orchestration. Agents could do a contract check, UI check, capability map or repair in isolation and still miss the full business path. v4 makes those capabilities children of one Work Item.

## Vertical slicing

Prefer slices that leave a coherent business path working after each commit. Avoid splitting exclusively by frontend/backend/controller/service layers unless the architecture or team boundary requires it.

## API handoff

Producer changes and consumer changes are one engineering concern. If they cannot land together, create a concrete handoff and keep completion status truthful.

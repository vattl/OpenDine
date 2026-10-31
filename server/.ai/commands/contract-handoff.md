# /contract-handoff — Bidirectional Frontend ↔ Backend Collaboration

Use when one layer needs another layer to change an interface or capability.

## Direction A — Backend → Frontend
Generate `FRONTEND_CONSUMER_HANDOFF` describing:
- changed API/field/enum/validation/error behavior
- before/after contract
- required client types/state/request mapping
- UI/interaction/display implications
- example calls
- compatibility and migration order

## Direction B — Frontend → Backend
Generate `BACKEND_CAPABILITY_REQUEST` describing:
- UI/business data need
- current API capability
- exact gap
- preferred contract extension/new API only when justified
- expected request/response semantics
- backend layers likely affected
- verification criteria

For UI prototype-originated requests also update `PROTOTYPE_INTERACTION_CONTRACT.md` and `BACKEND_COORDINATION_REPORT.md`. A handoff makes the dependency explicit; it does not authorize fake frontend behavior or full UI acceptance.

Do not let one layer silently assume the other will adapt.

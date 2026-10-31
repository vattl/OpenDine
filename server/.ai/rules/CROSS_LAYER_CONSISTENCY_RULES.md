# v4.0 Integration

This rule is now part of DISCOVER/SELF_VERIFY in the Unified Workflow. Prefer recording the result in the Work Item IMPACT_MAP rather than creating disconnected lifecycle state.


---

# Cross-Layer Consistency Rules

## Hard rules

1. Do not mark a cross-layer task complete while any relevant layer is UNKNOWN.
2. Changes to API/request/response/state semantics trigger consumer search.
3. Backend contract changes trigger frontend and UI inspection.
4. UI interaction changes trigger backend/API capability inspection.
5. Request and response propagation must both be evaluated.
6. Business semantic changes trigger UI semantic impact review even when fields are unchanged.
7. Shared domain state changes require UI state/action mapping review.
8. Do not silently adapt mismatched contracts in one layer as a local workaround.
9. If the UI requires unsupported backend behavior, record CONTRACT_GAP and either extend the contract or explicitly redesign the UI.
10. End-to-end evidence is required for high-risk cross-layer changes.

## Required statuses

Each layer entry must be one of:

- CHANGE
- VERIFY_NO_CHANGE
- NOT_APPLICABLE
- UNKNOWN

VERIFIED_DONE requires UNKNOWN = 0.

## Triggers

Frontend/UI inspection is mandatory when touching:

- API routes
- DTOs
- params
- enums
- validation
- authorization
- state machines
- filters/sorting/pagination
- response fields
- event schemas
- shared business semantics

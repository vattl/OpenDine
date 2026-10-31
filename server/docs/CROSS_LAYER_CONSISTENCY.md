# Cross-Layer Consistency

## Why this exists

A common AI failure pattern is to fix only the layer explicitly mentioned by the user. Typical consequences:

- backend expects a new parameter but frontend still sends the old one
- response field changes but UI mapping still reads the old key
- domain state changes but available UI actions are stale
- business semantics change but labels/tooltips/filters still communicate the old meaning
- UI adds a filter that the API cannot represent

## Required model

For each STANDARD+ task, evaluate:

1. UI
2. Interaction
3. Frontend state
4. API client
5. Request contract
6. Backend controller/handler
7. Service/domain logic
8. persistence/schema if relevant
9. Response contract
10. Frontend mapping/types
11. Display/empty/error/permission states
12. regression consumers

## Layer Impact Matrix

Every relevant layer must be classified. Example:

| Layer | Relevant | Action | Evidence |
|---|---:|---|---|
| UI | yes | CHANGE | shift selector screenshot/test |
| Frontend state | yes | CHANGE | form state diff |
| API client | yes | CHANGE | request payload test |
| Request DTO | yes | CHANGE | backend contract test |
| Service | yes | CHANGE | unit/integration test |
| DB | no | NOT_APPLICABLE | schema unchanged |
| Response mapping | yes | VERIFY_NO_CHANGE | type check |
| Display | yes | CHANGE | UI verification |

## Contract Delta

When contract semantics change, record BEFORE and AFTER. Search all known consumers of the old contract.

## Semantic UI Impact

Even without DTO changes, domain meaning can change. Review:

- labels
- helper text/tooltips
- filters
- validation messages
- button availability
- disabled/loading/error states
- permissions
- empty states
- state badges

## End-to-End Data Flow

Verify a representative flow:

`User input → UI state → request payload → backend receives → domain logic → response → frontend mapping → rendered result`

A controller-only test is insufficient evidence for a cross-layer change.

# Workflow Router Rules

The router is a hard pre-implementation gate for `/work`.

## Route before editing
Classify:
- work type: FEATURE / CHANGE / BUG / REPAIR / REFACTOR / MAINTENANCE
- complexity: TRIVIAL / STANDARD / STRUCTURAL / CRITICAL
- UI impact: NONE / MINOR / STRUCTURAL
- contract impact: NONE / CONSUMER_ACTION / PROVIDER_ACTION / BOTH
- baseline impact: LEVEL_0 / LEVEL_1 / LEVEL_2 / LEVEL_3

## UI HTML prototype hard gate
If `UI_IMPACT=MINOR|STRUCTURAL` or UI intent is `REFINE|REFACTOR|REDESIGN`, set:

- `UI_DESIGN_TRACK=REQUIRED`
- `PROTOTYPE_REQUIREMENT=REQUIRED`
- `PROTOTYPE_MODE=HTML`

Production UI implementation is BLOCKED until:
- project/design baseline is read
- UI Design Strategy exists
- an isolated renderable `.html` or `.htm` prototype artifact exists
- prototype visual reference/screenshot exists
- design critique completed
- the rendered prototype has been presented to the user
- explicit user approval is recorded as `Approval Status: APPROVED`
- UI lock exists
- measured UI spec, complete production mapping and classified legacy structural diff exist
- `validate_ui_fidelity.py --phase plan` passes with zero unmapped/unclassified regions
- every prototype interaction/data need is mapped in `PROTOTYPE_INTERACTION_CONTRACT.md`
- API_EXTENSION/NEW_API rows have assigned Backend Capability Requests; NOT_SUPPORTED rows are resolved by prototype revision
- `validate_ui_capabilities.py --phase plan` passes
- device/input/context profiles, component families and business operations are complete in `ADAPTIVE_UI_CONTRACT.md`
- every REQUIRED profile has prototype evidence and `validate_ui_adaptive.py --phase plan` passes
- all structurally changed surfaces are covered by the Prototype Coverage Matrix or have an explicit user-approved exception

Native/component-compatible prototypes may be supporting implementation experiments, but they do not satisfy the review gate. HTML is the mandatory review format; production implementation still uses the target stack after approval.

Do not treat an Implementation Plan as a UI Design Plan.

## API/contract routing
If request/response fields, enums, requiredness, validation, route, errors, auth or pagination semantics change, trigger Contract Collaboration automatically.

## Capability repair escalation
Repeated patches, duplicated rules, shared-owner defects or multiple inconsistent consumers escalate to capability-aware repair.

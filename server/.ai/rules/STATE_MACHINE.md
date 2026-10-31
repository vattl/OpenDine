# Development State Machine

Authoritative phases:

IDLE → SPEC → PLANNING → IMPLEMENTATION → TESTING → REVIEW → SYNC → RELEASE_READY → RELEASED → IDLE

Alternative state: BLOCKED.

## Forward Transitions

- Spec defined → PLANNING
- Plan + Diff sufficient → IMPLEMENTATION
- Required tasks + Diff verified → TESTING
- Required tests pass → REVIEW
- No unresolved CRITICAL/HIGH → SYNC
- Sync complete → RELEASE_READY
- Actual release recorded → RELEASED → IDLE

## Reverse Transitions

- TESTING failure → IMPLEMENTATION
- REVIEW blocking finding → IMPLEMENTATION
- SYNC finds implementation defect → IMPLEMENTATION
- Release gate failure → BLOCKED

## /continue Routing

- SPEC → resume spec
- PLANNING → resume Diff/plan
- IMPLEMENTATION → resume active task
- TESTING → /test
- REVIEW → /review
- SYNC → /sync
- RELEASE_READY → /release
- BLOCKED → re-evaluate blocker
- IDLE → no active work
- unreliable state → Recovery Mode


## UI Prototype Substates

UI design substates live inside the planning stage and do not replace the global lifecycle:

UI_AUDIT → BLUEPRINT → PROTOTYPE_DRAFT → PROTOTYPE_REVIEW → APPROVED → UI_DIFF → IMPLEMENTATION

Transitions:
- PROTOTYPE_REVIEW + revision requested → PROTOTYPE_DRAFT
- PROTOTYPE_REVIEW + user approval → APPROVED
- APPROVED + sufficient UI Diff → IMPLEMENTATION
- No UI-impacting work may enter IMPLEMENTATION before the HTML prototype is explicitly approved by the user and locked.

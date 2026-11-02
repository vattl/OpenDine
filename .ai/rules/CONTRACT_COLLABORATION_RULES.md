# Cross-Layer Contract Collaboration Rules

Frontend and backend are collaborating providers/consumers of one business capability.

## Core rule
No layer may silently assume another layer will adapt.

## Backend → Frontend
When backend changes a consumer-visible contract, either update consumers in the same Work Item or create an explicit frontend consumer handoff.

Handoff must state:
- endpoint/event/interface
- before/after schema and semantics
- field type/required/default/enum/validation
- error/auth/pagination changes
- client type and request/response mapping changes
- UI/interaction/display implications
- example call/result
- compatibility classification

## Frontend → Backend
When frontend needs unavailable data/behavior, create a backend capability request before inventing client workarounds.

Classify each need:
- AVAILABLE
- DERIVABLE
- API_EXTENSION
- NEW_API
- NOT_SUPPORTED

Prefer extending an appropriate existing contract over creating redundant APIs.

## Status
NO_CHANGE / PROPOSED / FRONTEND_ACTION_REQUIRED / BACKEND_ACTION_REQUIRED / BOTH_ACTION_REQUIRED / IMPLEMENTED / VERIFIED / BLOCKED

A Work Item cannot be fully accepted while a required cross-layer action remains unresolved unless the requested scope explicitly ends at a documented handoff.

For an approved UI prototype entering production development, a documented handoff makes the unfinished dependency visible but does not make the UI accepted. The UI remains BLOCKED/PARTIAL until the provider contract, consumer integration and end-to-end evidence are VERIFIED. Surface all pending items in `BACKEND_COORDINATION_REPORT.md`.

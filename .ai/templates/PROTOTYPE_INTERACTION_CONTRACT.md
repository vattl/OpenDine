# Prototype Interaction Capability Contract

UI ID:
Approved Prototype:
Parent Work Item:

Capability Mapping Status: DRAFT / COMPLETE
All Prototype Interactions Mapped: NO
Unmapped Prototype Interactions: 0
Production Fake/Mock/Placeholder Interactions: 0
Unresolved Required Backend Capabilities: 0

## Interaction-to-Capability Matrix

| Interaction ID | Prototype Interaction | Classification | Production Integration | Contract / Capability Evidence | Capability Request | E2E Evidence | Status |
|---|---|---|---|---|---|---|---|
| INT-001 | describe click/input/filter/submit/data need | AVAILABLE / DERIVABLE / API_EXTENSION / NEW_API / NOT_SUPPORTED | repository-relative production file/component | existing contract/code evidence for AVAILABLE/DERIVABLE, otherwise N/A | repository-relative Backend Capability Request or N/A | evidence path or PENDING during plan | PLANNED / IMPLEMENTING / IMPLEMENTED / VERIFIED / BLOCKED |

## Classification Rules

- AVAILABLE: an existing verified backend/interface directly supports the interaction.
- DERIVABLE: production code can safely derive it from existing verified data without inventing business truth.
- API_EXTENSION: an existing contract must be extended.
- NEW_API: a new backend/interface capability is required.
- NOT_SUPPORTED: implementation is blocked; revise and re-approve the prototype or authorize backend capability work.

Every visible datum, button, form submission, filter, sort, pagination action, state transition, upload/download, notification and permission-dependent action needs a row. Prototype-only mock behavior must never become a production integration path.

AVAILABLE and DERIVABLE are evidence claims, not convenient defaults. Link a real contract, client, controller, schema or verified capability record; a bare label does not pass the plan gate.

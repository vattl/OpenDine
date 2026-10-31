# Implementation Design — WI-059

## Root Fix / Owner
`ApprovalService` applies a versioned binding policy at both issuance and consumption; controllers may not weaken it.

## Why this location
All approval modes converge in this service and the approval row is the CAS authority.

## End-to-End Change
### Backend
Add v2 validation and explicit legacy telemetry. Propagate terminal/resource/amount into every AccessContext consumer.
### Frontend
No code edit here; handoff specifies sending `bindingVersion: 2`, a stable resource and terminal ID.
### UI / Interaction
No visual change.
### Data / Persistence
Flyway V037 adds non-null `binding_version` default 1 and index/metadata remains compatible with historical rows.
### Interfaces / Contracts
Add fields and error codes without removing v1 fields.
### Jobs / Events / Integrations
None.

## Preserve / Compatibility
Historical/null versions normalize to v1. v1 keeps current behavior temporarily but returns `legacyBinding=true` and logs `approval_legacy_binding`.

## API Consumer Migration / Handoff
See `CONTRACT_HANDOFF.md`; no layer is assumed to adapt silently.

## Failure / Boundary Behavior
V2 issuance rejects placeholder IDs (`N/A`, `ID:`), missing fields and invalid version. V2 consumption compares normalized strings and `BigDecimal.compareTo`; mismatch returns false before CAS.

## Runtime / Performance / Reliability
No additional round trips. CAS remains the sole state transition. Rejected comparisons do not mutate state.

## Security / Permissions
This slice binds context; action-level approver permission and rate limiting remain WI-061.

## UI Design Track
NOT_APPLICABLE (no UI production edit).

## Vertical Slice Plan
1. RED unit tests for issuance and each mismatch.
2. Migration/entity/service implementation.
3. Context propagation and controller tests.
4. OpenAPI/API docs/handoff; package and accept.

## Verification Strategy
Focused approval/controller tests, migration review, full package build, security review, executable gates.

## Rollback / Recovery
Feature semantics can fall back to v1 without dropping the additive column. Never roll back CAS/expiry behavior.

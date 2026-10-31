# UI Implementation Map

UI ID: UI-DAILY-SEQUENCE-001

Approved Prototype: review candidate `daily-close-sequence.html`

Measured Spec: `MEASURED_UI_SPEC.md`

Parent Feature / Change: WI-067

Interaction Capability Contract: `PROTOTYPE_INTERACTION_CONTRACT.md`

Backend Coordination Report: `BACKEND_COORDINATION_REPORT.md`

Mapping Status: COMPLETE

All Prototype Regions Mapped: YES

Unmapped Prototype Regions: 0

Legacy Structure Reused Without Approval: NO

## Prototype-to-Production Mapping

| Prototype Region | Production File / Component | Operation | Business Logic | Visual Constraints | Notes |
|---|---|---|---|---|---|
| App header | external Flutter `DailySettlePage` AppBar | REUSE | PRESERVE | 56px white header | existing approved structure |
| Authority/backlog card | external Flutter `DailySettlePage._body` | EXTEND | MODIFY | date-first, orange soft notice | consumes server context |
| Sequence progress | external Flutter local widget | CREATE | MODIFY | two equal nodes, no overflow | today locked until prior close |
| Precheck card | external Flutter `_precheckCard` | REUSE | PRESERVE | existing status colors | bind authoritative date |
| Summary grid | external Flutter `_summaryCard` | REUSE | PRESERVE | two columns | load server date |
| Close action | external Flutter `_confirmSettle` | MODIFY | MODIFY | 48px danger button, date label | sends server date/token |

## Token Mapping

| Visual Constraint | Target | Existing Token | Action |
|---|---:|---|---|
| brand | #EA580C | `MobileColors.brand` | REUSE |
| brand soft | #FFF1E6 | `MobileColors.brandSoft` | REUSE |
| spacing | 14px | `MobileMetrics.pagePadding` | REUSE |
| radius | 8px | `MobileMetrics.radius` | REUSE |

## Business Logic to Preserve

- `daily:settle` permission guard.
- blockers disable the action; warnings require manager authorization.
- settle confirmation and idempotency.
- Z report after successful close.

## Legacy Visual Implementation to Remove

- Local-clock-derived date content and hardcoded “16:00” authority text.

## High-Fidelity Constraints

- Do not redesign the page or introduce a date picker that could imply arbitrary close order.
- Backlog message must remain informational, not an overridable warning.

## Responsive Mapping

| Target Width | Prototype Behavior | Production Behavior Required |
|---|---|---|
| 320–480px | single column, two flexible progress nodes | same, no horizontal overflow |

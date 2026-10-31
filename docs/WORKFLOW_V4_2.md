# Workflow v4.2 — Domain & Workflow Consolidation

> Compatibility reference only. The current authoritative v4.3 lifecycle is `.ai/rules/WORKFLOW_CORE.md`; this document must not override its product, executable-gate, UI, security or release requirements.

v4.2 keeps the unified `/work` lifecycle and tightens its business logic around seven core objects:

1. Project Baseline
2. Work Item
3. Business Invariants
4. Impact Map
5. Implementation Design
6. Vertical Slices / Scenario Matrix
7. Acceptance Evidence

## Authoritative flow

`REQUEST → UNDERSTAND → BASELINE FAST CONTEXT → ROUTE → DISCOVER → DESIGN → PLAN → IMPLEMENTATION_READY → IMPLEMENT → SELF_VERIFY → REVIEW → ACCEPT → BASELINE UPDATE → INTEGRATE → optional RELEASE → optional MONITOR`

### Boundary rules

- UNDERSTAND owns product intent; DISCOVER owns repository truth.
- Baseline is cached context, never stronger than repository evidence.
- ROUTE selects required tracks/gates; it does not decide exact code changes.
- Impact Map is the single downstream authority for affected surfaces.
- UI, contract, migration, performance, security and reliability are specialist tracks under DESIGN/VERIFY, not independent lifecycles.
- IMPLEMENT cannot start before `IMPLEMENTATION_READY = YES`.
- SELF_VERIFY proves implementation behavior; ACCEPT proves user/business completion.
- `ACCEPTED`, `INTEGRATED`, `RELEASED` are distinct completion levels.

## Incident fast lane

Incidents remain `DETECT → TRIAGE → MITIGATE → STABILIZE → ROOT CAUSE`. Permanent fixes should create/re-enter a normal Work Item rather than stretching the incident flow into long-term engineering.

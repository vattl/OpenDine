# Implementation Ready Gate

`IMPLEMENTATION_READY` is the single hard gate between planning and production edits.

## Gate result

Only two results are valid:
- `YES`
- `NO` with explicit blockers

## Required inputs

Before `YES`, verify as applicable:
- Requirement Contract is clear enough to implement
- Project Baseline relevant facts have been validated
- Impact Map has no material UNKNOWN surfaces
- applicable Business Invariants are identified
- Implementation Design exists for non-trivial work
- for any UI impact or REFINE/REFACTOR/REDESIGN intent: `PROTOTYPE_REQUIREMENT=REQUIRED`, `PROTOTYPE_MODE=HTML`, an isolated `.html/.htm` artifact, visual reference, critique, presentation, explicit `Approval Status: APPROVED`, applicable coverage matrix, and UI lock are present
- for any UI impact: measured UI spec, complete prototype-to-production map, classified legacy structural diff, zero unmapped/unclassified regions, and `validate_ui_fidelity.py --phase plan` PASS are present
- for any UI impact: every material prototype interaction/data need is in `PROTOTYPE_INTERACTION_CONTRACT.md`; API_EXTENSION/NEW_API rows have assigned Backend Capability Requests; NOT_SUPPORTED rows are resolved by prototype revision; and `validate_ui_capabilities.py --phase plan` passes
- for any UI impact: `ADAPTIVE_UI_CONTRACT.md` defines every REQUIRED terminal/input/context profile, component family/variant and promised business operation; each REQUIRED profile has prototype evidence; and `validate_ui_adaptive.py --phase plan` passes
- required Contract Handoff/Capability Request is defined
- migration/data/NFR/security plans exist when required
- Scenario Matrix exists for STANDARD+
- vertical slices have observable outcomes and DoD
- workstream isolation/ownership is safe
- implementation work has a live-state-bound `WORKTREE_READINESS.md` PASS; setup and baseline tests passed before production edits
- `TDD_CYCLE_REPORT.md` maps each implementation task to a selector or allowed explicit N/A classification
- `TASK_AGENT_LEDGER.md` covers every implementation task and reserves fresh implementer, spec-review and quality-review roles without requiring future results prematurely
- no conflicting dirty work blocks safe implementation
- `DELIVERY_GATE.md` records every specialist track as REQUIRED or NOT_APPLICABLE with rationale
- `python .ai/scripts/gate.py work --work-item <dir> --phase ready` passes

## Enforcement

Production edits are forbidden while the gate is `NO`.

An agent-authored checklist is not a substitute for the executable ready gate.

Do not treat an Implementation Plan, design strategy, layout blueprint, component map, native-framework preview, or prototype-mode decision as proof that the gate passed. Design-direction approval is not HTML prototype approval. Missing HTML evidence or explicit user approval is an independent blocker.

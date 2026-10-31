# Prototype Enforcement Rules (v4.3)

Every UI-impacting request requires an isolated, renderable HTML prototype and explicit user approval before production UI implementation.

## 1. Separate requirement from mode

Two fields must be recorded:

- `PROTOTYPE_REQUIREMENT`: REQUIRED for any UI impact; NOT_APPLICABLE only when `UI_IMPACT=NONE`
- `PROTOTYPE_MODE`: HTML

Native or component-compatible experiments may support implementation planning, but they never satisfy the user-review gate.

## 2. Mandatory prototype triggers

Set `PROTOTYPE_REQUIREMENT=REQUIRED` and `PROTOTYPE_MODE=HTML` when any is true:
- UI impact is MINOR or STRUCTURAL
- UI intent is REFINE, REFACTOR or REDESIGN
- any visible layout, styling, content hierarchy, component composition or interaction changes

This repository policy does not support per-Work-Item prototype or approval waivers. Changing that behavior requires an explicit workflow-policy change.

## 3. What counts as a prototype

A prototype must include both:
1. an isolated renderable `.html` or `.htm` entry, with its CSS/JS/assets as needed, and
2. at least one captured visual output/reference.

The HTML prototype must use realistic content/state density and reflect the target project's fonts, icons, tokens, responsive constraints, component capabilities and data feasibility.

Create `ADAPTIVE_UI_CONTRACT.md` before prototype approval. Render and present the HTML prototype for every REQUIRED experience profile whose navigation, layout, density or interaction pattern materially differs. A desktop screenshot does not approve an unseen phone/tablet/kiosk layout.

Prototype interaction feasibility is part of approval readiness. Catalogue all material data/actions in `PROTOTYPE_INTERACTION_CONTRACT.md`. Prototype mocks demonstrate design intent only; they do not establish an existing backend capability.

The following DO NOT satisfy `PROTOTYPE_CREATED` by themselves:
- UI_DESIGN_STRATEGY.md
- LAYOUT_BLUEPRINT.md
- IMPLEMENTATION_PLAN.md
- textual tables describing a proposed design
- component mapping only

## 4. HTML review artifact + target-stack awareness

HTML is the mandatory review format even when production uses Flutter, React, Vue, Svelte, Mini Program, Taro, UniApp or another stack. Before building HTML, inspect the real target stack and record the production component mapping, unsupported interactions, and expected translation deviations. Approval applies to the design/interaction contract, not to copying prototype code into production.

## 5. Approval states are distinct

Do not conflate design-direction approval with prototype approval.

Required states for any UI impact:
- DESIGN_STRATEGY_READY
- DESIGN_DIRECTION_APPROVED (optional if the user prefers reviewing only the rendered prototype)
- PROTOTYPE_CREATED
- PROTOTYPE_CRITIQUED
- PROTOTYPE_PRESENTED
- PROTOTYPE_APPROVED
- UI_LOCKED

Only explicit user confirmation recorded as `Approval Status: APPROVED` authorizes the visual/interaction design for production translation. `WAIVED_BY_USER`, inferred approval, silence, or design-direction approval do not pass.

## 6. Coverage

For multi-surface refactors, create a Prototype Coverage Matrix. Every surface with `STRUCTURAL_CHANGE=YES` must have prototype coverage or an explicit user-approved exception.

Surfaces include:
- primary pages
- secondary/tertiary pages
- dialogs/drawers/sheets
- important empty/loading/error states
- materially different responsive modes

## 7. Critique before presentation

Before presenting the prototype, perform a design critique covering:
- user goal and task clarity
- information hierarchy and IA
- visual weight and action hierarchy
- grouping / Gestalt
- spacing and typography systems
- density
- state coverage
- component feasibility
- data feasibility
- refactor independence when applicable

Material failures require revision before user presentation.

## 8. Implementation planning order

Before prototype approval, only a feasibility-oriented technical plan is allowed.

After prototype approval, produce the production Implementation Plan and UI Lock mapping exact approved intent to production components.

## 9. Production edit block

For any UI impact, production UI files must not be edited while any required state is missing.

`IMPLEMENTATION_READY=NO` when:
- required `.html/.htm` prototype artifact is missing
- required visual reference is missing
- prototype has not been presented or explicitly approved by the user
- UI lock is missing
- any structurally changed surface lacks required prototype coverage
- any approved prototype interaction is unmapped, has an unassigned backend gap, or is NOT_SUPPORTED without prototype revision
- `validate_ui_capabilities.py --phase plan` has not passed
- any REQUIRED experience profile, component family/variant or promised business operation is unresolved
- `validate_ui_adaptive.py --phase plan` has not passed

## 10. Evidence over claims

A natural-language claim such as “prototype complete” is not evidence. Validators should verify actual HTML paths, approval record with `Approval Status: APPROVED`, screenshots, coverage matrix, and lock artifacts where available.

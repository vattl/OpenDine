# UI Prototype Enforcement — v4.3

> An approved HTML mock proves design intent, not backend availability. Every prototype datum/action must also be mapped in `PROTOTYPE_INTERACTION_CONTRACT.md`; missing backend work is surfaced in `BACKEND_COORDINATION_REPORT.md` and blocks production UI acceptance until verified end-to-end.

v4.3 closes the workflow gap where an agent could treat a strategy, implementation plan or native-framework preview as sufficient approval and proceed without a user-reviewed HTML prototype.

## Core rule

Every UI-impacting change requires an isolated, renderable `.html/.htm` prototype, captured visual evidence and explicit user approval. This applies to REFINE/MINOR as well as REFACTOR/REDESIGN/STRUCTURAL work.

## Two independent decisions

- Prototype requirement is `REQUIRED` whenever UI impact is not `NONE`.
- Prototype mode is `HTML`.

Example for a Flutter production target:

```text
UI Intent: REFACTOR
UI Impact: STRUCTURAL
Prototype Requirement: REQUIRED
Prototype Mode: HTML
Production Target: Flutter
```

The HTML artifact is reviewed for design and interaction intent. A component/feasibility audit still maps it to real Flutter widgets before production implementation.

## Required flow

```text
UI Track Required
→ Design Strategy
→ Prototype Mode = HTML
→ Renderable .html/.htm Prototype
→ Screenshot / Visual Reference
→ Design Critique
→ User Presentation
→ Explicit User Approval (`Approval Status: APPROVED`)
→ UI Lock
→ Production Implementation Plan
→ IMPLEMENTATION_READY=YES
→ Production Implementation
→ UI Verification
```

## Non-prototypes

A Markdown strategy, layout blueprint, implementation plan, component map or native-framework preview is supporting evidence, not the required HTML review prototype.

## Multi-surface refactors

Use `PROTOTYPE_COVERAGE_MATRIX.md`. Secondary pages, tertiary pages, dialogs and other structurally changed surfaces must not disappear behind approval of the primary page.

## Prototype approval is not implementation acceptance

After approval, complete the measured UI specification, implementation map and structural diff. The translation plan gate must pass before editing production UI. After implementation, capture prototype and production at the same reference viewport, generate diff evidence, remove unapproved legacy structure, present the production result to the user, and pass the final fidelity gate before ACCEPT.

# Prototype Rules

> v4.3 authority: also read `PROTOTYPE_ENFORCEMENT_RULES.md`. If there is any conflict, v4.3 enforcement wins.

## Purpose

Define implementation-aware prototype creation, review, approval, lock, and production translation.

## 1. Audit Before Prototype

For any UI-impacting work, inspect target framework/platform, component library, fonts, icons, tokens, responsive conventions, and relevant existing components before building the HTML prototype.

## 2. Prototype Mode

Use `PROTOTYPE_MODE=HTML`. The review artifact must have a renderable `.html/.htm` entry. Target-stack/native experiments may support feasibility work but do not replace the HTML review artifact.

## 3. Prototype Is Disposable Design Code

Prototype code is not production architecture or business truth.

## 4. Location

Use `design/prototypes/UIXXX-name/` or the project's configured design-work location.

Recommended artifacts include:
- prototype implementation
- UI_DESIGN_STRATEGY.md
- COMPONENT_CAPABILITY_AUDIT.md
- PROTOTYPE_TECHNICAL_PLAN.md
- approved.md after approval

## 5. Isolation

Avoid production mutations, credentials, and irreversible side effects. Use deterministic realistic fixture data where appropriate.

## 6. Approval Gate

DRAFT → CRITIQUE → REVIEW → REVISE / APPROVED

Production UI implementation must not begin before a real HTML prototype is created, visually captured, critiqued, presented, explicitly approved by the user, and locked.

## 7. Design Critique

Before user approval, review methodology quality and implementation feasibility. For refactor intent, check that the proposal is not merely a reskin of legacy composition.

## 8. Approval Evidence

Record approved version/reference, reference viewport, accepted deviations, and remaining open details.

## 9. UI Lock

When fidelity matters, `/ui-lock` freezes content/elements/structure/tokens/component mapping/responsive behavior and a golden reference.

## 10. Production Mapping

After approval, create explicit mapping from prototype regions to production components. Reuse only where it preserves the approved intent.

## 11. Verification

Use `/ui-verify` after implementation. Content/required elements/structure should normally be exact; geometry/style should meet the project's fidelity tolerances.

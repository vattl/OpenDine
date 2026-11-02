# v4.0 Unified Routing

`/ui` is the UI-led entry into a normal Work Item. The existing UI methodology remains authoritative for the UI Design Track, but the work must still participate in UNDERSTAND → DISCOVER → DESIGN → PLAN → IMPLEMENT → SELF_VERIFY → REVIEW → ACCEPT. UI changes must not ignore backend/API/data implications, and backend changes must not ignore required UI semantics.


---

# /ui

Design or refactor UI using project-aware design reasoning before producing a prototype.

## 0. Determine UI Intent

Classify:
- REFINE
- REFACTOR
- REDESIGN

If the user explicitly requests a refactor/redesign, do not downgrade to a minor refinement merely to maximize component reuse.

## 1. Project Context Audit

Inspect relevant repository reality:
- language/framework/platform
- UI/component library
- styling/theme/token system
- production font stack
- icon system
- layout/responsive conventions
- existing shared components
- target routes/screens and business capability

Create/update `UI_DESIGN_STRATEGY.md` or equivalent for STANDARD+ structural UI work.

## 2. Product + User Goal

Identify:
- product type
- primary user goal
- primary information
- primary action
- secondary/support information

## 3. Legacy UI Decomposition

For REFACTOR/REDESIGN, inspect existing UI to extract capabilities, not to preserve appearance.

Classify old regions/components:
PRESERVE / MODIFY / MOVE / REPLACE / REMOVE

## 4. Design Methodology Pass

Before visual styling, establish:
- information hierarchy
- information architecture
- action hierarchy
- density mode
- visual hierarchy
- spacing system
- typography hierarchy
- progressive disclosure
- state coverage
- responsive behavior

Follow `.ai/rules/UI_DESIGN_METHODOLOGY.md`.

Before arranging components, define product-relevant experience profiles in `ADAPTIVE_UI_CONTRACT.md`: terminal/platform, representative viewport, orientation, input modality, usage context, support level, density/navigation model and promised business operations. Do not treat generic breakpoints as device strategy.

## 5. Component Capability Audit

Map intended elements to the real project:
REUSE / RESTYLE / EXTEND / CREATE / REPLACE

Identify fidelity risks caused by current component APIs or platform limitations.

Define component families and semantic variants for every REQUIRED profile. Equivalent controls in the same hierarchy must share visual size, hit target, icon, typography and spacing tokens. Pointer-compact and touch-comfortable variants may differ intentionally; arbitrary per-screen sizes may not.

## 6. HTML Prototype Requirement

For every UI-impacting request set:

- `PROTOTYPE_REQUIREMENT=REQUIRED`
- `PROTOTYPE_MODE=HTML`

This includes REFINE/MINOR changes. Keep small changes proportional, but do not skip HTML review or explicit approval. Native/component-compatible previews may support feasibility work but do not satisfy the gate.

## 7. Prototype-to-Production Technical Plan

Before or alongside the prototype, document:
- target stack
- component mapping
- component changes/new components
- styling/token strategy
- font/icon strategy
- responsive implementation
- interaction/API dependencies
- technical risks and mitigation

The HTML prototype must not invent controls that production contracts cannot support without recording required cross-layer changes.

Create `PROTOTYPE_INTERACTION_CONTRACT.md` and enumerate every material datum/action. Classify each as AVAILABLE / DERIVABLE / API_EXTENSION / NEW_API / NOT_SUPPORTED. API_EXTENSION/NEW_API requires an assigned Backend Capability Request; NOT_SUPPORTED requires revising and re-approving the prototype before production work.

## 8. Prototype

Create an actual isolated, renderable `.html/.htm` prototype using realistic content and state density. A Markdown strategy/plan or native-framework preview is not the required review prototype. Capture at least one visual reference/screenshot.

For multi-surface structural work, maintain a Prototype Coverage Matrix for primary pages, secondary/tertiary pages, dialogs and materially changed states.

Render the HTML prototype for every REQUIRED experience profile with a materially different layout or interaction pattern. Include representative orientation/input assumptions and keep every promised business operation visible and completable.

For REFACTOR/REDESIGN, do not merely copy the old DOM/component structure and reskin it.

## 9. Design Critique

Before asking for approval, independently critique:
- task clarity
- hierarchy
- grouping
- density
- spacing
- typography
- action competition
- container overuse
- state coverage
- implementation feasibility
- refactor independence where relevant

Revise material failures first.

## 10. Approval

User review is mandatory for every UI change. Distinguish `DESIGN_DIRECTION_APPROVED` from `PROTOTYPE_APPROVED`; only explicit user confirmation recorded as `Approval Status: APPROVED` authorizes production translation. Silence, inferred approval and `WAIVED_BY_USER` do not pass.

After prototype approval, use `/ui-lock` before production implementation. All production UI edits remain blocked until the lock exists.

## 11. Production

Use `/ui-implement` to translate the approved design into the target framework without silently redesigning it.

Do not implement missing backend behavior with static data, local-only state, empty handlers, hardcoded success, mock responses or disabled controls presented as complete functionality.

## 12. Verification

Use `/ui-verify` after implementation. Verify content, elements, structure, geometry, style, responsive behavior, interaction, and accepted technical deviations.

Produce `DEVICE_UX_VERIFICATION_REPORT.md` and verify every REQUIRED profile and operation/profile pair against the real production stack. Component consistency violations, unintended clipping/overflow or business-operation failures block acceptance.

Verification must produce a backend coordination report. Any OPEN backend item is shown to the user and keeps the UI BLOCKED/PARTIAL.

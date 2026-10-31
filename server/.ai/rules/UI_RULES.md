# UI Rules

## Purpose

Prevent visually incoherent, implementation-detached, legacy-preserving-by-accident UI changes while preserving engineering and design judgment.

## Core Principles

1. Design from product/user goals before decoration.
2. For refactors, preserve capability — not legacy appearance.
3. Prototype design must be implementation-aware.
4. Production implementation must be faithful to the approved target.
5. Existing components are tools, not constraints that override the user-approved design.

## Intent

Classify meaningful UI work as REFINE / REFACTOR / REDESIGN.

Explicit refactor requests must not be silently treated as small visual refinement.

## Design Reasoning Gate

For STANDARD+ UI work, apply `.ai/rules/UI_DESIGN_METHODOLOGY.md` before producing the HTML prototype.

Establish product context, user goal, hierarchy, IA, density, visual weight, spacing, typography, actions, states, responsive strategy, and implementation feasibility.

## Project Context Before Prototype

Audit framework/platform, component library, design tokens, fonts, icons, responsive system, existing components, and interaction/API constraints.

Produce the mandatory HTML review prototype after auditing the target stack. Record how approved HTML regions/interactions map to real production components.

## Refactor Behavior

For REFACTOR/REDESIGN, decompose old UI into capability and visual implementation. Classify legacy regions/components as PRESERVE/MODIFY/MOVE/REPLACE/REMOVE.

Do not retain legacy composition simply to maximize code reuse.

## Prototype Gate

Every UI change uses an isolated implementation-aware `.html/.htm` prototype, screenshot, user presentation and explicit approval before production implementation. Small UI changes may use a proportionally small single-state HTML artifact, but they do not bypass the gate.

## Hierarchy Before Decoration

Determine primary task/content/action and secondary/support content before choosing decoration.

## Whole-Page Coherence

Avoid:
- every section as equally prominent card
- excessive nested containers
- inconsistent spacing/density
- multiple competing primary actions
- duplicate headers/toolbars
- decorative elements with no information purpose

## Component Strategy

Classify relevant existing components as REUSE_AS_IS / RESTYLE / EXTEND / REPLACE / REMOVE.

Do not let unsuitable existing components pull a refactor back toward the old design.

## Realistic Density & States

Prototype with realistic data and relevant loading/empty/error/permission states.

For every visible server datum and material interaction, record the real production capability in `PROTOTYPE_INTERACTION_CONTRACT.md`. Do not infer backend support from a working HTML mock.

## Responsive Behavior

Responsive design is part of correctness where supported. Preserve hierarchy and task usability across target viewports.

## Approval & Lock

After explicit user approval, lock material content/elements/structure/style/component mapping/responsive intent.

## Production Translation

Production implementation is translation, not redesign. Material technical deviations must be recorded, not hidden.

## Visual Verification

Build success does not prove visual correctness. Compare rendered production to the approved/locked target using structural, geometry, style, and screenshot evidence when available.

## Replacement Completeness

Retire obsolete layout/components/styles after verified replacement unless coexistence is intentionally required.

# UI Refactor Rules

## Intent Modes

Meaningful UI work must classify intent as one of:

- REFINE: preserve the existing visual system and improve it
- REFACTOR: preserve product capability but allow structural and visual replacement
- REDESIGN: rethink information architecture and interaction model within product/technical constraints

When the user explicitly asks for "refactor", "restructure", "重新设计", "重构", or equivalent, do not silently downgrade to REFINE.

## Core Rule

When the user requests UI refactoring, preserve product capability — not legacy appearance.

Existing UI is reference material for understanding functionality, data, states, and constraints. It is not a visual constraint unless the user says to preserve it.

## REFACTOR may change

- layout
- information grouping
- component composition
- hierarchy
- density
- typography
- spacing
- card/table presentation
- navigation presentation
- visual tokens within project strategy

## REFACTOR must preserve or intentionally migrate

- business capability
- required data
- routes
- permissions
- contract semantics
- required interactions
- accessibility requirements
- target-framework feasibility

## Legacy Decomposition

Before structural refactor, classify old UI regions/components as:
- PRESERVE
- MODIFY
- MOVE
- REPLACE
- REMOVE

Do not retain legacy UI merely because reusable components already exist.

## Reuse Decision

Existing components must be classified:
- REUSE_AS_IS
- RESTYLE
- EXTEND
- REPLACE
- REMOVE

Reuse is a means, not a goal. A legacy component that forces the new design back into the old visual structure should not be reused unchanged.

## Refactor Independence Check

A refactor is insufficient if the result mostly preserves the old information architecture and component composition while only changing color, radius, shadows, or spacing.

If the requested change is REFACTOR/REDESIGN, review whether:
- major regions changed where justified
- information hierarchy was reconsidered
- component composition was reconsidered
- obsolete containers/styles were removed

If not, report `REFACTOR_INSUFFICIENT` rather than claiming a redesign.

## Replacement Completeness

When new UI replaces old UI, remove obsolete active markup/components/styles after verification unless compatibility requires temporary coexistence.

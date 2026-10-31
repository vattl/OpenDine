# Design System Rules

## Purpose

Keep AI-generated UI visually coherent without forcing a rigid universal style.

## 1. Prefer Existing Tokens

Before introducing new values, inspect existing:
- spacing tokens
- typography
- colors
- radii
- shadows
- component heights
- breakpoints

Reuse them when coherent.

## 2. Small Token Vocabulary

If a local token set is needed, keep it intentionally small.

Example spacing scale:
8 / 12 / 16 / 24 / 32

Example radius scale:
8 / 12

These are examples, not mandatory universal values.

## 3. Avoid Arbitrary Per-Component Styling

Do not give every card/button/section independent spacing, radius, shadow, or typography values without reason.

## 4. Typography Hierarchy

Define clear roles such as:
- page title
- section title
- body
- metadata
- label

Do not use many near-duplicate font sizes/weights.

## 5. Control Consistency

Equivalent controls should share:
- height
- radius
- padding
- typography
- icon sizing

unless functional hierarchy requires otherwise.

Consistency is evaluated within a component family, semantic hierarchy and experience profile. Define explicit variants for pointer-compact, touch-comfortable, prominent action, destructive action and icon-only control when the product needs them. Do not create a new height/padding/icon combination for each screen.

Record visual size and interaction hit target separately. Different platform units and input modalities must not be collapsed into one universal pixel minimum.

## 6. Container Discipline

Do not wrap every grouping in another card/container.

Use borders/backgrounds/shadows only when they clarify grouping or hierarchy.

## 7. Color Discipline

Use color to communicate hierarchy/state, not decoration alone.

Status colors should remain semantically consistent.

## 8. Density Is Contextual

Admin/operations tools often benefit from medium or compact density.
Consumer/marketing pages may justify more whitespace.

Choose density from user task, not aesthetic fashion.

## 9. Accessibility

Preserve readable contrast, focus states, keyboard interaction where relevant, and usable target sizes.

Do not trade usability for visual novelty.

## 10. Approved Prototype Proportions Take Precedence Over Incidental Legacy Density

Existing tokens are preferred, but only when they can reproduce the approved target with reasonable fidelity.

Do not automatically force an approved prototype into existing compact values such as smaller row heights, card padding, or controls if this materially changes the design.

When a visual mismatch exists, explicitly decide whether to:

- reuse an existing suitable token
- use an existing component variant
- add a small scoped token/variant
- adapt the prototype because of a genuine product constraint

Never silently accept large scale drift.

## 11. Measure Relationships, Not Only Individual Values

A design system must preserve relationships such as:

- title size relative to body
- card height relative to content
- toolbar height relative to input/button controls
- row height relative to typography/avatar
- page padding relative to viewport

## 12. Adaptive Component Contract

For UI-impacting work, material component families and variants belong in `ADAPTIVE_UI_CONTRACT.md`. Before acceptance, `DEVICE_UX_VERIFICATION_REPORT.md` must show zero component consistency violations across REQUIRED profiles.

Matching isolated colors while these relationships drift is not visual fidelity.

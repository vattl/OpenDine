# /ui-lock

Freeze an approved HTML UI prototype into an implementation contract before production coding.

## Preconditions
- approved renderable `.html/.htm` prototype exists for the UI change (design-direction approval alone is insufficient)
- prototype visual reference/screenshot exists
- explicit user approval evidence records `Approval Status: APPROVED`
- structurally changed surfaces are covered or explicitly excepted
- target project stack is known
- material open design decisions are resolved or explicitly recorded

## Lock
Create or update the relevant UI lock artifacts:
- content contract
- element contract
- structure/layout contract
- design tokens/style contract
- production component map
- responsive rules
- deterministic fixture/reference data when appropriate
- golden screenshot/reference viewport
- accepted deviations

## Required principle
A lock freezes design intent, not prototype implementation code.

Prototype code remains disposable; the UI contract is the production translation target.

## Output state
`UI_LOCKED`

If unresolved HIGH fidelity incompatibility exists, return `UI_LOCK_BLOCKED` and describe the production constraint instead of silently degrading the design.

# Design System Profile — DS-1

## Product UI Context

- Product type: backend/server repository.
- Primary interaction environment: REST/JSON and WebSocket contracts.
- Design goals: not applicable to backend-only changes.
- Density: not applicable.

## Visual Direction

No production UI design system is owned by this repository. Static resources are support/demo assets and are not an accepted cross-product visual baseline.

## Typography

Not applicable.

## Tokens

Not applicable.

## Components

Not applicable.

## Interaction & States

Consumer-facing state semantics belong in API contracts and explicit frontend handoffs. Any future UI-impacting change must inspect the actual consumer repository and use the mandatory HTML prototype track.

## Responsive Behavior

Not applicable.

## Accessibility

Not applicable to backend-only scope; consumer UI remains responsible for accessible presentation.

## Approved Variations / Exceptions

None.

## Evidence / Last Verified

- Verified 2026-10-15 from repository ownership, source layout and the absence of an owned production frontend stack in `pom.xml`.

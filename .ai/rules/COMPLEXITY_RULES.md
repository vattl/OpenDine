# Architecture and Complexity Rules

## Principle

A feature that works but materially worsens maintainability may require redesign before completion.

## Compare before vs after

When a change materially expands a module, inspect:
- responsibilities,
- dependency count,
- coupling,
- duplicate logic,
- public API surface,
- state ownership,
- file/function complexity trends.

Do not use arbitrary line-count limits as the sole criterion.

## Complexity triggers

Escalate to architecture review when one or more are true:
- a module gains unrelated responsibilities,
- a new dependency cycle appears,
- logic is duplicated across modules,
- the change introduces many new cross-module dependencies,
- existing abstractions are bypassed repeatedly,
- complexity rises substantially compared with delivered value.

## Preferred responses

1. Reuse existing capability.
2. Extend a coherent abstraction.
3. Extract a responsibility only when there is a real boundary.
4. Avoid speculative microservices or layers.

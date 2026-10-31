# Evidence Integrity Rules

## Core rule

Completion is a claim that requires evidence. The agent's own statement is not evidence.

## Forbidden production substitutions

Unless explicitly requested for demo/prototype/test scope, do not use:

- fabricated records
- hardcoded success responses
- fake counts/revenue/statuses
- placeholder API results
- mock JSON in production runtime paths
- catch-and-return-success patterns that hide failure
- stubs that bypass persistence/business logic

If the requested behavior cannot be completed, report BLOCKED or PARTIAL.

## Allowed scopes

Mocks are allowed only when clearly scoped as:

- TEST_MOCK
- PROTOTYPE_MOCK
- DEMO_FIXTURE

Production paths must use real production behavior.

For UI prototypes, an interaction that only changes local display state is a fake production capability when the approved business outcome requires persistence, authorization, server computation, shared state or an external side effect. Record the missing capability; do not simulate completion.

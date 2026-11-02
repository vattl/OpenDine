# Self Verification Rules

SELF_VERIFY selects checks from the Impact Map.

Possible checks include compile/typecheck/lint, unit, integration, contract, consumer, E2E data flow, UI behavior, visual comparison, content stress, accessibility, database migration, performance, reliability and security.

Do not run irrelevant ceremony. Do not skip material risk.

For changed shared interfaces, verify both producer and consumer semantics.

For end-to-end business paths, verify data propagation from user/input through request/domain and back to rendered/observable result when practical.

For UI work, SELF_VERIFY must include same-viewport prototype/production captures, structural-diff closure, legacy-removal evidence, and the strict fidelity gate. Source inspection and functional tests alone are insufficient.

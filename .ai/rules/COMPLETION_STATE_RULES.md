# Completion State Rules

Separate engineering completion from repository integration and production delivery.

## States

- `IMPLEMENTED`: code exists, not necessarily verified
- `SELF_VERIFIED`: selected technical checks passed
- `REVIEWED`: independent engineering review completed
- `ACCEPTED`: original requirement is proven with evidence
- `INTEGRATED`: accepted changes are safely merged/integrated
- `RELEASE_READY`: release prerequisites are satisfied
- `DEPLOYED`: the integrated artifact was delivered to the intended environment, but production verification may still be pending
- `PRODUCTION_VERIFIED`: required smoke/critical journeys and health signals passed in the target environment
- `RELEASED`: deployment and required production verification are complete
- `MONITORED`: the required observation window completed without unresolved release blockers
- `CLOSED`: delivery evidence, follow-ups and durable learning/baseline updates are complete

## Rules

1. `DONE` must not hide these distinctions.
2. Normal engineering work finishes at `INTEGRATED` when deployment is outside scope. `ACCEPTED` without a local task commit is `READY_TO_COMMIT`, not completed.
3. When deployment is in scope, follow `RELEASE_READY → DEPLOYED → PRODUCTION_VERIFIED → RELEASED → MONITORED → CLOSED` without collapsing states.
4. Release-sensitive work must not claim delivery success before `RELEASED`.
5. Monitoring is required only when project policy or change risk requires it.
6. `INTEGRATED` requires a successful task-scoped local commit and `gate.py work --phase integrate` from a clean worktree.

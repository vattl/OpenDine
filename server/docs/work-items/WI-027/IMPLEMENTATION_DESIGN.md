# Implementation Design — WI-027

## Root Fix / Owner

Integrate the two accepted commits rather than adding a duplicate emergency endpoint. The missing route is one surface of the entire receivables capability and depends on schema, permissions, service rules and API documentation.

## Why this location

The integration branch is the source used for release builds. A controller-only patch would compile against missing entities/tables or bypass accepted commercial rules.

## End-to-End Change

- Cherry-pick `49e5e847` then `ea447567` in dependency order.
- Resolve conflicts semantically, preserving current integration features and accepted payment/receivable behavior.
- Rename merchant commercialization, receivables and JSAPI attempts migrations to `V027/V028/V029`.
- Update only references belonging to those migrations; keep existing V024/V025/V026 meanings unchanged.
- Verify route registration through controller/security tests and static contract checks.

## Preserve / Compatibility

Existing API paths remain additive. Database migrations are content-identical except for safe version renumbering before deployment.

## Failure / Boundary Behavior

No eligible account returns 200 with an empty list. Missing permission returns authorization failure, not 404. Missing schema must fail migration/startup rather than silently degrade.

## Runtime / Performance / Reliability

No new design beyond previously accepted work. Integration validation includes unique migration versions and full Maven regression.

## Security / Permissions

Target route remains `receivable:view`; all reads derive shop scope from authenticated cashier context/header validation.

## UI Design Track

NOT_APPLICABLE.

## Vertical Slice Plan

1. Integrate WI-020~023 and resolve migration/API conflicts.
2. Integrate WI-024~026 and resolve settlement/report conflicts.
3. Verify route, migration uniqueness, tests, docs and JAR.

## Verification Strategy

Static route/permission/OpenAPI assertions, migration-version uniqueness script, focused receivable/security tests, full Maven tests, OpenAPI YAML parse and mandatory clean package.

## Rollback / Recovery

Cherry-picks remain individually identifiable; abort on unresolved conflicts. No production database is modified by this local integration.

# Acceptance Report — WI-030

Decision: ACCEPTED

## Decision

- Work Item acceptance: **ACCEPTED**
- Whole dirty-worktree integration: **NOT CONFIRMED**
- Production release: **NOT RELEASED**

## Acceptance evidence

- All ten Scenario Matrix cases pass.
- Scoped payment regression: 68/68 pass.
- OpenAPI parses, migration assertions pass and `git diff --check` reports no whitespace error.
- Security review finds no unresolved HIGH/CRITICAL issue.
- Runnable Spring Boot JAR packaging passes.

## Integration exception

The full suite has three failures in the pre-existing KDS workflow area, outside the WI-030 Impact Map and with no KDS files changed by this work item. This prevents marking the combined dirty worktree INTEGRATED. WI-030 itself is accepted on scoped evidence; KDS repair requires a separate Work Item.

## Release condition

Before production deployment:

1. Query and remediate duplicate `t_order.order_no` rows.
2. Back up the database and deploy the generated JAR.
3. Confirm Flyway V033 succeeds.
4. Smoke-test one JSAPI, one Native/MICROPAY transaction as applicable, one refund and one cross-shop rejection per configured merchant.
5. Resolve or formally disposition the unrelated KDS full-suite failures before declaring the repository INTEGRATED/RELEASED.

## Completion level

ACCEPTED

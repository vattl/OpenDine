# Completion Evidence — WI-030

Status: ACCEPTED

## Delivered

- New-payment routing is server-authoritative and ignores client merchant fallback.
- Runtime merchant status/version is read from the DB for new transactions.
- Bound credentials validate shop ownership across JSAPI, Native, MICROPAY, callback and refund paths.
- Payment callbacks require matching `mchid/appid`.
- Refund requests persist exact merchant/transaction bindings; callbacks cannot create unknown refund facts.
- V033 adds refund binding columns, callback indexes and global order-number uniqueness.
- OpenAPI/API/schema/architecture documentation is synchronized.

## Evidence

- Scenario Matrix: 10/10 PASS.
- Scoped payment tests: 68/68 PASS.
- OpenAPI parse and migration assertions: PASS.
- Security and local code review: PASS, no unresolved HIGH/CRITICAL issue.
- Runnable JAR: `target/diancan-0.0.1-SNAPSHOT.jar`, build PASS.

## Lifecycle status

- ACCEPTED: YES.
- INTEGRATED: NO — full dirty-worktree suite retains three unrelated KDS failures documented in `TEST_REPORT.md`.
- RELEASED: NO — no production deployment was requested or performed.

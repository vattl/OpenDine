# WI-064 Tasks

## Task 1 — Shared revision guard
- [x] RED tests cover aliases, invalid input, stale conflict and CAS failure.
- [x] Implement `OrderRevisionService`.
- [x] Verify focused unit tests.

## Task 2 — Add-dishes slice
- [x] Direct and cashier inputs propagate expectedVersion.
- [x] Success increments/returns revision; stale request has zero side effects.
- [x] KDS POS add increments t_order revision once.

## Task 3 — Refund/price/discount slice
- [x] Lock order and reject stale version before approval.
- [x] Successful mutation increments/returns revision.
- [x] Existing amount/table/payment behavior remains green.

## Task 4 — Delivery evidence
- [x] Sync OpenAPI/API.md and frontend handoff.
- [x] Focused and expanded regressions pass.
- [x] Review/security/accept gates pass.
- [x] Full `mvnw.cmd clean package -DskipTests` succeeds.

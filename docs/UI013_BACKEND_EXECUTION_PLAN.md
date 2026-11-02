# UI013 Backend Execution Plan

Date: 2026-10-04
Status: COMPLETE
Complexity: CRITICAL
Runtime risk: HIGH

## Current

- The dirty working tree contains an uncommitted commercial drawer/daily-close implementation that overlaps UI013.
- `GET /cashier/shift/current?previewExpected=true` can expose blind-count values before handover.
- Daily pre-check always emits a token, but settle does not validate its expiry, shop, business day, operator, or watermarks.
- Shift report and Z report do not yet expose the fixed UI013 structured contracts.
- Workbench and paginated history endpoints are absent.

## Target

- Blind-count values are unavailable from all query endpoints until a shift is closed.
- Pre-check distinguishes blocked/passed responses, signs a five-minute token only on success, and settle revalidates identity, shop, day, and ledger/cash/order watermarks.
- Existing responses remain backward compatible while adding integer-fen structured fields.
- Shift workbench/report, daily preview/channel data, Z watermarks/session schema, and P2 cursor history endpoints match the UI013 coordination contract.
- Retryable financial writes accept idempotency keys and return trace/business/time metadata.
- OpenAPI/API docs, contract tests, migration docs, and runnable JAR stay synchronized.

## Diff

- MODIFY daily close service/controller contract and snapshot persistence.
- MODIFY drawer session service/controller response safety and report projection.
- ADD workbench, shift report history, cash-event history, and Z-report history endpoints.
- ADD additive migration for settle idempotency metadata.
- MODIFY permission mapping, OpenAPI, API guide, database docs, and tests.

## Verification

1. Targeted controller/service/security/schema regression: 30 tests passed.
2. Full Maven test suite: 1090 tests, 0 failures, 5 skipped.
3. OpenAPI YAML parsed successfully with no duplicate mapping keys.
4. `mvnw clean package -DskipTests`: passed; runnable JAR SHA-256 `8C8483FCD39BD6FCC3269101260A44E5E9FD82D5465A27E689B2E4F09205A692`.
5. `.ai/scripts/validate.py --release`: 0 errors, 2 warnings (pre-existing uncommitted tree and PROJECT_STATE metadata).

## Safety notes

- Existing uncommitted overlapping work is preserved and is not attributed to this task.
- No production migration or deployment is performed.

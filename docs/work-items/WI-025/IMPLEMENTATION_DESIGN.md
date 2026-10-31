# Implementation Design — WI-025

## Root Fix / Owner

Keep `PaymentLedgerService` as the single immutable money lifecycle owner. Entry-point services prepare a locked order and exact channel facts, call the ledger first, then update wallet/order projections in the same transaction. Fulfillment runs after commit.

## Ledger lifecycle

- PAYMENT idempotency compares only currently active (not fully reversed) payment entries. A fully reversed historical generation does not block a new request.
- REVERSAL is linked by `original_ledger_id` and is limited to the original payment's remaining unreversed amount.
- REFUND must link to a compatible original PAYMENT where available and exact-replay validation rejects idempotency conflicts.
- Every inserted row checks persistence success and explicitly records native/high-trust provenance.

## Refund routing

- Cashier cash refunds move from controller-owned mutation into `CashierCheckoutService`.
- Wallet principal and gift refunds create separate linked channel entries using one request id.
- WeChat refund success records its immutable REFUND before modifying `refund_amount` and channel projections.

## Consistency gate

Add a read-only consistency component that compares, per successful non-receivable order, the current order channel projection with the net successful ledger by channel. Daily close adds a blocking item with bounded mismatch details. Zero-money and receivable orders are explicitly excluded from the payment-ledger requirement.

## Reconciliation

Use `pay_time` within the shop settlement window for order scope, exclude receivable orders, and compare order current channel totals to ledger net amount. Summary status includes unmatched internal entries. Channel matching requires compatible entry type and does not overwrite duplicate order-number entries.

## Failure behavior

Any ledger persistence or exact-idempotency failure throws and rolls back the containing transaction. No catch-and-continue is permitted on authoritative money writes. Historical repair remains an explicit migration operation only.

## Vertical slices

1. RED/GREEN ledger reversal, recheckout and refund idempotency.
2. RED/GREEN balance/admin/refund entry points and removal of write-on-read behavior.
3. RED/GREEN daily-close consistency gate and reconciliation scope/status.
4. Documentation, full regression, review and runnable JAR.

## Verification Strategy

- TDD RED/GREEN tests for active-payment lifecycle, exact refund idempotency and every repaired entry point.
- Focused service/controller tests after each vertical slice.
- Full Maven regression, OpenAPI parse, diff/secret review and `clean package -DskipTests` after the final code state.

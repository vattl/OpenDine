# Impact Map — WI-025

## Authoritative Owner

- Payment lifecycle: `PaymentLedgerServiceImpl`.
- Cashier settlement/refund/reversal: `CashierCheckoutService`.
- C-end balance settlement: `PaymentFacadeService`.
- WeChat refund convergence: `WechatRefundSettlementService`.
- Admin checkout adapter: `AdminOrderController` -> `CashierCheckoutService`.
- Read/report gates: `CashierShiftController`, `DailyCloseServiceImpl`, `ReconciliationServiceImpl`.

## Affected surfaces

| Surface | Impact | Planned action |
|---|---|---|
| Balance payment | AFFECTED | Row lock, ledger-first, checked order update, after-commit fulfillment |
| Admin checkout | AFFECTED | Delegate successful settlement to authoritative cashier service |
| Cash refund | AFFECTED | Move to transactional service and write linked REFUND first |
| Wallet refund | AFFECTED | Write principal/gift REFUND entries before wallet/order projection |
| WeChat refund | AFFECTED | Remove best-effort catch; write linked REFUND before order projection |
| Reversal/recheckout | AFFECTED | Compute remaining unreversed PAYMENT and allow new generation |
| Fulfillment | AFFECTED | Remove ledger self-heal from post-payment handler |
| Shift/daily reads | AFFECTED | Remove write-on-read self-heal |
| Daily close | AFFECTED | Add order-ledger consistency blocker |
| Reconciliation | AFFECTED | Payment-day scope, receivable exclusion, unmatched-internal status |
| Persistence | VERIFIED_UNAFFECTED | Existing immutable ledger schema supports linked refund/reversal lifecycle |
| External API | COMPATIBLE_SEMANTIC_TIGHTENING | Existing routes/shapes retained; additional blocker/error conditions documented |

## Layer Coverage

| Layer | Classification | Evidence |
|---|---|---|
| UI | NOT_APPLICABLE | Server repository only; no visual change |
| API/controller | AFFECTED | Existing checkout/refund/precheck semantics become strict |
| Domain/service | AFFECTED | Ledger lifecycle and consistency checker |
| Persistence | VERIFIED_UNAFFECTED | No schema delta required |
| External WeChat | VERIFIED_UNAFFECTED | Signing/callback transport unchanged |
| Jobs/events | AFFECTED | Refund compensation uses strict settlement path |
| Reporting | AFFECTED | Read-only daily/shift and corrected reconciliation scope |
| Security/multi-shop | VERIFIED_PRESERVED | Every lookup remains shop scoped or derives shop from locked order |
| Tests/docs/build | AFFECTED | New scenario tests, API docs sync, full package |

Material UNKNOWN count: 0

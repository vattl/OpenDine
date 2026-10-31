# Impact Map — WI-024

## Authoritative Owners

- JSAPI request orchestration: `PaymentFacadeService`, new JSAPI attempt service.
- WeChat transport/signing: `WechatJsapiChannel`, `WechatNativeApiClient` query/close primitives, `WechatMerchantKeyStore`.
- Payment success: `WechatPaymentNotifyHandler`, `WechatPaymentSuccessService`.
- Amount mutations: `OrderDetailRefundService`, `OrderAmountRecalculationService`, cashier/admin order controllers, add-dish flow.

## Affected Surfaces

| Surface | Impact | Planned action |
|---|---|---|
| Database | New durable JSAPI attempt state | Add V026 migration, entity, mapper, unique active key |
| Mini-program prepay API | Same route/fields, safer conflict semantics | Delegate to attempt service; additive attempt metadata |
| Payment callback | Exact attempt matching | Resolve JSAPI attempt before applying success |
| Payment ledger/reporting | Ledger must precede order settlement | Record exact authoritative PAYMENT before order success; reject conflicting settlement |
| Refund dish / quantity | Old prepay may remain payable | Add common mutation guard before mutation |
| Cashier price / discount | Old prepay may remain payable | Add common mutation guard and order row lock |
| Add dishes | Amount grows after prepay | Add common mutation guard before detail persistence |
| Admin amount edits | Same risk as cashier | Route through guarded domain service where affected |
| Merchant credentials | Historical version must remain stable | Store config id/key/version on attempt |
| Native/micropay | Regression only | Preserve existing behavior and run tests |
| Reconciliation/logging | Payment conflicts must be visible | Structured attempt statuses and safe logs |
| External consumers | New conflict codes/refresh behavior | Explicit handoff; no UI files owned here |

## Data / Migration

- Additive `t_wechat_jsapi_payment_attempt` table.
- Unique `out_trade_no`; nullable unique `active_key`.
- No destructive changes and no backfill of expired legacy prepay sessions.

## Security / Reliability

- Treat微信 responses and callbacks as untrusted until signature and field validation pass.
- No prepay ID, private key or APIv3 key in logs.
- Timeouts remain UNKNOWN and occupy the active key until authoritative query convergence.
- Order lock is acquired before attempt mutation to serialize payment and price changes.
- Authoritative payment ledger and order settlement share one transaction; ledger failure cannot leave a successfully settled order.

## Consumers

- Mini program: existing success shape preserved; on conflict must refresh order and request a new prepay session.
- Cashier/admin: amount mutation may receive safe conflict when payment state is unknown or already successful.

## Layer Coverage

| Layer | Classification | Reason / Evidence |
|---|---|---|
| UI | NOT_APPLICABLE | UI repository is outside this checkout; consumer handoff is required |
| Interaction | AFFECTED | Stale pay parameters become unusable and amount mutation can return payment-state conflict |
| Frontend State | AFFECTED | Consumer must discard stale payParams and refresh the order on conflict |
| API Client | AFFECTED | Existing `/order/getPrepayId` response gains optional attempt metadata |
| Request Contract | VERIFIED_UNAFFECTED | Existing request fields and route remain unchanged |
| Backend/Domain | AFFECTED | JSAPI attempt lifecycle and common amount-mutation guard become authoritative |
| Persistence | AFFECTED | Additive V026 JSAPI attempt table |
| Response Contract | AFFECTED | Additive metadata and stricter conflict semantics |
| Jobs/Events/Integrations | AFFECTED | WeChat create/query/close/callback convergence |
| Config/Security | AFFECTED | Historical merchant binding and payer identity are persisted and verified |
| Runtime/NFR | AFFECTED | Order row lock, active-key uniqueness, fail-closed unknown state |
| Tests | AFFECTED | Scenario, service, callback, mutation and regression coverage |

Material UNKNOWN count: 0

# Impact Map — WI-015

## Authoritative Owner

- WeChat transaction transport: `com.lanf.payment.channel.wechat`.
- Local payment confirmation and fulfillment: new shared service under `com.lanf.payment`, reusing `PaymentSuccessHandler` and immutable payment ledger helpers.
- Order amount: `PaymentSettlementService`/`OrderNetRevenue`, never the cashier request.

## Change Propagation Path

```text
Cashier JWT + orderNo
-> Native cashier controller
-> shop/order/capability validation
-> persistent Native payment attempt
-> signed WeChat POST /v3/pay/transactions/native
-> codeUrl response to cashier
-> signed callback OR signed authoritative query
-> shared idempotent payment-success application
-> t_order + t_payment_ledger
-> coupon/table/printing/KDS/delivery side effects
-> cashier status response
```

## Consumer Coverage

| Consumer | Relationship | Classification | Needs Change | Evidence |
|---|---|---|---|---|
| Cashier Flutter/admin client | New Native create/status/close API consumer | AFFECTED | YES, explicit handoff | `API_CONSUMER_HANDOFF.md` |
| Mini program JSAPI flow | Existing shared callback consumer | AFFECTED | No request contract change; regression required | `WechatJsapiChannel`, `WechatPaymentNotifyHandler` |
| Admin refund flow | Existing paid-order refund consumer | VERIFIED_UNAFFECTED | No new endpoint | `WechatJsapiChannel.domesticRefund`, refund scheduler |
| Payment ledger and reconciliation | Downstream confirmed-payment consumer | AFFECTED | Native confirmation must continue to produce WECHAT ledger | `PaymentSuccessHandler`, `ReconciliationServiceImpl` |
| KDS/printing/table/delivery | Post-payment downstream effects | AFFECTED | Reuse existing `PaymentSuccessHandler` | `PaymentSuccessHandler` |

## Layer Coverage

| Layer | Classification | Reason / Evidence |
|---|---|---|
| UI | NOT_APPLICABLE | No production UI edit in this server repository; handoff only. |
| Interaction | AFFECTED | Cashier must display QR and poll/query terminal states. |
| Frontend State | AFFECTED | Consumer maps `tradeState` and local order status; documented handoff. |
| API Client | AFFECTED | Three new cashier endpoints. |
| Request Contract | AFFECTED | Create uses orderNo/optional terminalId; amount is intentionally absent. |
| Backend/Domain | AFFECTED | Native attempt lifecycle and shared payment confirmation. |
| Persistence | AFFECTED | New migration/table for durable Native attempts and one-active-attempt invariant. |
| Response Contract | AFFECTED | QR/status/close response fields and error semantics. |
| Jobs/Events/Integrations | AFFECTED | WeChat Native/create/query/close and existing callback/ledger/reconciliation. |
| Config/Security | AFFECTED | Existing merchant credentials; new permission mappings; no new secrets. |
| Runtime/NFR | AFFECTED | Timeouts remain UNKNOWN; retry/reuse and multi-instance idempotency required. |
| Tests | AFFECTED | Unit/integration/contract/regression and full Maven package. |

Classifications: AFFECTED / VERIFIED_UNAFFECTED / NOT_APPLICABLE / UNKNOWN.

## Duplicate Logic / Patch Smells

- Callback and authoritative query must not each implement a separate local settlement path.
- Native transport may share low-level signing helpers with JSAPI, but must not copy client mini-program pay-param construction.
- Existing refund and reconciliation capabilities are reused, not duplicated.

## Contract Delta Summary

Additive cashier endpoints under `/cashier/payment/wechat/native/orders`; no breaking change to existing endpoints.

## UI Semantic Impact

Consumer must distinguish `NOTPAY/USERPAYING` (waiting), `SUCCESS` (confirmed), `CLOSED/PAYERROR` (terminal failure) and transport/query uncertainty (not success). Detailed mapping is in the handoff.

## Risks

- Double settlement from callback/query races.
- Reusing or regenerating QR attempts incorrectly after timeout.
- Cross-shop access to an order or attempt.
- Marking paid from an unverified or mismatched WeChat payload.
- Holding database locks across a slow external call; attempt reservation must remain bounded and recoverable.

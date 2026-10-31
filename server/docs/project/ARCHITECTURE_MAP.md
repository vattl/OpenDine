# Architecture Map — PB-2

## System Boundaries

- This repository owns the cloud Spring Boot backend and its MySQL/Redis persistence.
- WeChat Pay is an external payment authority; only verified API responses or signed callbacks may confirm payment.
- Mini program, cashier/admin and KDS clients are consumers; production UI code is maintained outside this server checkout.
- For KDS, cloud state is authoritative and cashier is proxy/cache only.

## Major Modules

- API/controllers: `com.lanf.controller`, including cashier and admin subpackages.
- Domain/application services: `com.lanf.service` and `com.lanf.service.impl`.
- Payment capability: `com.lanf.payment` plus order/refund callback endpoints in `OrderController`.
- Persistence: MyBatis-Plus entities/mappers and versioned SQL migrations.
- KDS: `com.lanf.kds` with HTTP, WebSocket, command ledger and event recovery.
- Operations/reporting: daily close, drawer/shift, payment ledger, reconciliation and reports.
- Security: JWT/interceptors, permission mapping, sensitive-operation authorization and audit logging.

## Domain / Capability Owners

- Order lifecycle: `IOrderService`, `OrderController`, cashier order services.
- Cashier settlement: `CashierCheckoutService`.
- External WeChat transaction transport: `WechatJsapiChannel`, `WechatMerchantKeyStore`, `WechatPayV3Crypto`.
- Confirmed-payment application: `WechatPaymentNotifyHandler` and `PaymentSuccessHandler`.
- Refund requests and compensation: `WechatJsapiChannel`, `PaymentRefundLedger`, `WechatRefundSettlementService`, `WechatRefundQueryScheduler`.
- Accounting evidence: `PaymentLedgerService`, `PaymentSettlementLedgerHelper`, `ReconciliationServiceImpl`.
- Merchant configuration: `PaymentMerchantConfigService` and admin payment controllers.
- Approval token lifecycle: `ApprovalService`; authenticated QR token persistence envelopes: `ApprovalTokenEnvelopeCipher`.

## Dependency Direction

```text
HTTP controller/interceptor
  -> application/domain service
  -> payment/KDS/report integration service
  -> mapper/entity/database

WeChat Pay callback/query
  -> signature/decryption boundary
  -> idempotent payment state transition
  -> immutable ledger + fulfillment side effects
```

Controllers should not own credential loading or payment signing. Clients must not supply authoritative payable amounts or directly mark an order paid.

## Frontend ↔ API ↔ Backend Paths

- Mini program payment: `/order/getPrepayId` -> `PaymentFacadeService` -> `WechatJsapiChannel` -> WeChat JSAPI; `/order/pay/notify` applies success.
- Cashier settlement: `/cashier/order/checkout` -> `CashierCheckoutService` -> order + payment ledger + fulfillment.
- Merchant configuration: `/admin/payment/**` -> `PaymentMerchantConfigService` -> encrypted configuration records and referenced key files.
- Reconciliation: `/admin/reconciliation/**` -> `ReconciliationServiceImpl` -> payment ledger/channel statement/case tables.

## Events / Jobs / Integrations

- WeChat Pay APIv3 HTTPS requests and signed encrypted callbacks.
- WebSocket KDS events published only after committed cloud authority state.
- Scheduled WeChat refund query compensation.
- Payment success triggers printing, KDS, coupon, points, table and delivery side effects.

## Data Stores

- MySQL is the authoritative business store.
- Redis supports runtime integration where configured but is not the payment source of truth.
- `t_order` is current order/payment state; `t_payment_ledger` is immutable accounting evidence.
- `t_order.order_no` is globally unique and is the deterministic business-order identity used by payment callbacks.
- `t_payment_refund_request` tracks idempotent WeChat refund requests and binds each request to the originating shop, merchant configuration version, WeChat transaction and merchant number.
- `t_channel_statement_*` and `t_reconciliation_case` support external statement reconciliation.

## Critical Runtime Paths

- Payment: server-owned order amount -> signed WeChat request -> signed callback/query -> idempotent local settlement -> ledger -> fulfillment.
- KDS: authenticated command -> cloud transaction/command ledger -> committed event -> WebSocket/changes recovery.
- Cashier close: authenticated operator -> locked order -> capability/amount validation -> settlement -> ledger -> after-commit fulfillment.
- QR approval: manager decision -> token hash + AES-GCM envelope in MySQL -> authenticated cross-instance poll -> one-time CAS consumption.

## Known Architectural Constraints

- Never place payment private keys/APIv3 keys in client code or API responses.
- Callback delivery is at-least-once; all success/refund application must be idempotent.
- New payment merchant routing is server-authoritative. Client `merchantId` is legacy metadata only; transaction creation binds the selected merchant configuration ID/version, and every later query, close, reversal, payment callback and refund must validate that binding against the order shop.
- Timeouts are unknown outcomes until authoritative query resolves them.
- Cross-layer API changes require either same-Work-Item consumer changes or an explicit handoff.
- Every backend instance must share the same independent `APPROVAL_TOKEN_ENVELOPE_KEY`; approval tokens must never be persisted as directly usable plaintext.

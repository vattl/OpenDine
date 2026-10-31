# Implementation Design — WI-015

## Root Fix / Owner

Create a dedicated Native payment application service under `com.lanf.payment.channel.wechat` and a shared confirmed-payment application service under `com.lanf.payment`. `WechatPaymentNotifyHandler` and Native query both delegate to that shared owner.

## Why this location

The repository already centralizes WeChat merchant credentials, signing and refund transport in `com.lanf.payment.channel.wechat`, while `PaymentSuccessHandler` owns downstream business effects. Extending these owners preserves one payment authority and avoids a cashier-only settlement fork.

## End-to-End Change

### Backend

- Add a cashier Native controller with create, query and close operations.
- Add `WechatNativePaymentService` for order validation, attempt reservation/reuse and WeChat APIv3 transport.
- Add `WechatPaymentSuccessService` to validate and atomically apply a confirmed transaction from callback or query.
- Update `WechatPaymentNotifyHandler` to decrypt and delegate successful transaction application.

### Frontend

No code edit in this repository. Provide `API_CONSUMER_HANDOFF.md` covering request/response/state mapping and polling behavior.

### UI / Interaction

No production UI edit. Consumer requirements: render `codeUrl` as QR, poll the status endpoint, never treat network timeout as paid, stop on terminal state, and offer retry only after close/expiry.

### Data / Persistence

Add a higher-version migration creating `t_wechat_native_payment_attempt` with:

- immutable identifiers: shop/order/out_trade_no/merchant key/amount;
- QR and lifecycle: code_url/status/trade_state/expires_at;
- confirmed identifiers: transaction_id/success_time;
- query/diagnostic timestamps without secrets;
- unique `out_trade_no`;
- nullable unique `active_key` (`shop_id:order_no`) so at most one active attempt exists while multiple historical terminal rows remain allowed.

No applied migration is modified.

### Interfaces / Contracts

- `POST /cashier/payment/wechat/native/orders`
  - request: `orderNo` required, `terminalId` optional;
  - response: `paymentId`, `outTradeNo`, `codeUrl`, `amountFen`, `expiresAt`, `tradeState`, `reused`.
- `GET /cashier/payment/wechat/native/orders/{orderNo}`
  - resolves the latest relevant attempt through authoritative WeChat query when needed;
  - response includes local order state and WeChat trade state.
- `POST /cashier/payment/wechat/native/orders/{orderNo}/close`
  - closes only a non-success active attempt and releases `active_key`.

All endpoints use the existing `R` envelope and current cashier authentication conventions.

### Jobs / Events / Integrations

- WeChat endpoints: Native create, merchant-order query and close, per official APIv3 contract.
- Existing callback URL remains `/order/pay/notify`.
- Existing refund scheduler, payment ledger and statement reconciliation remain owners of their respective capabilities.

## Preserve / Compatibility

- Existing `/order/getPrepayId`, recharge, payment callback URL, refund API and merchant configuration remain compatible.
- `PaymentMerchantNoUtil.parseOrderNoFromOutTradeNo` remains supported for historical JSAPI callbacks; new Native attempts are also resolved by persisted `out_trade_no`.
- Existing consumers can ignore the additive endpoints.

## API Consumer Migration / Handoff

Backend scope ends with the explicit `API_CONSUMER_HANDOFF.md`. The cashier consumer must be updated in a later/same cross-repository Work Item before the feature is user-visible.

## Failure / Boundary Behavior

- Transport timeout: return an indeterminate/query-required error and preserve the reserved attempt; next request queries/reuses it rather than charging with a blind new attempt.
- Duplicate create: return the active stored QR when amount and merchant context still match.
- Amount/order changed: close/release an unpaid stale attempt before creating a new attempt; never reuse mismatched amount.
- Query `SUCCESS`: validate and apply locally; repeated application is idempotent.
- Close sees `SUCCESS`: apply success and reject close.
- `NOTPAY/USERPAYING`: remain pending.
- `CLOSED/PAYERROR/REVOKED`: mark terminal and release `active_key`.

## Runtime / Performance / Reliability

- External requests use configured `RestTemplate` timeouts.
- Database uniqueness protects multi-instance concurrency.
- No blocking sleeps in request handling.
- Callback/query race converges using the existing per-order lock plus locked/order-state idempotency and unique ledger evidence.

## Security / Permissions

- STRIDE boundaries: cashier request, WeChat response, callback and database attempt state.
- Cashier endpoints require `cashier:operate` and obtain shop scope from authenticated request context.
- Server derives amount/order/shop/merchant configuration.
- Signed callback verification remains mandatory; query/create/close are signed using server-held private key.
- Decrypted payload must match expected appid, mchid, out_trade_no and exact amount before settlement.
- Do not log code URL, private keys, APIv3 keys, signatures or decrypted full payloads.

## UI Design Track

NOT_APPLICABLE: no production UI edit in this backend repository. Consumer handoff is not a UI implementation.

## Vertical Slice Plan

1. Persistence and repository contract: migration/entity/mapper plus tests for one-active-attempt semantics.
2. Create QR path: RED tests, minimal transport/service/controller, permission and contract.
3. Query/close path: state mapping and unknown-outcome recovery tests.
4. Shared success application: callback/query concurrency and validation regression tests.
5. Documentation, security review, complete test/package and executable acceptance gate.

## Verification Strategy

- Unit tests for signing request paths, payload construction, state mapping and validation.
- Service tests with fake/mocked WeChat boundary for QR reuse, expiry, query and close.
- Callback regression tests proving existing signed callback semantics remain intact.
- Concurrency/idempotency test for duplicate query/callback success.
- OpenAPI/document synchronization checks.
- `mvnw.cmd test` followed by mandatory `mvnw.cmd clean package -DskipTests`.

## Rollback / Recovery

- New endpoints are additive; rollback application code leaves the new table unused.
- Migration is forward-only and safe to retain; no existing table is destructively modified.
- Pending/unknown attempts remain queryable by `out_trade_no` for operational recovery.

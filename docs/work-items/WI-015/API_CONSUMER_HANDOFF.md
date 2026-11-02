# API Consumer Handoff — WI-015

## Interface

Cashier WeChat Native create/status/close endpoints under `/cashier/payment/wechat/native/orders`.

## Compatibility

ACTION_REQUIRED

## Before

Cashier supports manual/offline collection confirmation and immediate checkout, but has no order-specific WeChat Native QR flow.

## After

Cashier creates a server-owned Native payment attempt, renders the returned `codeUrl`, polls status, and finishes only after the server reports confirmed success.

## Consumer Impact

The cashier client must add a payment-pending state. It must not call normal `/cashier/order/checkout` for the same WeChat Native transaction.

## Required Frontend / Consumer Changes

1. Call create with only `orderNo` and optional terminal identifier.
2. Render `codeUrl` as a QR without modifying it.
3. Poll status while `tradeState` is `NOTPAY` or `USERPAYING`; use bounded backoff and stop when the dialog closes.
4. Treat only `SUCCESS` plus local `orderPaid=true` as paid.
5. On timeout/network error show “支付结果确认中” and keep querying; do not create a blind second attempt.
6. Close the attempt when the operator explicitly cancels before payment; if close reports success, transition to paid.

## Type / Model Changes

Add a Native payment attempt model containing `paymentId`, `orderNo`, `outTradeNo`, `codeUrl`, `amountFen`, `expiresAt`, `tradeState`, `orderPaid`, `reused`.

## Request Construction

```json
{
  "orderNo": "ORD202610150001",
  "terminalId": "POS-01"
}
```

Do not send amount, mchid, appid, notify URL, credentials or a local paid flag.

## Response Mapping / Display

- `NOTPAY`: waiting for scan/payment.
- `USERPAYING`: customer is confirming payment.
- `SUCCESS`: confirmed paid; dismiss QR and refresh the order/table.
- `CLOSED`, `PAYERROR`, `REVOKED`: terminal unsuccessful; allow a new attempt after refreshing.
- request timeout/5xx: unknown result; keep the same order and query status.

## UI / Interaction Impact

Requires a modal/panel with amount, QR, countdown, waiting/querying/error states and explicit cancel. This is a future UI Work Item and therefore must complete the repository's mandatory HTML prototype approval before production UI edits.

## Example Call

```http
POST /cashier/payment/wechat/native/orders
Authorization: Bearer <cashier-jwt>
Content-Type: application/json

{"orderNo":"ORD202610150001","terminalId":"POS-01"}
```

## Example Response

```json
{
  "code": 0,
  "paymentId": 123,
  "orderNo": "ORD202610150001",
  "outTradeNo": "ORD202610150001_1234567890",
  "codeUrl": "weixin://wxpay/bizpayurl?...",
  "amountFen": 8800,
  "expiresAt": "2026-10-15T20:10:00+08:00",
  "tradeState": "NOTPAY",
  "orderPaid": false,
  "reused": false
}
```

## Defaults / Fallbacks

- No offline success fallback exists.
- If status cannot be confirmed, keep the order unsettled and show an unknown/querying state.

## Rollout / Migration Order

1. Apply server migration and deploy backend.
2. Verify merchant Native product permission and bound AppID.
3. Implement/prototype cashier UI against the documented contract.
4. Perform low-value real-merchant smoke test before enabling broadly.

## Verification Checklist

- [ ] consumer request updated
- [ ] consumer response mapping updated
- [ ] UI/state semantics updated if applicable
- [ ] old contract references removed or intentionally supported
- [ ] end-to-end flow verified

## Owner / Status

Owner: cashier client repository. Status: FRONTEND_ACTION_REQUIRED; backend Work Item scope explicitly ends at handoff.

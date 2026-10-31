# Contract Delta — WI-015

Capability: Cashier WeChat Native payment
Reason: allow customers to scan an order-specific cashier QR and settle directly to the configured merchant.

## Request

### Before

No cashier Native payment create/query/close contract exists.

### After

- `POST /cashier/payment/wechat/native/orders` accepts `orderNo` and optional `terminalId`; no client amount or merchant credential fields.
- `GET /cashier/payment/wechat/native/orders/{orderNo}` queries the authoritative transaction state.
- `POST /cashier/payment/wechat/native/orders/{orderNo}/close` closes an unpaid attempt.

### Consumers

| Consumer | Reviewed | Change needed | Evidence |
|---|---:|---:|---|
| Cashier application | yes | yes | `API_CONSUMER_HANDOFF.md` |
| Mini program | yes | no | Existing `/order/getPrepayId` unchanged |

## Response

### Before

No Native QR response exists.

### After

Create returns attempt identity, `codeUrl`, `outTradeNo`, `amountFen`, `expiresAt`, `tradeState` and reuse marker. Query/close return stable attempt/order state without credentials or decrypted callback data.

### Consumers

| Consumer | Reviewed | Change needed | Evidence |
|---|---:|---:|---|
| Cashier application | yes | yes | `API_CONSUMER_HANDOFF.md` |
| Admin reconciliation | yes | no | Existing ledger/statement contract reused |

## Semantic Delta

Cashier checkout can now remain pending until WeChat authority confirms success. Network success and QR creation are not payment success.

## UI Impact

- labels: distinguish waiting, confirmed, closed/failed and unknown/querying.
- controls: show QR; allow cancel/close only before confirmed success.
- validation: never collect an amount from the UI for this API.
- state/action mapping: `SUCCESS` is the only paid state.
- empty/error/loading states: documented in the consumer handoff; UI implementation is out of this repository's scope.

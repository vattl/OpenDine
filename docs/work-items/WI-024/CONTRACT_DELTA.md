# Contract Delta — WI-024

## Existing endpoint

`POST /order/getPrepayId`

### Preserved success fields

- `prepay_id`
- `payParams`

### Additive response fields

- `paymentAttemptId`
- `outTradeNo`
- `amountFen`
- `expiresAt`
- `reused`

### Tightened errors

- Active payment state unknown: client must wait/query, not retry-create.
- Order amount changed: old payment is closed; client refreshes order then requests new prepay.
- Payment already succeeded: client refreshes order and must not mutate price.

No client-supplied amount, merchant configuration ID, or payment status is accepted.

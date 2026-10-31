# API Consumer Handoff — WI-024

## Consumers

Mini program and cashier/admin clients outside this repository.

## Required behavior

1. Never cache `payParams` across an order refresh or amount-changing operation.
2. On payment-state conflict, fetch the order again and request a new prepay session.
3. Display the server-returned order amount immediately before `wx.requestPayment`.
4. Disable repeated payment taps while the prepay request or `wx.requestPayment` is active.
5. Treat “payment already succeeded” as refresh-success, not another payment request.

## Compatibility

Existing success fields remain valid. New metadata is additive. Error behavior is stricter to prevent duplicate or stale-amount collection.

Owner: external mini-program/cashier teams — PENDING.

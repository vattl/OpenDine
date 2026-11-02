# Security Audit — WI-079

## Decision

- **Work Item**: `WI-079`
- **Decision**: `PASS`

## Verified Controls

1. **C-Side User Token Anti-Spoofing (`NotificationChannelController` & `UnifiedNotificationWebSocketHandler`)**:
   - Requests carrying `X-User-Token` (`subject = "user"`) are cryptographically verified via `JwtTokenService`.
   - Any attempt to pass a mismatched `openid` in query parameters, JSON body, or WebSocket handshake query string is rejected (`403` on REST, `1008 POLICY_VIOLATION` on WebSocket).
2. **Role & Channel Segregation**:
   - Customer-specific notifications (`COUPON_GRANTED`, `COUPON_EXPIRING_SOON`, `ORDER_READY_FOR_PICKUP`) are scoped to `target.scope = USER` (`openid`).
   - Internal cashier operational alerts (`REFUND_REQUESTED`, `ORDER_PREP_TIMEOUT`) are scoped to `target.scope = SHOP` and `client_type = CASHIER`, never leaking to `MINI_PROGRAM` sessions.

# Security Audit — WI-078

## Scope & Decision

- **Work Item**: `WI-078`
- **Decision**: `PASS`
- **Audited Surfaces**:
  - `UnifiedNotificationWebSocketHandler` (`/ws/v1/notify`)
  - `NotificationChannelController` (`/admin/shop/notification-config`, `/cashier/notifications/sync`, `/cashier/notifications/ack`, `/api/v1/notifications/sync`, `/api/v1/notifications/ack`)
  - `ApiPermissionMapping` & `V053__unified_realtime_notification_channel.sql`
  - `UnifiedSessionRegistry` & `UnifiedNotificationService`

## Security Verification Checklist

1. **WebSocket Authentication & Shop Tenant Isolation (`CASHIER` / `ADMIN`)**:
   - `UnifiedNotificationWebSocketHandler.authenticateAndRegister` validates JWT tokens via `JwtTokenService.parseToken` or active cashier device lease via `CashierKdsLeaseService.authenticateRequest`.
   - Unauthenticated connections for `CASHIER`/`ADMIN` are immediately closed with `CloseStatus.POLICY_VIOLATION` (`1008`) before registering in `UnifiedSessionRegistry`.
2. **Mini Program User Isolation (`MINI_PROGRAM`)**:
   - User-scoped events (`target.scope = USER`, e.g., `COUPON_GRANTED`) are routed strictly to sessions matching `openid` / `user_id` via `UnifiedSessionRegistry.sendToUser` and filtered by `user_openid` in `syncNotifications` and `acknowledgeNotifications`.
   - Shop-internal operational alerts (`ORDER_PREP_TIMEOUT`, `NEW_ORDER_PAID`, `TAKEOUT_DISPATCH_ALERT`) use `client_type = CASHIER` and are never leaked to `MINI_PROGRAM` sessions.
3. **RBAC Enforcement on REST Endpoints**:
   - `GET /admin/shop/notification-config` and `PUT /admin/shop/notification-config` require `shop:manage,order:config` in `ApiPermissionMapping` and `t_api_permission`.
   - `GET /cashier/notifications/sync` and `POST /cashier/notifications/ack` require `cashier:operate,order:view` in `ApiPermissionMapping` and `t_api_permission`.
4. **Input Validation & Bounds**:
   - `ShopNotificationConfigService.updateConfig` enforces `prep_timeout_minutes` in `[5, 120]` and `timeout_repeat_interval_seconds` in `[15, 600]`, returning HTTP/business code `400` on out-of-range values.

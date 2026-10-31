# Test Report — WI-078

## Test Summary

- **Work Item**: `WI-078` (Unified Realtime Notification Channel Phase 1)
- **Status**: `PASS`
- **Test Class**: `com.lanf.realtime.UnifiedNotificationChannelTest`
- **Tests Run**: 5, Failures: 0, Errors: 0, Skipped: 0

## Scenario Matrix Coverage Verification

| Scenario ID | Test Method | Result | Evidence |
|---|---|---|---|
| `S-01` | `unifiedNotificationPermissionsAndWebSocketEndpointShouldBeRegistered` | PASS | Verifies RBAC mappings in `ApiPermissionMapping` (`/admin/shop/notification-config`, `/cashier/notifications/sync`, `/cashier/notifications/ack`, `/api/v1/notifications/sync`, `/api/v1/notifications/ack`) and `/ws/v1/notify` registration in `WebSocketConfig` alongside `/ws/menu`, `/ws/kds`, `/ws/cashier-events`. |
| `S-02` | `dynamicShopNotificationConfigShouldDefaultValidateAndPersist` | PASS | Verifies default shop notification config (`prep_timeout_enabled=true`, `prep_timeout_minutes=15`, `timeout_repeat_interval_seconds=60`), rejects invalid thresholds (`< 5` or `> 120` minutes with code `400`), and persists valid updates (`25` minutes, `45` seconds repeat). |
| `S-03` | `watchdogShouldTriggerDynamicOrderPrepTimeoutAndDeduplicate` | PASS | Verifies `OrderTimeoutWatchdogScheduler` dynamically evaluates per-shop timeout thresholds (`10` min for Shop 1, disabled for Shop 2), emits `ORDER_PREP_TIMEOUT` (`P0`, `require_ack=true`, `ntf_timeout_ORD_TIMEOUT_101_stage1`), and deduplicates on subsequent watchdog scans. |
| `S-04` | `couponGrantShouldPushRealtimeWhenOnlineAndFallbackToSubscribeMessageWhenOffline` | PASS | Verifies `ICouponServiceImpl.receiveCoupon` emits `COUPON_GRANTED` (`P1`, `aggregation_key=COUPON_GRANTED`, `aggregation_window_ms=800`) over WebSocket when the user is online (`MINI_PROGRAM`), and falls back to `WechatCouponSubscribePushService` when the user has 0 online WebSocket sessions. |
| `S-05` | `websocketHandlerSyncAndMultiDeviceAckShouldDismissAcrossShopTerminals` | PASS | Verifies `/ws/v1/notify` rejects invalid JWT (`CloseStatus.POLICY_VIOLATION`), pushes `NEW_ORDER_PAID` (`P0`) to multiple Cashier POS terminals, handles `PING`/`PONG` with `server_head_seq_id`, supports cursor-based `/cashier/notifications/sync`, broadcasts `ALERT_DISMISSED` across sibling terminals on `ACK`, and dual-publishes `TABLE_ORDER_CHANGED` and `DISH_CATALOG_CHANGED`. |

## Build & Packaging Verification

- **Command**: `.\mvnw.cmd clean package -DskipTests`
- **Result**: `BUILD SUCCESS` (`target/diancan-0.0.1-SNAPSHOT.jar` generated and repackaged cleanly).

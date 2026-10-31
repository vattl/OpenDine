# Acceptance Report — WI-078

## Acceptance Decision

- **Work Item**: `WI-078` (Unified Realtime Notification Channel Phase 1)
- **Acceptance Status**: `PASS`

## Requirement Verification Matrix

| Requirement | Implementation Evidence | Verification Evidence | Status |
|---|---|---|---|
| Unified WebSocket Channel (`/ws/v1/notify`) with standard `UnifiedMessageEnvelope` (`P0`–`P3`, `display_strategy`, `seq_id`, `PING`/`PONG`, `ACK`, `SYNC`) | `UnifiedMessageEnvelope.java`, `UnifiedSessionRegistry.java`, `UnifiedNotificationWebSocketHandler.java`, `WebSocketConfig.java` | `UnifiedNotificationChannelTest#unifiedNotificationPermissionsAndWebSocketEndpointShouldBeRegistered`, `UnifiedNotificationChannelTest#websocketHandlerSyncAndMultiDeviceAckShouldDismissAcrossShopTerminals` | PASS |
| Dynamic Per-Shop Preparation Timeout Threshold Configuration (`prep_timeout_enabled`, `prep_timeout_minutes` 5–120, `timeout_repeat_interval_seconds`) + Watchdog Scheduler (`ORDER_PREP_TIMEOUT`) | `V053__unified_realtime_notification_channel.sql`, `ShopNotificationConfigService.java`, `OrderTimeoutWatchdogScheduler.java`, `NotificationChannelController.java` | `UnifiedNotificationChannelTest#dynamicShopNotificationConfigShouldDefaultValidateAndPersist`, `UnifiedNotificationChannelTest#watchdogShouldTriggerDynamicOrderPrepTimeoutAndDeduplicate` | PASS |
| New Coupon Real-Time Push (`COUPON_GRANTED`, `P1`, 800ms aggregation) + Offline WeChat Subscribe Message Fallback | `ICouponServiceImpl.java`, `UnifiedNotificationService.java`, `WechatCouponSubscribePushService.java` | `UnifiedNotificationChannelTest#couponGrantShouldPushRealtimeWhenOnlineAndFallbackToSubscribeMessageWhenOffline` | PASS |
| New Order Paid (`NEW_ORDER_PAID`, `P0`) & Dual-Publish Bridge for Cashier/Menu Events (`KDS_DELIVERY_AVAILABLE`, `TABLE_ORDER_CHANGED`, `DISH_CATALOG_CHANGED`, `TAKEOUT_DISPATCH_ALERT`, `MEAL_PICKUP_READY`) | `PaymentSuccessHandler.java`, `CashierEventWebSocketHub.java`, `DishMenuPushService.java`, `AppConfigController.java` | `UnifiedNotificationChannelTest#websocketHandlerSyncAndMultiDeviceAckShouldDismissAcrossShopTerminals` | PASS |
| Mandatory OpenAPI/API Doc Sync & Runnable JAR Build | `docs/openapi.yaml`, `docs/API.md`, `target/diancan-0.0.1-SNAPSHOT.jar` | `.\mvnw.cmd clean package -DskipTests` (`BUILD SUCCESS`) | PASS |

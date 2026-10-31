# Completion Evidence — WI-078

## 1. Delivered Files & Components

1. **Database Migration**:
   - `src/main/resources/db/migration/V053__unified_realtime_notification_channel.sql`: Creates `t_realtime_notification` (persistent outbox with monotonic `seq_id`), `t_shop_notification_config` (per-shop dynamic timeout threshold), and seeds `t_api_permission` RBAC mappings.
2. **Entities & Mappers**:
   - `src/main/java/com/lanf/entity/RealtimeNotification.java` & `src/main/java/com/lanf/mapper/RealtimeNotificationMapper.java`
   - `src/main/java/com/lanf/entity/ShopNotificationConfig.java` & `src/main/java/com/lanf/mapper/ShopNotificationConfigMapper.java`
3. **Unified Realtime WebSocket Engine (`/ws/v1/notify`)**:
   - `src/main/java/com/lanf/realtime/UnifiedMessageEnvelope.java`
   - `src/main/java/com/lanf/realtime/UnifiedSessionRegistry.java`
   - `src/main/java/com/lanf/realtime/UnifiedNotificationWebSocketHandler.java`
   - `src/main/java/com/lanf/config/WebSocketConfig.java`
4. **Notification Services, Dynamic Timeout Watchdog & Offline Subscribe Fallback**:
   - `src/main/java/com/lanf/notify/service/UnifiedNotificationService.java`
   - `src/main/java/com/lanf/notify/service/ShopNotificationConfigService.java`
   - `src/main/java/com/lanf/notify/service/OrderTimeoutWatchdogScheduler.java`
   - `src/main/java/com/lanf/notify/service/WechatCouponSubscribePushService.java`
5. **REST Controller & Business Event Producers**:
   - `src/main/java/com/lanf/controller/NotificationChannelController.java`
   - `src/main/java/com/lanf/config/ApiPermissionMapping.java`
   - `src/main/java/com/lanf/payment/success/PaymentSuccessHandler.java` (`NEW_ORDER_PAID`)
   - `src/main/java/com/lanf/service/impl/ICouponServiceImpl.java` (`COUPON_GRANTED` on `receiveCoupon`, `redeemCouponByCode`, `grantConfiguredEntryCoupons`)
   - `src/main/java/com/lanf/realtime/CashierEventWebSocketHub.java` (dual-publish bridge for `KDS_DELIVERY_AVAILABLE`, `TABLE_ORDER_CHANGED`, `TAKEOUT_DISPATCH_ALERT`, `TAKEOUT_DISPATCH_CHANGED`, `MEAL_PICKUP_READY`)
   - `src/main/java/com/lanf/service/DishMenuPushService.java` & `src/main/java/com/lanf/controller/AppConfigController.java` (dual-publish bridge for `DISH_CATALOG_CHANGED`, `SHOP_BUSINESS_CHANGED`)
6. **API Documentation & Tests**:
   - `docs/openapi.yaml` & `docs/API.md`
   - `src/test/java/com/lanf/realtime/UnifiedNotificationChannelTest.java`

## 2. Verification Commands & Outputs

- **TDD Cycle (`RED → GREEN → REFACTOR → REGRESSION`)**:
  - Recorded in `docs/work-items/WI-078/EXECUTION_JOURNAL.jsonl` (`SHA256: eb5907c22fc6a32b103fa2045aae2fcfacc1df2b5664e0f5a597dae42408ccba`).
  - All 5 test scenarios in `UnifiedNotificationChannelTest` passed (`0` failures, `0` errors).
- **Mandatory Full Maven Package Build**:
  - Command: `.\mvnw.cmd clean package -DskipTests`
  - Output: `BUILD SUCCESS`, runnable artifact generated at `target/diancan-0.0.1-SNAPSHOT.jar`.

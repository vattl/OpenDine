# Impact Map — WI-078

## Audit Routing Inputs

Risk Level: MEDIUM
UI Impact: NONE
Contract Impact: CONSUMER_ACTION
Security Impact: YES
Data / Migration Impact: YES
Reliability / Performance Impact: YES

## Affected Surfaces
- **Database Schema (`src/main/resources/db/migration/V053__unified_realtime_notification_channel.sql`)**:
  - New table `t_realtime_notification`
  - New table `t_shop_notification_config`
  - New rows in `t_api_permission` for `/admin/shop/notification-config`, `/cashier/notifications/sync`, `/cashier/notifications/ack`, `/api/v1/notifications/sync`, `/api/v1/notifications/ack`
- **Security & Interceptors**:
  - `src/main/java/com/lanf/config/ApiPermissionMapping.java`: static route-permission inventory sync
  - `src/main/java/com/lanf/config/WebAppConfigurer.java`: `/ws/**` already excluded from `SysInterceptor`; `/api/v1/notifications/**` supports both B-end JWT and C-end `openid` authentication
- **WebSocket & Realtime Layer**:
  - `src/main/java/com/lanf/config/WebSocketConfig.java`: register `/ws/v1/notify` alongside `/ws/menu`, `/ws/kds`, `/ws/kds/v2`, `/ws/cashier-events`
  - `src/main/java/com/lanf/realtime/UnifiedMessageEnvelope.java`: standard message envelope & `DisplayStrategy` model
  - `src/main/java/com/lanf/realtime/UnifiedSessionRegistry.java`: multi-dimensional session registry (`shopId`, `openid`, `clientType`) + `WebSocketOutboundDispatcher` integration
  - `src/main/java/com/lanf/realtime/UnifiedNotificationWebSocketHandler.java`: `/ws/v1/notify` lifecycle, auth, `PING`/`PONG`, `ACK`, `BIND_CONTEXT`
  - `src/main/java/com/lanf/realtime/CashierEventWebSocketHub.java`: dual-publish bridge to `UnifiedNotificationService`
- **Notification Domain & Services**:
  - `src/main/java/com/lanf/entity/RealtimeNotification.java` & `src/main/java/com/lanf/mapper/RealtimeNotificationMapper.java`
  - `src/main/java/com/lanf/entity/ShopNotificationConfig.java` & `src/main/java/com/lanf/mapper/ShopNotificationConfigMapper.java`
  - `src/main/java/com/lanf/notify/service/ShopNotificationConfigService.java`: dynamic per-shop timeout threshold CRUD & validation (`5..120` minutes)
  - `src/main/java/com/lanf/notify/service/UnifiedNotificationService.java`: transactional outbox persistence, afterCommit WebSocket push, cursor-based `sync`, multi-terminal `ack` & `ALERT_DISMISSED` broadcast
  - `src/main/java/com/lanf/notify/service/OrderTimeoutWatchdogScheduler.java`: scheduled scan for paid uncompleted orders exceeding shop's dynamic threshold
  - `src/main/java/com/lanf/notify/service/WechatCouponSubscribePushService.java`: offline WeChat Subscribe Message fallback for `COUPON_GRANTED`
  - `src/main/java/com/lanf/controller/NotificationChannelController.java`: REST endpoints for sync, ack, and shop notification config
- **Business Event Producers**:
  - `src/main/java/com/lanf/payment/success/PaymentSuccessHandler.java`: publish `NEW_ORDER_PAID`
  - `src/main/java/com/lanf/service/impl/ICouponServiceImpl.java`: publish `COUPON_GRANTED` on `receiveCoupon`
  - `src/main/java/com/lanf/service/DishMenuPushService.java`: dual-publish menu/business/pickup/takeout events to unified channel
  - `src/main/java/com/lanf/controller/AppConfigController.java`: include `couponGranted` template ID in `/config/subscribe-templates`
- **API Documentation**:
  - `docs/openapi.yaml`
  - `docs/API.md`

## Invariants Preserved
- **KDS Authority Invariant**: `/ws/kds` and `/ws/kds/v2` remain untouched; cloud remains the sole business authority.
- **Backward Compatibility Invariant**: Legacy `/ws/menu` and `/ws/cashier-events` continue broadcasting their original JSON payloads without breaking existing clients.
- **Transactional Outbox Invariant**: Persistent notifications (`P0`/`P1`/`P2`) are dispatched over WebSocket only after the business database transaction commits (`afterCommit`), preventing phantom notifications on rollback.
- **Shop Isolation Invariant**: Cashier notifications and `sync`/`ack` operations are strictly scoped to the authenticated `shop_id`.

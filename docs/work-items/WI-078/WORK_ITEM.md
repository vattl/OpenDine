# Work Item — WI-078: Unified Realtime Message Channel (Phase 1: Server + Cashier POS + Dynamic Prep Timeout + Coupon Push)

## Summary
Implement Phase 1 of the Unified Realtime Message Channel (`/ws/v1/notify`) and accompanying REST endpoints for incremental cursor sync, multi-terminal ACK/alert dismissal, dynamic per-shop order preparation timeout thresholds, new order & new coupon real-time push (with offline WeChat Subscribe Message fallback), and dual-publish compatibility bridges for existing `/ws/cashier-events` and `/ws/menu` channels.

## Type
FEATURE

## Risk Tier
STANDARD

## Scope
1. **Database & Permissions (`V053__unified_realtime_notification_channel.sql`, `ApiPermissionMapping.java`)**:
   - Create `t_realtime_notification` (monotonic `seq_id` PK, `message_id` UK, target scope, `shop_id`, `user_id`, `user_openid`, `client_type`, `business_type`, `event_type`, `priority`, `require_ack`, `display_strategy_json`, `payload_json`, `read_status`, `expire_at`, `created_at`, `updated_at`).
   - Create `t_shop_notification_config` (`shop_id` PK, `prep_timeout_enabled` default 1, `prep_timeout_minutes` default 15 [range 5..120], `timeout_repeat_interval_seconds` default 60, `updated_by`, `updated_at`).
   - Register API permission mappings for `/admin/shop/notification-config`, `/cashier/notifications/sync`, `/cashier/notifications/ack`, `/api/v1/notifications/sync`, `/api/v1/notifications/ack`.
2. **Unified WebSocket Endpoint & Session Registry (`/ws/v1/notify`)**:
   - `UnifiedMessageEnvelope` & `DisplayStrategy` standard JSON envelope (`frame_type`, `message_id`, `seq_id`, `timestamp`, `expire_at`, `target`, `business_type`, `event_type`, `priority`, `require_ack`, `display_strategy`, `payload`).
   - `UnifiedSessionRegistry`: indexes active WebSocket sessions by `shopId` (separated by `CASHIER` and `MINI_PROGRAM` client types) and `openid`/`userId`, backed by `WebSocketOutboundDispatcher`.
   - `UnifiedNotificationWebSocketHandler`: supports `CASHIER` (JWT or cashier lease authentication + shop binding) and `MINI_PROGRAM` (`openid` + `shop_id` binding), `PING`/`PONG` heartbeat with `server_head_seq_id`, `ACK` frame handling, and `BIND_CONTEXT` dynamic context rebinding.
3. **Persistence, Transactional Outbox Dispatch, Sync & Multi-Device ACK (`UnifiedNotificationService`)**:
   - Persist P0/P1/P2 notifications into `t_realtime_notification` and dispatch to online WebSocket sessions after transaction commit (`TransactionSynchronizationManager.registerSynchronization` or immediate dispatch when non-transactional).
   - Incremental cursor pull (`syncNotifications`) returning unread, non-expired messages where `seq_id > lastSeqId` plus `serverHeadSeqId`.
   - Multi-terminal ACK (`acknowledgeNotifications`): marks messages read (`read_status = 1`), acknowledges outbound dispatcher window, and broadcasts `ALERT_DISMISSED` to all cashier terminals of the same `shop_id`.
4. **Dynamic Shop Prep Timeout Configuration & Watchdog (`ShopNotificationConfigService`, `OrderTimeoutWatchdogScheduler`)**:
   - Admin/Cashier read & write endpoints (`GET/PUT /admin/shop/notification-config`) with strict range validation (`prep_timeout_minutes` in `[5, 120]`, `timeout_repeat_interval_seconds` in `[15, 600]`).
   - Scheduled watchdog (`OrderTimeoutWatchdogScheduler`) scanning paid (`transac_status = 'success'`), uncompleted (`off_time IS NULL`) orders against each shop's dynamic threshold (`prep_timeout_enabled == 1` and `now - pay_time >= prep_timeout_minutes * 60s`), publishing idempotent `ORDER_PREP_TIMEOUT` (`P0`, `message_id = "ntf_timeout_" + orderNo + "_stage1"`, `repeat_interval_ms = timeout_repeat_interval_seconds * 1000`).
5. **Business Event Producers & Dual-Publish Compatibility Bridges**:
   - `PaymentSuccessHandler`: publish `NEW_ORDER_PAID` (`P1`, voice + toast/banner) to the order's shop cashier channel upon order payment completion.
   - `ICouponServiceImpl.receiveCoupon`: publish `COUPON_GRANTED` (`P1`, `aggregation_key = "COUPON_GRANTED"`, `aggregation_window_ms = 800`) to the recipient's `openid` WebSocket session; if the user has no active WebSocket session and a coupon subscribe message template is configured (`weixin.subscribeTemplates.couponGranted`), trigger offline WeChat Subscribe Message delivery via `WechatCouponSubscribePushService`.
   - `AppConfigController`: expose `couponGranted` template ID in `GET /config/subscribe-templates`.
   - `CashierEventWebSocketHub` & `DishMenuPushService`: dual-publish `kds_delivery_available` (`KDS_DELIVERY_AVAILABLE`), `table_order_changed` (`TABLE_ORDER_CHANGED`), `dish_catalog_changed` (`DISH_CATALOG_CHANGED`), `business_changed` (`SHOP_BUSINESS_CHANGED`), `takeout_dispatch_alert` (`TAKEOUT_DISPATCH_ALERT`), `takeout_dispatch_changed` (`TAKEOUT_DISPATCH_CHANGED`), and `meal_pickup_ready` (`MEAL_PICKUP_READY`) to `/ws/v1/notify` while preserving `/ws/cashier-events` and `/ws/menu`.
6. **Documentation & Packaging**:
   - Synchronize `docs/openapi.yaml` and `docs/API.md`.
   - Build runnable JAR via `.\mvnw.cmd clean package -DskipTests`.

## Out of Scope
- Removing legacy `/ws/menu` or `/ws/cashier-events` endpoints (preserved in Phase 1 for zero-downtime dual-track compatibility).
- Modifying `/ws/kds` or `/ws/kds/v2` KDS business authority protocols.

## Tasks / Vertical Slices
- [ ] T01 Unified realtime notification channel, dynamic timeout config & watchdog, coupon/order/bridge producers, REST sync/ack & config endpoints, and OpenAPI sync

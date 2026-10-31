# Implementation Design — WI-078

## 1. Architecture Overview
Phase 1 establishes a unified real-time notification channel (`/ws/v1/notify`) and incremental sync/ack REST APIs while maintaining 100% backward compatibility with `/ws/menu` and `/ws/cashier-events`.

```
Business Producers (PaymentSuccessHandler / ICouponServiceImpl / OrderTimeoutWatchdogScheduler / DishMenuPushService / CashierEventWebSocketHub)
        │
        ▼
UnifiedNotificationService
  ├── 1. Persist P0/P1/P2 into t_realtime_notification (monotonic seq_id, unique message_id)
  ├── 2. Register TransactionSynchronization.afterCommit (or immediate if non-tx)
  └── 3. Dispatch UnifiedMessageEnvelope via UnifiedSessionRegistry -> WebSocketOutboundDispatcher
               ├── Online WebSocket Session (/ws/v1/notify)
               └── Offline Fallback (COUPON_GRANTED -> WechatCouponSubscribePushService)
```

## 2. Standard Message Envelope (`UnifiedMessageEnvelope`)
- `frame_type`: `"EVENT"` | `"CONNECTED"` | `"PONG"` | `"ACK_RESULT"` | `"CONTEXT_BOUND"`
- `message_id`: globally unique idempotent key (e.g., `"ntf_order_paid_" + orderNo`, `"ntf_timeout_" + orderNo + "_stage1"`, `"ntf_coupon_" + userCouponId`)
- `seq_id`: monotonic `BIGINT` cursor from `t_realtime_notification.seq_id` (`0` for ephemeral `P3` frames)
- `timestamp`: server epoch ms
- `expire_at`: expiration epoch ms
- `target`: `{ "scope": "SHOP" | "USER" | "BROADCAST", "shop_id": 12, "user_id": null, "openid": "..." }`
- `business_type`: `"ORDER"` | `"COUPON"` | `"TABLE"` | `"KDS"` | `"MENU"` | `"TAKEOUT"` | `"SYSTEM"`
- `event_type`:
  - `"NEW_ORDER_PAID"` (`P1`)
  - `"ORDER_PREP_TIMEOUT"` (`P0`)
  - `"COUPON_GRANTED"` (`P1`)
  - `"ALERT_DISMISSED"` (`P2`)
  - `"MEAL_PICKUP_READY"` (`P1`)
  - `"TAKEOUT_DISPATCH_ALERT"` (`P0`)
  - `"TAKEOUT_DISPATCH_CHANGED"` (`P2`)
  - `"TABLE_ORDER_CHANGED"` (`P2`)
  - `"KDS_DELIVERY_AVAILABLE"` (`P2`)
  - `"DISH_CATALOG_CHANGED"` (`P3`)
  - `"SHOP_BUSINESS_CHANGED"` (`P2`)
- `priority`: `"P0"` | `"P1"` | `"P2"` | `"P3"`
- `require_ack`: `true` for `P0`/`P1`, `false` for `P2`/`P3`
- `display_strategy`: `{ "ui_type", "sound", "tts_text", "duration_ms", "repeat_interval_ms", "aggregation_key", "aggregation_window_ms", "action_text", "action_route" }`
- `payload`: business-specific map

## 3. Dynamic Per-Shop Prep Timeout (`ShopNotificationConfigService` + `OrderTimeoutWatchdogScheduler`)
- Table `t_shop_notification_config`:
  - `shop_id` INT PK
  - `prep_timeout_enabled` TINYINT(1) NOT NULL DEFAULT 1
  - `prep_timeout_minutes` INT NOT NULL DEFAULT 15 (validated in `[5, 120]`)
  - `timeout_repeat_interval_seconds` INT NOT NULL DEFAULT 60 (validated in `[15, 600]`)
- `OrderTimeoutWatchdogScheduler` runs every 30 seconds:
  - Queries paid (`transac_status = 'success'`), uncompleted (`off_time IS NULL`) orders from the last 24 hours.
  - Groups by `shop_id`, loads `ShopNotificationConfig` via `ShopNotificationConfigService.getOrDefaultConfig(shopId)`.
  - If `prep_timeout_enabled == 1` and `now - pay_time >= prep_timeout_minutes * 60_000L`, publishes `ORDER_PREP_TIMEOUT` with `message_id = "ntf_timeout_" + orderNo + "_stage1"`.
  - `UnifiedNotificationService` deduplicates by `message_id` (`t_realtime_notification.uk_message_id`) so each timed-out order triggers the persistent P0 alert once and relies on client `repeat_interval_ms` + incremental sync until acknowledged or completed.

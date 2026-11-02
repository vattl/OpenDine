# API Consumer Handoff — WI-078

## Interface
1. `WS /ws/v1/notify` — Unified Realtime Notification WebSocket Channel
2. `GET /cashier/notifications/sync` & `GET /api/v1/notifications/sync` — Incremental Notification Cursor Sync
3. `POST /cashier/notifications/ack` & `POST /api/v1/notifications/ack` — Notification Read & Multi-Device Alert Dismissal ACK
4. `GET /admin/shop/notification-config` & `PUT /admin/shop/notification-config` — Per-Shop Dynamic Order Prep Timeout Configuration
5. `GET /config/subscribe-templates` — Extended with `couponGranted` template ID

## Compatibility
NON_BREAKING (Legacy `/ws/menu` and `/ws/cashier-events` remain active and dual-published)

## Before
- Cashier POS connected separately to `/ws/cashier-events` and `/ws/menu` with heterogeneous JSON payloads and no monotonic `seq_id` or multi-device alert dismissal.
- Order preparation timeout had no server-side configurable threshold or persistent P0 watchdog push.
- Coupon grants (`receiveCoupon`, batch grant, redeem code) had no real-time WebSocket push or offline subscribe message push.

## After
- Single unified endpoint `/ws/v1/notify` delivers standardized `UnifiedMessageEnvelope` frames (`NEW_ORDER_PAID`, `ORDER_PREP_TIMEOUT`, `COUPON_GRANTED`, `ALERT_DISMISSED`, `TABLE_ORDER_CHANGED`, `KDS_DELIVERY_AVAILABLE`, `MEAL_PICKUP_READY`, `TAKEOUT_DISPATCH_ALERT`, `TAKEOUT_DISPATCH_CHANGED`, `DISH_CATALOG_CHANGED`, `SHOP_BUSINESS_CHANGED`).
- `GET /cashier/notifications/sync?last_seq_id=<cursor>&limit=50` pulls missed unread notifications after reconnect.
- `POST /cashier/notifications/ack` marks notifications as read and broadcasts `ALERT_DISMISSED` across all cashier terminals of the same shop.
- `GET/PUT /admin/shop/notification-config` reads and updates `prep_timeout_enabled` (`true/false`), `prep_timeout_minutes` (`5..120`, default `15`), and `timeout_repeat_interval_seconds` (`15..600`, default `60`).

## Consumer Impact
- Cashier POS can connect to `/ws/v1/notify?client_type=CASHIER&shop_id=<shopId>&token=<jwt>` (or lease headers), store `localLastSeqId`, call `/cashier/notifications/sync` upon `CONNECTED` or `PONG` gap detection, and call `/cashier/notifications/ack` when dismissing `P0`/`P1` alerts.
- Admin / Cashier settings UI can bind to `GET/PUT /admin/shop/notification-config` to configure per-shop preparation timeout alerts.
- Mini Program can connect to `/ws/v1/notify?client_type=MINI_PROGRAM&shop_id=<shopId>&openid=<openid>` and aggregate `COUPON_GRANTED` events by `display_strategy.aggregation_key` (`800ms` window).

## Required Frontend / Consumer Changes
1. Connect Cashier `NotificationBus` to `/ws/v1/notify` and handle `EVENT` frames by `priority` (`P0` persistent alert + repeat sound, `P1` toast/banner + voice, `P2`/`P3` silent store refresh).
2. Listen for `event_type === "ALERT_DISMISSED"` to automatically close active alerts acknowledged by another POS terminal in the same shop.
3. Add shop notification threshold form bound to `GET/PUT /admin/shop/notification-config`.

## Type / Model Changes
- `UnifiedMessageEnvelope`: `{ frame_type, message_id, seq_id, timestamp, expire_at, target, business_type, event_type, priority, require_ack, display_strategy, payload }`
- `ShopNotificationConfigDTO`: `{ shop_id, prep_timeout_enabled, prep_timeout_minutes, timeout_repeat_interval_seconds, updated_by, updated_at }`

## Request Construction
- `GET /cashier/notifications/sync?shop_id=1&last_seq_id=100&limit=50` with `Authorization: Bearer <jwt>` and `X-Shop-Id: 1`
- `POST /cashier/notifications/ack` with JSON body `{"shop_id": 1, "message_ids": ["ntf_timeout_ORD123_stage1"]}`
- `PUT /admin/shop/notification-config` with JSON body `{"shop_id": 1, "prep_timeout_enabled": true, "prep_timeout_minutes": 15, "timeout_repeat_interval_seconds": 60}`

## Response Mapping / Display
- Standard `R` envelope (`code: 0`, `data: { ... }`).

## UI / Interaction Impact
- `P0` (`ORDER_PREP_TIMEOUT`, `TAKEOUT_DISPATCH_ALERT`): persistent top red banner/modal + repeating audio alert until ACKed.
- `P1` (`NEW_ORDER_PAID`, `COUPON_GRANTED`, `MEAL_PICKUP_READY`): non-blocking banner/toast or coupon modal + single voice/sound prompt.
- `P2`/`P3`: silent background store invalidation.

## Example Call
```http
PUT /admin/shop/notification-config HTTP/1.1
Authorization: Bearer <jwt>
X-Shop-Id: 1
Content-Type: application/json

{
  "shop_id": 1,
  "prep_timeout_enabled": true,
  "prep_timeout_minutes": 20,
  "timeout_repeat_interval_seconds": 60
}
```

## Example Response
```json
{
  "code": 0,
  "msg": "操作成功",
  "data": {
    "shop_id": 1,
    "prep_timeout_enabled": true,
    "prep_timeout_minutes": 20,
    "timeout_repeat_interval_seconds": 60
  }
}
```

## Defaults / Fallbacks
- Default `prep_timeout_enabled = true`, `prep_timeout_minutes = 15`, `timeout_repeat_interval_seconds = 60` when a shop has not customized its row in `t_shop_notification_config`.
- Offline WeChat Subscribe Message fallback for `COUPON_GRANTED` is skipped gracefully if `weixin.subscribeTemplates.couponGranted` is not configured.

## Rollout / Migration Order
1. Apply database migration `V053__unified_realtime_notification_channel.sql`.
2. Deploy backend server with `/ws/v1/notify` and dual-publish bridges.
3. Migrate Cashier POS and Mini Program clients to `/ws/v1/notify`.

## Verification Checklist
- [x] consumer request updated
- [x] consumer response mapping updated
- [x] UI/state semantics updated if applicable
- [x] old contract references removed or intentionally supported
- [x] end-to-end flow verified

## Owner / Status
- Owner: Server & Cashier Engineering (`WI-078`)
- Status: READY_FOR_CONSUMER
